#!/usr/bin/env bash
set -euo pipefail

LOCAL_IMAGE="${ALERT_INDEX_LOCAL_IMAGE:-coinbase-alert-index:latest}"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GAR_LOCATION="${GAR_LOCATION:-}"
GAR_REPOSITORY="${GAR_REPOSITORY:-}"
IMAGE_NAME="${ALERT_INDEX_IMAGE_NAME:-coinbase-alert-index}"
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

mkdir -p artifacts/alert-index
printf '%s\n' "$REMOTE_IMAGE" > artifacts/alert-index/alert_index_image_uri.txt
echo "Pushed alert index image: ${REMOTE_IMAGE}"
