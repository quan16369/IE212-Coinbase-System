#!/usr/bin/env bash
set -euo pipefail

GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GAR_LOCATION="${GAR_LOCATION:-}"
GAR_REPOSITORY="${GAR_REPOSITORY:-}"
LOCAL_IMAGE="${FEATURE_PLATFORM_LOCAL_IMAGE:-coinbase-feature-platform:latest}"
IMAGE_NAME="${FEATURE_PLATFORM_IMAGE_NAME:-coinbase-feature-platform}"
IMAGE_TAG="${IMAGE_TAG:-dev}"
OUTPUT_FILE="${FEATURE_PLATFORM_IMAGE_URI_FILE:-artifacts/feature-platform/feature_platform_image_uri.txt}"

if [[ -z "$GCP_PROJECT_ID" || -z "$GAR_LOCATION" || -z "$GAR_REPOSITORY" ]]; then
  echo "GCP_PROJECT_ID, GAR_LOCATION, and GAR_REPOSITORY are required."
  echo "Example:"
  echo "  GCP_PROJECT_ID=my-project GAR_LOCATION=asia-southeast1 GAR_REPOSITORY=coinbase-mlops IMAGE_TAG=dev make feature-platform-push"
  exit 1
fi

REMOTE_IMAGE="${GAR_LOCATION}-docker.pkg.dev/${GCP_PROJECT_ID}/${GAR_REPOSITORY}/${IMAGE_NAME}:${IMAGE_TAG}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "Tagging $LOCAL_IMAGE as $REMOTE_IMAGE"
docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE"

echo "Pushing $REMOTE_IMAGE"
docker push "$REMOTE_IMAGE"

printf '%s\n' "$REMOTE_IMAGE" >"$OUTPUT_FILE"
echo "Pushed feature platform image: $REMOTE_IMAGE"
