# Operations

## Production Path Runbook

### GKE Standard topology

Terraform provisions a regional GKE Standard cluster with:

- two zones;
- one `e2-standard-4` node per zone minimum;
- cluster autoscaling up to two nodes per zone;
- a dedicated least-privilege node service account;
- Workload Identity, Dataplane V2, Shielded Nodes, auto-repair and auto-upgrade;
- Container-Optimized OS with `containerd`.

Autopilot cannot be converted to Standard in place. Recreate the cluster:

```bash
make terraform-destroy
make terraform-init
make terraform-plan
terraform -chdir=infra/terraform apply
```

Then deploy the complete stack with `make gke-workday-start`. For a long-lived
production cluster set `gke_deletion_protection = true`; keep it false for the
daily teardown workflow.

The complete GKE path is:

```text
Coinbase -> Kafka -> raw Parquet/GCS
                  -> validation -> validated/quality topics
                  -> feature platform (Redis/PostgreSQL)
                  -> model training/MLflow -> validation gate
                  -> BentoML -> inference orchestrator
                  -> governance decisions/outcomes
```

Start every service and the observability stack:

```bash
cd /home/quan/projects/Coinbase_Streaming
git checkout add/ops
git pull origin add/ops
gcloud config set project awesome-pilot-494017-u5

DEPLOY_SERVICES=true INSTALL_OBSERVABILITY=true make gke-workday-start
```

Add `ENABLE_PUBLIC_INGRESS=true` only when a billable public LoadBalancer is
required:

```bash
DEPLOY_SERVICES=true INSTALL_OBSERVABILITY=true ENABLE_PUBLIC_INGRESS=true make gke-workday-start
```

Verify Kafka routing, feature-store connectivity, offset idempotency, raw GCS
Parquet, replay checkpoints, inference, governance telemetry, and rollout
health:

```bash
make production-e2e-smoke
```

Skip replay while diagnosing:

```bash
RUN_REPLAY_CHECK=false make production-e2e-smoke
```

Train immediately, then validate, promote, deploy, smoke test, and rollback on
failure:

```bash
make model-training-run
RUN_FULL_E2E_AFTER_DEPLOY=true make mlops-validate-promote-deploy
```

Expose only the inference orchestrator:

```bash
make gke-install-ingress-nginx
make inference-orchestrator-ingress
make inference-orchestrator-public-url
make inference-orchestrator-smoke-public
```

For external production, configure a hostname and TLS. Kafka, Redis,
PostgreSQL, MLflow, feature platform, and Bento remain private.

```bash
INFERENCE_ORCHESTRATOR_INGRESS_ENABLED=true \
INFERENCE_ORCHESTRATOR_INGRESS_HOST=api.example.com \
INFERENCE_ORCHESTRATOR_INGRESS_TLS_ENABLED=true \
INFERENCE_ORCHESTRATOR_INGRESS_TLS_SECRET=coinbase-api-tls \
  make inference-orchestrator-deploy
```

Open observability tools:

```bash
make gke-monitoring-grafana
make gke-monitoring-prometheus
make gke-monitoring-alertmanager
make gke-logging-loki
make gke-tracing-tempo
```

Prometheus rules cover Kafka, producer, raw sink, validation, feature
platform, MLflow/training, Bento, and inference. Set
`ALERTMANAGER_WEBHOOK_URL` during monitoring installation for a real receiver.

Replay raw Parquet with GCS offset checkpoints:

```bash
make raw-data-replay-run
```

Stop all billable resources:

```bash
make gke-uninstall-ingress-nginx
make gke-uninstall-monitoring
make gke-uninstall-logging
make gke-uninstall-tracing

make inference-orchestrator-delete
make model-training-delete
make data-validation-delete
make feature-platform-delete
make streaming-platform-delete
make gke-delete-bento

make terraform-destroy
```

After cluster deletion, check for orphaned `pvc-*` Compute Engine disks.

## Jenkins full E2E and automatic rollback

For GKE deployments, Jenkins runs a deployment transaction:

```text
record current Bento Helm revision
-> deploy Bento
-> Bento in-cluster smoke
-> Kafka/validation/feature-platform streaming E2E
-> inference/governance full-stack E2E
-> optional public ingress smoke
```

If deployment or any enabled smoke test fails, Jenkins automatically rolls
Bento back to the previously recorded Helm revision. A failed first deployment
with no previous revision is uninstalled.

Run the same transaction manually:

```bash
RUN_FULL_E2E_AFTER_DEPLOY=true make gke-deploy-bento-safe
```

In Jenkins, enable:

```text
DEPLOY_GKE=true
RUN_FULL_E2E_AFTER_DEPLOY=true
```

## Start a workday after full cleanup

Create only Terraform-managed GCP resources and refresh kubeconfig:

```bash
make gke-workday-start
```

The startup script imports an existing `coinbase-mlops` Artifact Registry
repository or GKE cluster when either resource exists in GCP but is missing
from the local Terraform state. This prevents `409 already exists` failures
after an interrupted create or a lost local state entry.

Create infrastructure, rebuild/push all application images, and deploy the
application stack:

```bash
DEPLOY_SERVICES=true make gke-workday-start
```

Include Prometheus/Grafana, Loki, and Tempo only when they are needed:

```bash
DEPLOY_SERVICES=true INSTALL_OBSERVABILITY=true make gke-workday-start
```

## Raw-data replay and automatic model promotion

Raw Kafka events are archived as Parquet in GCS with their source Kafka topic,
partition, and offset. The replay workflow is suspended by default. When run,
it reads Parquet objects, publishes records to `coin-data-replay`, and stores a
high-watermark checkpoint per source partition in GCS. Running the same replay
ID again does not publish offsets that were already restored.

```bash
make raw-data-replay-build
make raw-data-replay-push
terraform -chdir=infra/terraform apply
make raw-data-replay-deploy
RAW_DATA_REPLAY_ID=incident-2026-06-11 make raw-data-replay-run
```

Promote the latest registered MLflow model only when it passes the configured
return R2, direction accuracy, and naive-baseline improvement gates, then roll
out BentoML using the `champion` alias:

```bash
MLFLOW_TRACKING_URI=http://localhost:5000 make mlops-validate-promote-deploy
```

## Streaming, training, and outcome pipeline

The production path is:

```text
Coinbase -> coin-data-model -> Data Validation -> coin-data-validated
-> Feature Platform (Redis + PostgreSQL) -> model training / inference
-> governance decisions + outcomes
```

Deploy in dependency order:

```bash
make streaming-platform-deploy
make feature-platform-deploy
make data-validation-deploy
make model-training-deploy
make gke-deploy-bento
make inference-orchestrator-deploy
```

Run one training job and inspect MLflow:

```bash
make model-training-run
kubectl -n model-training logs -l job-name=<job-name> --tail=200
kubectl -n model-training port-forward svc/mlflow 5000:5000
```

Run the in-cluster validation gate after training:

```bash
make model-validation-run
kubectl -n model-training logs job/<validation-job-name>
```

The validation Job promotes the newest registered version to `champion` only
when it beats the naive MAE/RMSE baseline, has non-negative return R2, and
meets the direction-accuracy threshold. A rejected candidate exits non-zero
and leaves the current champion unchanged.

Validate the Kafka-to-feature-store path:

```bash
bash scripts/smoke_streaming_e2e.sh
```

## GKE full demo quick start and shutdown

Use this section when the whole GKE demo was deleted yesterday and you want to start from zero again. It creates the Terraform-managed GCP resources, pushes images, deploys the internal services, exposes the inference orchestrator as the public API, and gives the shutdown commands to avoid leaving billable resources running.

### Start From Zero

From the repository root:

```bash
cd /home/quan/projects/Coinbase_Streaming
cp -n .env.example .env
```

Confirm `.env` contains the GCP and Artifact Registry values:

```text
GCP_PROJECT_ID=awesome-pilot-494017-u5
GAR_LOCATION=asia-southeast1
GAR_REPOSITORY=coinbase-mlops
```

Create or recreate GCP infrastructure:

```bash
gcloud config set project awesome-pilot-494017-u5
gcloud auth application-default login

cp -n infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars
terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform apply
```

Connect local tools to GKE and Artifact Registry:

```bash
gcloud container clusters get-credentials coinbase-mlops --region=asia-southeast1
gcloud auth configure-docker asia-southeast1-docker.pkg.dev
```

Build and push all demo images with one immutable tag. The Bento image must be built from `mlops/bento.Dockerfile`; it installs `libgomp1`, which is required by LightGBM at runtime.

```bash
IMAGE_TAG="$(git rev-parse --short HEAD)"

COMPOSE_PROFILES=mlops docker compose --env-file .env build bento-price-predictor
IMAGE_TAG="$IMAGE_TAG" make mlops-push-bento

make data-validation-build
IMAGE_TAG="$IMAGE_TAG" make data-validation-push

make feature-platform-build
IMAGE_TAG="$IMAGE_TAG" make feature-platform-push

make inference-orchestrator-build
IMAGE_TAG="$IMAGE_TAG" make inference-orchestrator-push
```

Deploy the application stack in dependency order. For the current demo, keep one replica and leave NetworkPolicy, PDB, and HPA disabled unless you explicitly want to test those controls.

```bash
BENTO_NETWORK_POLICY_ENABLED=false \
BENTO_PDB_ENABLED=false \
BENTO_AUTOSCALING_ENABLED=false \
make gke-deploy-bento

FEATURE_PLATFORM_PDB_ENABLED=false \
FEATURE_PLATFORM_AUTOSCALING_ENABLED=false \
make feature-platform-deploy

DATA_VALIDATION_FEATURE_PLATFORM_ENABLED=true \
DATA_VALIDATION_FEATURE_PLATFORM_URL=http://feature-platform.feature-platform.svc.cluster.local \
make data-validation-deploy

make inference-orchestrator-deploy
```

Expose the product-style public API through nginx ingress:

```bash
make gke-install-ingress-nginx

make inference-orchestrator-ingress

make inference-orchestrator-public-url
```

The public API is:

```text
POST http://<ingress-ip>/orchestrate/predict
```

Smoke test the public inference path:

```bash
conda activate openex-ai
make inference-orchestrator-smoke-public
```

If you already know the ingress URL, test it explicitly:

```bash
INFERENCE_ORCHESTRATOR_URL=http://<ingress-ip> make inference-orchestrator-smoke
```

Expected smoke output:

```text
prediction exists
alert_evaluation.triggered is true or false
alert_evaluation.indexed is true when an alert is triggered
sources.bento_predict_url points to the in-cluster Bento service
```

Optional observability stack:

```bash
make gke-install-monitoring
make gke-install-logging
make gke-install-tracing
```

For cost-sensitive demos, install only `gke-install-monitoring` unless you need Loki logs or Tempo traces in the UI.

After installing tracing, refresh Grafana datasources and redeploy Bento with tracing enabled:

```bash
make gke-install-monitoring

BENTO_TRACING_ENABLED=true \
BENTO_NETWORK_POLICY_ENABLED=false \
BENTO_PDB_ENABLED=false \
BENTO_AUTOSCALING_ENABLED=false \
make gke-deploy-bento
```

Run another public smoke test after tracing is enabled so Grafana/Loki/Tempo have fresh request data.

### Production-Style MLOps Additions

The demo now includes the next operational pieces from the target architecture:

- Workflow orchestration: Airflow DAG `coinbase_mlops_retraining`.
- Feature store: Redis online store plus PostgreSQL offline store in the `feature-platform` Helm chart.
- Data/model versioning: hash manifest for training data, model artifact, and Git SHA.
- Feedback loop: feature-platform drift endpoint returns a retraining signal.
- Drift monitoring: CLI and Airflow task read `/feedback/retraining-signal/{symbol}`.

Deploy the feature platform with real stores on GKE:

```bash
make feature-platform-build
IMAGE_TAG="$(git rev-parse --short HEAD)" make feature-platform-push

FEATURE_ONLINE_STORE=redis \
FEATURE_OFFLINE_STORE=postgres \
FEATURE_DATA_VERSION="$(git rev-parse --short HEAD)" \
FEATURE_PLATFORM_PDB_ENABLED=false \
FEATURE_PLATFORM_AUTOSCALING_ENABLED=false \
make feature-platform-deploy
```

Smoke test the feature store locally through port-forward:

```bash
PORT=8090 make feature-platform-port-forward
```

In another terminal:

```bash
FEATURE_PLATFORM_URL=http://localhost:8090 make feature-platform-smoke
FEATURE_PLATFORM_URL=http://localhost:8090 make mlops-drift-check
```

Expected feature store status:

```text
online.configured = redis
online.connected = true
offline.configured = postgres
offline.connected = true
```

Create a reproducible data/model version manifest:

```bash
DATA=/home/quan/projects/Coinbase_Streaming/data/BTCUSDT_5m_full.csv \
make mlops-version-manifest
```

The manifest is written to:

```text
artifacts/mlops/data_version_manifest.json
```

### Raw Streaming Archive on GCS

Kafka remains the realtime transport. PostgreSQL remains the offline feature
store. The raw-data sink independently consumes `coin-data-model` and writes
immutable Snappy-compressed Parquet batches to GCS:

```text
gs://BUCKET/raw/topic=coin-data-model/date=YYYY-MM-DD/hour=HH/part-*.parquet
```

The sink uses at-least-once delivery: it uploads a Parquet batch before
committing Kafka offsets. Each row includes `_kafka_topic`,
`_kafka_partition`, `_kafka_offset`, and `_archived_at` so replay jobs can
deduplicate records. The default flush policy is 1000 events or 5 minutes.

Provision the bucket and keyless Workload Identity permissions:

```bash
make terraform-plan
terraform -chdir=infra/terraform apply
```

Build and push the sink:

```bash
make raw-data-sink-build
IMAGE_TAG="$(git rev-parse --short HEAD)" make raw-data-sink-push
```

Deploy streaming with the raw archive enabled:

```bash
RAW_DATA_SINK_ENABLED=true \
RAW_DATA_BUCKET="$(terraform -chdir=infra/terraform output -raw raw_data_bucket_name)" \
RAW_DATA_SINK_GCP_SERVICE_ACCOUNT="$(terraform -chdir=infra/terraform output -raw raw_data_sink_service_account_email)" \
make streaming-platform-deploy
```

Verify Parquet objects:

```bash
make raw-data-sink-smoke
```

Start Airflow locally for orchestration:

```bash
COMPOSE_PROFILES=orchestration docker compose --env-file .env up -d airflow
make airflow-logs
```

Open Airflow:

```text
http://localhost:8089
```

Use DAG:

```text
coinbase_mlops_retraining
```

The DAG flow is:

```text
check feature drift -> choose train/skip -> train model -> create version manifest -> summarize -> optional promote
```

By default it does not promote a model. To force a demo retrain:

```bash
AIRFLOW_FORCE_RETRAIN=true COMPOSE_PROFILES=orchestration docker compose --env-file .env up -d airflow
```

Only enable automatic promotion when you intentionally provide `MODEL_VERSION`:

```bash
AIRFLOW_PROMOTE_MODEL=true MODEL_VERSION=<mlflow-version> COMPOSE_PROFILES=orchestration docker compose --env-file .env up -d airflow
```

### Test Checklist

Use this checklist after starting the stack from zero.

Core runtime:

```bash
make inference-orchestrator-public-url
INFERENCE_ORCHESTRATOR_URL=http://<ingress-ip> make inference-orchestrator-smoke
```

Service health:

```bash
make gke-status-bento
make feature-platform-status
make data-validation-status
make inference-orchestrator-status
```

Logs:

```bash
make gke-logs-bento
make inference-orchestrator-logs
```

Monitoring:

```bash
make gke-monitoring-status
PORT=3003 make gke-monitoring-grafana
```

Open Grafana at `http://localhost:3003`, login with `admin / admin`, then open:

```text
Dashboards -> Coinbase / Bento Price Predictor
Explore -> Loki
Explore -> Tempo
```

Useful Loki query examples:

```text
{namespace="app", app="bento-price-predictor"}
{namespace="model-serving", app="inference-orchestrator"}
```

Useful Prometheus checks:

```text
kube_deployment_status_replicas_available{namespace="app", deployment="bento-price-predictor"}
sum(increase(kube_pod_container_status_restarts_total{namespace="app", container="bento-price-predictor"}[5m]))
```

Alerting:

```bash
PORT=9091 make gke-monitoring-prometheus
PORT=9094 make gke-monitoring-alertmanager
```

Open:

```text
http://localhost:9091/alerts
http://localhost:9094
```

### Common Recovery

If Bento repeatedly restarts and logs contain this error:

```text
OSError: libgomp.so.1: cannot open shared object file
```

Rebuild and push the Bento image after confirming `mlops/bento.Dockerfile` installs `libgomp1`:

```bash
IMAGE_TAG="$(git rev-parse --short HEAD)-libgomp"
docker build -f mlops/bento.Dockerfile -t coinbase_streaming-bento-price-predictor:latest .
IMAGE_TAG="$IMAGE_TAG" make mlops-push-bento

HELM_TIMEOUT=600s \
BENTO_NETWORK_POLICY_ENABLED=false \
BENTO_PDB_ENABLED=false \
BENTO_AUTOSCALING_ENABLED=false \
make gke-deploy-bento
```

If creating an Ingress fails with `no endpoints available for service "ingress-nginx-controller-admission"`, wait for the nginx controller and rerun:

```bash
kubectl -n ingress-nginx wait --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=180s
make inference-orchestrator-ingress
```

If `make inference-orchestrator-public-url` prints an empty URL, wait for the cloud LoadBalancer:

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller -w
```

### Check Current State

```bash
kubectl get ns
make gke-status-bento
make data-validation-status
make feature-platform-status
make inference-orchestrator-status
make inference-orchestrator-ingress-status
make gke-monitoring-status
```

### Shutdown To Avoid Cost

Run this when the demo is done. The important cost items are the GKE Autopilot cluster, public LoadBalancer from nginx ingress, optional direct LoadBalancer for Bento, and Artifact Registry image storage. Destroying Terraform-managed infrastructure removes the GKE cluster and Artifact Registry repository.

First remove public endpoints and optional observability:

```bash
cd /home/quan/projects/Coinbase_Streaming

make gke-uninstall-ingress-nginx
make gke-unexpose-bento

make gke-uninstall-monitoring
make gke-uninstall-logging
make gke-uninstall-tracing
```

Then remove application workloads while the cluster still exists:

```bash
make inference-orchestrator-delete
make data-validation-delete
make feature-platform-delete
make gke-delete-bento
```

If the feature platform used PostgreSQL, delete its demo PVC after the Helm release is removed:

```bash
kubectl -n feature-platform delete pvc -l app.kubernetes.io/name=feature-platform --ignore-not-found
```

Finally destroy Terraform-managed GCP resources:

```bash
terraform -chdir=infra/terraform plan
terraform -chdir=infra/terraform destroy
```

If you only want to stop local Docker Compose services:

```bash
docker compose --env-file .env down
```

If you also started Airflow locally and want to remove its local state:

```bash
COMPOSE_PROFILES=orchestration docker compose --env-file .env down
```

After `terraform destroy`, verify there is no cluster and no Artifact Registry repository left:

```bash
gcloud container clusters list --region=asia-southeast1
gcloud artifacts repositories list --location=asia-southeast1
```

### Remaining Work Before Merge

The current branch is enough for a working demo. To make the ops stack cleaner before merging to `main`, finish these items:

- Add a single `make gke-smoke-full-stack` target that runs the public orchestrator smoke test plus basic Kubernetes status checks.
- Decide whether `artifacts/mlops/bento_image_uri.txt` should stay committed or be generated only by CI. For production, prefer generated CI artifacts and immutable image tags.
- Add `checkov` installation to the Jenkins image or docs, because Jenkins treats Checkov as required while local `ci_check.sh` currently skips it when missing.
- Make Grafana/Loki/Tempo query examples permanent in `OPERATIONS.md` after verifying the exact labels in the live cluster.
- Decide whether to keep tracing enabled by default for Bento or only enable it during observability demos.
- Add a short architecture section mapping the deployed services to the diagram: ingestion, feature platform, model serving, alert routing, dashboard, monitoring, logging, tracing.
- Add a cost note explaining that GKE Autopilot, nginx LoadBalancer, monitoring stack, and Artifact Registry storage are the main billable resources.

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

### GitHub webhook trigger

Jenkins can run automatically when GitHub receives a push.

For production-like usage, prefer a Jenkins Multibranch Pipeline connected to GitHub with a GitHub App. A regular single Pipeline job is acceptable for local demos, but Multibranch is closer to how teams handle branches and pull requests.

Production shape:

```text
GitHub push or pull request
-> GitHub App webhook
-> Jenkins Multibranch Pipeline
-> Jenkinsfile in this repo
-> CI, security checks, image push, GKE deploy
```

Jenkins should be reachable on a real HTTPS URL:

```text
https://jenkins.example.com
```

The GitHub webhook endpoint is:

```text
https://jenkins.example.com/github-webhook/
```

Do not use `localhost` for production webhooks. GitHub must be able to reach Jenkins from the public internet or through an approved private connectivity pattern.

#### Production: Multibranch Pipeline with GitHub App

In GitHub, create a GitHub App for Jenkins:

```text
GitHub -> Settings -> Developer settings -> GitHub Apps -> New GitHub App
```

Recommended permissions:

```text
Repository metadata: Read
Repository contents: Read
Pull requests: Read
Checks: Read and write
Commit statuses: Read and write
Webhooks: Read and write
```

Subscribe to these events:

```text
Push
Pull request
Check suite
```

Set the webhook URL:

```text
https://jenkins.example.com/github-webhook/
```

Install the GitHub App on the repository or organization, then create Jenkins credentials for the GitHub App:

```text
Manage Jenkins
-> Credentials
-> System
-> Global credentials
-> Add Credentials
Kind: GitHub App
App ID: <github-app-id>
Private Key: <github-app-private-key.pem>
ID: github-app-coinbase-streaming
```

Create the Jenkins job:

```text
New Item
-> Multibranch Pipeline
-> Branch Sources: GitHub
-> Credentials: github-app-coinbase-streaming
-> Repository HTTPS URL: https://github.com/quan16369/Coinbase_Streaming.git
-> Build Configuration: by Jenkinsfile
-> Script Path: Jenkinsfile
```

Recommended scan behavior:

```text
Discover branches
Discover pull requests from origin
Ignore branches that are also filed as PRs
```

With this setup, Jenkins discovers branches and pull requests automatically and uses the `Jenkinsfile` from each branch.

The local Jenkins image also includes the required plugins for this pattern:

```text
configuration-as-code
github
github-branch-source
git
job-dsl
workflow-aggregator
```

For a fresh local controller, you can bootstrap a simple multibranch job with Jenkins Configuration as Code:

```bash
CASC_JENKINS_CONFIG=/opt/jenkins/casc/jenkins.yaml \
JENKINS_PUBLIC_URL=https://jenkins.example.com/ \
JENKINS_GITHUB_REPOSITORY_URL=https://github.com/quan16369/Coinbase_Streaming.git \
COMPOSE_PROFILES=ci docker compose --env-file .env up -d --build jenkins
```

If the GitHub repository is private, set `JENKINS_GITHUB_CREDENTIALS_ID` to a Jenkins credential ID that can read the repository. For a production GitHub App setup, create that credential in Jenkins first, then rescan the multibranch job.

The JCasC files live under:

```text
ops/jenkins/casc/jenkins.yaml
ops/jenkins/jobs/coinbase-streaming-multibranch.groovy
```

They are intentionally minimal. Credentials and secrets stay outside Git.

#### Local demo fallback

In Jenkins:

1. Install or enable the GitHub plugin if it is not already available.
2. Configure the CI job to use this repository as the SCM source.
3. Keep the `Jenkinsfile` from this repository as the pipeline definition.

In GitHub, open the repository settings and add a webhook:

```text
Payload URL: http://<jenkins-host>:8088/github-webhook/
Content type: application/json
Events: Just the push event
Active: checked
```

For a local Jenkins running behind WSL or Docker, GitHub must be able to reach the webhook URL. Use a public tunnel such as ngrok or Cloudflare Tunnel only for demos:

```bash
ngrok http 8088
```

Then use the generated HTTPS URL:

```text
https://<ngrok-id>.ngrok-free.app/github-webhook/
```

The pipeline declares `githubPush()`, so GitHub push events trigger Jenkins without manually pressing `Build`.

#### CI/CD credentials

Production Jenkins should avoid long-lived JSON keys when possible. Prefer one of these:

```text
Jenkins on GKE + Workload Identity
Jenkins on GCE VM + attached service account
Short-lived federated credentials
```

For this local demo, Jenkins still supports a Secret file credential:

```text
gcp-jenkins-sa-key
```

Rotate or recreate that key whenever Terraform destroys and recreates the deployer service account.

#### Production checklist

Before treating this CI/CD flow as production, confirm:

```text
Jenkins has a stable HTTPS URL.
GitHub App is used instead of a personal token where possible.
Webhook delivery succeeds from GitHub.
Jenkins credentials are not stored in Git.
GCP deploy identity has only the required Artifact Registry and GKE permissions.
Branch protection requires Jenkins CI and security checks.
main deploys only after review or an explicit approved promotion.
GKE deploy uses immutable image tags, not latest.
Monitoring and logs are available before public exposure.
```

Pipeline stages:

- `Prepare`: creates `.env` from `.env.example` if needed.
- `CI Checks`: validates Compose, checks Python syntax, lints Helm charts, checks Terraform formatting, runs Go tests when Go is installed, and runs Checkov as a required Jenkins gate.
- `SonarQube Scan`: required Jenkins code quality gate.
- `Build Images`: builds all Docker images.
- `Train CPU ML Model`: trains the LightGBM model, logs to MLflow, and archives model artifacts when enabled.
- `Build BentoML Image`: builds only the BentoML predictor image when enabled.
- `Trivy Image Scan`: required Jenkins HIGH/CRITICAL image vulnerability gate.
- `Generate Image SBOM`: required Jenkins CycloneDX SBOM artifact.
- `Push BentoML Image`: tags and pushes the BentoML image to GCP Artifact Registry when enabled.
- `Promote Model`: points an MLflow model alias, usually `champion`, at a reviewed model version.
- `Deploy BentoML`: recreates only the BentoML predictor service.
- `Deploy`: runs `scripts/deploy_compose.sh` only on `main` or `master`.

MLOps stages are controlled by Jenkins build parameters:

- `BUILD_ALL_IMAGES=true` builds every Docker Compose image.
- `BUILD_MLOPS_IMAGE=true` builds the BentoML service image.
- `RUN_SONARQUBE_SCAN=true` runs the SonarQube gate.
- `RUN_TRIVY_IMAGE_SCAN=true` scans the built BentoML image with Trivy.
- `TRIVY_FAIL_ON_FINDINGS=true` makes actionable HIGH/CRITICAL Trivy findings fail the build.
- `GENERATE_IMAGE_SBOM=true` archives a CycloneDX dependency inventory for the built BentoML image.
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
RUN_SONARQUBE_SCAN=true
RUN_TRIVY_IMAGE_SCAN=true
TRIVY_FAIL_ON_FINDINGS=true
GENERATE_IMAGE_SBOM=true
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

Trivy image scanning archives this file in Jenkins:

```text
artifacts/security/trivy-image-scan.txt
```

SBOM generation archives this file in Jenkins:

```text
artifacts/security/bento-image-sbom.cdx.json
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

## IaC security checks

Run Checkov against Terraform, Helm, and Kubernetes manifests:

```bash
make security-check
```

Known demo exceptions are documented in `.checkov.yaml`. Keep that file small; when a skipped check becomes part of the production scope, remove the skip and implement the control.

CI also calls the same script, but skips it when `checkov` is not installed. To make the check mandatory in a CI image, install Checkov first:

```bash
python3 -m pip install --user checkov
```

The Jenkins image already installs Checkov, and Jenkins runs:

```bash
CHECKOV_REQUIRED=true bash scripts/ci_check.sh
```

So Checkov is a blocking Jenkins gate.

## SonarQube

SonarQube is a blocking Jenkins gate. For local setup, run it with the CI profile:

```bash
COMPOSE_PROFILES=ci docker compose --env-file .env up -d sonarqube
```

Open `http://localhost:${SONARQUBE_PORT:-9002}`, log in with `admin/admin`, change the password, create a local project, and create a token.

Run a scan from your machine:

```bash
SONAR_TOKEN=your-token make sonar-scan
```

In Jenkins, add the token as a Secret text credential with ID `sonarqube-token`. `RUN_SONARQUBE_SCAN` defaults to `true`. Jenkins uses `SONAR_HOST_URL` from `.env` unless the `SONARQUBE_URL` parameter is set.

The project Jenkins image installs Checkov, so Jenkins CI runs this scan as part of `scripts/ci_check.sh`.

## Image vulnerability scan

Run Trivy against the local BentoML image after building it:

```bash
COMPOSE_PROFILES=mlops docker compose --env-file .env build bento-price-predictor
make trivy-image-scan
```

For local baseline work, the script can report HIGH and CRITICAL findings without failing:

```text
TRIVY_EXIT_CODE=0
```

To turn it into a blocking gate:

```bash
TRIVY_EXIT_CODE=1 make trivy-image-scan
```

The BentoML image uses a multi-stage Dockerfile: build packages stay in the builder stage, and the runtime stage uses `python:3.12-slim-bookworm` with only runtime packages. The Trivy script defaults `TRIVY_IGNORE_UNFIXED=true`, so the gate blocks fixable HIGH/CRITICAL vulnerabilities but does not fail on base-image advisories that have no patched package yet.

In Jenkins, the recommended gate is:

```text
RUN_TRIVY_IMAGE_SCAN=true
TRIVY_FAIL_ON_FINDINGS=true
TRIVY_SEVERITY=HIGH,CRITICAL
```

## Image SBOM

Generate a CycloneDX SBOM for the local BentoML image:

```bash
COMPOSE_PROFILES=mlops docker compose --env-file .env build bento-price-predictor
make image-sbom
```

The SBOM lists the OS and application packages included in the image. Archive it with every pushed image so a future vulnerability advisory can be mapped back to the exact deployed artifact.

In Jenkins, this defaults to:

```text
GENERATE_IMAGE_SBOM=true
```

## Minimal GKE deploy

After pushing the BentoML image to Artifact Registry and connecting `kubectl` to a GKE cluster, deploy the predictor only:

```bash
make gke-deploy-bento
```

The GKE deploy script is intentionally strict: it deploys only an explicit immutable image URI. The URI must come from one of these sources:

```text
IMAGE_URI environment variable
artifacts/mlops/bento_image_uri.txt written by make mlops-push-bento
```

This avoids accidentally deploying an image tag that was never pushed to Artifact Registry. A normal build/push/deploy sequence is:

```bash
COMPOSE_PROFILES=mlops docker compose --env-file .env build bento-price-predictor
IMAGE_TAG="$(git rev-parse --short HEAD)" make mlops-push-bento
BENTO_INGRESS_ENABLED=true BENTO_TRACING_ENABLED=true make gke-deploy-bento
```

For emergency rollback or a known image, pass the image explicitly:

```bash
IMAGE_URI=asia-southeast1-docker.pkg.dev/<project>/<repo>/<image>:<tag> \
BENTO_INGRESS_ENABLED=true \
BENTO_TRACING_ENABLED=true \
make gke-deploy-bento
```

Helm deploys use `--atomic`, so a failed rollout is rolled back instead of leaving a half-upgraded release.

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

Runtime Kubernetes security is intentionally not part of the main demo path. `NetworkPolicy` and app `securityContext` are off by default to keep the deployment easy to reason about.

If you want to re-enable a small NetworkPolicy later, set:

```bash
BENTO_NETWORK_POLICY_ENABLED=true make gke-deploy-bento
```

Then Bento accepts in-cluster traffic only from namespaces listed under `networkPolicy.allowedNamespaces` in `charts/bento-price-predictor/values.yaml`.

For a more production-like serving deployment, run at least two replicas and then enable a PodDisruptionBudget:

```bash
BENTO_INGRESS_ENABLED=true \
BENTO_TRACING_ENABLED=true \
BENTO_REPLICA_COUNT=2 \
BENTO_PDB_ENABLED=true \
BENTO_PDB_MIN_AVAILABLE=1 \
make gke-deploy-bento
```

This lets Kubernetes keep at least one Bento pod available during voluntary disruptions such as node maintenance. Keep `BENTO_PDB_ENABLED=false` when running one replica for a small demo.

Enable HorizontalPodAutoscaler only when you want serving capacity to scale with CPU load. For a one-replica demo, leave it disabled:

```bash
BENTO_INGRESS_ENABLED=true \
BENTO_TRACING_ENABLED=true \
BENTO_REPLICA_COUNT=2 \
BENTO_PDB_ENABLED=true \
BENTO_PDB_MIN_AVAILABLE=1 \
BENTO_AUTOSCALING_ENABLED=true \
BENTO_AUTOSCALING_MIN_REPLICAS=2 \
BENTO_AUTOSCALING_MAX_REPLICAS=4 \
BENTO_AUTOSCALING_TARGET_CPU=70 \
make gke-deploy-bento
```

Check the serving rollout, Service, Ingress, HPA, and PDB:

```bash
make gke-status-bento
```

Keep autoscaling disabled for short demos when cost matters more than scale testing.

Enable the lightweight synthetic probe CronJob when you want Kubernetes to test the Bento API from inside the cluster:

```bash
BENTO_INGRESS_ENABLED=true \
BENTO_TRACING_ENABLED=true \
BENTO_SYNTHETIC_PROBE_ENABLED=true \
make gke-deploy-bento
```

By default it runs every 5 minutes and calls:

```text
GET /readyz
POST /health
```

Run one probe immediately:

```bash
make gke-run-synthetic-probe-bento
```

Then inspect the created Job and logs:

```bash
kubectl -n app get job -l app.kubernetes.io/component=synthetic-probe
kubectl -n app logs job/<job-name>
```

### Data ingestion validation service

The first `data-ingestion` namespace component is a small validation API. It validates OHLCV candle records before the pipeline routes data into validated or quality streams.

Build and push the image:

```bash
make data-validation-build
IMAGE_TAG="$(git rev-parse --short HEAD)" make data-validation-push
```

Deploy to GKE:

```bash
make data-validation-deploy
```

Enable the demo telemetry producer CronJob when you want the `data-ingestion` namespace to generate sample records and exercise both routes:

```bash
DATA_VALIDATION_TELEMETRY_PRODUCER_ENABLED=true make data-validation-deploy
```

To also forward valid telemetry records into the feature platform:

```bash
DATA_VALIDATION_TELEMETRY_PRODUCER_ENABLED=true \
DATA_VALIDATION_FEATURE_PLATFORM_ENABLED=true \
DATA_VALIDATION_FEATURE_PLATFORM_URL=http://feature-platform.feature-platform.svc.cluster.local \
make data-validation-deploy
```

This creates:

- namespace `data-ingestion`
- Helm release `data-validation`
- Deployment `data-validation`
- ClusterIP Service `data-validation`
- optional telemetry producer CronJob

Check status:

```bash
make data-validation-status
```

View service logs and namespace events:

```bash
make data-validation-logs
make data-validation-events
```

Smoke test locally:

```bash
make data-validation-port-forward
```

From another terminal:

```bash
make data-validation-smoke
```

The validation endpoint is:

```text
POST /validate
```

It currently checks required fields, positive prices, non-negative volume, OHLC high/low consistency, and strictly increasing timestamps in a batch. The next step is to connect this service to Kafka or object storage and route valid records to the feature platform while storing rejected records for data quality review.

The response includes route targets:

```text
validated_target=validated-candles
quality_target=quality-candles
```

The telemetry producer CronJob sends a mixed sample batch to `/validate`, so logs show one record accepted for the validated route and one rejected for the quality route. Run it immediately with:

```bash
make data-validation-run-telemetry-producer
```

Then inspect the job logs:

```bash
kubectl -n data-ingestion get job -l app.kubernetes.io/component=telemetry-producer
kubectl -n data-ingestion logs job/<job-name>
```

If feature forwarding is enabled, the same job also sends the valid sample record to:

```text
POST http://feature-platform.feature-platform.svc.cluster.local/features/ingest
```

Verify it from your local machine by port-forwarding the feature platform and reading the latest feature:

```bash
make feature-platform-port-forward
FEATURE_PLATFORM_URL=http://localhost:8090 make feature-platform-smoke
```

To change route names:

```bash
DATA_VALIDATION_VALIDATED_TARGET=validated-candles \
DATA_VALIDATION_QUALITY_TARGET=quality-candles \
make data-validation-deploy
```

The monitoring stack includes Prometheus alerts for this namespace:

- `DataValidationUnavailable`
- `DataValidationRestarting`
- `DataValidationProblemPods`
- `DataValidationTelemetryProducerFailed`

Apply or refresh the monitoring rules with:

```bash
make gke-install-monitoring
```

Then check Prometheus rule health:

```bash
PORT=9091 make gke-monitoring-prometheus
```

Browse to `http://localhost:9091`, then open `Status > Rule health` and search for `data-validation`.

To remove only this data-ingestion service:

```bash
make data-validation-delete
```

### Feature platform service

The first `feature-platform` namespace component is a small feature API. It receives validated candle records, computes simple online features, and exposes latest/history endpoints. The first version uses an in-memory store so the demo stays cheap and easy to reset. Redis/PostgreSQL can replace this later without changing the upstream validation API shape.

Build and push the image:

```bash
make feature-platform-build
IMAGE_TAG="$(git rev-parse --short HEAD)" make feature-platform-push
```

Deploy to GKE:

```bash
make feature-platform-deploy
```

This creates:

- namespace `feature-platform`
- Helm release `feature-platform`
- Deployment `feature-platform`
- ClusterIP Service `feature-platform`

Check status:

```bash
make feature-platform-status
```

Smoke test locally:

```bash
make feature-platform-port-forward
```

From another terminal:

```bash
FEATURE_PLATFORM_URL=http://localhost:8090 make feature-platform-smoke
```

The main endpoints are:

```text
POST /features/ingest
GET /features/latest/{symbol}
GET /features/history/{symbol}
```

The current feature set includes return, log return, volume change, high/low spread, open/close spread, and rolling close means for windows 3, 6, and 12.

Kafka candle events use the shared versioned envelope from
`contracts/events.py`:

```text
event_id, schema_version, event_type, timestamp, source, payload
```

`event_id` is the idempotency key. Feature-platform stores processed IDs in
PostgreSQL and ignores retries. Data validation uses a bounded memory cache for
one-replica demos. For multiple validation replicas, use the existing
feature-platform Redis as the shared idempotency backend:

```bash
VALIDATION_IDEMPOTENCY_REDIS_URL=redis://feature-platform-redis.feature-platform.svc.cluster.local:6379/0 \
make data-validation-deploy
```

To remove only this feature service:

```bash
make feature-platform-delete
```

### Streaming platform on GKE

The `data-streaming` namespace contains a single Kafka KRaft broker with a 2 Gi
PVC and the Coinbase WebSocket producer. Helm creates these topics:

```text
coin-data
coin-data-model
coin-data-validated
coin-data-quality
```

Build, push, and deploy:

```bash
make streaming-platform-build
IMAGE_TAG="$(git rev-parse --short HEAD)" make streaming-platform-push
make streaming-platform-deploy
```

Verify Kafka, topics, and producer:

```bash
make streaming-platform-status
make streaming-platform-smoke
make streaming-platform-logs
```

Remove the release when stopping the environment:

```bash
make streaming-platform-delete
```

The single broker and replication factor one are appropriate for the current
Autopilot development cluster. Use a multi-broker Kafka deployment with
replication when migrating to GKE Standard for production.

### Inference orchestrator service

The `model-serving` namespace contains the `inference-orchestrator` API. It receives recent candle history, calls BentoML for prediction, attaches feature context, evaluates the alert rule, and persists alert history. These responsibilities share one request lifecycle and are intentionally deployed as one service.

The default alert history uses JSONL on a 1 Gi PVC and requires one orchestrator
replica. Move alert history to PostgreSQL before enabling HPA or multiple
orchestrator replicas.

Every successful prediction also persists governance decision telemetry with
the decision, model identity, latency, available drift evidence, and
operational health. The JSONL records form a tamper-evident hash chain. For a
regulated production system, move this audit trail to immutable external
storage before enabling multiple replicas.

Build and push the image:

```bash
make inference-orchestrator-build
IMAGE_TAG="$(git rev-parse --short HEAD)" make inference-orchestrator-push
```

Deploy to GKE:

```bash
make inference-orchestrator-deploy
```

Expose the orchestrator as the public prediction API through nginx ingress:

```bash
make inference-orchestrator-ingress
```

Get the public base URL:

```bash
make inference-orchestrator-public-url
```

The public endpoint is:

```text
POST http://<ingress-ip>/orchestrate/predict
```

Smoke test the public API:

```bash
make inference-orchestrator-smoke-public
```

BentoML should stay internal in this flow. External clients call the orchestrator, and the orchestrator calls BentoML and feature-platform inside the cluster. Alert evaluation and history are handled internally.

By default it calls these in-cluster services:

```text
http://bento-price-predictor.app.svc.cluster.local/predict
http://feature-platform.feature-platform.svc.cluster.local
```

Check status:

```bash
make inference-orchestrator-status
make inference-orchestrator-ingress-status
```

Smoke test locally:

```bash
make inference-orchestrator-port-forward
```

From another terminal:

```bash
INFERENCE_ORCHESTRATOR_URL=http://localhost:8091 make inference-orchestrator-smoke
```

The main endpoints are:

```text
GET /config
POST /orchestrate/predict
GET /orchestrate/latest/{symbol}
GET /alerts
GET /alerts/{alert_id}
GET /governance/decisions
GET /governance/decisions/{decision_id}
GET /governance/integrity
```

To remove only this inference service:

```bash
make inference-orchestrator-delete
```

### Minimal GKE monitoring and logs

For the first GKE version, use Kubernetes status, events, and pod logs directly. This keeps the setup small while still showing whether the predictor is healthy.

Check deployment, pod, and service status:

```bash
make gke-status-bento
```

Show a compact operational snapshot:

```bash
make gke-observe-bento
```

Check nginx ingress and the Bento ingress route:

```bash
make gke-ingress-status-bento
```

Describe the deployment and pod when readiness, image pull, or scheduling fails:

```bash
make gke-describe-bento
```

Show pod CPU and memory usage when metrics are available:

```bash
make gke-top-bento
```

Show recent BentoML logs:

```bash
make gke-logs-bento
```

Follow BentoML logs live:

```bash
make gke-follow-logs-bento
```

Read centralized GKE logs from Google Cloud Logging:

```bash
make gke-cloud-logs-bento
```

Useful filters:

```bash
LIMIT=50 FRESHNESS=24h make gke-cloud-logs-bento
GKE_CLUSTER=coinbase-mlops GKE_REGION=asia-southeast1 make gke-cloud-logs-bento
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

### Optional public GKE endpoint with nginx ingress

The chart defaults to `ClusterIP`, so the predictor is private inside the cluster. For a short demo with one shared public load balancer, install nginx ingress:

```bash
make gke-install-ingress-nginx
```

Enable the BentoML ingress route:

```bash
make gke-ingress-bento
```

Get the nginx ingress URL and test it:

```bash
BENTO_URL="$(make -s gke-ingress-url-bento)"
curl -fsS "$BENTO_URL/readyz"
curl -fsS -X POST "$BENTO_URL/health"
```

Prediction smoke test through ingress:

```bash
MLOPS_PREDICT_URL="$BENTO_URL/predict" \
DATA=/home/quan/projects/Coinbase_Streaming/data/BTCUSDT_5m_full.csv \
make mlops-test-predict
```

For a quick one-service demo without nginx, you can still expose the Bento service directly:

```bash
make gke-expose-bento
make gke-public-url-bento
```

When the direct service demo is done, switch back to the private service to remove that direct load balancer:

```bash
make gke-unexpose-bento
```

### Cleanup to control GCP cost

At the end of a demo, remove public load balancers first:

```bash
make gke-unexpose-bento
make gke-uninstall-ingress-nginx
```

If you no longer need the BentoML workload in the cluster:

```bash
make gke-delete-bento
```

To stop GKE cluster charges entirely, destroy the Terraform-managed GCP resources:

```bash
cd /home/quan/projects/Coinbase_Streaming
make terraform-destroy
```

Before destroying, confirm Terraform is using the expected project:

```bash
cd infra/terraform
terraform plan
```

`terraform destroy` removes the GKE cluster, Artifact Registry repository, and Jenkins deployer service account managed by Terraform. Do not run it if you still need the pushed Docker images or the live demo endpoint.

### GKE monitoring and logging

Install the Prometheus/Grafana stack:

```bash
make gke-install-monitoring
```

Open Grafana locally:

```bash
PORT=3003 make gke-monitoring-grafana
```

Then browse `http://localhost:3003` and log in with `admin/admin`.

Check that Prometheus has targets:

```promql
up
```

Useful Kubernetes dashboards:

```text
Kubernetes / Compute Resources / Namespace (Pods)
Kubernetes / Compute Resources / Pod
Kubernetes / Networking / Namespace (Workload)
```

The monitoring install also provisions a project dashboard:

```text
Coinbase / Bento Price Predictor
Coinbase / Streaming and Predictions
```

`Coinbase / Streaming and Predictions` reads validated candles from the
feature-platform PostgreSQL store and refreshes every 10 seconds. It also
compares each stored prediction with the actual candle received at its target
time. Choose the symbol at the top and use a time range that contains the
streamed candle timestamps.

After changing this dashboard or its application storage, rebuild and deploy
the feature platform and inference orchestrator, then refresh monitoring:

```bash
IMAGE_TAG=$(git rev-parse --short HEAD) make feature-platform-build feature-platform-push
IMAGE_TAG=$(git rev-parse --short HEAD) make inference-orchestrator-build inference-orchestrator-push
make feature-platform-deploy
make inference-orchestrator-deploy
make gke-install-monitoring
PORT=3003 make gke-monitoring-grafana
```

The Bento dashboard contains available/ready replicas, problem pod count,
restart trend, recent Bento logs, and warning/error logs. If a dashboard is not
visible right after reinstalling monitoring, wait for the Grafana sidecar
refresh or restart Grafana:

```bash
kubectl -n monitoring rollout restart deploy/kube-prometheus-stack-grafana
```

It also provisions lightweight Prometheus alerts for Bento:

```text
BentoPredictorUnavailable
BentoPredictorRestarting
BentoPredictorProblemPods
```

Alertmanager is enabled with a no-op receiver by default so alerts have proper grouping, silencing, and lifecycle state without sending external notifications.

Open Alertmanager locally:

```bash
PORT=9094 make gke-monitoring-alertmanager
```

Then browse:

```text
http://localhost:9094
```

To route alerts to a webhook receiver, reinstall monitoring with:

```bash
ALERTMANAGER_WEBHOOK_URL="https://example.com/alert-webhook" make gke-install-monitoring
```

For real production, use a controlled destination such as Slack, PagerDuty, Google Chat, or an internal webhook service, and store the receiver URL in your secret manager or CI credentials instead of committing it.

To test the alert path, temporarily make the Bento deployment unavailable:

```bash
kubectl -n app scale deploy/bento-price-predictor --replicas=0
```

Wait at least 2 minutes, then check Alertmanager. Restore the service after the test:

```bash
kubectl -n app scale deploy/bento-price-predictor --replicas=1
kubectl -n app rollout status deploy/bento-price-predictor
```

For a quick built-in GKE log check, use Google Cloud Logging:

```bash
make gke-cloud-logs-bento
```

Install the optional Loki logging stack when you want Grafana Explore logs:

```bash
make gke-install-logging
```

Grafana is configured with this Loki datasource:

```text
http://loki.logging.svc.cluster.local:3100
```

If Grafana was installed before Loki, refresh the monitoring release so the datasource appears:

```bash
make gke-install-monitoring
```

Then open Grafana Explore, select `Loki`, use `Code` mode, set the time range to `Last 1 hour`, and query:

```logql
{namespace="app"}
```

For the BentoML predictor only:

```logql
{namespace="app", app="bento-price-predictor"}
```

If the log list is empty, generate a new request and refresh Grafana:

```bash
BENTO_URL="$(make -s gke-ingress-url-bento)"
curl -fsS "$BENTO_URL/" >/dev/null
```

If Grafana shows a warning in `Logs volume` but the `Logs` section displays lines, logging is working. The volume panel can be ignored for this demo.

Check Loki directly from the cluster:

```bash
kubectl -n logging exec loki-0 -- \
  wget -qO- 'http://localhost:3100/loki/api/v1/query_range?query=%7Bnamespace%3D%22app%22%7D&limit=5'
```

Check Promtail and Loki health:

```bash
make gke-logging-status
kubectl -n logging exec loki-0 -- wget -qO- http://localhost:3100/ready
```

Install the optional production-style tracing stack when you want Grafana Explore traces:

```bash
make gke-install-tracing
```

This installs:

```text
OpenTelemetry Collector: receives OTLP from application workloads
Tempo: stores and queries traces
```

Trace flow:

```text
BentoML predictor
-> otel-collector.tracing.svc.cluster.local:4317
-> tempo.tracing.svc.cluster.local:4317
-> Grafana Tempo datasource
```

Grafana is configured with this Tempo datasource:

```text
http://tempo.tracing.svc.cluster.local:3200
```

If Grafana was installed before Tempo, refresh the monitoring release so the datasource appears:

```bash
make gke-install-monitoring
```

Redeploy BentoML with OTLP tracing environment variables:

```bash
BENTO_TRACING_ENABLED=true make gke-deploy-bento
```

If the app is exposed through nginx ingress, keep ingress enabled while redeploying:

```bash
BENTO_INGRESS_ENABLED=true BENTO_TRACING_ENABLED=true make gke-deploy-bento
```

Generate a request so traces/logs have fresh traffic:

```bash
BENTO_URL="$(make -s gke-ingress-url-bento)"
curl -fsS "$BENTO_URL/" >/dev/null
```

Open Grafana Explore, select `Tempo`, and search by trace ID. BentoML request logs include a `trace=<id>` field, which is useful for checking trace/log correlation. If Tempo has no traces, keep using Loki logs and Prometheus metrics; the tracing backend is optional for this demo and can be wired deeper once application instrumentation is in scope.

The GKE chart enables these OpenTelemetry settings when tracing is on:

```text
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.tracing.svc.cluster.local:4317
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_TRACES_EXPORTER=otlp
OTEL_TRACES_SAMPLER=always_on
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=gke,service.namespace=app
```

The BentoML image includes the OTLP gRPC exporter dependency so the runtime can send spans to the collector.

Check tracing status:

```bash
make gke-tracing-status
```

Check the collector logs when traces do not arrive:

```bash
kubectl -n tracing logs deploy/otel-collector --tail=80
```

Remove the monitoring stack when the demo is done:

```bash
make gke-uninstall-tracing
make gke-uninstall-logging
make gke-uninstall-monitoring
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
RUN_SONARQUBE_SCAN=true
SONARQUBE_URL=http://sonarqube:9000
RUN_TRIVY_IMAGE_SCAN=true
TRIVY_FAIL_ON_FINDINGS=true
TRIVY_SEVERITY=HIGH,CRITICAL
GENERATE_IMAGE_SBOM=true
PUSH_BENTO_IMAGE=true
IMAGE_TAG=
DEPLOY_GKE=true
GCP_CREDENTIALS_ID=gcp-jenkins-sa-key
GKE_CLUSTER=coinbase-mlops
GKE_REGION=asia-southeast1
```

For local demo work, the service account can have Artifact Registry writer access and enough GKE permissions to deploy. For production, prefer keyless Workload Identity or a locked-down deploy agent.

### Production-style Jenkins to GKE runbook

Use this runbook for the current end-to-end multibranch flow:

```text
GitHub branch
-> Jenkins multibranch pipeline
-> CI checks
-> Checkov IaC/security checks
-> SonarQube scan
-> BentoML image build
-> Artifact Registry push
-> Helm deploy to GKE
-> in-cluster smoke test
-> nginx ingress public smoke test
```

#### 1. Start local CI services

Start Jenkins and SonarQube:

```bash
COMPOSE_PROFILES=ci docker compose --env-file .env up -d jenkins sonarqube
```

Open:

```text
Jenkins: http://localhost:8088
SonarQube from host: http://localhost:9002
SonarQube from Jenkins: http://sonarqube:9000
```

#### 2. Prepare GCP and GKE

Create or update the Terraform-managed infrastructure:

```bash
cd /home/quan/projects/Coinbase_Streaming
make terraform-init
make terraform-plan
terraform -chdir=infra/terraform apply
```

Connect local `kubectl` to the cluster:

```bash
gcloud config set account <your-user-account>
gcloud config set project awesome-pilot-494017-u5
gcloud container clusters get-credentials coinbase-mlops --region=asia-southeast1
kubectl get ns
```

If local `kubectl` fails with a service-account token error, switch back to your user account:

```bash
gcloud auth list
gcloud config set account <your-user-account>
gcloud container clusters get-credentials coinbase-mlops --region=asia-southeast1
```

The Jenkins service account is for Jenkins credentials. Local terminal operations should normally use your user account.

#### 3. Install nginx ingress

Install the shared public ingress controller once per cluster:

```bash
make gke-install-ingress-nginx
```

Check its public IP:

```bash
make gke-ingress-url-bento
```

#### 4. Jenkins credentials

Create these Jenkins credentials before the full pipeline:

```text
ID: sonarqube-token
Kind: Secret text
Value: SonarQube Project Analysis Token or User Token
```

```text
ID: gcp-jenkins-sa-key
Kind: Secret file
File: Jenkins deployer service account JSON key
```

For the local demo key path from Terraform:

```bash
cd /home/quan/projects/Coinbase_Streaming/infra/terraform
terraform output -raw jenkins_service_account_key_json_base64 | base64 -d > /tmp/gcp-jenkins-sa-key.json
```

Upload `/tmp/gcp-jenkins-sa-key.json` to Jenkins as the `gcp-jenkins-sa-key` Secret file. Do not commit this file.

#### 5. Run the branch pipeline

In Jenkins:

```text
Coinbase Streaming
-> Scan Multibranch Pipeline Now
-> add/ops
-> Build with Parameters
```

Use these parameters for the full demo:

```text
RUN_SONARQUBE_SCAN=true
SONARQUBE_URL=http://sonarqube:9000
SONARQUBE_TOKEN_CREDENTIALS_ID=sonarqube-token

BUILD_MLOPS_IMAGE=true
RUN_TRIVY_IMAGE_SCAN=true
TRIVY_FAIL_ON_FINDINGS=true
TRIVY_SEVERITY=HIGH,CRITICAL
GENERATE_IMAGE_SBOM=true
PUSH_BENTO_IMAGE=true
IMAGE_TAG=
IMAGE_URI=

GCP_PROJECT_ID=awesome-pilot-494017-u5
GAR_LOCATION=asia-southeast1
GAR_REPOSITORY=coinbase-mlops
BENTO_IMAGE_NAME=coinbase-bento-price-predictor
GCP_CREDENTIALS_ID=gcp-jenkins-sa-key

DEPLOY_GKE=true
GKE_CLUSTER=coinbase-mlops
GKE_REGION=asia-southeast1
ENABLE_BENTO_INGRESS=true
SMOKE_GKE_PUBLIC=true
BENTO_PUBLIC_URL=

BUILD_ALL_IMAGES=false
TRAIN_MLOPS_MODEL=false
PROMOTE_MODEL=false
DEPLOY_BENTO=false
DEPLOY_COMPOSE=false
```

Leave `IMAGE_TAG` empty so Jenkins uses an immutable tag like:

```text
build-10-cda70c4
```

Leave `IMAGE_URI` empty when `PUSH_BENTO_IMAGE=true`. Set `IMAGE_URI` only when you intentionally want to deploy an existing image without pushing a new one.

#### 6. Expected success output

The end of a successful run should include:

```text
Pushed BentoML image: asia-southeast1-docker.pkg.dev/.../coinbase-bento-price-predictor:<tag>
deployment "bento-price-predictor" successfully rolled out
GKE Bento smoke test passed
Public Bento smoke test passed at http://<nginx-ip>
Finished: SUCCESS
```

Recent successful demo image:

```text
asia-southeast1-docker.pkg.dev/awesome-pilot-494017-u5/coinbase-mlops/coinbase-bento-price-predictor:build-10-cda70c4
```

Recent successful public URL:

```text
http://35.240.132.151
```

Public IPs can change when the load balancer is recreated.

#### 7. Verify after Jenkins

Check the GKE workload:

```bash
make gke-status-bento
make gke-smoke-in-cluster-bento
make gke-smoke-public-bento
```

Check the public endpoint directly:

```bash
BENTO_URL="$(make -s gke-ingress-url-bento)"
curl -fsS "$BENTO_URL/readyz"
curl -fsS -X POST "$BENTO_URL/health"
```

Run a prediction through the public endpoint:

```bash
MLOPS_PREDICT_URL="$BENTO_URL/predict" \
DATA=/home/quan/projects/Coinbase_Streaming/data/BTCUSDT_5m_full.csv \
make mlops-test-predict
```

#### 8. Common failures

If SonarQube fails with `SONAR_TOKEN is required`, confirm Jenkins has the `sonarqube-token` Secret text credential and `SONARQUBE_TOKEN_CREDENTIALS_ID=sonarqube-token`.

If Artifact Registry push fails against `change-me-gcp-project`, set the Jenkins `GCP_PROJECT_ID` parameter to:

```text
awesome-pilot-494017-u5
```

If GKE deploy fails with `ImagePullBackOff`, check that `PUSH_BENTO_IMAGE=true` or set `IMAGE_URI` to an existing Artifact Registry image. Do not deploy from stale `artifacts/mlops/bento_image_uri.txt`.

If public smoke test cannot determine a URL, install nginx ingress and enable the Bento ingress:

```bash
make gke-install-ingress-nginx
```

Then rerun Jenkins with:

```text
ENABLE_BENTO_INGRESS=true
SMOKE_GKE_PUBLIC=true
```

If rollout waits on old replicas, inspect the deployment:

```bash
make gke-status-bento
make gke-describe-bento
make gke-events-bento
```

#### 9. Cleanup after demo

To stop public load balancer and workload costs:

```bash
make gke-uninstall-monitoring
make gke-uninstall-ingress-nginx
make gke-delete-bento
```

To stop GKE cluster charges entirely and remove Terraform-managed resources:

```bash
make terraform-destroy
```

Confirm before destroy:

```bash
terraform -chdir=infra/terraform plan
```

`terraform destroy` removes Terraform-managed GKE, Artifact Registry, and Jenkins deployer service account resources. Run it only when you no longer need the live endpoint or pushed images.

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

For the older single Pipeline fallback only, you can run the repository `Jenkinsfile` from the local mounted workspace with this script:

```groovy
node {
  dir('/workspace/Coinbase_Streaming') {
    load 'Jenkinsfile'
  }
}
```

Do not wrap that `load` call inside another `pipeline { ... }` block. Jenkins allows only one Declarative Pipeline block per run.

The production-style path is the multibranch job, which checks out each branch into Jenkins' own workspace and runs that branch's `Jenkinsfile` there.

## Monitoring and logs

The `ops` Compose profile starts:

- Prometheus for metrics.
- Alertmanager for basic alert routing.
- Blackbox Exporter for HTTP health checks.
- cAdvisor for container metrics.
- Loki and Promtail for Docker container logs.

Alert rules live in `ops/observability/monitoring/prometheus/alerts.yml`. Alertmanager currently uses a local no-op receiver so alerts are visible in the UI but not sent externally. Add Slack, email, or webhook receivers in `ops/observability/monitoring/alertmanager/alertmanager.yml` when you have a destination.

## Current limits

The active production-style path is GKE plus Helm. Local Docker Compose is kept
for developer support services such as Jenkins, SonarQube, MLflow, Airflow, and
observability experiments. For real production, the next step is managed or
highly available Kafka/object storage/secrets and external alert delivery.
