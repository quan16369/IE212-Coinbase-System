from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
from typing import Any


DEFAULT_OUTPUT = "artifacts/mlops/data_version_manifest.json"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_sha() -> str:
    try:
        return subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    except Exception:
        return "unknown"


def csv_profile(path: Path) -> dict[str, Any]:
    row_count = 0
    first_timestamp = None
    last_timestamp = None
    columns: list[str] = []
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        columns = list(reader.fieldnames or [])
        for row in reader:
            row_count += 1
            timestamp = row.get("timestamp") or row.get("time") or row.get("date")
            if timestamp:
                first_timestamp = first_timestamp or timestamp
                last_timestamp = timestamp
    return {
        "rows": row_count,
        "columns": columns,
        "first_timestamp": first_timestamp,
        "last_timestamp": last_timestamp,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a reproducible data/model version manifest.")
    parser.add_argument("--data", default=os.environ.get("DATA") or os.environ.get("MLOPS_TRAINING_CSV"))
    parser.add_argument("--model", default=os.environ.get("MLOPS_MODEL_OUTPUT", "artifacts/mlops/coinbase_ml_model.joblib"))
    parser.add_argument("--output", default=os.environ.get("MLOPS_VERSION_MANIFEST", DEFAULT_OUTPUT))
    parser.add_argument("--data-version", default=os.environ.get("FEATURE_DATA_VERSION"))
    args = parser.parse_args()

    if not args.data:
        raise SystemExit("Missing data path. Use DATA=/path/to/file.csv make mlops-version-manifest.")

    data_path = Path(args.data)
    if not data_path.exists():
        raise SystemExit(f"Data file not found: {data_path}")

    model_path = Path(args.model)
    data_hash = sha256_file(data_path)
    manifest = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "git_sha": git_sha(),
        "data": {
            "path": str(data_path.resolve()),
            "sha256": data_hash,
            "version": args.data_version or data_hash[:12],
            **csv_profile(data_path),
        },
        "model": {
            "path": str(model_path.resolve()),
            "exists": model_path.exists(),
            "sha256": sha256_file(model_path) if model_path.exists() else None,
        },
    }

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
