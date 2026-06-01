#!/usr/bin/env bash
set -euo pipefail

INGRESS_NAMESPACE="${INGRESS_NAMESPACE:-ingress-nginx}"
INGRESS_SERVICE="${INGRESS_SERVICE:-ingress-nginx-controller}"
PUBLIC_URL="${BENTO_PUBLIC_URL:-}"

if [[ -z "$PUBLIC_URL" ]]; then
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    INGRESS_ADDRESS="$(kubectl -n "$INGRESS_NAMESPACE" get svc "$INGRESS_SERVICE" \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"

    if [[ -n "$INGRESS_ADDRESS" ]]; then
      PUBLIC_URL="http://$INGRESS_ADDRESS"
      break
    fi

    echo "Waiting for ingress address..."
    sleep 10
  done
fi

if [[ -z "$PUBLIC_URL" ]]; then
  echo "Could not determine Bento public URL."
  echo "Set BENTO_PUBLIC_URL or install nginx ingress and enable Bento ingress first."
  exit 1
fi

PUBLIC_URL="${PUBLIC_URL%/}"

curl -fsS "$PUBLIC_URL/readyz"
curl -fsS -X POST "$PUBLIC_URL/health"

echo
echo "Public Bento smoke test passed at $PUBLIC_URL."
