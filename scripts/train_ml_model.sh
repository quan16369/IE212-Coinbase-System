#!/usr/bin/env bash
set -euo pipefail

DATA_PATH="${1:-${DATA:-${MLOPS_TRAINING_CSV:-}}}"
OUTPUT_PATH="${MLOPS_MODEL_OUTPUT:-artifacts/mlops/coinbase_ml_model.joblib}"
PYTHON_BIN="${PYTHON:-}"

if [[ -z "$PYTHON_BIN" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    echo "python or python3 is required to train the model."
    exit 1
  fi
fi

if [[ -z "$DATA_PATH" ]]; then
  echo "Usage: DATA=/path/to/ohlcv.csv make mlops-train"
  echo "or:   bash scripts/train_ml_model.sh /path/to/ohlcv.csv"
  exit 1
fi

if [[ ! -f "$DATA_PATH" ]]; then
  echo "Training data not found: $DATA_PATH"
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
"$PYTHON_BIN" -m mlops.train --data "$DATA_PATH" --output "$OUTPUT_PATH"
