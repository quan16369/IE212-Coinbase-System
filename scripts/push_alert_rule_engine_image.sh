#!/usr/bin/env bash
set -euo pipefail

LOCAL_IMAGE="${ALERT_RULE_ENGINE_LOCAL_IMAGE:-coinbase-alert-rule-engine:latest}"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GAR_LOCATION="${GAR_LOCATION:-}"
GAR_REPOSITORY="${GAR_REPOSITORY:-}"
IMAGE_NAME="${ALERT_RULE_ENGINE_IMAGE_NAME:-coinbase-alert-rule-engine}"
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

mkdir -p artifacts/alert-rule-engine
printf '%s\n' "$REMOTE_IMAGE" > artifacts/alert-rule-engine/alert_rule_engine_image_uri.txt
echo "Pushed alert rule engine image: ${REMOTE_IMAGE}"
