from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
from sklearn.impute import KNNImputer
from sklearn.metrics import mean_absolute_error, mean_squared_error
from sklearn.model_selection import KFold

from .constants import ETHNICITIES
from .schema import SCHEMA

try:
    from sklearn.ensemble import RandomForestRegressor

    _SKLEARN_RF_OK = True
except Exception:  # pragma: no cover
    _SKLEARN_RF_OK = False

try:
    import xgboost as xgb

    _XGB_OK = True
except Exception:  # pragma: no cover
    _XGB_OK = False


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _winsor_bounds(series: pd.Series, p_low: float = 0.01, p_high: float = 0.99) -> tuple[float, float]:
    s = series.dropna().astype(float)
    if s.empty:
        return (0.0, 0.0)
    lo = float(s.quantile(p_low))
    hi = float(s.quantile(p_high))
    if not np.isfinite(lo) or not np.isfinite(hi):
        return (0.0, 0.0)
    if hi < lo:
        hi = lo
    return (lo, hi)


@dataclass
class PreprocessorStats:
    numeric_columns: list[str]
    categorical: dict[str, list[str]]
    winsor_p01_p99: dict[str, dict[str, float]]
    mean: dict[str, float]
    std: dict[str, float]
    feature_order: list[str]

    def to_json_dict(self) -> dict[str, Any]:
        return {
            "numeric_columns": self.numeric_columns,
            "categorical": self.categorical,
            "winsor_p01_p99": self.winsor_p01_p99,
            "mean": self.mean,
            "std": self.std,
            "feature_order": self.feature_order,
        }


class Preprocessor:
    """
    Preprocess tabular features into a model-ready numeric matrix.

    Steps:
    - Winsorize numeric columns at p01/p99
    - Standardize numeric columns using train mean/std
    - One-hot encode categorical (sex, ethnicity) with fixed categories
    - KNN impute missing values (k=5) on the full feature matrix
    """

    def __init__(self, *, k_neighbors: int = 5) -> None:
        self.k_neighbors = k_neighbors
        self.numeric_columns: list[str] = []
        self.categorical: dict[str, list[str]] = {"sex": ["female", "male"], "ethnicity": ETHNICITIES}
        self.winsor: dict[str, tuple[float, float]] = {}
        self.mean: dict[str, float] = {}
        self.std: dict[str, float] = {}
        self.feature_order: list[str] = []
        self._imputer: KNNImputer | None = None

    def fit(self, df: pd.DataFrame) -> "Preprocessor":
        df = df.copy()
        self._ensure_categoricals(df)

        # Identify numeric columns (everything except categoricals + labels)
        label_cols = {SCHEMA.biological_age, SCHEMA.bio_age_delta}
        self.numeric_columns = [
            c
            for c in df.columns
            if c not in {"sex", "ethnicity"} and c not in label_cols and pd.api.types.is_numeric_dtype(df[c])
        ]

        # Winsor bounds, then stats on winsorized values
        for c in self.numeric_columns:
            lo, hi = _winsor_bounds(df[c])
            self.winsor[c] = (lo, hi)
            clipped = df[c].astype(float).clip(lo, hi)
            mu = float(clipped.mean(skipna=True))
            sd = float(clipped.std(skipna=True))
            if not np.isfinite(sd) or sd == 0.0:
                sd = 1.0
            self.mean[c] = mu
            self.std[c] = sd

        X = self._build_matrix(df, fit=True)
        self._imputer = KNNImputer(n_neighbors=self.k_neighbors, weights="distance")
        self._imputer.fit(X)
        return self

    def transform(self, df: pd.DataFrame) -> np.ndarray:
        if self._imputer is None:
            raise RuntimeError("Preprocessor.transform called before fit().")
        df = df.copy()
        self._ensure_categoricals(df)
        X = self._build_matrix(df, fit=False)
        return self._imputer.transform(X)

    def stats(self) -> PreprocessorStats:
        winsor_json = {k: {"p01": float(v[0]), "p99": float(v[1])} for k, v in self.winsor.items()}
        return PreprocessorStats(
            numeric_columns=self.numeric_columns,
            categorical=self.categorical,
            winsor_p01_p99=winsor_json,
            mean={k: float(v) for k, v in self.mean.items()},
            std={k: float(v) for k, v in self.std.items()},
            feature_order=self.feature_order,
        )

    def _ensure_categoricals(self, df: pd.DataFrame) -> None:
        df["sex"] = df["sex"].astype("string").fillna("unknown")
        df["ethnicity"] = df["ethnicity"].astype("string").fillna("unknown")

    def _one_hot(self, df: pd.DataFrame) -> pd.DataFrame:
        # Force categories so column set is stable.
        sex_cat = pd.Categorical(df["sex"], categories=self.categorical["sex"])
        eth_cat = pd.Categorical(df["ethnicity"], categories=self.categorical["ethnicity"])
        sex_df = pd.get_dummies(sex_cat, prefix="sex", dtype=float)
        eth_df = pd.get_dummies(eth_cat, prefix="ethnicity", dtype=float)
        return pd.concat([sex_df, eth_df], axis=1)

    def _build_matrix(self, df: pd.DataFrame, *, fit: bool) -> np.ndarray:
        # Winsorize + standardize numeric
        num = df[self.numeric_columns].astype(float).copy()
        for c in self.numeric_columns:
            lo, hi = self.winsor.get(c, (None, None))
            if lo is not None and hi is not None:
                num[c] = num[c].clip(lo, hi)
            num[c] = (num[c] - self.mean.get(c, 0.0)) / self.std.get(c, 1.0)

        cat = self._one_hot(df)
        Xdf = pd.concat([num, cat], axis=1)

        if fit:
            self.feature_order = list(Xdf.columns)
        else:
            # Reindex to training order
            Xdf = Xdf.reindex(columns=self.feature_order, fill_value=0.0)

        return Xdf.to_numpy(dtype=float)


def _cv_evaluate_model(
    model_name: str,
    model_factory,
    df: pd.DataFrame,
    y: np.ndarray,
    *,
    seed: int,
) -> dict[str, Any]:
    kf = KFold(n_splits=5, shuffle=True, random_state=seed)
    fold_metrics: list[dict[str, float]] = []

    for fold, (tr_idx, va_idx) in enumerate(kf.split(df), start=1):
        tr = df.iloc[tr_idx].reset_index(drop=True)
        va = df.iloc[va_idx].reset_index(drop=True)

        pre = Preprocessor(k_neighbors=5).fit(tr)
        X_tr = pre.transform(tr)
        X_va = pre.transform(va)

        y_tr = y[tr_idx]
        y_va = y[va_idx]

        model = model_factory()
        model.fit(X_tr, y_tr)
        pred = model.predict(X_va)

        rmse = math.sqrt(mean_squared_error(y_va, pred))
        mae = mean_absolute_error(y_va, pred)
        fold_metrics.append({"rmse": float(rmse), "mae": float(mae)})

    mean_rmse = float(np.mean([m["rmse"] for m in fold_metrics]))
    mean_mae = float(np.mean([m["mae"] for m in fold_metrics]))
    return {
        "model": model_name,
        "folds": fold_metrics,
        "mean": {"rmse": mean_rmse, "mae": mean_mae},
    }


def main() -> None:
    p = argparse.ArgumentParser(description="Train biological-age model and write artifacts.")
    p.add_argument("--data", required=True, help="Path to synthetic cohort CSV")
    p.add_argument("--outdir", required=True, help="Directory to write ML artifacts")
    p.add_argument("--seed", type=int, default=1337, help="RNG seed")
    args = p.parse_args()

    data_path = Path(args.data)
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(data_path)
    if SCHEMA.biological_age not in df.columns:
        raise ValueError(f"Missing required target column: {SCHEMA.biological_age}")

    y = df[SCHEMA.biological_age].astype(float).to_numpy()

    # Drop labels from X dataframe; keep categoricals for one-hot.
    X_df = df.drop(columns=[c for c in [SCHEMA.biological_age, SCHEMA.bio_age_delta] if c in df.columns])

    results: list[dict[str, Any]] = []

    # RandomForest
    if _SKLEARN_RF_OK:
        def rf_factory():
            return RandomForestRegressor(
                n_estimators=500,
                random_state=args.seed,
                n_jobs=-1,
                max_depth=None,
                min_samples_leaf=2,
            )

        results.append(_cv_evaluate_model("random_forest", rf_factory, X_df, y, seed=args.seed))

    # XGBoost
    if _XGB_OK:
        def xgb_factory():
            return xgb.XGBRegressor(
                n_estimators=600,
                max_depth=4,
                learning_rate=0.05,
                subsample=0.85,
                colsample_bytree=0.85,
                reg_lambda=1.0,
                objective="reg:squarederror",
                random_state=args.seed,
                n_jobs=0,
            )

        results.append(_cv_evaluate_model("xgboost", xgb_factory, X_df, y, seed=args.seed))

    if not results:
        raise RuntimeError("No models could be trained (missing dependencies).")

    # Select best by RMSE, then MAE.
    results_sorted = sorted(results, key=lambda r: (r["mean"]["rmse"], r["mean"]["mae"]))
    selected = results_sorted[0]["model"]

    # Fit final preprocessor on full dataset
    pre = Preprocessor(k_neighbors=5).fit(X_df)
    X_all = pre.transform(X_df)
    feature_order = pre.feature_order

    # Train selected final model
    model_type: str
    model_artifact: dict[str, Any] = {"selected_model": selected}

    if selected == "xgboost" and _XGB_OK:
        model_type = "xgboost"
        final_model = xgb.XGBRegressor(
            n_estimators=800,
            max_depth=4,
            learning_rate=0.05,
            subsample=0.85,
            colsample_bytree=0.85,
            reg_lambda=1.0,
            objective="reg:squarederror",
            random_state=args.seed,
            n_jobs=0,
        )
        final_model.fit(X_all, y)
        booster = final_model.get_booster()
        booster.feature_names = list(feature_order)
        booster_path = outdir / "xgboost_model.json"
        booster.save_model(str(booster_path))
        model_artifact["xgboost_model"] = str(booster_path)
    elif selected == "random_forest" and _SKLEARN_RF_OK:
        model_type = "random_forest"
        final_model = RandomForestRegressor(
            n_estimators=800,
            random_state=args.seed,
            n_jobs=-1,
            max_depth=None,
            min_samples_leaf=2,
        )
        final_model.fit(X_all, y)
        # Save model via joblib
        import joblib  # type: ignore

        model_path = outdir / "random_forest.joblib"
        joblib.dump(final_model, model_path)
        model_artifact["random_forest_model"] = str(model_path)
    else:
        # Fallback: if selected isn't exportable, prefer xgboost when available.
        if _XGB_OK:
            model_type = "xgboost"
            final_model = xgb.XGBRegressor(
                n_estimators=800,
                max_depth=4,
                learning_rate=0.05,
                subsample=0.85,
                colsample_bytree=0.85,
                reg_lambda=1.0,
                objective="reg:squarederror",
                random_state=args.seed,
                n_jobs=0,
            )
            final_model.fit(X_all, y)
            booster = final_model.get_booster()
            booster.feature_names = list(feature_order)
            booster_path = outdir / "xgboost_model.json"
            booster.save_model(str(booster_path))
            model_artifact["xgboost_model"] = str(booster_path)
            model_artifact["selected_model"] = "xgboost"
            model_artifact["note"] = "Selected model was not available/exportable; fell back to xgboost."
        else:
            raise RuntimeError("Selected model not trainable in this environment.")

    # Write artifacts
    metrics_path = outdir / "metrics.json"
    metrics_payload = {
        "created_at": _utc_now_iso(),
        "target": SCHEMA.biological_age,
        "models": results,
        "selected": model_artifact["selected_model"],
        "model_type": model_type,
    }
    metrics_path.write_text(json.dumps(metrics_payload, indent=2), encoding="utf-8")

    (outdir / "feature_list.json").write_text(json.dumps(feature_order, indent=2), encoding="utf-8")
    (outdir / "preprocessor.json").write_text(json.dumps(pre.stats().to_json_dict(), indent=2), encoding="utf-8")

    # Also write app-consumable resources.
    repo_root = Path(__file__).resolve().parents[1]
    resources_dir = repo_root / "Resources"
    resources_dir.mkdir(parents=True, exist_ok=True)

    (resources_dir / "FeatureStats.json").write_text(json.dumps(pre.stats().to_json_dict(), indent=2), encoding="utf-8")
    (resources_dir / "ModelSchema.json").write_text(
        json.dumps(
            {
                "created_at": _utc_now_iso(),
                "target": SCHEMA.biological_age,
                "model_type": model_type,
                "feature_order": feature_order,
                "categorical": pre.stats().categorical,
                "notes": "Model expects winsorized+standardized numeric features plus one-hot categoricals; missing values imputed via KNN(k=5).",
            },
            indent=2,
        ),
        encoding="utf-8",
    )

    print(f"Wrote metrics: {metrics_path}")
    print(f"Wrote artifacts: {outdir}")
    print(f"Wrote app resources: {resources_dir / 'FeatureStats.json'} and {resources_dir / 'ModelSchema.json'}")


if __name__ == "__main__":
    main()


