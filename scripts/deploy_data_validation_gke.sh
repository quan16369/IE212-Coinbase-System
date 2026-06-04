#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
NAMESPACE="${DATA_INGESTION_NAMESPACE:-data-ingestion}"
IMAGE_URI="${IMAGE_URI:-}"
HELM_RELEASE="${DATA_VALIDATION_HELM_RELEASE:-data-validation}"
HELM_CHART="${DATA_VALIDATION_HELM_CHART:-charts/data-validation}"
REPLICA_COUNT="${DATA_VALIDATION_REPLICA_COUNT:-}"
NETWORK_POLICY_ENABLED="${DATA_VALIDATION_NETWORK_POLICY_ENABLED:-}"
PDB_ENABLED="${DATA_VALIDATION_PDB_ENABLED:-}"
AUTOSCALING_ENABLED="${DATA_VALIDATION_AUTOSCALING_ENABLED:-}"
VALIDATED_TARGET="${DATA_VALIDATION_VALIDATED_TARGET:-}"
QUALITY_TARGET="${DATA_VALIDATION_QUALITY_TARGET:-}"
TELEMETRY_PRODUCER_ENABLED="${DATA_VALIDATION_TELEMETRY_PRODUCER_ENABLED:-}"
TELEMETRY_PRODUCER_SCHEDULE="${DATA_VALIDATION_TELEMETRY_PRODUCER_SCHEDULE:-}"
FEATURE_PLATFORM_ENABLED="${DATA_VALIDATION_FEATURE_PLATFORM_ENABLED:-}"
FEATURE_PLATFORM_URL="${DATA_VALIDATION_FEATURE_PLATFORM_URL:-}"
HELM_TIMEOUT="${HELM_TIMEOUT:-300s}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "./$ENV_FILE"
  set +a
fi

if [[ -z "$IMAGE_URI" && -f artifacts/data-ingestion/validation_image_uri.txt ]]; then
  IMAGE_URI="$(cat artifacts/data-ingestion/validation_image_uri.txt)"
fi

if [[ -z "$IMAGE_URI" ]]; then
  echo "IMAGE_URI is required."
  echo "Push the validation image first, or set IMAGE_URI explicitly."
  exit 1
fi

IMAGE_REPOSITORY="${IMAGE_URI%:*}"
IMAGE_TAG="${IMAGE_URI##*:}"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

HELM_ARGS=(
  --namespace "$NAMESPACE"
  --create-namespace
  --atomic
  --timeout "$HELM_TIMEOUT"
  --history-max 10
  --set namespace="$NAMESPACE"
  --set image.repository="$IMAGE_REPOSITORY"
  --set image.tag="$IMAGE_TAG"
)

if [[ -n "$REPLICA_COUNT" ]]; then
  HELM_ARGS+=(--set replicaCount="$REPLICA_COUNT")
fi

if [[ -n "$NETWORK_POLICY_ENABLED" ]]; then
  HELM_ARGS+=(--set networkPolicy.enabled="$NETWORK_POLICY_ENABLED")
fi

if [[ -n "$PDB_ENABLED" ]]; then
  HELM_ARGS+=(--set podDisruptionBudget.enabled="$PDB_ENABLED")
fi

if [[ -n "$AUTOSCALING_ENABLED" ]]; then
  HELM_ARGS+=(--set autoscaling.enabled="$AUTOSCALING_ENABLED")
fi

if [[ -n "$VALIDATED_TARGET" ]]; then
  HELM_ARGS+=(--set routing.validatedTarget="$VALIDATED_TARGET")
fi

if [[ -n "$QUALITY_TARGET" ]]; then
  HELM_ARGS+=(--set routing.qualityTarget="$QUALITY_TARGET")
fi

if [[ -n "$TELEMETRY_PRODUCER_ENABLED" ]]; then
  HELM_ARGS+=(--set telemetryProducer.enabled="$TELEMETRY_PRODUCER_ENABLED")
fi

if [[ -n "$TELEMETRY_PRODUCER_SCHEDULE" ]]; then
  HELM_ARGS+=(--set telemetryProducer.schedule="$TELEMETRY_PRODUCER_SCHEDULE")
fi

if [[ -n "$FEATURE_PLATFORM_ENABLED" ]]; then
  HELM_ARGS+=(--set telemetryProducer.featurePlatform.enabled="$FEATURE_PLATFORM_ENABLED")
fi

if [[ -n "$FEATURE_PLATFORM_URL" ]]; then
  HELM_ARGS+=(--set telemetryProducer.featurePlatform.url="$FEATURE_PLATFORM_URL")
fi

helm upgrade --install "$HELM_RELEASE" "$HELM_CHART" "${HELM_ARGS[@]}"
kubectl -n "$NAMESPACE" rollout status deployment/"$HELM_RELEASE" --timeout=180s

echo "Deployed data validation image: $IMAGE_URI"
echo "Namespace: $NAMESPACE"
echo "Validated target: ${VALIDATED_TARGET:-chart default}"
echo "Quality target: ${QUALITY_TARGET:-chart default}"
echo "NetworkPolicy enabled: ${NETWORK_POLICY_ENABLED:-chart default}"
echo "Telemetry producer enabled: ${TELEMETRY_PRODUCER_ENABLED:-chart default}"
echo "Feature platform forwarding enabled: ${FEATURE_PLATFORM_ENABLED:-chart default}"
echo "Test locally with:"
echo "  kubectl -n $NAMESPACE port-forward svc/data-validation 8089:80"
