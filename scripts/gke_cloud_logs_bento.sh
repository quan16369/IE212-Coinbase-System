#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
CLUSTER_NAME="${GKE_CLUSTER:-coinbase-mlops}"
LOCATION="${GKE_REGION:-asia-southeast1}"
NAMESPACE="${K8S_NAMESPACE:-app}"
CONTAINER="${BENTO_CONTAINER:-bento-price-predictor}"
LIMIT="${LIMIT:-20}"
FRESHNESS="${FRESHNESS:-2h}"

if [[ -z "$PROJECT_ID" ]]; then
  echo "GCP project is required. Set GCP_PROJECT_ID or run: gcloud config set project <project-id>"
  exit 1
fi

FILTER='resource.type="k8s_container"'
FILTER="$FILTER AND resource.labels.project_id=\"$PROJECT_ID\""
FILTER="$FILTER AND resource.labels.cluster_name=\"$CLUSTER_NAME\""
FILTER="$FILTER AND resource.labels.location=\"$LOCATION\""
FILTER="$FILTER AND resource.labels.namespace_name=\"$NAMESPACE\""
FILTER="$FILTER AND resource.labels.container_name=\"$CONTAINER\""

echo "Reading Cloud Logging entries for $NAMESPACE/$CONTAINER in $CLUSTER_NAME ($LOCATION)."
echo

gcloud logging read "$FILTER" \
  --project "$PROJECT_ID" \
  --freshness "$FRESHNESS" \
  --limit "$LIMIT" \
  --order desc \
  --format 'table(timestamp,severity,resource.labels.pod_name,textPayload)'
