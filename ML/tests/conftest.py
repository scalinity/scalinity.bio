import sys
from pathlib import Path

# Ensure repo root is importable so `import ML.*` works without installing a wheel.
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))


