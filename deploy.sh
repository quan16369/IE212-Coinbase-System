#!/bin/bash
# Quick Start Script - Deploy Everything

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   🚀 Crypto Pipeline Production Deployment               ║"
echo "║   SOTA Stack: K8s + Terraform + MLOps + GitOps          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
echo "📋 Checking prerequisites..."
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI is required but not installed. Aborting." >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl is required but not installed. Aborting." >&2; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "❌ Terraform is required but not installed. Aborting." >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "❌ Helm is required but not installed. Aborting." >&2; exit 1; }

echo "✅ All prerequisites installed!"
echo ""

# Configuration
read -p "AWS Region [us-east-1]: " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

read -p "Cluster Name [crypto-pipeline-cluster]: " CLUSTER_NAME
CLUSTER_NAME=${CLUSTER_NAME:-crypto-pipeline-cluster}

read -p "Your GitHub Username: " GITHUB_USERNAME
if [ -z "$GITHUB_USERNAME" ]; then
    echo "❌ GitHub username is required!"
    exit 1
fi

echo ""
echo "🔧 Configuration:"
echo "   AWS Region: $AWS_REGION"
echo "   Cluster Name: $CLUSTER_NAME"
echo "   GitHub: $GITHUB_USERNAME"
echo ""
read -p "Continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Deployment cancelled."
    exit 0
fi

# Step 1: Deploy Infrastructure
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Step 1/6: Deploying Infrastructure with Terraform"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cd terraform
terraform init
terraform apply -auto-approve \
  -var="aws_region=$AWS_REGION" \
  -var="cluster_name=$CLUSTER_NAME"

# Configure kubectl
echo "⚙️  Configuring kubectl..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "✅ Infrastructure deployed!"
cd ..

# Step 2: Install Helm Dependencies
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Step 2/6: Installing Core Dependencies with Helm"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cd helm
chmod +x install.sh
./install.sh
cd ..

# Step 3: Deploy ArgoCD
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Step 3/6: Setting up GitOps with ArgoCD"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cd argocd

# Update ArgoCD configs with GitHub username
sed -i "s|YOUR_USERNAME|$GITHUB_USERNAME|g" *.yaml

chmod +x install.sh
./install.sh
cd ..

# Step 4: Build and Push Images
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Step 4/6: Building and Pushing Docker Images"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ECR_REGISTRY=$(terraform output -raw ecr_repositories | jq -r '.["coinbase-producer"]' | cut -d'/' -f1)
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"

echo "🔨 Building Producer..."
cd coinbase_kafka_producer
docker build -t "$ECR_REGISTRY/coinbase-producer:latest" -f producer.Dockerfile .
docker push "$ECR_REGISTRY/coinbase-producer:latest"
cd ..

echo "🔨 Building Spark Processor..."
cd kafka_spark_processor
docker build -t "$ECR_REGISTRY/spark-processor:latest" -f processor.Dockerfile .
docker push "$ECR_REGISTRY/spark-processor:latest"
cd ..

echo "🔨 Building Prediction Service..."
cd prediction_service
docker build -t "$ECR_REGISTRY/prediction-service:latest" -f prediction.Dockerfile .
docker push "$ECR_REGISTRY/prediction-service:latest"
cd ..

# Step 5: Deploy Applications
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Step 5/6: Deploying Applications"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Wait for ArgoCD to be ready
kubectl wait --for=condition=Ready --timeout=300s pod -l app.kubernetes.io/name=argocd-server -n argocd

# Sync ArgoCD applications
kubectl apply -f argocd/application-crypto-pipeline.yaml
kubectl apply -f argocd/application-monitoring.yaml
kubectl apply -f argocd/application-mlops.yaml

echo "⏳ Waiting for applications to sync..."
sleep 30

# Step 6: Verification
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Step 6/6: Verifying Deployment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "🔍 Checking ArgoCD Applications:"
kubectl get applications -n argocd

echo ""
echo "🔍 Checking Pods in crypto-pipeline:"
kubectl get pods -n crypto-pipeline

echo ""
echo "🔍 Checking Pods in crypto-mlops:"
kubectl get pods -n crypto-mlops

echo ""
echo "🔍 Checking Pods in crypto-monitoring:"
kubectl get pods -n crypto-monitoring

# Get ArgoCD password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   ✅ Deployment Completed Successfully!                  ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "📊 Access Your Dashboards:"
echo ""
echo "1️⃣  ArgoCD UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   URL: https://localhost:8080"
echo "   User: admin"
echo "   Pass: $ARGOCD_PASSWORD"
echo ""
echo "2️⃣  Grafana Dashboard:"
echo "   kubectl port-forward -n crypto-monitoring svc/prometheus-grafana 3000:80"
echo "   URL: http://localhost:3000"
echo "   User: admin"
echo "   Pass: admin123"
echo ""
echo "3️⃣  MLflow UI:"
echo "   kubectl port-forward -n crypto-mlops svc/mlflow 5000:5000"
echo "   URL: http://localhost:5000"
echo ""
echo "4️⃣  Prometheus:"
echo "   kubectl port-forward -n crypto-monitoring svc/prometheus-server 9090:80"
echo "   URL: http://localhost:9090"
echo ""
echo "📋 Useful Commands:"
echo ""
echo "   # View all pods"
echo "   kubectl get pods --all-namespaces"
echo ""
echo "   # Check logs"
echo "   kubectl logs -f deployment/prediction-service -n crypto-pipeline"
echo ""
echo "   # Scale services"
echo "   kubectl scale deployment prediction-service --replicas=5 -n crypto-pipeline"
echo ""
echo "   # Trigger manual retraining"
echo "   kubectl create job --from=cronjob/model-retraining manual-train -n crypto-mlops"
echo ""
echo "📚 Documentation:"
echo "   - Deployment Guide: DEPLOYMENT.md"
echo "   - Stack Overview: STACK_OVERVIEW.md"
echo ""
echo "💡 Next Steps:"
echo "   1. Configure GitHub Secrets for CI/CD"
echo "   2. Push code to trigger automated deployment"
echo "   3. Monitor dashboards and set up alerts"
echo "   4. Configure custom domain with Route53"
echo ""
echo "🎉 Happy Coding!"
