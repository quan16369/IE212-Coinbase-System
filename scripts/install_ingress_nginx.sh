#!/usr/bin/env bash
set -euo pipefail

RELEASE="${INGRESS_NGINX_RELEASE:-ingress-nginx}"
NAMESPACE="${INGRESS_NGINX_NAMESPACE:-ingress-nginx}"
CHART="${INGRESS_NGINX_CHART:-ingress-nginx/ingress-nginx}"
REPO_NAME="${INGRESS_NGINX_REPO_NAME:-ingress-nginx}"
REPO_URL="${INGRESS_NGINX_REPO_URL:-https://kubernetes.github.io/ingress-nginx}"

helm repo add "$REPO_NAME" "$REPO_URL" >/dev/null
helm repo update "$REPO_NAME"

helm upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" \
  --create-namespace

echo "Installed nginx ingress release: $RELEASE"
echo "Namespace: $NAMESPACE"
echo "Check public IP with:"
echo "  kubectl -n $NAMESPACE get svc ${RELEASE}-controller"
