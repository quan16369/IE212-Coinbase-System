#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${K8S_NAMESPACE:-app}"
DEPLOYMENT="${BENTO_DEPLOYMENT:-bento-price-predictor}"
APP_LABEL="${BENTO_APP_LABEL:-app.kubernetes.io/name=bento-price-predictor}"

POD="$(kubectl -n "$NAMESPACE" get pod -l "$APP_LABEL" \
  -o jsonpath='{.items[0].metadata.name}')"

if [[ -z "$POD" ]]; then
  echo "No BentoML pod found in namespace $NAMESPACE with label $APP_LABEL."
  exit 1
fi

kubectl -n "$NAMESPACE" wait --for=condition=Ready "pod/$POD" --timeout=120s

kubectl -n "$NAMESPACE" exec "$POD" -- curl -fsS http://localhost:3000/readyz
kubectl -n "$NAMESPACE" exec "$POD" -- curl -fsS -X POST http://localhost:3000/health

echo
echo "GKE Bento smoke test passed for deployment $DEPLOYMENT on pod $POD."
