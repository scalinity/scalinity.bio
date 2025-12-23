import pandas as pd

from ML.data_simulation import generate_synthetic_cohort


def test_simulation_meets_diversity_constraints():
    df, meta = generate_synthetic_cohort(n=600, seed=123, missing_rate=0.0)
    assert len(df) == 600
    assert meta["validation_summary"]["warning_count"] == 0

    female = (df["sex"] == "female").mean()
    assert 0.30 <= female <= 0.50

    eth_counts = df["ethnicity"].value_counts().to_dict()
    # balanced: all four should be close for n=600
    assert len(eth_counts) == 4
    assert max(eth_counts.values()) - min(eth_counts.values()) <= 5

    diabetes = df["comorbidity_diabetes"].mean()
    assert 0.15 <= diabetes <= 0.25

    assert df["chronological_age"].min() >= 30
    assert df["chronological_age"].max() <= 80


def test_simulation_can_write_csv(tmp_path):
    df, _ = generate_synthetic_cohort(n=200, seed=1, missing_rate=0.01)
    out = tmp_path / "cohort.csv"
    df.to_csv(out, index=False)
    df2 = pd.read_csv(out)
    assert len(df2) == 200


