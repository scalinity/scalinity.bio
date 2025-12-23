from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class PublicSeedPaths:
    gtex_expression_seed_csv: Path
    tcga_clinical_seed_csv: Path


def default_seed_paths(repo_root: Path) -> PublicSeedPaths:
    return PublicSeedPaths(
        gtex_expression_seed_csv=repo_root / "Data" / "public_seeds" / "gtex_expression_seed.csv",
        tcga_clinical_seed_csv=repo_root / "Data" / "public_seeds" / "tcga_clinical_seed.csv",
    )


def write_csv(path: Path, rows: Iterable[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in rows:
            w.writerow(r)


def download_url(url: str, dest: Path, timeout_s: int = 60) -> None:
    """
    Download a small public CSV/TSV file.

    This is intentionally generic: public multi-omics sources frequently change URLs.
    """
    try:
        import requests  # type: ignore
    except Exception as e:  # pragma: no cover
        raise RuntimeError(
            "requests is required to download seed data. Install it via `pip install requests`."
        ) from e

    dest.parent.mkdir(parents=True, exist_ok=True)
    resp = requests.get(url, timeout=timeout_s)
    resp.raise_for_status()
    dest.write_bytes(resp.content)


def seeds_present(paths: PublicSeedPaths) -> bool:
    return paths.gtex_expression_seed_csv.exists() or paths.tcga_clinical_seed_csv.exists()


