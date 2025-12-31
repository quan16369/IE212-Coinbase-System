# Production Deployment Guide - Crypto Pipeline

## Overview

This is a deployment guide for the **Kappa Architecture + Continuous Learning** system for the cryptocurrency price prediction project to a Production environment with a SOTA (State-of-the-art) stack.

## Architecture Stack

### Infrastructure Layer
- **Kubernetes (EKS)**: Container orchestration
- **Terraform**: Infrastructure as Code with modular structure
- **Helm**: Package management for Kubernetes

### Data Streaming Layer
- **Kafka** (3 brokers): Distributed streaming platform
- **Zookeeper** (3 nodes): Kafka coordination
- **Spark Streaming**: Real-time data processing

### Storage Layer
- **Cassandra** (3 nodes): Time-series data storage
- **EFS**: Shared storage for models
- **S3**: Data lake and model artifacts

### MLOps Layer
- **MLflow**: Model tracking and registry
- **Seldon Core**: Model serving with canary deployment
- **Continuous Learning**: Auto-retrain every 6 hours

### Observability Layer
- **Prometheus**: Metrics collection
- **Grafana**: Visualization dashboards
- **Alertmanager**: Alert management
- **Loki**: Log aggregation

### GitOps Layer
- **ArgoCD**: Continuous deployment
- **GitHub Actions**: CI/CD automation

## Project Structure

```
.
├── k8s/                      # Kubernetes manifests
│   ├── namespace.yaml
│   ├── kafka-statefulset.yaml
│   ├── cassandra-statefulset.yaml
│   ├── producer-deployment.yaml
│   ├── spark-processor-deployment.yaml
│   └── prediction-service-deployment.yaml
├── helm/                     # Helm charts
│   ├── Chart.yaml
│   ├── values.yaml
│   └── install.sh
├── terraform/               # Infrastructure as Code
│   ├── main.tf
│   ├── eks.tf
│   ├── addons.tf
│   └── deploy.sh
├── mlops/                   # MLOps configurations
│   ├── mlflow-deployment.yaml
│   ├── seldon-deployment.yaml
│   ├── mlflow_manager.py
│   └── continuous-learning-cronjob.yaml
├── monitoring/              # Observability
│   ├── prometheus-config.yaml
│   ├── prometheus-rules.yaml
│   ├── grafana-production-dashboard.json
│   └── alertmanager-config.yaml
├── argocd/                  # GitOps
│   ├── application-*.yaml
│   └── install.sh
└── .github/workflows/       # CI/CD pipelines
    ├── ci-cd.yml
    ├── infrastructure.yml
    └── continuous-learning.yml
```

## Deployment Steps

### Step 1: Prerequisites

```bash
# Install required tools
# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Terraform
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Configure AWS credentials
aws configure
```

### Step 2: Deploy Infrastructure with Terraform

```bash
cd terraform

# Initialize Terraform
terraform init

# Plan infrastructure
terraform plan

# Apply infrastructure (creates EKS cluster, VPC, S3, ECR, EFS)
terraform apply

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name crypto-pipeline-cluster

# Verify cluster
kubectl get nodes
```

**Resources Created:**
- EKS Cluster with 3 node groups (stateful, compute, general)
- VPC with public/private subnets
- S3 bucket for data lake
- ECR repositories for Docker images
- EFS for shared model storage
- IAM roles for services

### Step 3: Install Core Dependencies with Helm

```bash
cd ../helm

# Make install script executable
chmod +x install.sh

# Install all dependencies
./install.sh
```

**Components Installed:**
- Kafka (3 replicas)
- Zookeeper (3 replicas)
- Cassandra (3 replicas)
- Prometheus & Grafana
- MLflow with PostgreSQL
- Seldon Core

### Step 4: Deploy ArgoCD for GitOps

```bash
cd ../argocd

# Make install script executable
chmod +x install.sh

# Install ArgoCD
./install.sh

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login with displayed credentials
# Username: admin
# Password: (shown in terminal)
```

### Step 5: Configure GitHub Secrets

Go to **GitHub Repository Settings** → **Secrets and variables** → **Actions**, add:

```
AWS_ACCESS_KEY_ID=your_aws_access_key
AWS_SECRET_ACCESS_KEY=your_aws_secret_key
ECR_REGISTRY=123456789.dkr.ecr.us-east-1.amazonaws.com
SLACK_WEBHOOK=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

### Step 6: Build and Push Docker Images

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REGISTRY

# Build Producer
cd coinbase_kafka_producer
docker build -t $ECR_REGISTRY/coinbase-producer:latest -f producer.Dockerfile .
docker push $ECR_REGISTRY/coinbase-producer:latest

# Build Spark Processor
cd ../kafka_spark_processor
docker build -t $ECR_REGISTRY/spark-processor:latest -f processor.Dockerfile .
docker push $ECR_REGISTRY/spark-processor:latest

# Build Prediction Service
cd ../prediction_service
docker build -t $ECR_REGISTRY/prediction-service:latest -f prediction.Dockerfile .
docker push $ECR_REGISTRY/prediction-service:latest
```

Or simply: **Push code to GitHub**, and the CI/CD pipeline will automatically build!

### Step 7: Deploy Services via ArgoCD

```bash
# Update ArgoCD applications with your Git repo
sed -i 's|YOUR_USERNAME|your-github-username|g' argocd/*.yaml
sed -i 's|YOUR_ECR_REGISTRY|your-ecr-registry|g' argocd/*.yaml

# Apply ArgoCD applications
kubectl apply -f argocd/application-crypto-pipeline.yaml
kubectl apply -f argocd/application-monitoring.yaml
kubectl apply -f argocd/application-mlops.yaml

# Watch deployment
kubectl get applications -n argocd
kubectl get pods -n crypto-pipeline
```

### Step 8: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n crypto-pipeline
kubectl get pods -n crypto-mlops
kubectl get pods -n crypto-monitoring

# Check services
kubectl get svc -n crypto-pipeline

# Check StatefulSets
kubectl get statefulsets -n crypto-pipeline

# View logs
kubectl logs -f deployment/prediction-service -n crypto-pipeline
```

## Access Dashboards

### Grafana Dashboard
```bash
kubectl port-forward -n crypto-monitoring svc/prometheus-grafana 3000:80
# Access: http://localhost:3000
# User: admin, Password: admin123
```

### MLflow UI
```bash
kubectl port-forward -n crypto-mlops svc/mlflow 5000:5000
# Access: http://localhost:5000
```

### Prometheus UI
```bash
kubectl port-forward -n crypto-monitoring svc/prometheus-server 9090:80
# Access: http://localhost:9090
```

### ArgoCD UI
```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Access: https://localhost:8080
```

## Continuous Learning Workflow

### Automatic Retraining (Every 6 hours)

CronJob runs automatically:
```bash
# Check CronJob status
kubectl get cronjobs -n crypto-mlops

# View retraining history
kubectl get jobs -n crypto-mlops

# Check retraining logs
kubectl logs -n crypto-mlops job/model-retraining-xxxxx
```

### Manual Retraining

```bash
# Trigger manual retraining
kubectl create job --from=cronjob/model-retraining manual-retrain-$(date +%s) -n crypto-mlops

# Monitor training
kubectl logs -f job/manual-retrain-xxxxx -n crypto-mlops
```

### Model Promotion Flow

1. **Train**: Model is trained with the latest data
2. **Track**: MLflow logs metrics, params, artifacts
3. **Compare**: Compare with Production model
4. **Auto-Promote**: If MAE decreases > 2% → automatically promote
5. **Canary**: Deploy with 10% traffic
6. **Monitor**: Monitor error rate for 5 minutes
7. **Full Rollout**: If OK → 100% traffic

## Monitoring & Alerts

### Critical Alerts (PagerDuty)
- Service down > 2 minutes
- Kafka cluster down
- Cassandra node down
- Canary deployment errors > 10%

### Warning Alerts (Slack)
- High prediction latency > 1s
- Error rate > 5%
- Memory usage > 90%
- CPU usage > 80%
- Kafka consumer lag > 10k messages
- Model accuracy drift (MAE > 0.1)

### Custom Metrics

```bash
# View prediction latency
kubectl exec -n crypto-monitoring prometheus-0 -- promtool query instant \
  'histogram_quantile(0.95, rate(prediction_duration_seconds_bucket[5m]))'

# View error rate
kubectl exec -n crypto-monitoring prometheus-0 -- promtool query instant \
  'rate(prediction_errors_total[5m])'

# View Kafka lag
kubectl exec -n crypto-monitoring prometheus-0 -- promtool query instant \
  'kafka_consumergroup_lag{topic="crypto-prices"}'
```

## Troubleshooting

### Service Not Starting

```bash
# Check pod status
kubectl describe pod <pod-name> -n crypto-pipeline

# Check logs
kubectl logs <pod-name> -n crypto-pipeline --previous

# Check events
kubectl get events -n crypto-pipeline --sort-by='.lastTimestamp'
```

### Kafka Issues

```bash
# Check Kafka brokers
kubectl exec -it kafka-0 -n crypto-pipeline -- kafka-broker-api-versions --bootstrap-server localhost:9092

# List topics
kubectl exec -it kafka-0 -n crypto-pipeline -- kafka-topics --list --bootstrap-server localhost:9092

# Check consumer group lag
kubectl exec -it kafka-0 -n crypto-pipeline -- kafka-consumer-groups \
  --bootstrap-server localhost:9092 --describe --group spark-consumer-group
```

### Cassandra Issues

```bash
# Check cluster status
kubectl exec -it cassandra-0 -n crypto-pipeline -- nodetool status

# Check data
kubectl exec -it cassandra-0 -n crypto-pipeline -- cqlsh -e "SELECT * FROM crypto_data.predictions LIMIT 10;"
```

### Model Serving Issues

```bash
# Check Seldon deployment
kubectl get seldondeployments -n crypto-pipeline

# View Seldon logs
kubectl logs -l seldon-app=crypto-model-serving -n crypto-pipeline

# Test prediction endpoint
kubectl port-forward svc/crypto-model-serving-default 8080:8000 -n crypto-pipeline
curl -X POST http://localhost:8080/api/v1.0/predictions \
  -H "Content-Type: application/json" \
  -d '{"data": {"ndarray": [[1,2,3,4,5]]}}'
```

## Scaling

### Horizontal Pod Autoscaling (HPA)

Already pre-configured:
```bash
# Check HPA status
kubectl get hpa -n crypto-pipeline

# Scale prediction service based on CPU/Memory/RPS
# Min: 3, Max: 10 replicas
```

### Cluster Autoscaling

```bash
# Check node autoscaler
kubectl get pods -n kube-system | grep cluster-autoscaler

# View autoscaler logs
kubectl logs -f deployment/cluster-autoscaler -n kube-system
```

### Manual Scaling

```bash
# Scale prediction service
kubectl scale deployment prediction-service --replicas=5 -n crypto-pipeline

# Scale Kafka brokers
kubectl scale statefulset kafka --replicas=5 -n crypto-pipeline
```

## Cost Optimization

### Current Estimated Costs (Monthly)

- **EKS Cluster**: ~$73
- **EC2 Instances**: ~$1,500 (r6i.2xlarge × 3 + c6i.4xlarge × 3 + m6i.2xlarge × 3)
- **EBS Volumes**: ~$200 (2TB total)
- **EFS**: ~$50
- **S3**: ~$10
- **NAT Gateway**: ~$100
- **Data Transfer**: ~$50
- **ALB**: ~$20

**Total**: ~$2,000/month

### Cost Reduction Tips

1. **Use Spot Instances** cho compute node group (save 70%)
2. **Right-size instances** based on monitoring
3. **Enable EBS/EFS lifecycle policies**
4. **Use S3 Intelligent-Tiering**
5. **Schedule non-prod environments** (stop at night)

## Security Best Practices

- All data encrypted at rest (EBS, EFS, S3)
- All data encrypted in transit (TLS)
- Network isolation with VPC, security groups
- RBAC enabled on Kubernetes
- Image scanning with Trivy
- Secret management with Kubernetes Secrets
- IAM roles for service accounts (IRSA)

## Next Steps

1. **Setup Custom Domain** with Route53 and ALB Ingress
2. **Enable Service Mesh** (Istio) for advanced traffic management
3. **Implement A/B Testing** with Seldon's Traffic Splitting
4. **Setup Disaster Recovery** with cross-region replication
5. **Enable Cost Monitoring** with AWS Cost Explorer
6. **Setup Log Aggregation** with ELK Stack
7. **Implement Chaos Engineering** with Chaos Mesh

## Contributing

1. Fork the repository
2. Create feature branch
3. Commit changes
4. Push to branch
5. Create Pull Request

## Support

- **Slack**: #crypto-pipeline-support
- **Email**: devops@example.com
- **PagerDuty**: On-call rotation

## License

MIT License

---

**Built by the Crypto Pipeline Team**
