#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${K8S_NAMESPACE:-app}"
RELEASE="${HELM_RELEASE:-bento-price-predictor}"
RUN_FULL_E2E="${RUN_FULL_E2E_AFTER_DEPLOY:-true}"
RUN_PUBLIC_SMOKE="${SMOKE_GKE_PUBLIC:-false}"
PREVIOUS_REVISION="$(helm -n "$NAMESPACE" status "$RELEASE" -o json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])' 2>/dev/null || true)"

rollback() {
  exit_code=$?
  if [[ "$exit_code" -eq 0 ]]; then
    return
  fi
  echo "Deployment or smoke test failed. Starting automatic rollback." >&2
  if [[ -n "$PREVIOUS_REVISION" ]]; then
    helm -n "$NAMESPACE" rollback "$RELEASE" "$PREVIOUS_REVISION" --wait --timeout "${ROLLBACK_TIMEOUT:-300s}"
    kubectl -n "$NAMESPACE" rollout status "deployment/$RELEASE" --timeout=180s
    echo "Rolled back $RELEASE to Helm revision $PREVIOUS_REVISION." >&2
  else
    helm -n "$NAMESPACE" uninstall "$RELEASE" --wait 2>/dev/null || true
    echo "No previous revision existed; removed failed first deployment." >&2
  fi
  exit "$exit_code"
}
trap rollback EXIT

bash scripts/deploy_bento_gke.sh
bash scripts/smoke_bento_gke.sh

if [[ "$RUN_FULL_E2E" == "true" ]]; then
  bash scripts/smoke_streaming_e2e.sh
  bash scripts/smoke_gke_full_stack.sh
fi

if [[ "$RUN_PUBLIC_SMOKE" == "true" ]]; then
  bash scripts/smoke_bento_public.sh
fi

trap - EXIT
echo "Deployment transaction passed. Automatic rollback was not required."
