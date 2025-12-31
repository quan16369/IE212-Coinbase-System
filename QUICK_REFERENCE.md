# Quick Reference Guide

## TL;DR - Deploy in 5 Minutes

```bash
# 1. Clone repo
git clone YOUR_REPO
cd Coinbase_Streaming_Data_Pipeline_for_Cryptocurrency_Price_Forecasting

# 2. For Development (Local)
docker-compose up -d

# 3. For Production (AWS)
./deploy.sh
```

## Common Commands Cheat Sheet

### Docker Compose (Development)

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f [service_name]

# Restart service
docker-compose restart [service_name]

# Stop everything
docker-compose down

# Rebuild service
docker-compose up -d --build [service_name]
```

### Kubernetes (Production)

```bash
# Get all resources
kubectl get all -n crypto-pipeline

# Check pod status
kubectl get pods -n crypto-pipeline

# View logs
kubectl logs -f deployment/prediction-service -n crypto-pipeline

# Execute into pod
kubectl exec -it pod-name -n crypto-pipeline -- bash

# Port forward service
kubectl port-forward svc/prediction-service 8080:8080 -n crypto-pipeline

# Scale deployment
kubectl scale deployment prediction-service --replicas=5 -n crypto-pipeline

# Delete pod (will auto-restart)
kubectl delete pod pod-name -n crypto-pipeline
```

### Terraform

```bash
# Initialize
terraform init

# Plan changes
terraform plan

# Apply changes
terraform apply

# Destroy infrastructure
terraform destroy

# Show current state
terraform show

# List resources
terraform state list
```

### Helm

```bash
# Install chart
helm install crypto-pipeline ./helm

# Upgrade chart
helm upgrade crypto-pipeline ./helm

# Uninstall chart
helm uninstall crypto-pipeline

# List installed charts
helm list

# Get values
helm get values crypto-pipeline
```

### ArgoCD

```bash
# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forward UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Sync application
kubectl patch application crypto-pipeline -n argocd -p '{"operation": {"initiatedBy": {"username": "admin"}, "sync": {}}}' --type merge

# List applications
kubectl get applications -n argocd
```

### MLflow

```bash
# Port forward MLflow UI
kubectl port-forward -n crypto-mlops svc/mlflow 5000:5000

# Trigger manual retraining
kubectl create job --from=cronjob/model-retraining manual-retrain-$(date +%s) -n crypto-mlops

# Check retraining jobs
kubectl get jobs -n crypto-mlops

# View retraining logs
kubectl logs job/model-retraining-xxxxx -n crypto-mlops
```

### Prometheus & Grafana

```bash
# Port forward Grafana
kubectl port-forward -n crypto-monitoring svc/prometheus-grafana 3000:80
# Access: http://localhost:3000 (admin/admin123)

# Port forward Prometheus
kubectl port-forward -n crypto-monitoring svc/prometheus-server 9090:80
# Access: http://localhost:9090

# Query metrics
kubectl exec -n crypto-monitoring prometheus-0 -- promtool query instant 'up'
```

### Kafka

```bash
# List topics
kubectl exec -it kafka-0 -n crypto-pipeline -- kafka-topics --list --bootstrap-server localhost:9092

# Describe topic
kubectl exec -it kafka-0 -n crypto-pipeline -- kafka-topics --describe --topic crypto-prices --bootstrap-server localhost:9092

# Consumer group lag
kubectl exec -it kafka-0 -n crypto-pipeline -- kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group spark-consumer

# Produce test message
kubectl exec -it kafka-0 -n crypto-pipeline -- kafka-console-producer --topic crypto-prices --bootstrap-server localhost:9092

# Consume messages
kubectl exec -it kafka-0 -n crypto-pipeline -- kafka-console-consumer --topic crypto-prices --from-beginning --bootstrap-server localhost:9092
```

### Cassandra

```bash
# Execute CQL
kubectl exec -it cassandra-0 -n crypto-pipeline -- cqlsh

# Check cluster status
kubectl exec -it cassandra-0 -n crypto-pipeline -- nodetool status

# Query data
kubectl exec -it cassandra-0 -n crypto-pipeline -- cqlsh -e "SELECT * FROM crypto_data.predictions LIMIT 10;"

# Describe keyspace
kubectl exec -it cassandra-0 -n crypto-pipeline -- cqlsh -e "DESCRIBE KEYSPACE crypto_data;"
```

## Troubleshooting Quick Fixes

### Pod Stuck in Pending
```bash
kubectl describe pod POD_NAME -n NAMESPACE
# Check: Insufficient CPU/memory? Node selector issues?
```

### Pod CrashLoopBackOff
```bash
kubectl logs POD_NAME -n NAMESPACE --previous
# Check: Configuration errors? Missing dependencies?
```

### Service Not Accessible
```bash
kubectl get svc -n NAMESPACE
kubectl get endpoints -n NAMESPACE
# Check: Selector matches pods? Ports correct?
```

### Kafka Consumer Lag Too High
```bash
# Scale up Spark processor
kubectl scale deployment spark-processor --replicas=5 -n crypto-pipeline
```

### Model Not Updating
```bash
# Check retraining job
kubectl get cronjobs -n crypto-mlops
kubectl get jobs -n crypto-mlops
kubectl logs job/model-retraining-xxxxx -n crypto-mlops
```

### High Memory Usage
```bash
# Check HPA status
kubectl get hpa -n crypto-pipeline

# Manually scale up
kubectl scale deployment prediction-service --replicas=10 -n crypto-pipeline
```

## Monitoring URLs

After port-forwarding, access:

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3000 | admin / admin123 |
| Prometheus | http://localhost:9090 | - |
| MLflow | http://localhost:5000 | - |
| ArgoCD | https://localhost:8080 | admin / (get from secret) |
| Prediction API | http://localhost:8080 | - |

## Emergency Procedures

### Rollback Deployment
```bash
# Using kubectl
kubectl rollout undo deployment/prediction-service -n crypto-pipeline

# Using ArgoCD
kubectl patch application crypto-pipeline -n argocd --type merge -p '{"spec": {"source": {"targetRevision": "previous-commit-hash"}}}'
```

### Stop Continuous Learning (Emergency)
```bash
kubectl patch cronjob model-retraining -n crypto-mlops -p '{"spec": {"suspend": true}}'
```

### Scale Down (Cost Saving)
```bash
# Scale non-essential services to 0
kubectl scale deployment producer --replicas=0 -n crypto-pipeline
kubectl scale deployment spark-processor --replicas=0 -n crypto-pipeline

# Keep only prediction service
kubectl scale deployment prediction-service --replicas=1 -n crypto-pipeline
```

### Full Restart
```bash
# Restart all deployments
kubectl rollout restart deployment -n crypto-pipeline
kubectl rollout restart deployment -n crypto-mlops
```

## Cost Optimization

### Stop Non-Production Hours
```bash
# Scale down at night (23:00)
kubectl scale deployment --all --replicas=0 -n crypto-pipeline

# Scale up in morning (08:00)
kubectl scale deployment producer --replicas=2 -n crypto-pipeline
kubectl scale deployment prediction-service --replicas=3 -n crypto-pipeline
```

### Use Spot Instances
Edit `terraform/variables.tf`:
```hcl
capacity_type = "SPOT"  # Add this to node group configs
```

## Security Checklist

- [ ] Change default passwords
- [ ] Rotate AWS access keys
- [ ] Enable pod security policies
- [ ] Setup network policies
- [ ] Enable audit logging
- [ ] Configure RBAC properly
- [ ] Scan images for vulnerabilities
- [ ] Encrypt secrets at rest
- [ ] Enable TLS for all services
- [ ] Setup backup strategy

## Getting Help

1. Check [DEPLOYMENT.md](./DEPLOYMENT.md) for detailed guide
2. Check [STACK_OVERVIEW.md](./STACK_OVERVIEW.md) for architecture
3. Check [PROJECT_STRUCTURE.md](./PROJECT_STRUCTURE.md) for file layout
4. View logs: `kubectl logs -f POD_NAME -n NAMESPACE`
5. Check events: `kubectl get events -n NAMESPACE --sort-by='.lastTimestamp'`

## Performance Tuning

### Kafka
```yaml
# Increase partitions
num.partitions=12

# Increase replication
default.replication.factor=3
```

### Cassandra
```yaml
# Tune memory
MAX_HEAP_SIZE=8G
HEAP_NEWSIZE=2G

# Increase concurrent writes
concurrent_writes=128
```

### Spark
```bash
# Increase executors
--conf spark.executor.instances=10
--conf spark.executor.memory=4g
--conf spark.executor.cores=4
```

### Prediction Service
```yaml
# Increase resources
resources:
  requests:
    memory: "4Gi"
    cpu: "2000m"
  limits:
    memory: "8Gi"
    cpu: "4000m"
```

## Useful Aliases

Add to `~/.bashrc`:

```bash
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods --all-namespaces'
alias kl='kubectl logs -f'
alias kdp='kubectl describe pod'
alias kgd='kubectl get deployments'
alias kgs='kubectl get services'

# Namespace shortcuts
alias kcp='kubectl -n crypto-pipeline'
alias kcm='kubectl -n crypto-mlops'
alias kmon='kubectl -n crypto-monitoring'

# Quick context switch
alias ctx-crypto='kubectl config set-context --current --namespace=crypto-pipeline'
```

---

**Need more help? Check the full documentation files!**
