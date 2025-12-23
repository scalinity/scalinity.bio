from __future__ import annotations

from dataclasses import dataclass

from .constants import (
    EPIGENETIC_CLOCKS,
    GENES,
    METABOLITES,
    PROTEIN_BIOMARKERS,
    SNP_NAMES,
)


@dataclass(frozen=True)
class CohortSchema:
    """
    Column schema for the synthetic cohort.

    Notes:
    - The dataset is designed to be *model-ready* but also interpretable for
      downstream driver attribution in the macOS app.
    - Categorical fields: `sex`, `ethnicity`.
    """

    # Demographics / lifestyle
    chronological_age: str = "chronological_age"
    sex: str = "sex"  # "female" | "male"
    ethnicity: str = "ethnicity"
    bmi: str = "bmi"
    diet_score: str = "diet_score"  # 1–10
    exercise_score: str = "exercise_score"  # 1–10
    sleep_score: str = "sleep_score"  # 1–10
    comorbidity_diabetes: str = "comorbidity_diabetes"  # 0/1

    # Outcomes
    telomere_length_kb: str = "telomere_length_kb"
    crp_mg_L: str = "crp_mg_L"
    il6_pg_mL: str = "il6_pg_mL"
    frailty_index: str = "frailty_index"

    # Labels (synthetic ground truth)
    biological_age: str = "biological_age"
    bio_age_delta: str = "bio_age_delta"


SCHEMA = CohortSchema()


def feature_columns() -> list[str]:
    """All model input features (no labels)."""
    cols: list[str] = [
        SCHEMA.chronological_age,
        SCHEMA.sex,
        SCHEMA.ethnicity,
        SCHEMA.bmi,
        SCHEMA.diet_score,
        SCHEMA.exercise_score,
        SCHEMA.sleep_score,
        SCHEMA.comorbidity_diabetes,
    ]
    cols += SNP_NAMES
    cols += PROTEIN_BIOMARKERS
    cols += METABOLITES
    cols += [f"expr_{g}" for g in GENES]
    cols += EPIGENETIC_CLOCKS
    cols += [
        SCHEMA.telomere_length_kb,
        SCHEMA.crp_mg_L,
        SCHEMA.il6_pg_mL,
        SCHEMA.frailty_index,
    ]
    return cols


def label_columns() -> list[str]:
    """Ground-truth labels (synthetic)."""
    return [SCHEMA.biological_age, SCHEMA.bio_age_delta]


def all_columns() -> list[str]:
    return feature_columns() + label_columns()


def expected_ranges() -> dict[str, tuple[float, float]]:
    """
    Expected biological/physiological ranges used by validation.

    These are intentionally broad; the validator focuses on outliers and
    non-physiological values rather than enforcing clinical reference ranges.
    """
    r: dict[str, tuple[float, float]] = {
        SCHEMA.chronological_age: (30.0, 80.0),
        SCHEMA.bmi: (16.0, 50.0),
        SCHEMA.diet_score: (1.0, 10.0),
        SCHEMA.exercise_score: (1.0, 10.0),
        SCHEMA.sleep_score: (1.0, 10.0),
        SCHEMA.comorbidity_diabetes: (0.0, 1.0),
        SCHEMA.telomere_length_kb: (3.0, 15.0),
        SCHEMA.crp_mg_L: (0.0, 50.0),
        SCHEMA.il6_pg_mL: (0.0, 100.0),
        SCHEMA.frailty_index: (0.0, 1.0),
        SCHEMA.biological_age: (25.0, 90.0),
        SCHEMA.bio_age_delta: (-25.0, 25.0),
        # Key metabolite ranges (broad)
        "metab_glucose_mg_dL": (50.0, 250.0),
        "metab_insulin_uIU_mL": (1.0, 80.0),
        "metab_hba1c_pct": (4.0, 12.0),
        "metab_triglycerides_mg_dL": (30.0, 600.0),
        "metab_hdl_mg_dL": (10.0, 120.0),
        "metab_ldl_mg_dL": (30.0, 250.0),
        "metab_total_cholesterol_mg_dL": (80.0, 400.0),
        "metab_uric_acid_mg_dL": (1.0, 12.0),
        "metab_homocysteine_umol_L": (3.0, 40.0),
        "metab_creatinine_mg_dL": (0.3, 2.5),
        "metab_lactate_mmol_L": (0.2, 10.0),
        "metab_beta_hydroxybutyrate_mmol_L": (0.0, 8.0),
        "metab_vitamin_d_ng_mL": (5.0, 120.0),
        "metab_folate_ng_mL": (1.0, 24.0),
        "metab_b12_pg_mL": (80.0, 2000.0),
        "metab_magnesium_mg_dL": (1.0, 3.2),
        "metab_zinc_ug_dL": (30.0, 180.0),
    }
    for c in EPIGENETIC_CLOCKS:
        if c == "epigenetic_age_acceleration":
            r[c] = (-15.0, 15.0)
        else:
            r[c] = (25.0, 90.0)
    return r


