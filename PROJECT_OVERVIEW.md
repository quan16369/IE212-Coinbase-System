# Project Structure

## Root Directory

```
Coinbase_Streaming_Data_Pipeline_for_Cryptocurrency_Price_Forecasting/
├── README.md                           # Main project documentation
├── DEPLOYMENT.md                       # Deployment guide
├── STACK_OVERVIEW.md                   # Technology stack
├── ENVIRONMENT_COMPARISON.md           # Environment comparison
├── QUICK_REFERENCE.md                  # Command reference
├── CHANGELOG.md                        # Change history
├── ARCHITECTURE_DIAGRAM.txt            # Visual architecture
├── docker-compose.yml                  # Local development setup
├── deploy.sh                           # Main deployment script
├── validate.sh                         # Validation script
├── .gitignore                          # Git ignore rules
│
├── k8s/                                # Kubernetes manifests
│   ├── namespace.yaml
│   ├── kafka-statefulset.yaml
│   ├── cassandra-statefulset.yaml
│   ├── zookeeper-statefulset.yaml
│   ├── producer-deployment.yaml
│   ├── spark-processor-deployment.yaml
│   ├── prediction-service-deployment.yaml
│   └── hpa.yaml
│
├── terraform/                          # Infrastructure as Code
│   ├── README.md                       # Terraform documentation
│   ├── deploy.sh                       # Terraform deploy script
│   ├── modules/                        # Reusable modules
│   │   ├── vpc/                        # VPC module
│   │   ├── eks/                        # EKS module
│   │   ├── storage/                    # Storage module (S3, EFS, ECR)
│   │   └── iam/                        # IAM module
│   └── environments/                   # Environment-specific configs
│       ├── dev/                        # Development (K8s)
│       ├── staging/                    # Staging
│       └── production/                 # Production
│
├── helm/                               # Helm charts
│   ├── Chart.yaml
│   ├── values.yaml
│   └── install.sh
│
├── mlops/                              # MLOps configuration
│   ├── mlflow-deployment.yaml
│   ├── seldon-deployment.yaml
│   ├── mlflow_manager.py
│   └── continuous-learning-cronjob.yaml
│
├── monitoring/                         # Observability
│   ├── prometheus-config.yaml
│   ├── prometheus-rules.yaml
│   ├── alertmanager-config.yaml
│   └── grafana-production-dashboard.json
│
├── argocd/                             # GitOps
│   ├── install.sh
│   ├── application-crypto-pipeline.yaml
│   ├── application-mlops.yaml
│   ├── application-monitoring.yaml
│   ├── project.yaml
│   └── applicationset-environments.yaml
│
├── .github/workflows/                  # CI/CD pipelines
│   ├── ci-cd.yml
│   ├── infrastructure.yml
│   └── continuous-learning.yml
│
├── coinbase_kafka_producer/            # Producer service
│   ├── producer.py
│   ├── producer.Dockerfile
│   └── requirements.txt
│
├── go_kafka_consumer/                  # Consumer service (Go)
│   ├── consumer.go
│   ├── consumer.Dockerfile
│   └── go.mod
│
├── kafka_spark_processor/              # Spark processor
│   ├── spark_processor.py
│   ├── processor.Dockerfile
│   └── requirements.txt (if any)
│
├── prediction_service/                 # Prediction API
│   ├── src/
│   │   ├── prediction_service.py
│   │   ├── predictor.py
│   │   ├── data_fetcher.py
│   │   ├── data_writer.py
│   │   └── cassandra_client.py
│   ├── configs/
│   │   └── prediction_config.yaml
│   ├── prediction.Dockerfile
│   └── requirements.txt
│
├── Crypto-TS-Model-master/             # ML model code
│   ├── src/
│   │   ├── train.py
│   │   ├── data_loader.py
│   │   ├── lstm_attention_model.py
│   │   └── ...
│   ├── configs/
│   │   └── train_config.yaml
│   ├── notebooks/
│   ├── checkpoints/
│   └── requirements.txt
│
├── cassandra/                          # Cassandra setup
│   ├── cassandra.Dockerfile
│   └── scripts/
│       ├── Basic_tables.sh
│       └── setup_prediction_table.sh
│
└── grafana/                            # Grafana configuration
    ├── grafana.Dockerfile
    ├── grafana.ini
    ├── config/
    │   └── datasource.yaml
    └── dashboards/
        ├── dashboard.json
        ├── dashboard.yaml
        └── predict_dashboard.json
```

## Directory Descriptions

### Infrastructure Configuration
- **k8s/**: Kubernetes manifests for all services
- **terraform/**: Infrastructure as Code with modular structure
- **helm/**: Helm charts for package management
- **argocd/**: GitOps configuration

### Application Services
- **coinbase_kafka_producer/**: Python service to collect data from Coinbase WebSocket
- **go_kafka_consumer/**: Go service to consume Kafka messages
- **kafka_spark_processor/**: Spark Structured Streaming for real-time processing
- **prediction_service/**: REST API for serving predictions
- **Crypto-TS-Model-master/**: ML model training and inference code

### Supporting Services
- **cassandra/**: Database setup and initialization scripts
- **grafana/**: Visualization and monitoring dashboards
- **mlops/**: MLflow and Seldon Core for model lifecycle
- **monitoring/**: Prometheus, Grafana, Alertmanager configs

### CI/CD
- **.github/workflows/**: GitHub Actions pipelines for build, test, deploy

## Key Files

### Documentation
- `README.md` - Project overview and quick start
- `DEPLOYMENT.md` - Step-by-step deployment guide
- `STACK_OVERVIEW.md` - Technology stack details
- `ENVIRONMENT_COMPARISON.md` - Environment comparison guide
- `QUICK_REFERENCE.md` - Command cheat sheet
- `CHANGELOG.md` - Change history

### Configuration
- `docker-compose.yml` - Local development environment
- `.gitignore` - Git ignore rules

### Scripts
- `deploy.sh` - Main deployment script (calls terraform or docker-compose)
- `validate.sh` - Validation script to check setup
- `terraform/deploy.sh` - Terraform environment selector

## File Counts

- Total Kubernetes manifests: 8 files
- Terraform modules: 4 modules (12 files)
- Terraform environments: 3 environments (12 files)
- Documentation files: 7 markdown files
- Total configuration files: 60+ files

## Notes

- All Terraform state files are excluded via .gitignore
- Model checkpoints and data files are not tracked in Git
- The .terraform/ cache directories are ignored
- Python cache files (__pycache__) are ignored
