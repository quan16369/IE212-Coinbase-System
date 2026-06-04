#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
NAMESPACE="${ALERT_INDEX_NAMESPACE:-alert-routing}"
IMAGE_URI="${IMAGE_URI:-}"
HELM_RELEASE="${ALERT_INDEX_HELM_RELEASE:-alert-index}"
HELM_CHART="${ALERT_INDEX_HELM_CHART:-charts/alert-index}"
REPLICA_COUNT="${ALERT_INDEX_REPLICA_COUNT:-}"
INDEX_PATH="${ALERT_INDEX_PATH:-}"
HELM_TIMEOUT="${HELM_TIMEOUT:-300s}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "./$ENV_FILE"
  set +a
fi

if [[ -z "$IMAGE_URI" && -f artifacts/alert-index/alert_index_image_uri.txt ]]; then
  IMAGE_URI="$(cat artifacts/alert-index/alert_index_image_uri.txt)"
fi

if [[ -z "$IMAGE_URI" ]]; then
  echo "IMAGE_URI is required."
  echo "Push the alert index image first, or set IMAGE_URI explicitly."
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

if [[ -n "$INDEX_PATH" ]]; then
  HELM_ARGS+=(--set index.path="$INDEX_PATH")
fi

helm upgrade --install "$HELM_RELEASE" "$HELM_CHART" "${HELM_ARGS[@]}"
kubectl -n "$NAMESPACE" rollout status deployment/"$HELM_RELEASE" --timeout=180s

echo "Deployed alert index image: $IMAGE_URI"
echo "Namespace: $NAMESPACE"
echo "Index path: ${INDEX_PATH:-chart default}"
echo "Test locally with:"
echo "  kubectl -n $NAMESPACE port-forward svc/alert-index 8093:80"
