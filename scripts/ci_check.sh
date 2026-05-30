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
    'coinbase_kafka_producer/producer.py',
    'kafka_spark_processor/spark_processor.py',
    'mlops/features.py',
    'mlops/service.py',
    'mlops/train.py',
    'scripts/promote_mlflow_model.py',
    'scripts/test_bento_predict.py',
]; [ast.parse(pathlib.Path(path).read_text(), filename=path) for path in files]"
else
  echo "python not found; skipping Python syntax check"
fi

if command -v go >/dev/null 2>&1; then
  echo "Running Go tests"
  pushd go_kafka_consumer >/dev/null
  go test ./...
  popd >/dev/null
else
  echo "go not found; skipping Go tests"
fi

if command -v helm >/dev/null 2>&1; then
  echo "Linting Helm charts"
  helm lint charts/bento-price-predictor
else
  echo "helm not found; skipping Helm chart lint"
fi

if [[ "${BUILD_IMAGES:-false}" == "true" ]]; then
  echo "Building Docker images"
  docker compose --env-file "$ENV_FILE" build
fi
