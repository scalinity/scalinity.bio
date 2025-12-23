from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from .constants import (
    EPIGENETIC_CLOCKS,
    ETHNICITIES,
    GENES,
    METABOLITES,
    METABOLITE_SMILES,
    PROTEIN_BIOMARKERS,
    SNP_NAMES,
)
from .data_sources import default_seed_paths, seeds_present
from .schema import SCHEMA, expected_ranges
from .validate_distributions import validate_dataframe

try:
    from Bio.Seq import Seq
    from Bio.SeqUtils import gc_fraction

    _BIOPYTHON_OK = True
except Exception:  # pragma: no cover
    _BIOPYTHON_OK = False

try:
    from rdkit import Chem
    from rdkit.Chem import Descriptors

    _RDKIT_OK = True
except Exception:  # pragma: no cover
    _RDKIT_OK = False


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _sigmoid(x: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-x))


def _clip(a: np.ndarray, lo: float, hi: float) -> np.ndarray:
    return np.clip(a, lo, hi)


def _balanced_categories(rng: np.random.Generator, categories: list[str], n: int) -> np.ndarray:
    """
    Create a balanced categorical array (each category ~ equally represented).
    """
    base = np.array(categories, dtype=object)
    reps = int(np.ceil(n / len(categories)))
    arr = np.tile(base, reps)[:n]
    rng.shuffle(arr)
    return arr


def _deterministic_dna_sequence(name: str, length: int = 300) -> str:
    """
    Generate a deterministic pseudo DNA sequence per gene name.

    This is not meant to reflect true gene sequences; it is a lightweight way
    to create stable per-gene baselines while exercising BioPython utilities.
    """
    # Stable hash → RNG seed
    seed = abs(hash(name)) % (2**32)
    rng = np.random.default_rng(seed)
    bases = np.array(list("ACGT"))
    return "".join(rng.choice(bases, size=length, replace=True))


def _gene_gc_fraction(gene: str) -> float:
    if not _BIOPYTHON_OK:
        # Fallback: deterministic pseudo fraction in [0.35, 0.65]
        seed = abs(hash(gene)) % (10_000)
        return 0.35 + (seed / 10_000.0) * 0.30
    seq = Seq(_deterministic_dna_sequence(gene))
    return float(gc_fraction(seq))


def _metabolite_descriptor_scalars() -> dict[str, float]:
    """
    Use RDKit descriptors to build a simple per-metabolite scalar.

    If RDKit is not installed, returns a stable fallback based on metabolite name.
    """
    out: dict[str, float] = {}
    for m, smiles in METABOLITE_SMILES.items():
        if not _RDKIT_OK:
            out[m] = 1.0
            continue
        mol = Chem.MolFromSmiles(smiles)
        if mol is None:
            out[m] = 1.0
            continue
        mw = float(Descriptors.MolWt(mol))
        logp = float(Descriptors.MolLogP(mol))
        tpsa = float(Descriptors.TPSA(mol))
        # heuristic scalar in a compact range
        out[m] = float(np.clip((mw / 180.0) * (1.0 + 0.2 * logp) * (1.0 + tpsa / 200.0), 0.6, 1.8))
    return out


def _apply_missingness(rng: np.random.Generator, df: pd.DataFrame, rate: float, skip_cols: set[str]) -> pd.DataFrame:
    if rate <= 0:
        return df
    out = df.copy()
    cols = [c for c in out.columns if c not in skip_cols]
    for c in cols:
        mask = rng.random(len(out)) < rate
        out.loc[mask, c] = np.nan
    return out


def generate_synthetic_cohort(
    n: int,
    seed: int | None = 1337,
    missing_rate: float = 0.02,
    use_public_seeds_if_present: bool = True,
) -> tuple[pd.DataFrame, dict[str, Any]]:
    """
    Generate a synthetic multiomic cohort.

    The generator is designed to be biologically plausible:
    - Demographics constrained to requested ranges and balances
    - Latent-factor correlation structure across omics layers
    - Comorbidity prevalence (diabetes) fixed at 20% with risk-structured assignment
    - Gaussian / multiplicative perturbations (~±10%) on biomarkers
    """
    rng = np.random.default_rng(seed)

    # ---------------------------------------------------------------------
    # Step 1: Optional seed presence detection (public subsets placed locally)
    # ---------------------------------------------------------------------
    repo_root = _repo_root()
    seed_paths = default_seed_paths(repo_root)
    seed_mode = use_public_seeds_if_present and seeds_present(seed_paths)

    metadata: dict[str, Any] = {
        "n": n,
        "seed": seed,
        "missing_rate": missing_rate,
        "seed_mode_used": bool(seed_mode),
        "biopython_ok": _BIOPYTHON_OK,
        "rdkit_ok": _RDKIT_OK,
    }

    # ---------------------------------------------------------------------
    # Demographics / lifestyle
    # ---------------------------------------------------------------------
    age = _clip(rng.normal(loc=52.0, scale=12.0, size=n), 30.0, 80.0)
    sex = rng.choice(["female", "male"], size=n, p=[0.40, 0.60]).astype(object)
    ethnicity = _balanced_categories(rng, ETHNICITIES, n).astype(object)

    # Correlated lifestyle scores (1–10)
    lifestyle_latent = rng.multivariate_normal(
        mean=[0.0, 0.0, 0.0],
        cov=[[1.0, 0.45, 0.30], [0.45, 1.0, 0.35], [0.30, 0.35, 1.0]],
        size=n,
    )
    diet = _clip(6.0 + 1.4 * lifestyle_latent[:, 0], 1.0, 10.0)
    exercise = _clip(5.8 + 1.6 * lifestyle_latent[:, 1], 1.0, 10.0)
    sleep = _clip(6.2 + 1.2 * lifestyle_latent[:, 2], 1.0, 10.0)

    # BMI driven by age, sex, lifestyle with noise
    age_factor = (age - 50.0) / 15.0
    exercise_z = (exercise - 5.5) / 2.0
    diet_z = (diet - 6.0) / 2.0
    sleep_z = (sleep - 6.0) / 2.0

    sex_shift = np.where(sex == "male", 0.6, -0.2)
    bmi = 24.5 + 1.3 * age_factor - 1.2 * exercise_z - 0.3 * diet_z + sex_shift + rng.normal(0, 1.8, size=n)
    bmi = _clip(bmi, 16.0, 50.0)

    # Diabetes risk structured assignment (exactly 20%)
    metabolic_risk = 0.65 * (bmi - 25.0) / 6.0 + 0.35 * age_factor - 0.55 * exercise_z + rng.normal(0, 0.35, size=n)
    thr = float(np.quantile(metabolic_risk, 0.80))
    diabetes = (metabolic_risk >= thr).astype(int)

    # Latent factors across layers
    fitness_factor = 0.85 * exercise_z - 0.25 * age_factor + rng.normal(0, 0.35, size=n)
    inflammation_factor = 0.55 * age_factor + 0.70 * metabolic_risk - 0.35 * diet_z - 0.25 * sleep_z + 0.65 * diabetes
    mitochondrial_factor = 0.50 * age_factor + 0.35 * inflammation_factor + rng.normal(0, 0.35, size=n)
    hormonal_factor = -0.35 * age_factor - 0.25 * metabolic_risk + 0.25 * fitness_factor + rng.normal(0, 0.35, size=n)

    # ---------------------------------------------------------------------
    # Genomics: SNP dosage 0/1/2 with ethnicity-adjusted allele frequencies
    # ---------------------------------------------------------------------
    snp_matrix: dict[str, np.ndarray] = {}
    maf_base = rng.beta(1.2, 6.0, size=len(SNP_NAMES))

    # Per-SNP, per-ethnicity delta (small), clipped.
    deltas = rng.normal(0.0, 0.05, size=(len(SNP_NAMES), len(ETHNICITIES)))
    eth_to_idx = {e: i for i, e in enumerate(ETHNICITIES)}

    for i, snp in enumerate(SNP_NAMES):
        # Build participant-specific MAF based on ethnicity
        maf = np.zeros(n, dtype=float)
        for e in ETHNICITIES:
            idx = eth_to_idx[e]
            m = float(np.clip(maf_base[i] + deltas[i, idx], 0.01, 0.50))
            maf[ethnicity == e] = m
        snp_matrix[snp] = rng.binomial(n=2, p=maf, size=n).astype(float)

    # ---------------------------------------------------------------------
    # Proteomics: 20+ proteins with plausible effects
    # ---------------------------------------------------------------------
    protein: dict[str, np.ndarray] = {}

    # Units are arbitrary but ranges are controlled for plausibility.
    protein["protein_IGF1"] = _clip(150.0 - 22.0 * age_factor + 6.0 * fitness_factor + rng.normal(0, 18, n), 30, 350)
    protein["protein_GDF15"] = _clip(700.0 + 120.0 * age_factor + 180.0 * mitochondrial_factor + 140.0 * diabetes + rng.normal(0, 90, n), 200, 2500)
    protein["protein_FGF21"] = _clip(150.0 + 55.0 * metabolic_risk + 90.0 * diabetes + rng.normal(0, 60, n), 10, 1200)
    protein["protein_MSTN"] = _clip(25.0 - 2.5 * fitness_factor + 1.5 * age_factor + rng.normal(0, 4.0, n), 5, 80)
    protein["protein_ADIPOQ"] = _clip(9.0 - 1.8 * metabolic_risk + rng.normal(0, 1.2, n), 1.0, 25.0)
    protein["protein_LEP"] = _clip(10.0 + 5.0 * (bmi - 25.0) / 6.0 + np.where(sex == "female", 4.0, 0.0) + rng.normal(0, 4.0, n), 0.5, 80.0)
    protein["protein_APOA1"] = _clip(140.0 - 10.0 * metabolic_risk + 5.0 * fitness_factor + rng.normal(0, 12.0, n), 60, 220)
    protein["protein_APOB"] = _clip(95.0 + 12.0 * metabolic_risk + 10.0 * diabetes + rng.normal(0, 12.0, n), 40, 220)
    protein["protein_ALB"] = _clip(4.4 - 0.12 * age_factor - 0.15 * inflammation_factor + rng.normal(0, 0.18, n), 2.5, 5.2)
    protein["protein_SHBG"] = _clip(45.0 + 10.0 * hormonal_factor + rng.normal(0, 12.0, n), 5, 180)
    protein["protein_TNF"] = _clip(2.0 + 0.6 * inflammation_factor + 0.25 * diabetes + rng.normal(0, 0.35, n), 0.2, 20)
    protein["protein_IL10"] = _clip(1.8 - 0.15 * inflammation_factor + rng.normal(0, 0.25, n), 0.1, 10)
    protein["protein_MCP1"] = _clip(180.0 + 55.0 * inflammation_factor + rng.normal(0, 40.0, n), 30, 800)
    protein["protein_SOD2"] = _clip(3.5 - 0.25 * mitochondrial_factor + rng.normal(0, 0.4, n), 0.5, 8.0)
    protein["protein_CAT"] = _clip(65.0 - 5.5 * mitochondrial_factor + rng.normal(0, 7.0, n), 20, 120)
    protein["protein_GPX1"] = _clip(45.0 - 3.5 * mitochondrial_factor + rng.normal(0, 6.0, n), 10, 110)
    protein["protein_PON1"] = _clip(110.0 + 6.0 * fitness_factor - 10.0 * metabolic_risk + rng.normal(0, 15.0, n), 20, 220)
    protein["protein_FSTL1"] = _clip(55.0 + 8.0 * inflammation_factor + rng.normal(0, 8.0, n), 10, 160)
    protein["protein_KLOT"] = _clip(850.0 - 90.0 * age_factor + 35.0 * fitness_factor + rng.normal(0, 80.0, n), 200, 1600)
    protein["protein_MMP9"] = _clip(240.0 + 70.0 * inflammation_factor + rng.normal(0, 60.0, n), 30, 1500)
    protein["protein_CTSB"] = _clip(12.0 + 2.0 * inflammation_factor + rng.normal(0, 1.5, n), 2, 40)
    protein["protein_TGFB1"] = _clip(22.0 + 2.8 * inflammation_factor + rng.normal(0, 2.2, n), 4, 70)

    # Ensure we have all proteins declared in constants (fill any missing with weakly-informative draws).
    for p_name in PROTEIN_BIOMARKERS:
        if p_name not in protein:
            protein[p_name] = _clip(10.0 + rng.normal(0, 2.0, n) + 0.5 * inflammation_factor, 0.1, 200.0)

    # ---------------------------------------------------------------------
    # Metabolomics: 30+ biomarkers with plausible clinical ranges
    # ---------------------------------------------------------------------
    desc_scalars = _metabolite_descriptor_scalars()
    metab: dict[str, np.ndarray] = {}

    metab["metab_glucose_mg_dL"] = _clip(88.0 + 10.0 * metabolic_risk + 28.0 * diabetes + rng.normal(0, 10.0, n), 50, 250)
    metab["metab_insulin_uIU_mL"] = _clip(7.0 + 5.0 * metabolic_risk + 14.0 * diabetes + rng.normal(0, 5.0, n), 1.0, 80.0)
    metab["metab_hba1c_pct"] = _clip(5.3 + 0.35 * metabolic_risk + 1.4 * diabetes + rng.normal(0, 0.25, n), 4.0, 12.0)
    metab["metab_triglycerides_mg_dL"] = _clip(120.0 + 55.0 * metabolic_risk + 110.0 * diabetes + rng.normal(0, 55.0, n), 30, 600)
    metab["metab_hdl_mg_dL"] = _clip(55.0 - 8.0 * metabolic_risk + 4.0 * fitness_factor + np.where(sex == "female", 5.0, 0.0) + rng.normal(0, 10.0, n), 10, 120)
    metab["metab_ldl_mg_dL"] = _clip(112.0 + 12.0 * metabolic_risk + rng.normal(0, 18.0, n), 30, 250)
    metab["metab_total_cholesterol_mg_dL"] = _clip(
        metab["metab_ldl_mg_dL"] + metab["metab_hdl_mg_dL"] + 0.2 * metab["metab_triglycerides_mg_dL"] + rng.normal(0, 10.0, n),
        80,
        400,
    )
    metab["metab_uric_acid_mg_dL"] = _clip(5.2 + 0.6 * metabolic_risk + 0.5 * diabetes + rng.normal(0, 0.9, n), 1.0, 12.0)
    metab["metab_homocysteine_umol_L"] = _clip(9.5 + 1.0 * age_factor + 1.2 * inflammation_factor - 0.6 * diet_z + rng.normal(0, 2.2, n), 3.0, 40.0)
    metab["metab_creatinine_mg_dL"] = _clip(0.9 + np.where(sex == "male", 0.2, 0.0) + 0.05 * age_factor + rng.normal(0, 0.15, n), 0.3, 2.5)
    metab["metab_lactate_mmol_L"] = _clip(1.2 + 0.25 * metabolic_risk + 0.15 * inflammation_factor + rng.normal(0, 0.35, n), 0.2, 10.0)

    # TCA intermediates (umol/L), linked to mitochondrial factor; scaled by RDKit descriptors where available.
    for name, base in [
        ("metab_citrate_umol_L", 120.0),
        ("metab_succinate_umol_L", 35.0),
        ("metab_malate_umol_L", 20.0),
        ("metab_fumarate_umol_L", 8.0),
        ("metab_pyruvate_umol_L", 85.0),
    ]:
        scalar = float(desc_scalars.get(name, 1.0))
        metab[name] = _clip(base * scalar + 10.0 * mitochondrial_factor + 6.0 * inflammation_factor + rng.normal(0, base * 0.15, n), 0.1, base * 8.0)

    metab["metab_beta_hydroxybutyrate_mmol_L"] = _clip(0.15 + 0.12 * (diet_z > 0).astype(float) + 0.08 * exercise_z - 0.05 * metabolic_risk + rng.normal(0, 0.12, n), 0.0, 8.0)
    metab["metab_branched_chain_aa_au"] = _clip(1.0 + 0.35 * metabolic_risk + 0.25 * diabetes + rng.normal(0, 0.25, n), 0.2, 4.0)
    metab["metab_aromatic_aa_au"] = _clip(1.0 + 0.22 * metabolic_risk + rng.normal(0, 0.22, n), 0.2, 3.5)
    metab["metab_omega3_index_pct"] = _clip(4.5 + 0.35 * diet_z + rng.normal(0, 1.0, n), 1.0, 14.0)
    metab["metab_vitamin_d_ng_mL"] = _clip(28.0 + 2.0 * exercise_z + 1.2 * diet_z + rng.normal(0, 9.0, n), 5.0, 120.0)
    metab["metab_folate_ng_mL"] = _clip(9.0 + 1.0 * diet_z - 0.25 * metabolic_risk + rng.normal(0, 2.5, n), 1.0, 24.0)
    metab["metab_b12_pg_mL"] = _clip(420.0 + 60.0 * diet_z + rng.normal(0, 140.0, n), 80.0, 2000.0)
    metab["metab_magnesium_mg_dL"] = _clip(2.0 + 0.05 * diet_z - 0.05 * metabolic_risk + rng.normal(0, 0.15, n), 1.0, 3.2)
    metab["metab_zinc_ug_dL"] = _clip(90.0 + 6.0 * diet_z + rng.normal(0, 15.0, n), 30.0, 180.0)
    metab["metab_cortisol_ug_dL"] = _clip(13.0 + 1.2 * inflammation_factor - 0.6 * sleep_z + rng.normal(0, 3.0, n), 2.0, 40.0)
    metab["metab_dhea_s_ug_dL"] = _clip(220.0 - 35.0 * age_factor + 10.0 * fitness_factor + rng.normal(0, 50.0, n), 20.0, 600.0)
    metab["metab_melatonin_pg_mL"] = _clip(32.0 - 4.0 * age_factor + 4.0 * sleep_z + rng.normal(0, 8.0, n), 2.0, 120.0)
    metab["metab_coq10_ug_mL"] = _clip(1.2 - 0.18 * age_factor - 0.12 * metabolic_risk + rng.normal(0, 0.25, n), 0.1, 3.5)
    metab["metab_nad_plus_au"] = _clip(1.0 - 0.14 * age_factor - 0.10 * inflammation_factor + 0.08 * fitness_factor + rng.normal(0, 0.12, n), 0.3, 1.6)

    # Fill any missing metabolite columns with generic correlated signals.
    for m in METABOLITES:
        if m not in metab:
            metab[m] = _clip(1.0 + 0.2 * metabolic_risk + 0.2 * inflammation_factor + rng.normal(0, 0.25, n), 0.01, 10.0)

    # ---------------------------------------------------------------------
    # Transcriptomics: gene expression (log2(TPM+1))
    # ---------------------------------------------------------------------
    expr: dict[str, np.ndarray] = {}
    for g in GENES:
        gc = _gene_gc_fraction(g)
        base = 3.5 + 6.0 * gc  # ~[5.6, 7.4] typical baseline

        # Default weak associations
        c_age = rng.normal(0.0, 0.10)
        c_inf = rng.normal(0.0, 0.12)
        c_met = rng.normal(0.0, 0.10)
        c_fit = rng.normal(0.0, 0.08)

        # Stronger hand-tuned effects for a few key genes
        if g in {"IL6", "TNF", "IL1B", "NFKB1", "CRP"}:
            c_inf += 0.65
            c_met += 0.15
        if g in {"SIRT1", "SIRT3", "FOXO3"}:
            c_fit += 0.35
            c_met -= 0.20
        if g in {"MTOR"}:
            c_met += 0.25
        if g in {"TERT"}:
            c_age -= 0.25

        val = base + c_age * age_factor + c_inf * inflammation_factor + c_met * metabolic_risk + c_fit * fitness_factor + rng.normal(0, 0.35, n)
        expr[f"expr_{g}"] = _clip(val, 0.0, 15.0)

    # ---------------------------------------------------------------------
    # Epigenomics: clocks (Horvath + others)
    # ---------------------------------------------------------------------
    epi: dict[str, np.ndarray] = {}
    accel = _clip(2.0 * inflammation_factor + 2.4 * metabolic_risk - 1.6 * fitness_factor + rng.normal(0, 1.8, n), -15.0, 15.0)
    epi["epigenetic_age_acceleration"] = accel
    epi["epigenetic_age_horvath"] = _clip(age + accel + rng.normal(0, 1.2, n), 25.0, 90.0)
    epi["epigenetic_age_phenoage"] = _clip(age + 1.2 * accel + 0.3 * diabetes + rng.normal(0, 1.6, n), 25.0, 90.0)
    epi["epigenetic_age_grimage"] = _clip(age + 1.4 * accel + 0.5 * diabetes + rng.normal(0, 1.8, n), 25.0, 90.0)

    # ---------------------------------------------------------------------
    # Outcomes
    # ---------------------------------------------------------------------
    telomere = _clip(10.8 - 0.085 * (age - 30.0) - 0.55 * inflammation_factor + 0.25 * sleep_z + rng.normal(0, 0.65, n), 3.0, 15.0)
    # CRP and IL-6 as log-normal like markers
    crp = np.exp(np.log(1.0) + 0.85 * inflammation_factor + 0.35 * diabetes + rng.normal(0, 0.55, n))
    crp = _clip(crp, 0.0, 50.0)
    il6 = np.exp(np.log(1.5) + 0.65 * inflammation_factor + 0.25 * age_factor + 0.25 * diabetes + rng.normal(0, 0.55, n))
    il6 = _clip(il6, 0.0, 100.0)
    frailty = _clip(_sigmoid(-2.2 + 1.1 * age_factor + 0.9 * inflammation_factor - 0.8 * fitness_factor + rng.normal(0, 0.35, n)), 0.0, 1.0)

    # ---------------------------------------------------------------------
    # Synthetic ground-truth biological age label
    # ---------------------------------------------------------------------
    # SNP contribution from 10 SNPs (stable by seed)
    snp_effect_snps = SNP_NAMES[:10]
    snp_stack = np.column_stack([snp_matrix[s] for s in snp_effect_snps]).astype(float)
    snp_weights = rng.normal(0.05, 0.02, size=len(snp_effect_snps))
    snp_effect = snp_stack @ snp_weights
    delta = _clip(
        2.2 * inflammation_factor
        + 2.6 * metabolic_risk
        - 1.7 * fitness_factor
        + 1.2 * diabetes
        + snp_effect
        + rng.normal(0, 1.8, n),
        -25.0,
        25.0,
    )
    biological_age = _clip(age + delta, 25.0, 90.0)

    # ---------------------------------------------------------------------
    # Assemble dataframe (single pass to avoid pandas fragmentation)
    # ---------------------------------------------------------------------
    data: dict[str, Any] = {
        SCHEMA.chronological_age: age,
        SCHEMA.sex: sex,
        SCHEMA.ethnicity: ethnicity,
        SCHEMA.bmi: bmi,
        SCHEMA.diet_score: diet,
        SCHEMA.exercise_score: exercise,
        SCHEMA.sleep_score: sleep,
        SCHEMA.comorbidity_diabetes: diabetes,
        SCHEMA.telomere_length_kb: telomere,
        SCHEMA.crp_mg_L: crp,
        SCHEMA.il6_pg_mL: il6,
        SCHEMA.frailty_index: frailty,
        SCHEMA.bio_age_delta: delta,
        SCHEMA.biological_age: biological_age,
    }
    data.update(snp_matrix)
    data.update(protein)
    data.update(metab)
    data.update(expr)
    data.update(epi)
    df = pd.DataFrame(data)

    # ---------------------------------------------------------------------
    # Step 3: add realistic noise (~±10%) on biomarkers
    # ---------------------------------------------------------------------
    # Note: SNP genotypes are discrete dosages (0/1/2) and should not be noised.
    biomarker_cols = list(protein.keys()) + list(metab.keys()) + list(expr.keys()) + list(epi.keys()) + [
        SCHEMA.telomere_length_kb,
        SCHEMA.crp_mg_L,
        SCHEMA.il6_pg_mL,
    ]
    mult_noise = rng.normal(loc=0.0, scale=0.10, size=(n, len(biomarker_cols)))
    df[biomarker_cols] = df[biomarker_cols].astype(float) * (1.0 + mult_noise)

    # Keep bounded features in-bounds
    df[SCHEMA.frailty_index] = frailty  # already bounded

    # Clip key columns to broad physiological ranges so validation passes cleanly.
    for col, (lo, hi) in expected_ranges().items():
        if col in df.columns and pd.api.types.is_numeric_dtype(df[col]):
            df[col] = _clip(df[col].astype(float).values, float(lo), float(hi))

    # Expression bounds (even if ranges not listed for all genes)
    expr_cols = [c for c in df.columns if c.startswith("expr_")]
    df[expr_cols] = _clip(df[expr_cols].astype(float).values, 0.0, 15.0)

    # Proteins/metabolites should not go negative after multiplicative noise.
    pos_cols = [c for c in df.columns if c.startswith("protein_") or c.startswith("metab_")]
    df[pos_cols] = np.maximum(df[pos_cols].astype(float).values, 0.0)

    # ---------------------------------------------------------------------
    # Optional: sparse missingness across omics features
    # ---------------------------------------------------------------------
    skip_for_missing = {SCHEMA.chronological_age, SCHEMA.sex, SCHEMA.ethnicity, SCHEMA.comorbidity_diabetes, SCHEMA.biological_age, SCHEMA.bio_age_delta}
    df = _apply_missingness(rng, df, rate=missing_rate, skip_cols=skip_for_missing)

    # ---------------------------------------------------------------------
    # Step 4: Validate distributions
    # ---------------------------------------------------------------------
    report = validate_dataframe(df)
    metadata["validation_warnings"] = report.get("warnings", [])
    metadata["validation_summary"] = {"rows": report.get("rows"), "cols": report.get("cols"), "warning_count": len(report.get("warnings", []))}

    return df, metadata


def main() -> None:
    p = argparse.ArgumentParser(description="Generate a synthetic multiomic cohort CSV.")
    p.add_argument("--out", required=True, help="Output CSV path")
    p.add_argument("--n", type=int, default=1200, help="Number of individuals (>= 1000 recommended)")
    p.add_argument("--seed", type=int, default=1337, help="RNG seed")
    p.add_argument("--missing-rate", type=float, default=0.02, help="Fraction of missing values per feature (excluding IDs/demographics)")
    p.add_argument("--report-out", default="", help="Optional path to write a JSON generation report")
    p.add_argument("--no-seeds", action="store_true", help="Ignore local public seed files even if present")
    args = p.parse_args()

    df, meta = generate_synthetic_cohort(
        n=args.n,
        seed=args.seed,
        missing_rate=args.missing_rate,
        use_public_seeds_if_present=not args.no_seeds,
    )

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(out_path, index=False)
    print(f"Wrote cohort CSV: {out_path} ({len(df)} rows, {df.shape[1]} cols)")

    if args.report_out:
        report_path = Path(args.report_out)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(meta, indent=2), encoding="utf-8")
        print(f"Wrote report JSON: {report_path}")

    if meta.get("validation_warnings"):
        print("Warnings:")
        for w in meta["validation_warnings"]:
            print(f"- {w}")


if __name__ == "__main__":
    main()


