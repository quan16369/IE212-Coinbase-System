#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
RELEASE="${MONITORING_RELEASE:-kube-prometheus-stack}"
CHART_VERSION="${KUBE_PROMETHEUS_STACK_VERSION:-}"
VALUES_FILE="${MONITORING_VALUES_FILE:-monitoring/gke/kube-prometheus-stack-values.yaml}"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
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

helm upgrade --install "$RELEASE" prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$VALUES_FILE" \
  "${VERSION_ARGS[@]}" \
  --wait \
  --timeout 10m

kubectl -n "$NAMESPACE" get pods,svc

echo
echo "Monitoring installed."
echo "Open Grafana with:"
echo "  make gke-monitoring-grafana"
echo "Then browse: http://localhost:\${PORT:-3000}"
echo "Default login: admin / admin"
