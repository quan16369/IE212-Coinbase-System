#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
NAMESPACE="${K8S_NAMESPACE:-app}"
IMAGE_URI="${IMAGE_URI:-}"
HELM_RELEASE="${HELM_RELEASE:-bento-price-predictor}"
HELM_CHART="${HELM_CHART:-charts/bento-price-predictor}"

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
    DEFAULT_IMAGE_TAG="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
    IMAGE_URI="${GAR_LOCATION}-docker.pkg.dev/${GCP_PROJECT_ID}/${GAR_REPOSITORY}/${BENTO_IMAGE_NAME:-coinbase-bento-price-predictor}:${IMAGE_TAG:-$DEFAULT_IMAGE_TAG}"
  fi
fi

if [[ -z "$IMAGE_URI" ]]; then
  echo "IMAGE_URI is required. Push the image first or set IMAGE_URI explicitly."
  exit 1
fi

IMAGE_REPOSITORY="${IMAGE_URI%:*}"
IMAGE_TAG="${IMAGE_URI##*:}"

kubectl apply -f k8s/bento/namespace.yaml
kubectl -n "$NAMESPACE" delete configmap bento-model-artifact --ignore-not-found

helm upgrade --install "$HELM_RELEASE" "$HELM_CHART" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --set image.repository="$IMAGE_REPOSITORY" \
  --set image.tag="$IMAGE_TAG"

kubectl -n "$NAMESPACE" rollout status deployment/"$HELM_RELEASE" --timeout=180s

echo "Deployed BentoML predictor image: $IMAGE_URI"
echo "Test locally with:"
echo "  kubectl -n $NAMESPACE port-forward svc/bento-price-predictor 3001:80"
