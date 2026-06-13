#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${DATA_STREAMING_NAMESPACE:-data-streaming}"
CRONJOB="${RAW_DATA_REPLAY_CRONJOB:-streaming-platform-raw-data-replay}"
JOB_NAME="${RAW_DATA_REPLAY_JOB_NAME:-raw-data-replay-$(date +%s)}"

kubectl -n "$NAMESPACE" create job --from="cronjob/$CRONJOB" "$JOB_NAME"
kubectl -n "$NAMESPACE" wait --for=condition=complete "job/$JOB_NAME" --timeout=900s
kubectl -n "$NAMESPACE" logs "job/$JOB_NAME"
