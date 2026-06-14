#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
DEPLOY_SERVICES="${DEPLOY_SERVICES:-false}"
INSTALL_OBSERVABILITY="${INSTALL_OBSERVABILITY:-false}"
ENABLE_PUBLIC_INGRESS="${ENABLE_PUBLIC_INGRESS:-false}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "./$ENV_FILE"
  set +a
fi

GCP_PROJECT_ID="${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
GKE_CLUSTER="${GKE_CLUSTER:-coinbase-mlops}"
GKE_REGION="${GKE_REGION:-${GAR_LOCATION:-asia-southeast1}}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD)}"
GAR_LOCATION="${GAR_LOCATION:-$GKE_REGION}"
GAR_REPOSITORY="${GAR_REPOSITORY:-coinbase-mlops}"

terraform -chdir=infra/terraform init
STATE_LIST="$(terraform -chdir=infra/terraform state list 2>/dev/null || true)"

if ! grep -qx "google_artifact_registry_repository.mlops" <<<"$STATE_LIST"; then
  if gcloud artifacts repositories describe "$GAR_REPOSITORY" \
    --project="$GCP_PROJECT_ID" \
    --location="$GAR_LOCATION" >/dev/null 2>&1; then
    echo "Importing existing Artifact Registry repository into Terraform state."
    terraform -chdir=infra/terraform import google_artifact_registry_repository.mlops \
      "projects/$GCP_PROJECT_ID/locations/$GAR_LOCATION/repositories/$GAR_REPOSITORY"
  fi
fi

if ! grep -qx "google_container_cluster.mlops" <<<"$STATE_LIST"; then
  if gcloud container clusters describe "$GKE_CLUSTER" \
    --project="$GCP_PROJECT_ID" \
    --region="$GKE_REGION" >/dev/null 2>&1; then
    echo "Importing existing GKE cluster into Terraform state."
    terraform -chdir=infra/terraform import google_container_cluster.mlops \
      "projects/$GCP_PROJECT_ID/locations/$GKE_REGION/clusters/$GKE_CLUSTER"
  fi
fi

terraform -chdir=infra/terraform apply -auto-approve
gcloud config set project "$GCP_PROJECT_ID"
gcloud container clusters get-credentials "$GKE_CLUSTER" --region="$GKE_REGION"
gcloud auth configure-docker "${GAR_LOCATION}-docker.pkg.dev" --quiet

if [[ "$DEPLOY_SERVICES" != "true" ]]; then
  echo "GKE infrastructure is ready. Run DEPLOY_SERVICES=true make gke-workday-start to rebuild and deploy the application stack."
  exit 0
fi

make streaming-platform-build raw-data-sink-build raw-data-replay-build
make data-validation-build feature-platform-build model-training-build inference-orchestrator-build
COMPOSE_PROFILES=mlops docker compose --env-file "$ENV_FILE" build bento-price-predictor

IMAGE_TAG="$IMAGE_TAG" make streaming-platform-push raw-data-sink-push raw-data-replay-push
IMAGE_TAG="$IMAGE_TAG" make data-validation-push feature-platform-push model-training-push inference-orchestrator-push mlops-push-bento

RAW_DATA_BUCKET="${RAW_DATA_BUCKET:-$(terraform -chdir=infra/terraform output -raw raw_data_bucket_name)}"
RAW_DATA_SINK_GCP_SERVICE_ACCOUNT="${RAW_DATA_SINK_GCP_SERVICE_ACCOUNT:-$(terraform -chdir=infra/terraform output -raw raw_data_sink_service_account_email)}"
RAW_DATA_REPLAY_GCP_SERVICE_ACCOUNT="${RAW_DATA_REPLAY_GCP_SERVICE_ACCOUNT:-$(terraform -chdir=infra/terraform output -raw raw_data_replay_service_account_email)}"

RAW_DATA_SINK_ENABLED=true \
RAW_DATA_REPLAY_ENABLED=true \
RAW_DATA_BUCKET="$RAW_DATA_BUCKET" \
RAW_DATA_SINK_GCP_SERVICE_ACCOUNT="$RAW_DATA_SINK_GCP_SERVICE_ACCOUNT" \
RAW_DATA_REPLAY_GCP_SERVICE_ACCOUNT="$RAW_DATA_REPLAY_GCP_SERVICE_ACCOUNT" \
RAW_DATA_REPLAY_ID="${RAW_DATA_REPLAY_ID:-recovery-default}" \
  make streaming-platform-deploy
make feature-platform-deploy data-validation-deploy model-training-deploy
RUN_FULL_E2E_AFTER_DEPLOY=false make gke-deploy-bento-safe
if [[ "$ENABLE_PUBLIC_INGRESS" == "true" ]]; then
  make gke-install-ingress-nginx
  INFERENCE_ORCHESTRATOR_INGRESS_ENABLED=true make inference-orchestrator-deploy
else
  make inference-orchestrator-deploy
fi

if [[ "$INSTALL_OBSERVABILITY" == "true" ]]; then
  make gke-install-monitoring gke-install-logging gke-install-tracing
fi

kubectl get pods -A
RUN_REPLAY_CHECK=false make production-e2e-smoke
