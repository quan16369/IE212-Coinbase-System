#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
NAMESPACE="${FEATURE_PLATFORM_NAMESPACE:-feature-platform}"
IMAGE_URI="${IMAGE_URI:-}"
HELM_RELEASE="${FEATURE_PLATFORM_HELM_RELEASE:-feature-platform}"
HELM_CHART="${FEATURE_PLATFORM_HELM_CHART:-charts/feature-platform}"
REPLICA_COUNT="${FEATURE_PLATFORM_REPLICA_COUNT:-}"
HISTORY_LIMIT="${FEATURE_HISTORY_LIMIT:-}"
PDB_ENABLED="${FEATURE_PLATFORM_PDB_ENABLED:-}"
AUTOSCALING_ENABLED="${FEATURE_PLATFORM_AUTOSCALING_ENABLED:-}"
HELM_TIMEOUT="${HELM_TIMEOUT:-300s}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "./$ENV_FILE"
  set +a
fi

if [[ -z "$IMAGE_URI" && -f artifacts/feature-platform/feature_platform_image_uri.txt ]]; then
  IMAGE_URI="$(cat artifacts/feature-platform/feature_platform_image_uri.txt)"
fi

if [[ -z "$IMAGE_URI" ]]; then
  echo "IMAGE_URI is required."
  echo "Push the feature platform image first, or set IMAGE_URI explicitly."
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

if [[ -n "$HISTORY_LIMIT" ]]; then
  HELM_ARGS+=(--set store.historyLimit="$HISTORY_LIMIT")
fi

if [[ -n "$PDB_ENABLED" ]]; then
  HELM_ARGS+=(--set podDisruptionBudget.enabled="$PDB_ENABLED")
fi

if [[ -n "$AUTOSCALING_ENABLED" ]]; then
  HELM_ARGS+=(--set autoscaling.enabled="$AUTOSCALING_ENABLED")
fi

helm upgrade --install "$HELM_RELEASE" "$HELM_CHART" "${HELM_ARGS[@]}"
kubectl -n "$NAMESPACE" rollout status deployment/"$HELM_RELEASE" --timeout=180s

echo "Deployed feature platform image: $IMAGE_URI"
echo "Namespace: $NAMESPACE"
echo "History limit: ${HISTORY_LIMIT:-chart default}"
echo "Test locally with:"
echo "  kubectl -n $NAMESPACE port-forward svc/feature-platform 8090:80"
