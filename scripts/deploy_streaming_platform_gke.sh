#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
NAMESPACE="${DATA_STREAMING_NAMESPACE:-data-streaming}"
HELM_RELEASE="${STREAMING_PLATFORM_HELM_RELEASE:-streaming-platform}"
HELM_CHART="${STREAMING_PLATFORM_HELM_CHART:-charts/streaming-platform}"
IMAGE_URI="${IMAGE_URI:-}"
RAW_DATA_SINK_IMAGE_URI="${RAW_DATA_SINK_IMAGE_URI:-}"
RAW_DATA_SINK_ENABLED="${RAW_DATA_SINK_ENABLED:-false}"
RAW_DATA_BUCKET="${RAW_DATA_BUCKET:-}"
RAW_DATA_SINK_GCP_SERVICE_ACCOUNT="${RAW_DATA_SINK_GCP_SERVICE_ACCOUNT:-}"
RAW_DATA_REPLAY_IMAGE_URI="${RAW_DATA_REPLAY_IMAGE_URI:-}"
RAW_DATA_REPLAY_ENABLED="${RAW_DATA_REPLAY_ENABLED:-false}"
RAW_DATA_REPLAY_GCP_SERVICE_ACCOUNT="${RAW_DATA_REPLAY_GCP_SERVICE_ACCOUNT:-}"
RAW_DATA_REPLAY_ID="${RAW_DATA_REPLAY_ID:-recovery-default}"
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

if [[ -z "$RAW_DATA_SINK_IMAGE_URI" && -f artifacts/data-streaming/raw_data_sink_image_uri.txt ]]; then
  RAW_DATA_SINK_IMAGE_URI="$(cat artifacts/data-streaming/raw_data_sink_image_uri.txt)"
fi

if [[ -z "$RAW_DATA_REPLAY_IMAGE_URI" && -f artifacts/data-streaming/raw_data_replay_image_uri.txt ]]; then
  RAW_DATA_REPLAY_IMAGE_URI="$(cat artifacts/data-streaming/raw_data_replay_image_uri.txt)"
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
  --set rawDataSink.enabled="$RAW_DATA_SINK_ENABLED"
  --set rawDataReplay.enabled="$RAW_DATA_REPLAY_ENABLED"
)

if [[ "$RAW_DATA_SINK_ENABLED" == "true" ]]; then
  if [[ -z "$RAW_DATA_SINK_IMAGE_URI" || -z "$RAW_DATA_BUCKET" || -z "$RAW_DATA_SINK_GCP_SERVICE_ACCOUNT" ]]; then
    echo "RAW_DATA_SINK_IMAGE_URI, RAW_DATA_BUCKET, and RAW_DATA_SINK_GCP_SERVICE_ACCOUNT are required when RAW_DATA_SINK_ENABLED=true."
    exit 1
  fi
  RAW_SINK_REPOSITORY="${RAW_DATA_SINK_IMAGE_URI%:*}"
  RAW_SINK_TAG="${RAW_DATA_SINK_IMAGE_URI##*:}"
  HELM_ARGS+=(
    --set rawDataSink.image.repository="$RAW_SINK_REPOSITORY"
    --set rawDataSink.image.tag="$RAW_SINK_TAG"
    --set-string rawDataSink.bucket="$RAW_DATA_BUCKET"
    --set-string rawDataSink.gcpServiceAccount="$RAW_DATA_SINK_GCP_SERVICE_ACCOUNT"
  )
fi

if [[ "$RAW_DATA_REPLAY_ENABLED" == "true" ]]; then
  if [[ -z "$RAW_DATA_REPLAY_IMAGE_URI" || -z "$RAW_DATA_BUCKET" || -z "$RAW_DATA_REPLAY_GCP_SERVICE_ACCOUNT" ]]; then
    echo "RAW_DATA_REPLAY_IMAGE_URI, RAW_DATA_BUCKET, and RAW_DATA_REPLAY_GCP_SERVICE_ACCOUNT are required when RAW_DATA_REPLAY_ENABLED=true."
    exit 1
  fi
  RAW_REPLAY_REPOSITORY="${RAW_DATA_REPLAY_IMAGE_URI%:*}"
  RAW_REPLAY_TAG="${RAW_DATA_REPLAY_IMAGE_URI##*:}"
  HELM_ARGS+=(
    --set rawDataReplay.image.repository="$RAW_REPLAY_REPOSITORY"
    --set rawDataReplay.image.tag="$RAW_REPLAY_TAG"
    --set-string rawDataReplay.bucket="$RAW_DATA_BUCKET"
    --set-string rawDataReplay.gcpServiceAccount="$RAW_DATA_REPLAY_GCP_SERVICE_ACCOUNT"
    --set-string rawDataReplay.replayId="$RAW_DATA_REPLAY_ID"
  )
fi

if [[ -n "$KAFKA_STORAGE_SIZE" ]]; then
  HELM_ARGS+=(--set kafka.storageSize="$KAFKA_STORAGE_SIZE")
fi

if [[ -n "$COINBASE_PRODUCT_IDS" ]]; then
  HELM_ARGS+=(--set-string producer.productIds="$COINBASE_PRODUCT_IDS")
fi

helm upgrade --install "$HELM_RELEASE" "$HELM_CHART" "${HELM_ARGS[@]}"
kubectl -n "$NAMESPACE" rollout status statefulset/"$HELM_RELEASE"-kafka --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/"$HELM_RELEASE"-producer --timeout=180s
if [[ "$RAW_DATA_SINK_ENABLED" == "true" ]]; then
  kubectl -n "$NAMESPACE" rollout status deployment/"$HELM_RELEASE"-raw-data-sink --timeout=180s
fi

echo "Streaming platform deployed in namespace: $NAMESPACE"
echo "Kafka bootstrap server: $HELM_RELEASE-kafka.$NAMESPACE.svc.cluster.local:9092"
echo "Producer image: $IMAGE_URI"
echo "Raw-data GCS sink enabled: $RAW_DATA_SINK_ENABLED"
echo "Raw-data replay enabled: $RAW_DATA_REPLAY_ENABLED"
