from __future__ import annotations

ETHNICITIES: list[str] = [
    "European",
    "African",
    "EastAsian",
    "SouthAsian",
]

SNP_NAMES: list[str] = [f"snp_rs{i:05d}" for i in range(1, 61)]  # 60 SNPs

PROTEIN_BIOMARKERS: list[str] = [
    "protein_IGF1",
    "protein_GDF15",
    "protein_FGF21",
    "protein_MSTN",
    "protein_ADIPOQ",
    "protein_LEP",
    "protein_APOA1",
    "protein_APOB",
    "protein_ALB",
    "protein_SHBG",
    "protein_TNF",
    "protein_IL10",
    "protein_MCP1",
    "protein_SOD2",
    "protein_CAT",
    "protein_GPX1",
    "protein_PON1",
    "protein_FSTL1",
    "protein_KLOT",
    "protein_MMP9",
    "protein_CTSB",
    "protein_TGFB1",
]

METABOLITES: list[str] = [
    # Common clinical + metabolomics-like panel (units vary; see schema ranges)
    "metab_glucose_mg_dL",
    "metab_insulin_uIU_mL",
    "metab_hba1c_pct",
    "metab_triglycerides_mg_dL",
    "metab_hdl_mg_dL",
    "metab_ldl_mg_dL",
    "metab_total_cholesterol_mg_dL",
    "metab_uric_acid_mg_dL",
    "metab_homocysteine_umol_L",
    "metab_creatinine_mg_dL",
    "metab_lactate_mmol_L",
    "metab_citrate_umol_L",
    "metab_succinate_umol_L",
    "metab_malate_umol_L",
    "metab_fumarate_umol_L",
    "metab_pyruvate_umol_L",
    "metab_beta_hydroxybutyrate_mmol_L",
    "metab_branched_chain_aa_au",
    "metab_aromatic_aa_au",
    "metab_omega3_index_pct",
    "metab_vitamin_d_ng_mL",
    "metab_folate_ng_mL",
    "metab_b12_pg_mL",
    "metab_magnesium_mg_dL",
    "metab_zinc_ug_dL",
    "metab_cortisol_ug_dL",
    "metab_dhea_s_ug_dL",
    "metab_melatonin_pg_mL",
    "metab_coq10_ug_mL",
    "metab_nad_plus_au",
]

# A small optional mapping used when RDKit is installed; used only for generating
# correlations from simple molecule descriptors.
METABOLITE_SMILES: dict[str, str] = {
    "metab_glucose_mg_dL": "OC[C@H]1O[C@@H](O)[C@H](O)[C@@H](O)[C@H]1O",
    "metab_lactate_mmol_L": "CC(O)C(=O)O",
    "metab_citrate_umol_L": "C(C(=O)O)C(CC(=O)O)(C(=O)O)O",
    "metab_succinate_umol_L": "C(CC(=O)O)C(=O)O",
    "metab_fumarate_umol_L": "C(=CC(=O)O)C(=O)O",
    "metab_pyruvate_umol_L": "CC(=O)C(=O)O",
    "metab_beta_hydroxybutyrate_mmol_L": "CC(CC(=O)O)O",
}

# Mix of real gene symbols and generic placeholders.
GENES: list[str] = [
    "TP53",
    "SIRT1",
    "SIRT3",
    "FOXO3",
    "MTOR",
    "PTEN",
    "IGF1R",
    "IL1B",
    "IL6",
    "TNF",
    "NFKB1",
    "NFE2L2",
    "PPARGC1A",
    "ADIPOQ",
    "LEP",
    "CDKN2A",
    "TERT",
    "LMNA",
    "APOE",
    "CRP",
] + [f"GENE{i:03d}" for i in range(1, 121)]  # 140 total

EPIGENETIC_CLOCKS: list[str] = [
    "epigenetic_age_horvath",
    "epigenetic_age_phenoage",
    "epigenetic_age_grimage",
    "epigenetic_age_acceleration",
]



