#!/usr/bin/env bash
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${GAR_LOCATION:?GAR_LOCATION is required}"
: "${GAR_REPOSITORY:?GAR_REPOSITORY is required}"

IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD)}"
LOCAL_IMAGE="${MODEL_TRAINING_LOCAL_IMAGE:-coinbase-model-training:latest}"
REMOTE_IMAGE="$GAR_LOCATION-docker.pkg.dev/$GCP_PROJECT_ID/$GAR_REPOSITORY/coinbase-model-training:$IMAGE_TAG"
docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE"
docker push "$REMOTE_IMAGE"
mkdir -p artifacts/model-training
printf '%s\n' "$REMOTE_IMAGE" > artifacts/model-training/training_image_uri.txt
echo "Pushed model training image: $REMOTE_IMAGE"
