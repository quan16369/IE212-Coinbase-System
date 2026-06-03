#!/usr/bin/env bash
set -euo pipefail

REQUIRED="${SBOM_REQUIRED:-false}"
IMAGE="${SBOM_IMAGE:-${BENTO_LOCAL_IMAGE:-coinbase_streaming-bento-price-predictor:latest}}"
FORMAT="${SBOM_FORMAT:-cyclonedx}"
OUTPUT="${SBOM_OUTPUT:-artifacts/security/bento-image-sbom.cdx.json}"

if ! command -v trivy >/dev/null 2>&1; then
  if [[ "$REQUIRED" == "true" ]]; then
    echo "trivy is required to generate an image SBOM."
    echo "Install it locally or rebuild the Jenkins image."
    exit 1
  fi

  echo "trivy not found; skipping image SBOM generation"
  exit 0
fi

mkdir -p "$(dirname "$OUTPUT")"

echo "Generating image SBOM"
echo "Image: $IMAGE"
echo "Format: $FORMAT"
echo "Output: $OUTPUT"

trivy image \
  --no-progress \
  --format "$FORMAT" \
  --output "$OUTPUT" \
  "$IMAGE"

test -s "$OUTPUT"
