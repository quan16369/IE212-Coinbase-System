#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${LOGGING_NAMESPACE:-logging}"
RELEASE="${LOKI_RELEASE:-loki}"
CHART_VERSION="${LOKI_STACK_VERSION:-}"
VALUES_FILE="${LOGGING_VALUES_FILE:-monitoring/gke/loki-stack-values.yaml}"

helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo update

VERSION_ARGS=()
if [[ -n "$CHART_VERSION" ]]; then
  VERSION_ARGS=(--version "$CHART_VERSION")
fi

if helm -n "$NAMESPACE" status "$RELEASE" >/dev/null 2>&1; then
  RELEASE_STATUS="$(helm -n "$NAMESPACE" status "$RELEASE" -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["info"]["status"])')"
  if [[ "$RELEASE_STATUS" != "deployed" ]]; then
    echo "Removing non-deployed Helm release $RELEASE with status $RELEASE_STATUS."
    helm -n "$NAMESPACE" uninstall "$RELEASE" || true
    kubectl -n "$NAMESPACE" delete secret,configmap \
      -l "owner=helm,name=$RELEASE" \
      --ignore-not-found
  fi
fi

helm upgrade --install "$RELEASE" grafana/loki-stack \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$VALUES_FILE" \
  "${VERSION_ARGS[@]}" \
  --wait \
  --timeout 10m

kubectl -n "$NAMESPACE" get pods,svc

echo
echo "Logging installed."
echo "Loki in-cluster URL:"
echo "  http://loki.logging.svc.cluster.local:3100"
echo "If Grafana is already running, refresh or rerun:"
echo "  make gke-install-monitoring"
