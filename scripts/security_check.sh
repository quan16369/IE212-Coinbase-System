#!/usr/bin/env bash
set -euo pipefail

REQUIRED="${CHECKOV_REQUIRED:-false}"
TARGETS=(
  "infra/terraform"
  "charts"
  "k8s"
)

if ! command -v checkov >/dev/null 2>&1; then
  if [[ "$REQUIRED" == "true" ]]; then
    echo "checkov is required but not installed."
    echo "Install it with: python3 -m pip install --user checkov"
    exit 1
  fi

  echo "checkov not found; skipping IaC security checks"
  exit 0
fi

for target in "${TARGETS[@]}"; do
  if [[ -d "$target" ]]; then
    echo "Running Checkov on $target"
    checkov -d "$target"
  fi
done
