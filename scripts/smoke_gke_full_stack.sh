#!/usr/bin/env bash
set -euo pipefail

PORT_FORWARD_PID=""
cleanup() {
  if [[ -n "$PORT_FORWARD_PID" ]]; then
    kill "$PORT_FORWARD_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ -z "${INFERENCE_ORCHESTRATOR_URL:-}" ]]; then
  INFERENCE_ORCHESTRATOR_URL="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='http://{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
fi

if [[ -z "$INFERENCE_ORCHESTRATOR_URL" || "$INFERENCE_ORCHESTRATOR_URL" == "http://" ]]; then
  LOCAL_PORT="${INFERENCE_ORCHESTRATOR_SMOKE_PORT:-18091}"
  kubectl -n model-serving port-forward svc/inference-orchestrator "$LOCAL_PORT:80" >/tmp/inference-orchestrator-smoke-port-forward.log 2>&1 &
  PORT_FORWARD_PID=$!
  INFERENCE_ORCHESTRATOR_URL="http://localhost:$LOCAL_PORT"
  for _ in $(seq 1 30); do
    if curl -fsS "$INFERENCE_ORCHESTRATOR_URL/readyz" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  curl -fsS "$INFERENCE_ORCHESTRATOR_URL/readyz" >/dev/null
fi

echo "Testing public inference orchestrator at $INFERENCE_ORCHESTRATOR_URL"
INFERENCE_ORCHESTRATOR_URL="$INFERENCE_ORCHESTRATOR_URL" python scripts/smoke_inference_orchestrator.py

echo
echo "Checking Kubernetes rollout status"
kubectl -n app rollout status deployment/bento-price-predictor --timeout=180s
kubectl -n feature-platform rollout status deployment/feature-platform --timeout=180s
kubectl -n data-ingestion rollout status deployment/data-validation --timeout=180s
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
