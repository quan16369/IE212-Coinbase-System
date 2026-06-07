#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${DATA_STREAMING_NAMESPACE:-data-streaming}"
RELEASE="${STREAMING_PLATFORM_HELM_RELEASE:-streaming-platform}"
EXPECTED_TOPICS=(coin-data coin-data-model coin-data-validated coin-data-quality)

topics="$(kubectl -n "$NAMESPACE" exec statefulset/"$RELEASE"-kafka -- \
  kafka-topics --bootstrap-server localhost:9092 --list)"

for topic in "${EXPECTED_TOPICS[@]}"; do
  if ! grep -Fxq "$topic" <<<"$topics"; then
    echo "Missing Kafka topic: $topic"
    exit 1
  fi
done

kubectl -n "$NAMESPACE" get deployment/"$RELEASE"-producer statefulset/"$RELEASE"-kafka
echo "Kafka topics:"
printf '%s\n' "$topics"
