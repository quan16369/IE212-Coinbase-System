#!/usr/bin/env bash
set -euo pipefail

SONAR_REQUIRED="${SONAR_REQUIRED:-false}"
SONAR_HOST_URL="${SONAR_HOST_URL:-http://localhost:9002}"

if ! command -v sonar-scanner >/dev/null 2>&1; then
  if [[ "$SONAR_REQUIRED" == "true" ]]; then
    echo "sonar-scanner is required but not installed."
    exit 1
  fi

  echo "sonar-scanner not found; skipping SonarQube scan"
  exit 0
fi

if [[ -z "${SONAR_TOKEN:-}" ]]; then
  if [[ "$SONAR_REQUIRED" == "true" ]]; then
    echo "SONAR_TOKEN is required for SonarQube scan."
    exit 1
  fi

  echo "SONAR_TOKEN is not set; skipping SonarQube scan"
  exit 0
fi

sonar-scanner \
  -Dsonar.host.url="$SONAR_HOST_URL" \
  -Dsonar.token="$SONAR_TOKEN"
