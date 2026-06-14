#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${DATA_STREAMING_NAMESPACE:-data-streaming}"
BUCKET="${RAW_DATA_BUCKET:-}"

if [[ -z "$BUCKET" ]]; then
  BUCKET="$(terraform -chdir=infra/terraform output -raw raw_data_bucket_name)"
fi

kubectl -n "$NAMESPACE" rollout status deployment/streaming-platform-raw-data-sink --timeout=180s
kubectl -n "$NAMESPACE" logs deployment/streaming-platform-raw-data-sink --tail=100

object_count=0
for _ in $(seq 1 "${RAW_DATA_SINK_SMOKE_ATTEMPTS:-30}"); do
  object_count="$(gcloud storage ls "gs://${BUCKET}/raw/topic=coin-data-model/**" 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$object_count" -ge 1 ]]; then
    break
  fi
  sleep "${RAW_DATA_SINK_SMOKE_DELAY_SECONDS:-10}"
done
echo "Raw Parquet objects: $object_count"
if [[ "$object_count" -lt 1 ]]; then
  echo "No raw Parquet objects found in gs://${BUCKET}/raw/topic=coin-data-model/" >&2
  exit 1
fi
