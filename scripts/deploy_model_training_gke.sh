#!/usr/bin/env bash
set -euo pipefail

set -a
. ./.env
set +a

NAMESPACE="${MODEL_TRAINING_NAMESPACE:-model-training}"
IMAGE_URI="${IMAGE_URI:-}"
if [[ -z "$IMAGE_URI" && -f artifacts/model-training/training_image_uri.txt ]]; then
  IMAGE_URI="$(cat artifacts/model-training/training_image_uri.txt)"
fi
: "${IMAGE_URI:?Push the model-training image first}"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install model-training charts/model-training \
  --namespace "$NAMESPACE" \
  --atomic --timeout "${HELM_TIMEOUT:-300s}" \
  --set namespace="$NAMESPACE" \
  --set training.image.repository="${IMAGE_URI%:*}" \
  --set training.image.tag="${IMAGE_URI##*:}"
kubectl -n "$NAMESPACE" rollout status statefulset/mlflow --timeout=180s
