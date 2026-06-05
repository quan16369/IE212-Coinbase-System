#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "./$ENV_FILE"
  set +a
fi

NAMESPACE="${K8S_NAMESPACE:-app}"
IMAGE_URI="${IMAGE_URI:-}"
HELM_RELEASE="${HELM_RELEASE:-bento-price-predictor}"
HELM_CHART="${HELM_CHART:-charts/bento-price-predictor}"
SERVICE_TYPE="${BENTO_SERVICE_TYPE:-}"
INGRESS_ENABLED="${BENTO_INGRESS_ENABLED:-}"
INGRESS_CLASS="${BENTO_INGRESS_CLASS:-}"
INGRESS_HOST="${BENTO_INGRESS_HOST:-}"
INGRESS_PATH="${BENTO_INGRESS_PATH:-}"
TRACING_ENABLED="${BENTO_TRACING_ENABLED:-}"
TRACING_OTLP_ENDPOINT="${BENTO_TRACING_OTLP_ENDPOINT:-}"
REPLICA_COUNT="${BENTO_REPLICA_COUNT:-}"
NETWORK_POLICY_ENABLED="${BENTO_NETWORK_POLICY_ENABLED:-}"
PDB_ENABLED="${BENTO_PDB_ENABLED:-}"
PDB_MIN_AVAILABLE="${BENTO_PDB_MIN_AVAILABLE:-}"
AUTOSCALING_ENABLED="${BENTO_AUTOSCALING_ENABLED:-}"
AUTOSCALING_MIN_REPLICAS="${BENTO_AUTOSCALING_MIN_REPLICAS:-}"
AUTOSCALING_MAX_REPLICAS="${BENTO_AUTOSCALING_MAX_REPLICAS:-}"
AUTOSCALING_TARGET_CPU="${BENTO_AUTOSCALING_TARGET_CPU:-}"
SYNTHETIC_PROBE_ENABLED="${BENTO_SYNTHETIC_PROBE_ENABLED:-}"
SYNTHETIC_PROBE_SCHEDULE="${BENTO_SYNTHETIC_PROBE_SCHEDULE:-}"
HELM_TIMEOUT="${HELM_TIMEOUT:-300s}"

if [[ -z "$IMAGE_URI" ]]; then
  if [[ -f artifacts/mlops/bento_image_uri.txt ]]; then
    IMAGE_URI="$(cat artifacts/mlops/bento_image_uri.txt)"
  fi
fi

if [[ -z "$IMAGE_URI" ]]; then
  echo "IMAGE_URI is required."
  echo "Push the image first so artifacts/mlops/bento_image_uri.txt exists, or set IMAGE_URI explicitly."
  echo "Example:"
  echo "  IMAGE_URI=asia-southeast1-docker.pkg.dev/PROJECT/repo/image:tag BENTO_INGRESS_ENABLED=true make gke-deploy-bento"
  exit 1
fi

IMAGE_REPOSITORY="${IMAGE_URI%:*}"
IMAGE_TAG="${IMAGE_URI##*:}"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NAMESPACE" delete configmap bento-model-artifact --ignore-not-found

HELM_ARGS=(
  --namespace "$NAMESPACE"
  --create-namespace
  --atomic
  --timeout "$HELM_TIMEOUT"
  --history-max 10
  --set image.repository="$IMAGE_REPOSITORY"
  --set image.tag="$IMAGE_TAG"
)

if [[ -n "$SERVICE_TYPE" ]]; then
  HELM_ARGS+=(--set service.type="$SERVICE_TYPE")
fi

if [[ -n "$INGRESS_ENABLED" ]]; then
  HELM_ARGS+=(--set ingress.enabled="$INGRESS_ENABLED")
fi

if [[ -n "$INGRESS_CLASS" ]]; then
  HELM_ARGS+=(--set ingress.className="$INGRESS_CLASS")
fi

if [[ -n "$INGRESS_HOST" ]]; then
  HELM_ARGS+=(--set ingress.host="$INGRESS_HOST")
fi

if [[ -n "$INGRESS_PATH" ]]; then
  HELM_ARGS+=(--set ingress.path="$INGRESS_PATH")
fi

if [[ -n "$TRACING_ENABLED" ]]; then
  HELM_ARGS+=(--set tracing.enabled="$TRACING_ENABLED")
fi

if [[ -n "$TRACING_OTLP_ENDPOINT" ]]; then
  HELM_ARGS+=(--set tracing.otlpEndpoint="$TRACING_OTLP_ENDPOINT")
fi

if [[ -n "$REPLICA_COUNT" ]]; then
  HELM_ARGS+=(--set replicaCount="$REPLICA_COUNT")
fi

if [[ -n "$NETWORK_POLICY_ENABLED" ]]; then
  HELM_ARGS+=(--set networkPolicy.enabled="$NETWORK_POLICY_ENABLED")
fi

if [[ -n "$PDB_ENABLED" ]]; then
  HELM_ARGS+=(--set podDisruptionBudget.enabled="$PDB_ENABLED")
fi

if [[ -n "$PDB_MIN_AVAILABLE" ]]; then
  HELM_ARGS+=(--set podDisruptionBudget.minAvailable="$PDB_MIN_AVAILABLE")
fi

if [[ -n "$AUTOSCALING_ENABLED" ]]; then
  HELM_ARGS+=(--set autoscaling.enabled="$AUTOSCALING_ENABLED")
fi

if [[ -n "$AUTOSCALING_MIN_REPLICAS" ]]; then
  HELM_ARGS+=(--set autoscaling.minReplicas="$AUTOSCALING_MIN_REPLICAS")
fi

if [[ -n "$AUTOSCALING_MAX_REPLICAS" ]]; then
  HELM_ARGS+=(--set autoscaling.maxReplicas="$AUTOSCALING_MAX_REPLICAS")
fi

if [[ -n "$AUTOSCALING_TARGET_CPU" ]]; then
  HELM_ARGS+=(--set autoscaling.targetCPUUtilizationPercentage="$AUTOSCALING_TARGET_CPU")
fi

if [[ -n "$SYNTHETIC_PROBE_ENABLED" ]]; then
  HELM_ARGS+=(--set syntheticProbe.enabled="$SYNTHETIC_PROBE_ENABLED")
fi

if [[ -n "$SYNTHETIC_PROBE_SCHEDULE" ]]; then
  HELM_ARGS+=(--set syntheticProbe.schedule="$SYNTHETIC_PROBE_SCHEDULE")
fi

helm upgrade --install "$HELM_RELEASE" "$HELM_CHART" "${HELM_ARGS[@]}"

kubectl -n "$NAMESPACE" rollout status deployment/"$HELM_RELEASE" --timeout=180s

echo "Deployed BentoML predictor image: $IMAGE_URI"
echo "Service type: ${SERVICE_TYPE:-chart default}"
echo "Ingress enabled: ${INGRESS_ENABLED:-chart default}"
echo "Tracing enabled: ${TRACING_ENABLED:-chart default}"
echo "Replicas: ${REPLICA_COUNT:-chart default}"
echo "NetworkPolicy enabled: ${NETWORK_POLICY_ENABLED:-chart default}"
echo "PodDisruptionBudget enabled: ${PDB_ENABLED:-chart default}"
echo "Autoscaling enabled: ${AUTOSCALING_ENABLED:-chart default}"
echo "Synthetic probe enabled: ${SYNTHETIC_PROBE_ENABLED:-chart default}"
echo "Test locally with:"
echo "  kubectl -n $NAMESPACE port-forward svc/bento-price-predictor 3001:80"
