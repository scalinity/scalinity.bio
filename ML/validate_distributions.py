from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from .schema import expected_ranges


@dataclass(frozen=True)
class ColumnReport:
    name: str
    missing: int
    min: float | None
    p01: float | None
    p50: float | None
    p99: float | None
    max: float | None
    out_of_range: int
    expected_min: float | None
    expected_max: float | None


def _quantile(series: pd.Series, q: float) -> float | None:
    if series.dropna().empty:
        return None
    return float(series.quantile(q))


def validate_dataframe(df: pd.DataFrame) -> dict[str, Any]:
    """
    Validate a cohort DataFrame against broad physiological ranges.

    Returns a JSON-serializable dict with per-column stats and warnings.
    """
    ranges = expected_ranges()
    reports: list[ColumnReport] = []
    warnings: list[str] = []

    for col in df.columns:
        s = df[col]
        missing = int(s.isna().sum())

        # Only validate numeric-ish columns.
        if pd.api.types.is_numeric_dtype(s):
            expected = ranges.get(col)
            expected_min = expected[0] if expected else None
            expected_max = expected[1] if expected else None

            numeric = s.astype(float)
            mn = float(np.nanmin(numeric)) if not np.isnan(numeric).all() else None
            mx = float(np.nanmax(numeric)) if not np.isnan(numeric).all() else None
            p01 = _quantile(numeric, 0.01)
            p50 = _quantile(numeric, 0.50)
            p99 = _quantile(numeric, 0.99)

            out_of_range = 0
            if expected:
                out_of_range = int(((numeric < expected[0]) | (numeric > expected[1])).sum())
                if out_of_range > max(5, int(0.01 * len(df))):
                    warnings.append(
                        f"{col}: {out_of_range} values outside expected range [{expected[0]}, {expected[1]}]"
                    )

            reports.append(
                ColumnReport(
                    name=col,
                    missing=missing,
                    min=mn,
                    p01=p01,
                    p50=p50,
                    p99=p99,
                    max=mx,
                    out_of_range=out_of_range,
                    expected_min=expected_min,
                    expected_max=expected_max,
                )
            )
        else:
            # Non-numeric: just record missing.
            reports.append(
                ColumnReport(
                    name=col,
                    missing=missing,
                    min=None,
                    p01=None,
                    p50=None,
                    p99=None,
                    max=None,
                    out_of_range=0,
                    expected_min=None,
                    expected_max=None,
                )
            )

    return {
        "rows": int(len(df)),
        "cols": int(df.shape[1]),
        "warnings": warnings,
        "columns": [asdict(r) for r in reports],
    }


def main() -> None:
    p = argparse.ArgumentParser(description="Validate a synthetic cohort CSV.")
    p.add_argument("--data", required=True, help="Path to cohort CSV")
    p.add_argument("--out", required=True, help="Path to write JSON report")
    args = p.parse_args()

    df = pd.read_csv(args.data)
    report = validate_dataframe(df)

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    if report["warnings"]:
        print("Validation warnings:")
        for w in report["warnings"]:
            print(f"- {w}")
    else:
        print("Validation OK (no warnings).")


if __name__ == "__main__":
    main()



