# Operations

## Local or single-host deployment

Create a local env file before starting services:

```bash
cp .env.example .env
```

Review `.env` and replace the MinIO/Grafana passwords before using the stack outside local development.

Run the application with the ops profile:

```bash
COMPOSE_PROFILES=ops bash scripts/deploy_compose.sh
```

Main endpoints:

- Kafka UI: `http://localhost:8080`
- Grafana: `http://localhost:3000`
- Prometheus: `http://localhost:9090`
- Alertmanager: `http://localhost:9093`
- cAdvisor: `http://localhost:8081`
- MinIO Console: `http://localhost:9001`

Start the MLOps profile when you want MLflow and the BentoML model server:

```bash
COMPOSE_PROFILES=mlops docker compose --env-file .env up -d mlflow bento-price-predictor
```

MLOps endpoints:

- MLflow: `http://localhost:5000`
- BentoML predictor: `http://localhost:3001`

## Jenkins CI/CD

The repo now uses `Jenkinsfile` for CI/CD. A basic Jenkins host needs:

- Docker Engine and Docker Compose v2 available to the Jenkins agent.
- Permission for the Jenkins user to run Docker.
- A `.env` file on the Jenkins workspace or deployment host. If missing, the pipeline copies `.env.example` for CI/dev.

Pipeline stages:

- `Prepare`: creates `.env` from `.env.example` if needed.
- `CI Checks`: validates Compose, checks Python syntax, and runs Go tests when Go is installed.
- `Build Images`: builds all Docker images.
- `Train CPU ML Model`: trains the LightGBM model, logs to MLflow, and archives model artifacts when enabled.
- `Build BentoML Image`: builds only the BentoML predictor image when enabled.
- `Push BentoML Image`: tags and pushes the BentoML image to GCP Artifact Registry when enabled.
- `Promote Model`: points an MLflow model alias, usually `champion`, at a reviewed model version.
- `Deploy BentoML`: recreates only the BentoML predictor service.
- `Deploy`: runs `scripts/deploy_compose.sh` only on `main` or `master`.

Optional MLOps stages are controlled by Jenkins build parameters:

- `BUILD_ALL_IMAGES=true` builds every Docker Compose image.
- `BUILD_MLOPS_IMAGE=true` builds the BentoML service image.
- `PUSH_BENTO_IMAGE=true` pushes the BentoML image to Artifact Registry. Leave `IMAGE_TAG` empty to use `build-${BUILD_NUMBER}`.
- `TRAIN_MLOPS_MODEL=true` trains the CPU LightGBM model. Leave `MLOPS_TRAINING_CSV` empty to use the default from `.env`.
- `PROMOTE_MODEL=true` with `MODEL_VERSION=<version>` and `MODEL_ALIAS=champion` promotes a reviewed MLflow model version.
- `DEPLOY_BENTO=true` rebuilds and recreates only `bento-price-predictor`.
- `DEPLOY_COMPOSE=true` runs the local Compose deploy stage.

Common local MLOps runs:

```text
CI/image build:
BUILD_MLOPS_IMAGE=true
TRAIN_MLOPS_MODEL=false
PROMOTE_MODEL=false
DEPLOY_BENTO=false

Train:
BUILD_MLOPS_IMAGE=true
TRAIN_MLOPS_MODEL=true
MLOPS_TRAINING_CSV=
PROMOTE_MODEL=false
DEPLOY_BENTO=false

Promote and deploy:
BUILD_MLOPS_IMAGE=false
TRAIN_MLOPS_MODEL=false
PROMOTE_MODEL=true
MODEL_VERSION=<version>
MODEL_ALIAS=champion
DEPLOY_BENTO=true

Push BentoML image:
BUILD_MLOPS_IMAGE=true
PUSH_BENTO_IMAGE=true
IMAGE_TAG=dev
TRAIN_MLOPS_MODEL=false
PROMOTE_MODEL=false
DEPLOY_BENTO=false
```

Training archives these files in Jenkins:

```text
artifacts/mlops/coinbase_ml_model.joblib
artifacts/mlops/coinbase_ml_model.metadata.json
artifacts/mlops/training_summary.md
artifacts/mlops/training_summary.json
```

Pushing the BentoML image archives this file in Jenkins:

```text
artifacts/mlops/bento_image_uri.txt
```

For production-like usage, keep `.env` out of Git and manage the real values through Jenkins credentials, a protected file credential, or host-level secret management.

## GCP Artifact Registry

Create the Docker repository once from a machine with `gcloud` installed:

```bash
gcloud auth login
gcloud config set project <gcp-project-id>
gcloud services enable artifactregistry.googleapis.com
gcloud artifacts repositories create coinbase-mlops \
  --repository-format=docker \
  --location=asia-southeast1 \
  --description="Coinbase MLOps images"
gcloud auth configure-docker asia-southeast1-docker.pkg.dev
```

Set these values in `.env` or Jenkins credentials before pushing:

```text
GCP_PROJECT_ID=<gcp-project-id>
GAR_LOCATION=asia-southeast1
GAR_REPOSITORY=coinbase-mlops
BENTO_IMAGE_NAME=coinbase-bento-price-predictor
```

Then push from local shell:

```bash
COMPOSE_PROFILES=mlops docker compose --env-file .env build bento-price-predictor
IMAGE_TAG=dev make mlops-push-bento
```

### Local Jenkins with Compose

For local CI practice, start Jenkins with the `ci` profile:

```bash
make jenkins-up
```

Open Jenkins at `http://localhost:8088`. The initial admin password is in the container logs:

```bash
make jenkins-logs
```

The local Jenkins service runs as `root` and mounts:

- `jenkins-data` for Jenkins state.
- `/var/run/docker.sock` so Jenkins can run Docker builds.
- this repository at `/workspace/Coinbase_Streaming`.

The local Jenkins image is built from `ops/jenkins/jenkins.Dockerfile` and includes Python 3, Docker CLI, and the Docker Compose v2 plugin. The host Docker socket is still required for actual builds.

This socket mount is for local practice only. In production, prefer a dedicated Jenkins agent with registry credentials, or a Kubernetes-native builder such as Kaniko/BuildKit with cloud IAM.

If Docker in WSL fails with `docker-credential-desktop.exe`, remove the broken Docker Desktop credential helper from `~/.docker/config.json` or run Docker with a clean `DOCKER_CONFIG`.

To run the repository `Jenkinsfile` from the local mounted workspace, configure a Pipeline job with this script:

```groovy
node {
  dir('/workspace/Coinbase_Streaming') {
    load 'Jenkinsfile'
  }
}
```

Do not wrap that `load` call inside another `pipeline { ... }` block. Jenkins allows only one Declarative Pipeline block per run. The repository `Jenkinsfile` runs its shell steps from `/workspace/Coinbase_Streaming` for local Jenkins.

## Monitoring and logs

The `ops` Compose profile starts:

- Prometheus for metrics.
- Alertmanager for basic alert routing.
- Blackbox Exporter for HTTP health checks.
- cAdvisor for container metrics.
- Loki and Promtail for Docker container logs.

Alert rules live in `monitoring/prometheus/alerts.yml`. Alertmanager currently uses a local no-op receiver so alerts are visible in the UI but not sent externally. Add Slack, email, or webhook receivers in `monitoring/alertmanager/alertmanager.yml` when you have a destination.

## Cassandra migrations

Schema migrations live in `ops/cassandra/migrations`.

Apply them manually:

```bash
bash scripts/apply_cassandra_migrations.sh
```

Compose also includes a `cassandra-migrate` service that runs the current `.cql` migrations after Cassandra becomes healthy. New schema changes should go into versioned `.cql` files.

## Backup and restore

Create a Cassandra snapshot archive:

```bash
bash scripts/backup_cassandra.sh
```

Restore from an archive:

```bash
bash scripts/restore_cassandra.sh backups/cassandra/<snapshot>.tar.gz
```

The restore script performs a cold restore by stopping Cassandra, unpacking the archive into the Cassandra volume, then starting Cassandra. Validate the database and logs before accepting traffic.

## Current limits

This is still a single-host Docker Compose ops setup. It improves CI/CD, config hygiene, monitoring, logs, and backup basics, but it is not HA. For real production, the next step is Kubernetes or managed services for Kafka, Cassandra, object storage, secrets, and alert delivery.
