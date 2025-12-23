## Public seed data (optional)

The simulator can *optionally* read small public seed tables to calibrate distributions.

This folder is intentionally empty by default (so the repo stays lightweight). If you
have downloaded public summary tables, place them here using these filenames:

- `gtex_expression_seed.csv`
  - Columns: `gene`, `median_tpm` (or `median_log2_tpm1p`)
- `tcga_clinical_seed.csv`
  - Columns: `age_at_diagnosis`, `sex`, `bmi` (optional)

If these files are missing, the simulator falls back to curated biological ranges +
correlated latent factors (still realistic, but not sampled from raw public cohorts).



