#!/usr/bin/env bash
set -euo pipefail

RUN_RAW_SINK_CHECK="${RUN_RAW_SINK_CHECK:-true}"
RUN_REPLAY_CHECK="${RUN_REPLAY_CHECK:-true}"
RUN_INFERENCE_CHECK="${RUN_INFERENCE_CHECK:-true}"
TEMP_FILES=()

cleanup() {
  if [[ "${#TEMP_FILES[@]}" -gt 0 ]]; then
    rm -f "${TEMP_FILES[@]}"
  fi
}
trap cleanup EXIT

echo "Checking Kafka, validation, and feature platform path"
bash scripts/smoke_streaming_e2e.sh

if [[ "$RUN_RAW_SINK_CHECK" == "true" ]]; then
  echo
  echo "Checking raw GCS sink"
  bash scripts/smoke_raw_data_sink.sh
fi

if [[ "$RUN_REPLAY_CHECK" == "true" ]]; then
  echo
  echo "Checking raw GCS replay idempotency"
  first_run_log="$(mktemp)"
  second_run_log="$(mktemp)"
  TEMP_FILES+=("$first_run_log" "$second_run_log")
  bash scripts/run_raw_data_replay.sh | tee "$first_run_log"
  bash scripts/run_raw_data_replay.sh | tee "$second_run_log"
  if ! grep -Eq "published [0-9]+ records" "$first_run_log"; then
    echo "Replay job did not report published record count." >&2
    exit 1
  fi
  if ! grep -q "published 0 records" "$second_run_log"; then
    echo "Replay is not idempotent; second replay should publish 0 records." >&2
    exit 1
  fi
fi

if [[ "$RUN_INFERENCE_CHECK" == "true" ]]; then
  echo
  echo "Checking inference, alerting, outcomes, and governance telemetry"
  bash scripts/smoke_gke_full_stack.sh
fi

echo
echo "Production data path smoke test passed."
