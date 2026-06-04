#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
NAMESPACE="${ALERT_RULE_ENGINE_NAMESPACE:-alert-routing}"
IMAGE_URI="${IMAGE_URI:-}"
HELM_RELEASE="${ALERT_RULE_ENGINE_HELM_RELEASE:-alert-rule-engine}"
HELM_CHART="${ALERT_RULE_ENGINE_HELM_CHART:-charts/alert-rule-engine}"
REPLICA_COUNT="${ALERT_RULE_ENGINE_REPLICA_COUNT:-}"
RETURN_THRESHOLD="${ALERT_RETURN_THRESHOLD:-}"
ALERT_INDEX_URL="${ALERT_INDEX_URL:-}"
HELM_TIMEOUT="${HELM_TIMEOUT:-300s}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "./$ENV_FILE"
  set +a
fi

if [[ -z "$IMAGE_URI" && -f artifacts/alert-rule-engine/alert_rule_engine_image_uri.txt ]]; then
  IMAGE_URI="$(cat artifacts/alert-rule-engine/alert_rule_engine_image_uri.txt)"
fi

if [[ -z "$IMAGE_URI" ]]; then
  echo "IMAGE_URI is required."
  echo "Push the alert rule engine image first, or set IMAGE_URI explicitly."
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

if [[ -n "$RETURN_THRESHOLD" ]]; then
  HELM_ARGS+=(--set rules.returnThreshold="$RETURN_THRESHOLD")
fi

if [[ -n "$ALERT_INDEX_URL" ]]; then
  HELM_ARGS+=(--set alertIndex.url="$ALERT_INDEX_URL")
fi

helm upgrade --install "$HELM_RELEASE" "$HELM_CHART" "${HELM_ARGS[@]}"
kubectl -n "$NAMESPACE" rollout status deployment/"$HELM_RELEASE" --timeout=180s

echo "Deployed alert rule engine image: $IMAGE_URI"
echo "Namespace: $NAMESPACE"
echo "Return threshold: ${RETURN_THRESHOLD:-chart default}"
echo "Alert index URL: ${ALERT_INDEX_URL:-disabled}"
echo "Test locally with:"
echo "  kubectl -n $NAMESPACE port-forward svc/alert-rule-engine 8092:80"
