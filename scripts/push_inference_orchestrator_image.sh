#!/usr/bin/env bash
set -euo pipefail

LOCAL_IMAGE="${INFERENCE_ORCHESTRATOR_LOCAL_IMAGE:-coinbase-inference-orchestrator:latest}"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GAR_LOCATION="${GAR_LOCATION:-}"
GAR_REPOSITORY="${GAR_REPOSITORY:-}"
IMAGE_NAME="${INFERENCE_ORCHESTRATOR_IMAGE_NAME:-coinbase-inference-orchestrator}"
IMAGE_TAG="${IMAGE_TAG:-dev}"

if [[ -z "$GCP_PROJECT_ID" || -z "$GAR_LOCATION" || -z "$GAR_REPOSITORY" ]]; then
  echo "GCP_PROJECT_ID, GAR_LOCATION, and GAR_REPOSITORY are required."
  exit 1
fi

REMOTE_IMAGE="${GAR_LOCATION}-docker.pkg.dev/${GCP_PROJECT_ID}/${GAR_REPOSITORY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "Tagging ${LOCAL_IMAGE} as ${REMOTE_IMAGE}"
docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE"

echo "Pushing ${REMOTE_IMAGE}"
docker push "$REMOTE_IMAGE"

mkdir -p artifacts/inference-orchestrator
printf '%s\n' "$REMOTE_IMAGE" > artifacts/inference-orchestrator/inference_orchestrator_image_uri.txt
echo "Pushed inference orchestrator image: ${REMOTE_IMAGE}"
