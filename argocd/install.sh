#!/bin/bash
# ArgoCD Installation Script

set -e

echo "🚀 Installing ArgoCD..."

# Install ArgoCD
kubectl create namespace argocd || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "⏳ Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=Available --timeout=300s deployment/argocd-server -n argocd

# Get initial admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "✅ ArgoCD installed successfully!"
echo ""
echo "📋 Access Information:"
echo "   Username: admin"
echo "   Password: $ARGOCD_PASSWORD"
echo ""
echo "🌐 Port-forward to access UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Then open: https://localhost:8080"
echo ""
echo "💡 Or use LoadBalancer:"
echo "   kubectl patch svc argocd-server -n argocd -p '{\"spec\": {\"type\": \"LoadBalancer\"}}'"

# Apply ArgoCD applications
echo ""
echo "📦 Installing ArgoCD Applications..."
kubectl apply -f application-crypto-pipeline.yaml
kubectl apply -f application-monitoring.yaml
kubectl apply -f application-mlops.yaml

echo "✅ ArgoCD setup complete!"
