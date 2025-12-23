import pytest

from ML.data_simulation import generate_synthetic_cohort
from ML.model_training import Preprocessor
from ML.schema import SCHEMA


def test_preprocessor_shapes():
    df, _ = generate_synthetic_cohort(n=200, seed=7, missing_rate=0.05)
    y = df[SCHEMA.biological_age].astype(float).to_numpy()
    X_df = df.drop(columns=[SCHEMA.biological_age, SCHEMA.bio_age_delta])

    pre = Preprocessor(k_neighbors=5).fit(X_df)
    X = pre.transform(X_df)
    assert X.shape[0] == len(df)
    assert X.shape[1] == len(pre.feature_order)
    assert len(y) == len(df)


@pytest.mark.skip(reason="Full CV training is covered by integration runs; this is a stub placeholder.")
def test_model_training_script_smoke():
    pass



