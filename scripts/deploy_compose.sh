#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${ENV_FILE:-.env}
export COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-coinbase_streaming}
export COMPOSE_PROFILES=${COMPOSE_PROFILES:-ops}

if [[ ! -f "$ENV_FILE" ]]; then
  if [[ -f .env.example ]]; then
    cp .env.example "$ENV_FILE"
    echo "Created $ENV_FILE from .env.example. Review secrets before using this outside local/dev."
  else
    echo "Missing $ENV_FILE and .env.example"
    exit 1
  fi
fi

echo "Validating compose configuration"
docker compose --env-file "$ENV_FILE" config >/tmp/coinbase_streaming_deploy_compose.yml

if [[ "${PULL_IMAGES:-true}" == "true" ]]; then
  echo "Pulling base images"
  docker compose --env-file "$ENV_FILE" pull --ignore-pull-failures
fi

echo "Starting services"
docker compose --env-file "$ENV_FILE" up -d --build --remove-orphans

echo "Current service status"
docker compose --env-file "$ENV_FILE" ps
