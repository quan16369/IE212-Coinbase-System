#!/usr/bin/env bash
set -euo pipefail

GCP_PROJECT_ID="${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
GAR_LOCATION="${GAR_LOCATION:?GAR_LOCATION is required}"
GAR_REPOSITORY="${GAR_REPOSITORY:?GAR_REPOSITORY is required}"
LOCAL_IMAGE="${RAW_DATA_REPLAY_LOCAL_IMAGE:-coinbase-raw-data-replay:latest}"
IMAGE_NAME="${RAW_DATA_REPLAY_IMAGE_NAME:-coinbase-raw-data-replay}"
IMAGE_TAG="${IMAGE_TAG:-dev}"
REMOTE_IMAGE="${GAR_LOCATION}-docker.pkg.dev/${GCP_PROJECT_ID}/${GAR_REPOSITORY}/${IMAGE_NAME}:${IMAGE_TAG}"

docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE"
docker push "$REMOTE_IMAGE"
mkdir -p artifacts/data-streaming
printf '%s\n' "$REMOTE_IMAGE" > artifacts/data-streaming/raw_data_replay_image_uri.txt
echo "Pushed raw-data replay image: $REMOTE_IMAGE"
