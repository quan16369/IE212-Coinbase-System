#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
NAMESPACE="${K8S_NAMESPACE:-app}"
MODEL_ARTIFACT="${MODEL_ARTIFACT:-artifacts/mlops/coinbase_ml_model.joblib}"
IMAGE_URI="${IMAGE_URI:-}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "./$ENV_FILE"
  set +a
fi

if [[ -z "$IMAGE_URI" ]]; then
  if [[ -f artifacts/mlops/bento_image_uri.txt ]]; then
    IMAGE_URI="$(cat artifacts/mlops/bento_image_uri.txt)"
  elif [[ -n "${GCP_PROJECT_ID:-}" && -n "${GAR_LOCATION:-}" && -n "${GAR_REPOSITORY:-}" ]]; then
    IMAGE_URI="${GAR_LOCATION}-docker.pkg.dev/${GCP_PROJECT_ID}/${GAR_REPOSITORY}/${BENTO_IMAGE_NAME:-coinbase-bento-price-predictor}:${IMAGE_TAG:-dev}"
  fi
fi

if [[ -z "$IMAGE_URI" ]]; then
  echo "IMAGE_URI is required. Push the image first or set IMAGE_URI explicitly."
  exit 1
fi

if [[ ! -f "$MODEL_ARTIFACT" ]]; then
  echo "Model artifact not found: $MODEL_ARTIFACT"
  echo "Train the model first or set MODEL_ARTIFACT to a local .joblib file."
  exit 1
fi

TMP_DEPLOYMENT="$(mktemp)"
trap 'rm -f "$TMP_DEPLOYMENT"' EXIT

sed "s|IMAGE_PLACEHOLDER|${IMAGE_URI}|g" k8s/bento/deployment.yaml > "$TMP_DEPLOYMENT"

kubectl apply -f k8s/bento/namespace.yaml
kubectl -n "$NAMESPACE" create configmap bento-model-artifact \
  --from-file=coinbase_ml_model.joblib="$MODEL_ARTIFACT" \
  --dry-run=client -o yaml | kubectl replace -f - 2>/dev/null || \
  kubectl -n "$NAMESPACE" create configmap bento-model-artifact \
    --from-file=coinbase_ml_model.joblib="$MODEL_ARTIFACT"
kubectl apply -f "$TMP_DEPLOYMENT"
kubectl apply -f k8s/bento/service.yaml
kubectl -n "$NAMESPACE" rollout status deployment/bento-price-predictor --timeout=180s

echo "Deployed BentoML predictor image: $IMAGE_URI"
echo "Test locally with:"
echo "  kubectl -n $NAMESPACE port-forward svc/bento-price-predictor 3001:80"
