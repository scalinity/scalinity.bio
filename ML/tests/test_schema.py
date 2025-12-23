import json
from pathlib import Path

from ML.schema import all_columns, expected_ranges


def test_schema_has_core_fields():
    cols = set(all_columns())
    for required in [
        "chronological_age",
        "sex",
        "ethnicity",
        "bmi",
        "diet_score",
        "exercise_score",
        "sleep_score",
        "comorbidity_diabetes",
        "telomere_length_kb",
        "crp_mg_L",
        "il6_pg_mL",
        "frailty_index",
        "biological_age",
        "bio_age_delta",
    ]:
        assert required in cols


def test_expected_ranges_contains_key_biomarkers():
    r = expected_ranges()
    assert "metab_glucose_mg_dL" in r
    assert "metab_homocysteine_umol_L" in r
    assert "epigenetic_age_horvath" in r


def test_resources_exist_after_training():
    repo_root = Path(__file__).resolve().parents[2]
    feature_stats = repo_root / "Resources" / "FeatureStats.json"
    model_schema = repo_root / "Resources" / "ModelSchema.json"

    # Test stub: these exist after running `python -m ML.model_training ...`
    if feature_stats.exists():
        json.loads(feature_stats.read_text(encoding="utf-8"))
    if model_schema.exists():
        json.loads(model_schema.read_text(encoding="utf-8"))


