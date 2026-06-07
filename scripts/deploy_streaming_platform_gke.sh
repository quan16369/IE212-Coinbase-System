#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
NAMESPACE="${DATA_STREAMING_NAMESPACE:-data-streaming}"
HELM_RELEASE="${STREAMING_PLATFORM_HELM_RELEASE:-streaming-platform}"
HELM_CHART="${STREAMING_PLATFORM_HELM_CHART:-charts/streaming-platform}"
IMAGE_URI="${IMAGE_URI:-}"
KAFKA_STORAGE_SIZE="${KAFKA_STORAGE_SIZE:-}"
COINBASE_PRODUCT_IDS="${COINBASE_PRODUCT_IDS:-}"
HELM_TIMEOUT="${HELM_TIMEOUT:-600s}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "./$ENV_FILE"
  set +a
fi

if [[ -z "$IMAGE_URI" && -f artifacts/data-streaming/kafka_producer_image_uri.txt ]]; then
  IMAGE_URI="$(cat artifacts/data-streaming/kafka_producer_image_uri.txt)"
fi

if [[ -z "$IMAGE_URI" ]]; then
  echo "IMAGE_URI is required. Push the Kafka producer image first."
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
  --set producer.image.repository="$IMAGE_REPOSITORY"
  --set producer.image.tag="$IMAGE_TAG"
)

if [[ -n "$KAFKA_STORAGE_SIZE" ]]; then
  HELM_ARGS+=(--set kafka.storageSize="$KAFKA_STORAGE_SIZE")
fi

if [[ -n "$COINBASE_PRODUCT_IDS" ]]; then
  HELM_ARGS+=(--set-string producer.productIds="$COINBASE_PRODUCT_IDS")
fi

helm upgrade --install "$HELM_RELEASE" "$HELM_CHART" "${HELM_ARGS[@]}"
kubectl -n "$NAMESPACE" rollout status statefulset/"$HELM_RELEASE"-kafka --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/"$HELM_RELEASE"-producer --timeout=180s

echo "Streaming platform deployed in namespace: $NAMESPACE"
echo "Kafka bootstrap server: $HELM_RELEASE-kafka.$NAMESPACE.svc.cluster.local:9092"
echo "Producer image: $IMAGE_URI"
