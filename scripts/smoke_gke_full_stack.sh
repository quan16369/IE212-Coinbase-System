#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${INFERENCE_ORCHESTRATOR_URL:-}" ]]; then
  INFERENCE_ORCHESTRATOR_URL="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='http://{.status.loadBalancer.ingress[0].ip}')"
fi

if [[ -z "$INFERENCE_ORCHESTRATOR_URL" || "$INFERENCE_ORCHESTRATOR_URL" == "http://" ]]; then
  echo "Inference orchestrator public URL is not ready." >&2
  exit 1
fi

echo "Testing public inference orchestrator at $INFERENCE_ORCHESTRATOR_URL"
INFERENCE_ORCHESTRATOR_URL="$INFERENCE_ORCHESTRATOR_URL" python scripts/smoke_inference_orchestrator.py

echo
echo "Checking Kubernetes rollout status"
kubectl -n app rollout status deployment/bento-price-predictor --timeout=180s
kubectl -n feature-platform rollout status deployment/feature-platform --timeout=180s
kubectl -n data-ingestion rollout status deployment/data-validation --timeout=180s
kubectl -n alert-routing rollout status deployment/alert-index --timeout=180s
kubectl -n alert-routing rollout status deployment/alert-rule-engine --timeout=180s
kubectl -n model-serving rollout status deployment/inference-orchestrator --timeout=180s

echo
echo "Checking feature-platform store status"
kubectl -n feature-platform exec deploy/feature-platform -- python - <<'PY'
import json
import urllib.request

with urllib.request.urlopen("http://localhost:8080/store/status", timeout=10) as response:
    payload = json.loads(response.read().decode())
print(json.dumps(payload, indent=2))
if not payload["online"]["connected"] or not payload["offline"]["connected"]:
    raise SystemExit(1)
PY

echo
echo "Full GKE stack smoke test passed."
