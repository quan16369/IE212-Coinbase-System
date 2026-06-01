#!/usr/bin/env bash
set -euo pipefail

SONAR_REQUIRED="${SONAR_REQUIRED:-false}"
SONAR_HOST_URL="${SONAR_HOST_URL:-http://localhost:9002}"
SONAR_HOST_URL="$(printf '%s' "$SONAR_HOST_URL" | xargs)"

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

ANALYSIS_TOKEN="$SONAR_TOKEN"

env -u SONAR_TOKEN sonar-scanner \
  -Dsonar.host.url="$SONAR_HOST_URL" \
  -Dsonar.login="$ANALYSIS_TOKEN"
