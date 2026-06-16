#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${ENV_FILE:-}" ]]; then
  if [[ -f .env ]]; then
    ENV_FILE=.env
  else
    ENV_FILE=.env.example
  fi
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE"
  exit 1
fi

echo "Validating docker compose with $ENV_FILE"
docker compose --env-file "$ENV_FILE" config >/tmp/coinbase_streaming_compose.yml

PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1 && python3 -c "pass" >/dev/null 2>&1; then
  PYTHON_BIN=python3
elif command -v python >/dev/null 2>&1 && python -c "pass" >/dev/null 2>&1; then
  PYTHON_BIN=python
fi

if [[ -n "$PYTHON_BIN" ]]; then
  echo "Checking Python syntax"
  "$PYTHON_BIN" -c "import ast, pathlib; files = [
    'contracts/events.py',
    'mlops/features.py',
    'mlops/service.py',
    'mlops/train.py',
    'services/data_validation/app.py',
    'services/feature_platform/app.py',
    'services/inference_orchestrator/app.py',
    'services/raw_data_sink/sink.py',
    'services/telemetry_producer/producer.py',
    'scripts/promote_mlflow_model.py',
    'scripts/smoke_feature_platform.py',
    'scripts/smoke_data_validation.py',
    'scripts/smoke_inference_orchestrator.py',
    'scripts/test_bento_predict.py',
]; [ast.parse(pathlib.Path(path).read_text(), filename=path) for path in files]"
else
  echo "python not found; skipping Python syntax check"
fi

if command -v helm >/dev/null 2>&1; then
  echo "Linting Helm charts"
  helm lint charts/bento-price-predictor
  helm lint charts/data-validation
  helm lint charts/feature-platform
helm lint charts/inference-orchestrator
helm lint charts/streaming-platform
helm lint charts/model-training
else
  echo "helm not found; skipping Helm chart lint"
fi

if command -v terraform >/dev/null 2>&1; then
  echo "Checking Terraform formatting"
  terraform -chdir=infra/terraform fmt -check
else
  echo "terraform not found; skipping Terraform checks"
fi

bash scripts/security_check.sh

if [[ "${BUILD_IMAGES:-false}" == "true" ]]; then
  echo "Building Docker images"
  docker compose --env-file "$ENV_FILE" build
fi
