from __future__ import annotations

import argparse
import json
from pathlib import Path

import coremltools as ct


def main() -> None:
    p = argparse.ArgumentParser(description="Export trained model artifacts to a CoreML .mlmodel file.")
    p.add_argument("--artifacts", required=True, help="Path to ML artifacts directory (from model_training.py)")
    p.add_argument("--out", required=True, help="Output model path (.mlmodel or .mlmodeldata)")
    p.add_argument("--target", default="biological_age", help="Output name in the CoreML model")
    args = p.parse_args()

    artifacts_dir = Path(args.artifacts)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    feature_list_path = artifacts_dir / "feature_list.json"
    preproc_path = artifacts_dir / "preprocessor.json"
    xgb_path = artifacts_dir / "xgboost_model.json"

    if not feature_list_path.exists():
        raise FileNotFoundError(f"Missing feature list: {feature_list_path}")
    if not preproc_path.exists():
        raise FileNotFoundError(f"Missing preprocessor artifact: {preproc_path}")
    if not xgb_path.exists():
        raise FileNotFoundError(
            f"Missing xgboost model artifact: {xgb_path}. "
            "This exporter currently supports the xgboost path because coremltools sklearn export "
            "is version-constrained."
        )

    feature_names = json.loads(feature_list_path.read_text(encoding="utf-8"))

    import xgboost as xgb

    booster = xgb.Booster()
    booster.load_model(str(xgb_path))
    booster.feature_names = list(feature_names)

    # Convert
    mlmodel = ct.converters.xgboost.convert(
        booster,
        feature_names=list(feature_names),
        target=args.target,
    )

    # Metadata
    mlmodel.short_description = "scalinity.bio Biological Age Regressor"
    mlmodel.author = "scalinity.bio"
    mlmodel.license = "Internal use"
    mlmodel.version = "1.0"

    # Save
    # - If the user requests `.mlmodeldata`, write a `.mlmodel` temp file and then rename.
    if out_path.suffix == ".mlmodeldata":
        tmp_mlmodel = out_path.with_suffix(".mlmodel")
        mlmodel.save(str(tmp_mlmodel))
        if out_path.exists():
            out_path.unlink()
        tmp_mlmodel.rename(out_path)
    else:
        mlmodel.save(str(out_path))
    print(f"Wrote CoreML model: {out_path}")


if __name__ == "__main__":
    main()


