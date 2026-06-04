#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
NAMESPACE="${INFERENCE_ORCHESTRATOR_NAMESPACE:-model-serving}"
IMAGE_URI="${IMAGE_URI:-}"
HELM_RELEASE="${INFERENCE_ORCHESTRATOR_HELM_RELEASE:-inference-orchestrator}"
HELM_CHART="${INFERENCE_ORCHESTRATOR_HELM_CHART:-charts/inference-orchestrator}"
REPLICA_COUNT="${INFERENCE_ORCHESTRATOR_REPLICA_COUNT:-}"
BENTO_PREDICT_URL="${BENTO_PREDICT_URL:-}"
FEATURE_PLATFORM_URL="${FEATURE_PLATFORM_URL:-}"
ALERT_RULE_ENGINE_URL="${ALERT_RULE_ENGINE_URL:-}"
INGRESS_ENABLED="${INFERENCE_ORCHESTRATOR_INGRESS_ENABLED:-}"
INGRESS_CLASS="${INFERENCE_ORCHESTRATOR_INGRESS_CLASS:-}"
INGRESS_HOST="${INFERENCE_ORCHESTRATOR_INGRESS_HOST:-}"
INGRESS_PATH="${INFERENCE_ORCHESTRATOR_INGRESS_PATH:-}"
HELM_TIMEOUT="${HELM_TIMEOUT:-300s}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "./$ENV_FILE"
  set +a
fi

if [[ -z "$IMAGE_URI" && -f artifacts/inference-orchestrator/inference_orchestrator_image_uri.txt ]]; then
  IMAGE_URI="$(cat artifacts/inference-orchestrator/inference_orchestrator_image_uri.txt)"
fi

if [[ -z "$IMAGE_URI" ]]; then
  echo "IMAGE_URI is required."
  echo "Push the inference orchestrator image first, or set IMAGE_URI explicitly."
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

if [[ -n "$BENTO_PREDICT_URL" ]]; then
  HELM_ARGS+=(--set bento.predictUrl="$BENTO_PREDICT_URL")
fi

if [[ -n "$FEATURE_PLATFORM_URL" ]]; then
  HELM_ARGS+=(--set featurePlatform.url="$FEATURE_PLATFORM_URL")
fi

if [[ -n "$ALERT_RULE_ENGINE_URL" ]]; then
  HELM_ARGS+=(--set alertRuleEngine.url="$ALERT_RULE_ENGINE_URL")
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

helm upgrade --install "$HELM_RELEASE" "$HELM_CHART" "${HELM_ARGS[@]}"
kubectl -n "$NAMESPACE" rollout status deployment/"$HELM_RELEASE" --timeout=180s

echo "Deployed inference orchestrator image: $IMAGE_URI"
echo "Namespace: $NAMESPACE"
echo "Bento predict URL: ${BENTO_PREDICT_URL:-chart default}"
echo "Feature platform URL: ${FEATURE_PLATFORM_URL:-chart default}"
echo "Alert rule engine URL: ${ALERT_RULE_ENGINE_URL:-disabled}"
echo "Ingress enabled: ${INGRESS_ENABLED:-chart default}"
echo "Ingress path: ${INGRESS_PATH:-chart default}"
echo "Test locally with:"
echo "  kubectl -n $NAMESPACE port-forward svc/inference-orchestrator 8091:80"
