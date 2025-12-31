#!/bin/bash
# Helm Installation Script for Crypto Pipeline

set -e

echo "🚀 Installing Crypto Pipeline using Helm..."

# Add required Helm repositories
echo "📦 Adding Helm repositories..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add jetstack https://charts.jetstack.io
helm repo add seldon https://storage.googleapis.com/seldon-charts
helm repo update

# Install cert-manager (required for Seldon)
echo "🔐 Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
echo "⏳ Waiting for cert-manager..."
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager-webhook -n cert-manager

# Create namespaces
echo "🏗️  Creating namespaces..."
kubectl apply -f ../k8s/namespace.yaml

# Install Seldon Core
echo "🤖 Installing Seldon Core..."
helm install seldon-core seldon/seldon-core-operator \
  --namespace crypto-mlops \
  --set usageMetrics.enabled=true \
  --set istio.enabled=true

# Install main crypto pipeline
echo "📊 Installing Crypto Pipeline..."
helm install crypto-pipeline . \
  --namespace crypto-pipeline \
  --create-namespace \
  --values values.yaml \
  --timeout 10m

# Install monitoring stack
echo "📈 Installing Monitoring Stack..."
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace crypto-monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=100Gi

# Install MLflow
echo "🧪 Installing MLflow..."
helm install mlflow oci://registry-1.docker.io/bitnamicharts/mlflow \
  --namespace crypto-mlops \
  --set tracking.auth.enabled=false \
  --set postgresql.enabled=true \
  --set persistence.enabled=true \
  --set persistence.size=100Gi

echo "✅ Installation complete!"
echo ""
echo "📋 Next steps:"
echo "1. Check deployment status: kubectl get pods -n crypto-pipeline"
echo "2. Port-forward Grafana: kubectl port-forward -n crypto-monitoring svc/prometheus-grafana 3000:80"
echo "3. Port-forward MLflow: kubectl port-forward -n crypto-mlops svc/mlflow 5000:5000"
echo "4. Access Prediction Service: kubectl port-forward -n crypto-pipeline svc/prediction-service 8080:8080"
