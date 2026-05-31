#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${K8S_NAMESPACE:-app}"
APP_LABEL="${BENTO_APP_LABEL:-app.kubernetes.io/name=bento-price-predictor}"
LOG_TAIL="${TAIL:-80}"

echo "== BentoML workload =="
kubectl -n "$NAMESPACE" get deploy,po,svc,ingress -l "$APP_LABEL" -o wide

echo
echo "== Recent events =="
kubectl -n "$NAMESPACE" get events --sort-by=.lastTimestamp | tail -n 20

echo
echo "== Resource usage =="
if ! kubectl -n "$NAMESPACE" top pod -l "$APP_LABEL"; then
  echo "metrics API is not available yet; skipping resource usage."
fi

echo
echo "== Recent logs =="
kubectl -n "$NAMESPACE" logs deploy/bento-price-predictor --tail="$LOG_TAIL"
