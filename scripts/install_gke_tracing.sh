#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${TRACING_NAMESPACE:-tracing}"
TEMPO_RELEASE="${TEMPO_RELEASE:-tempo}"
OTEL_RELEASE="${OTEL_COLLECTOR_RELEASE:-otel-collector}"
CHART_VERSION="${TEMPO_CHART_VERSION:-}"
OTEL_CHART_VERSION="${OTEL_COLLECTOR_CHART_VERSION:-}"
VALUES_FILE="${TRACING_VALUES_FILE:-monitoring/gke/tempo-values.yaml}"
OTEL_VALUES_FILE="${OTEL_COLLECTOR_VALUES_FILE:-monitoring/gke/otel-collector-values.yaml}"

helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null
helm repo update

VERSION_ARGS=()
if [[ -n "$CHART_VERSION" ]]; then
  VERSION_ARGS=(--version "$CHART_VERSION")
fi

OTEL_VERSION_ARGS=()
if [[ -n "$OTEL_CHART_VERSION" ]]; then
  OTEL_VERSION_ARGS=(--version "$OTEL_CHART_VERSION")
fi

cleanup_release() {
  local release="$1"
  if helm -n "$NAMESPACE" status "$release" >/dev/null 2>&1; then
    RELEASE_STATUS="$(helm -n "$NAMESPACE" status "$release" -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["info"]["status"])')"
    if [[ "$RELEASE_STATUS" != "deployed" ]]; then
      echo "Removing non-deployed Helm release $release with status $RELEASE_STATUS."
      helm -n "$NAMESPACE" uninstall "$release" || true
      kubectl -n "$NAMESPACE" delete secret,configmap \
        -l "owner=helm,name=$release" \
        --ignore-not-found
    fi
  fi
}

cleanup_release "$TEMPO_RELEASE"
cleanup_release "$OTEL_RELEASE"

helm upgrade --install "$TEMPO_RELEASE" grafana/tempo \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$VALUES_FILE" \
  "${VERSION_ARGS[@]}" \
  --wait \
  --timeout 10m

helm upgrade --install "$OTEL_RELEASE" open-telemetry/opentelemetry-collector \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$OTEL_VALUES_FILE" \
  "${OTEL_VERSION_ARGS[@]}" \
  --wait \
  --timeout 10m

kubectl -n "$NAMESPACE" get pods,svc

echo
echo "Tracing installed."
echo "Tempo in-cluster URLs:"
echo "  Query: http://tempo.tracing.svc.cluster.local:3200"
echo "  OTLP gRPC: http://tempo.tracing.svc.cluster.local:4317"
echo "OpenTelemetry Collector in-cluster URLs:"
echo "  OTLP gRPC: http://otel-collector.tracing.svc.cluster.local:4317"
echo "  OTLP HTTP: http://otel-collector.tracing.svc.cluster.local:4318"
echo "If Grafana is already running, refresh or rerun:"
echo "  make gke-install-monitoring"
echo "Redeploy Bento with tracing enabled:"
echo "  BENTO_TRACING_ENABLED=true make gke-deploy-bento"
