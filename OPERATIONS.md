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
- `PUSH_BENTO_IMAGE=true` pushes the BentoML image to Artifact Registry. Leave `IMAGE_TAG` empty to use `build-${BUILD_NUMBER}-${GIT_COMMIT_SHORT}`.
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
IMAGE_TAG=
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

## GCP base infrastructure with Terraform

The reproducible setup path is under `infra/terraform`. It creates:

- required GCP APIs
- Artifact Registry Docker repository
- GKE Autopilot cluster
- Jenkins deployer service account
- IAM bindings for image push and GKE deploy

Use it instead of ad hoc `gcloud` commands when you want to recreate the environment:

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
gcloud auth application-default login
terraform init
terraform plan
terraform apply
```

If you already created the demo GKE cluster, Artifact Registry repository, or Jenkins service account manually, import or delete those resources before `terraform apply`; otherwise Terraform will try to create resources with names that already exist. See `infra/terraform/README.md` for import examples.

From the repository root, the helper targets are:

```bash
make terraform-fmt
make terraform-init
make terraform-validate
make terraform-plan
```

For a local Jenkins demo that still uses a JSON key, set `create_jenkins_key = true` in `terraform.tfvars`, apply, then create the Jenkins `Secret file` from:

```bash
cd infra/terraform
terraform output -raw jenkins_service_account_key_json_base64 | base64 -d > jenkins-deployer.json
```

For production, keep `create_jenkins_key = false` and use keyless authentication.

## GCP Artifact Registry

If you are not using Terraform yet, create the Docker repository once from a machine with `gcloud` installed:

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
make mlops-push-bento
```

## Minimal GKE deploy

After pushing the BentoML image to Artifact Registry and connecting `kubectl` to a GKE cluster, deploy the predictor only:

```bash
make gke-deploy-bento
```

This creates:

- namespace `app`
- Helm release `bento-price-predictor`
- Deployment `bento-price-predictor`
- ClusterIP Service `bento-price-predictor`

Validate the chart locally:

```bash
helm lint charts/bento-price-predictor
make helm-template-bento
```

Port-forward for smoke testing:

```bash
make gke-port-forward-bento
```

Then check from another terminal:

```bash
make gke-smoke-bento
```

The model artifact is packaged into the BentoML image during Docker build. Train the model before building the image when you want to deploy a fresh model.

### Minimal GKE monitoring and logs

For the first GKE version, use Kubernetes status, events, and pod logs directly. This keeps the setup small while still showing whether the predictor is healthy.

Check deployment, pod, and service status:

```bash
make gke-status-bento
```

Show recent BentoML logs:

```bash
make gke-logs-bento
```

Follow BentoML logs live:

```bash
make gke-follow-logs-bento
```

Show recent namespace events when rollout or image pull fails:

```bash
make gke-events-bento
```

Run the same smoke test Jenkins uses, without port-forwarding:

```bash
make gke-smoke-in-cluster-bento
```

If local port `3001` is busy, use another local port:

```bash
PORT=3002 make gke-port-forward-bento
PORT=3002 make gke-smoke-bento
```

### Optional public GKE endpoint

The chart defaults to `ClusterIP`, so the predictor is private inside the cluster. For a short demo, expose it with a Google Cloud load balancer:

```bash
make gke-expose-bento
make gke-public-url-bento
```

Wait until `make gke-public-url-bento` prints a real IP, then test:

```bash
BENTO_URL="$(make -s gke-public-url-bento)"
curl -fsS "$BENTO_URL/readyz"
curl -fsS -X POST "$BENTO_URL/health"
```

When the demo is done, switch back to the private service to remove the load balancer:

```bash
make gke-unexpose-bento
```

### Minimal GKE rollback

Each GKE deploy is a Helm release revision. Check the release history:

```bash
make gke-history-bento
```

Rollback to a previous revision:

```bash
REVISION=1 make gke-rollback-bento
```

Then confirm the rollout and running image:

```bash
make gke-status-bento
kubectl -n app get deploy bento-price-predictor -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

### Jenkins to GKE

The Jenkins image includes Docker CLI, Google Cloud CLI, the GKE auth plugin, `kubectl`, and Helm. Store the GCP service account JSON as a Jenkins `Secret file` credential, for example:

```text
gcp-jenkins-sa-key
```

Then run the Jenkins job with:

```text
BUILD_MLOPS_IMAGE=true
PUSH_BENTO_IMAGE=true
IMAGE_TAG=
DEPLOY_GKE=true
GCP_CREDENTIALS_ID=gcp-jenkins-sa-key
GKE_CLUSTER=coinbase-mlops
GKE_REGION=asia-southeast1
```

For local demo work, the service account can have Artifact Registry writer access and enough GKE permissions to deploy. For production, prefer keyless Workload Identity or a locked-down deploy agent.

### GKE demo runbook

Use this runbook when you want to demonstrate the Jenkins-to-GKE flow end to end.

1. Confirm the current GCP project and cluster access:

```bash
gcloud config get-value project
gcloud container clusters get-credentials coinbase-mlops --region=asia-southeast1
make gke-status-bento
```

2. Run the Jenkins job with these parameters:

```text
BUILD_MLOPS_IMAGE=true
PUSH_BENTO_IMAGE=true
IMAGE_TAG=
DEPLOY_GKE=true
GCP_CREDENTIALS_ID=gcp-jenkins-sa-key
GKE_CLUSTER=coinbase-mlops
GKE_REGION=asia-southeast1
```

3. Verify the GKE rollout:

```bash
make gke-status-bento
make gke-events-bento
make gke-smoke-in-cluster-bento
```

The pod should show `READY 1/1`, `STATUS Running`, and low or zero restarts.

4. Port-forward the internal ClusterIP service:

```bash
PORT=3010 make gke-port-forward-bento
```

Keep that terminal open. In another terminal, run:

```bash
PORT=3010 make gke-smoke-bento
```

5. Test prediction through the GKE pod:

```bash
MLOPS_PREDICT_URL=http://localhost:3010/predict \
DATA=/home/quan/projects/Coinbase_Streaming/data/BTCUSDT_5m_full.csv \
make mlops-test-predict
```

6. Check logs after the request:

```bash
make gke-logs-bento
```

Look for a line like:

```text
method=POST,path=/predict ... status=200
```

7. When you no longer need the demo cluster, delete it to stop GKE charges:

```bash
gcloud container clusters delete coinbase-mlops --region=asia-southeast1
```

If you also want to remove pushed images and repository storage, delete the Artifact Registry repository:

```bash
gcloud artifacts repositories delete coinbase-mlops --location=asia-southeast1
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
