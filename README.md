## scalinity.bio

Production-ready macOS SwiftUI app + Python ML pipeline to:
- Simulate a public-data-backed synthetic multiomic cohort (1,000+ individuals)
- Train a biological-age regressor and export to CoreML
- Run on-device inference and generate evidence-backed anti-aging regimens (RAG + OpenRouter)

### Requirements

- **macOS**: 13+ (Ventura)
- **Xcode**: 15+ recommended (Swift 5.9)
- **Python**: 3.11+ recommended for the ML pipeline

### Environment variables

Cursor blocks `.env*` files in this workspace, so use `ENV.example` as your template and export vars in your shell (or set in Xcode scheme env).

Required:

```bash
export OPENROUTER_API_KEY="..."
export ENTREZ_API_KEY="..."
export DATABASE_ENCRYPTION_KEY="..."   # 32+ chars; see App/Services/EnvironmentConfig.swift
```

### Quick start (ML)

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Optional realism extras (BioPython + RDKit):
# pip install -r requirements-optional.txt

# Generate a 1k+ synthetic cohort:
python -m ML.data_simulation --out Data/synthetic_cohort.csv --n 1200

# Train + export CoreML:
python -m ML.model_training --data Data/synthetic_cohort.csv --outdir ML/artifacts
python -m ML.coreml_export --artifacts ML/artifacts --out Resources/Models/BioAgeRegressor.mlmodeldata --target bio_age_delta
```

### Tests

```bash
# Python
source .venv/bin/activate
pytest -q

# Swift
swift test
```

### Quick start (macOS app)

Open the repo in Xcode (File → Open… → select the folder). Run the executable product `scalinity.bio`.

The app reads:
- `Data/synthetic_cohort.csv` for reference distributions and KNN imputation
- `Resources/FeatureStats.json` and `Resources/ModelSchema.json` for preprocessing
- `Resources/Models/BioAgeRegressor.mlmodeldata` for inference (compiled at runtime)

### Privacy model (high level)

- All stored data is written to a local **SQLite** DB, with **payload encryption** (AES-GCM via CryptoKit).
- Any identifiers are hashed (SHA-256 with per-install salt).
- Any analytics used for retraining requires explicit consent (see Settings → Privacy).

### Weekly retraining (optional)

There are two supported options:

- **Manual**: run:

```bash
./ML/retrain_weekly.sh
```

- **Scheduled (launchd)**:
  - Edit `[ML/launchd/com.scalinitybio.retrain.plist](ML/launchd/com.scalinitybio.retrain.plist)` and replace the placeholder path with your absolute repo path.
  - Load it:

```bash
launchctl bootstrap gui/$(id -u) ML/launchd/com.scalinitybio.retrain.plist
launchctl list | grep com.scalinitybio.retrain
```



