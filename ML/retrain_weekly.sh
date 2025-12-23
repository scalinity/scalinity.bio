#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "[scalinity.bio] Weekly retrain starting in: $ROOT_DIR"

if [[ ! -d ".venv" ]]; then
  echo "[scalinity.bio] Creating venv..."
  python3 -m venv .venv
fi

source .venv/bin/activate

echo "[scalinity.bio] Installing/updating dependencies..."
python -m pip install --upgrade pip
pip install -r requirements.txt

echo "[scalinity.bio] Regenerating cohort (optional)..."
python -m ML.data_simulation --out Data/synthetic_cohort.csv --n 1200 --report-out ML/artifacts/simulation_report.json

echo "[scalinity.bio] Training model..."
python -m ML.model_training --data Data/synthetic_cohort.csv --outdir ML/artifacts

echo "[scalinity.bio] Exporting CoreML model..."
python -m ML.coreml_export --artifacts ML/artifacts --out Resources/Models/BioAgeRegressor.mlmodeldata --target biological_age

echo "[scalinity.bio] Done."


