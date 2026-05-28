#!/usr/bin/env bash
set -euo pipefail

LOCAL_IMAGE="${BENTO_LOCAL_IMAGE:-coinbase_streaming-bento-price-predictor:latest}"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GAR_LOCATION="${GAR_LOCATION:-}"
GAR_REPOSITORY="${GAR_REPOSITORY:-}"
BENTO_IMAGE_NAME="${BENTO_IMAGE_NAME:-coinbase-bento-price-predictor}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

if [[ -z "$GCP_PROJECT_ID" || -z "$GAR_LOCATION" || -z "$GAR_REPOSITORY" ]]; then
  echo "GCP_PROJECT_ID, GAR_LOCATION, and GAR_REPOSITORY are required."
  echo "Example:"
  echo "  GCP_PROJECT_ID=my-project GAR_LOCATION=asia-southeast1 GAR_REPOSITORY=coinbase-mlops IMAGE_TAG=dev make mlops-push-bento"
  exit 1
fi

REGISTRY_HOST="${GAR_LOCATION}-docker.pkg.dev"
REMOTE_IMAGE="${REGISTRY_HOST}/${GCP_PROJECT_ID}/${GAR_REPOSITORY}/${BENTO_IMAGE_NAME}:${IMAGE_TAG}"

echo "Tagging ${LOCAL_IMAGE} as ${REMOTE_IMAGE}"
docker tag "${LOCAL_IMAGE}" "${REMOTE_IMAGE}"

echo "Pushing ${REMOTE_IMAGE}"
docker push "${REMOTE_IMAGE}"

mkdir -p artifacts/mlops
echo "${REMOTE_IMAGE}" > artifacts/mlops/bento_image_uri.txt
echo "Pushed BentoML image: ${REMOTE_IMAGE}"
