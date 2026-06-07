#!/usr/bin/env bash
set -euo pipefail

GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GAR_LOCATION="${GAR_LOCATION:-}"
GAR_REPOSITORY="${GAR_REPOSITORY:-}"
LOCAL_IMAGE="${KAFKA_PRODUCER_LOCAL_IMAGE:-coinbase-kafka-producer:latest}"
IMAGE_NAME="${KAFKA_PRODUCER_IMAGE_NAME:-coinbase-kafka-producer}"
IMAGE_TAG="${IMAGE_TAG:-dev}"
OUTPUT_FILE="${KAFKA_PRODUCER_IMAGE_URI_FILE:-artifacts/data-streaming/kafka_producer_image_uri.txt}"

if [[ -z "$GCP_PROJECT_ID" || -z "$GAR_LOCATION" || -z "$GAR_REPOSITORY" ]]; then
  echo "GCP_PROJECT_ID, GAR_LOCATION, and GAR_REPOSITORY are required."
  exit 1
fi

REMOTE_IMAGE="${GAR_LOCATION}-docker.pkg.dev/${GCP_PROJECT_ID}/${GAR_REPOSITORY}/${IMAGE_NAME}:${IMAGE_TAG}"
mkdir -p "$(dirname "$OUTPUT_FILE")"
docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE"
docker push "$REMOTE_IMAGE"
printf '%s\n' "$REMOTE_IMAGE" >"$OUTPUT_FILE"
echo "Pushed Kafka producer image: $REMOTE_IMAGE"
