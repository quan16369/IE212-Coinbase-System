#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "./$ENV_FILE"
  set +a
fi

MODEL_ALIAS="${MODEL_ALIAS:-champion}"
MODEL_NAME="${MLFLOW_REGISTERED_MODEL_NAME:-coinbase-price-lightgbm}"
MLFLOW_TRACKING_URI="${MLFLOW_TRACKING_URI:-http://localhost:5000}"

MODEL_VERSION="${MODEL_VERSION:-}" MODEL_ALIAS="$MODEL_ALIAS" MLFLOW_TRACKING_URI="$MLFLOW_TRACKING_URI" \
  python scripts/promote_mlflow_model.py

BENTO_MLOPS_MODEL_URI="models:/${MODEL_NAME}@${MODEL_ALIAS}" \
BENTO_MLFLOW_TRACKING_URI="${BENTO_MLFLOW_TRACKING_URI:-http://mlflow.model-training.svc.cluster.local:5000}" \
RUN_FULL_E2E_AFTER_DEPLOY="${RUN_FULL_E2E_AFTER_DEPLOY:-true}" \
  bash scripts/deploy_bento_with_rollback.sh
