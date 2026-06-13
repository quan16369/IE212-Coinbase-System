#!/usr/bin/env bash
set -euo pipefail

KAFKA_POD="${KAFKA_POD:-streaming-platform-kafka-0}"
KAFKA_NAMESPACE="${KAFKA_NAMESPACE:-data-streaming}"

for topic in coin-data-model coin-data-validated; do
  offsets="$(kubectl -n "$KAFKA_NAMESPACE" exec "$KAFKA_POD" -- \
    kafka-get-offsets \
    --bootstrap-server localhost:9092 --topic "$topic")"
  count="$(printf '%s\n' "$offsets" | awk -F: '{total += $3} END {print total + 0}')"
  echo "$topic messages: $count"
  if [[ "$count" -lt 1 ]]; then
    echo "Expected at least one message in $topic" >&2
    exit 1
  fi
done

kubectl -n feature-platform exec deploy/feature-platform -c feature-platform -- \
  python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8080/store/status', timeout=10).read().decode())"

echo "Streaming E2E smoke passed."
