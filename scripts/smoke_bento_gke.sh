#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${K8S_NAMESPACE:-app}"
DEPLOYMENT="${BENTO_DEPLOYMENT:-bento-price-predictor}"
APP_LABEL="${BENTO_APP_LABEL:-app.kubernetes.io/name=bento-price-predictor}"
SERVICE="${BENTO_SERVICE:-bento-price-predictor}"

POD="$(kubectl -n "$NAMESPACE" get pod -l "$APP_LABEL" \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1:].metadata.name}')"

if [[ -z "$POD" ]]; then
  echo "No BentoML pod found in namespace $NAMESPACE with label $APP_LABEL."
  exit 1
fi

kubectl -n "$NAMESPACE" wait --for=condition=Ready "pod/$POD" --timeout=120s

for attempt in 1 2 3 4 5; do
  if kubectl -n "$NAMESPACE" exec "$POD" -- sh -c \
    "curl -fsS http://$SERVICE/readyz && curl -fsS -X POST http://$SERVICE/health"; then
    echo
    echo "GKE Bento smoke test passed for deployment $DEPLOYMENT on pod $POD."
    exit 0
  fi

  echo "Smoke test attempt $attempt failed; retrying..."
  sleep 5
done

echo
echo "GKE Bento smoke test failed for deployment $DEPLOYMENT on pod $POD."
exit 1
