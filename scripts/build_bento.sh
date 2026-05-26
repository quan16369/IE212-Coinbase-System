#!/usr/bin/env bash
set -euo pipefail

if ! command -v bentoml >/dev/null 2>&1; then
  echo "bentoml is not installed. Install mlops requirements first:"
  echo "pip install -r mlops/requirements.txt"
  exit 1
fi

bentoml build -f mlops/bentofile.yaml .
