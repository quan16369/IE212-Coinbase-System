#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
RELEASE="${MONITORING_RELEASE:-kube-prometheus-stack}"
CHART_VERSION="${KUBE_PROMETHEUS_STACK_VERSION:-}"
VALUES_FILE="${MONITORING_VALUES_FILE:-monitoring/gke/kube-prometheus-stack-values.yaml}"
DASHBOARD_FILE="${BENTO_DASHBOARD_FILE:-monitoring/gke/dashboards/bento-price-predictor.json}"
DASHBOARD_CONFIGMAP="${BENTO_DASHBOARD_CONFIGMAP:-bento-price-predictor-dashboard}"
ALERTMANAGER_WEBHOOK_URL="${ALERTMANAGER_WEBHOOK_URL:-}"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update

VERSION_ARGS=()
if [[ -n "$CHART_VERSION" ]]; then
  VERSION_ARGS=(--version "$CHART_VERSION")
fi

VALUES_ARGS=(--values "$VALUES_FILE")
ALERTMANAGER_VALUES_FILE=""
if [[ -n "$ALERTMANAGER_WEBHOOK_URL" ]]; then
  ALERTMANAGER_VALUES_FILE="$(mktemp)"
  cat >"$ALERTMANAGER_VALUES_FILE" <<EOF
alertmanager:
  config:
    route:
      receiver: "webhook"
      group_by:
        - namespace
        - service
        - alertname
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
    receivers:
      - name: "webhook"
        webhook_configs:
          - url: "$ALERTMANAGER_WEBHOOK_URL"
            send_resolved: true
      - name: "noop"
      - name: "null"
EOF
  VALUES_ARGS+=(--values "$ALERTMANAGER_VALUES_FILE")
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
  "${VALUES_ARGS[@]}" \
  "${VERSION_ARGS[@]}" \
  --wait \
  --timeout 10m

if [[ -n "$ALERTMANAGER_VALUES_FILE" ]]; then
  rm -f "$ALERTMANAGER_VALUES_FILE"
fi

if [[ -f "$DASHBOARD_FILE" ]]; then
  kubectl -n "$NAMESPACE" create configmap "$DASHBOARD_CONFIGMAP" \
    --from-file="$(basename "$DASHBOARD_FILE")=$DASHBOARD_FILE" \
    --dry-run=client \
    -o yaml | kubectl apply -f -
  kubectl -n "$NAMESPACE" label configmap "$DASHBOARD_CONFIGMAP" grafana_dashboard=1 --overwrite
fi

kubectl -n "$NAMESPACE" get pods,svc

echo
echo "Monitoring installed."
echo "Open Grafana with:"
echo "  make gke-monitoring-grafana"
echo "Then browse: http://localhost:\${PORT:-3000}"
echo "Default login: admin / admin"
echo "Dashboard: Coinbase / Bento Price Predictor"
if [[ -n "$ALERTMANAGER_WEBHOOK_URL" ]]; then
  echo "Alertmanager receiver: webhook"
else
  echo "Alertmanager receiver: noop"
fi
