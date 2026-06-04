#!/usr/bin/env bash
set -euo pipefail

REQUIRED="${TRIVY_REQUIRED:-false}"
IMAGE="${TRIVY_IMAGE:-${BENTO_LOCAL_IMAGE:-coinbase_streaming-bento-price-predictor:latest}}"
SEVERITY="${TRIVY_SEVERITY:-HIGH,CRITICAL}"
EXIT_CODE="${TRIVY_EXIT_CODE:-0}"
SCANNERS="${TRIVY_SCANNERS:-vuln,secret}"
OUTPUT="${TRIVY_OUTPUT:-artifacts/security/trivy-image-scan.txt}"
IGNORE_UNFIXED="${TRIVY_IGNORE_UNFIXED:-true}"

if ! command -v trivy >/dev/null 2>&1; then
  if [[ "$REQUIRED" == "true" ]]; then
    echo "trivy is required but not installed."
    echo "Install it locally or rebuild the Jenkins image."
    exit 1
  fi

  echo "trivy not found; skipping image vulnerability scan"
  exit 0
fi

mkdir -p "$(dirname "$OUTPUT")"

echo "Running Trivy image scan"
echo "Image: $IMAGE"
echo "Severity: $SEVERITY"
echo "Scanners: $SCANNERS"
echo "Exit code on findings: $EXIT_CODE"
echo "Ignore unfixed vulnerabilities: $IGNORE_UNFIXED"

TRIVY_ARGS=()
if [[ "$IGNORE_UNFIXED" == "true" ]]; then
  TRIVY_ARGS+=(--ignore-unfixed)
fi

trivy image \
  --no-progress \
  "${TRIVY_ARGS[@]}" \
  --scanners "$SCANNERS" \
  --severity "$SEVERITY" \
  --exit-code "$EXIT_CODE" \
  "$IMAGE" | tee "$OUTPUT"
