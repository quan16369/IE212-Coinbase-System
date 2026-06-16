# MLOps

This repo includes a CPU-friendly MLOps path for price forecasting. The default MLOps model resamples input OHLCV data to 1-hour candles and forecasts the next 4-hour return. LightGBM predicts future return and BentoML reconstructs the future close from the latest close.

## Components

- ML model: `LightGBM` `LGBMRegressor`
- Experiment tracking: MLflow
- Serving: BentoML
- CI/CD: Jenkins
- Local runtime: Docker Compose profile `mlops`

## Train a CPU model

Prepare an OHLCV CSV with these columns:

```text
timestamp,open,high,low,close,volume
```

Capitalized Coinbase-style columns are also accepted:

```text
timestamp,Open,High,Low,Close,Volume
```

The current training CSV can stay at 5-minute resolution. Feature engineering resamples those rows to 1-hour OHLCV candles before building the target, lags, and rolling windows.

Train and save the model artifact:

```bash
pip install -r mlops/requirements.txt
DATA=/path/to/ohlcv.csv make mlops-train
```

The default output is:

```text
artifacts/mlops/coinbase_ml_model.joblib
artifacts/mlops/coinbase_ml_model.metadata.json
```

Training logs metrics and parameters to MLflow. By default, local training uses `sqlite:///mlflow.db`. To log into the Compose MLflow server, start MLflow first and set the tracking URI:

```bash
COMPOSE_PROFILES=mlops docker compose --env-file .env up -d mlflow
MLFLOW_TRACKING_URI=http://localhost:5000 DATA=/path/to/ohlcv.csv make mlops-train
```

The Compose MLflow server proxies artifact uploads into its `mlflow-data` volume so training from the host can log feature metadata and model artifacts through the tracking server. It also allows the Docker DNS host `mlflow:5000` so BentoML can read a promoted registry model from the tracking server on the local Compose network.

If the local `coinbase-price-forecasting` experiment was created before the Compose server used artifact proxying, start a new experiment name for the next run:

```bash
MLFLOW_EXPERIMENT_NAME=coinbase-price-forecasting-v2 \
MLFLOW_TRACKING_URI=http://localhost:5000 DATA=/path/to/ohlcv.csv make mlops-train
```

Each successful MLflow artifact log also registers a version under `coinbase-price-lightgbm`. Training creates versions; it does not decide which version should serve traffic.

## Promote a model version

Open MLflow `Model registry`, inspect `coinbase-price-lightgbm`, and choose the model version that should serve. Point the `champion` alias at that version:

```bash
MLFLOW_TRACKING_URI=http://localhost:5000 MODEL_VERSION=1 make mlops-promote-model
```

Then set the registry URI in `.env` so BentoML loads the promoted model from MLflow instead of the packaged image artifact:

```text
MLOPS_MODEL_URI=models:/coinbase-price-lightgbm@champion
```

Rebuild and recreate the BentoML service after changing `.env` or the service code:

```bash
COMPOSE_PROFILES=mlops docker compose --env-file .env up -d --build --force-recreate bento-price-predictor
```

The packaged `.joblib` path remains as a fallback for early local work. When `MLOPS_MODEL_URI` is set, BentoML loads the MLflow model URI first and reads feature metadata from the logged MLflow model metadata.

## Start MLflow and BentoML

Create `.env` if it does not exist:

```bash
cp .env.example .env
```

Train a model first, then start the MLOps profile:

```bash
make mlops-up
```

Endpoints:

- MLflow: `http://localhost:5000`
- BentoML predictor: `http://localhost:3001`
- BentoML readiness: `http://localhost:3001/readyz`

## Prediction request

Send enough recent candles to satisfy the lag and rolling-window features after hourly resampling. The default model requires at least 25 hourly model rows, which is roughly 300 raw 5-minute rows.

Test the running BentoML service with recent rows from a CSV:

```bash
DATA=/path/to/ohlcv.csv make mlops-test-predict
```

Override the endpoint or history length when needed:

```bash
MLOPS_PREDICT_URL=http://localhost:3001/predict MLOPS_TEST_ROWS=360 \
  DATA=/path/to/ohlcv.csv make mlops-test-predict
```

Use a direct HTTP request when debugging the payload shape:

```bash
curl -X POST http://localhost:3001/predict \
  -H 'Content-Type: application/json' \
  -d '{
    "records": [
      {"timestamp":"2026-05-21T00:00:00","open":100,"high":101,"low":99,"close":100.5,"volume":10}
    ]
  }'
```

The example above shows the JSON shape only. Real prediction needs enough historical rows. A response includes both `predicted_return` and reconstructed `predicted_close`.

## Jenkins

The Jenkins pipeline has optional MLOps stages. For local Jenkins, open `Build with Parameters` and choose one of these common modes.

### CI and BentoML image build

Use this for the normal code/image check:

```text
BUILD_ALL_IMAGES=false
BUILD_MLOPS_IMAGE=true
TRAIN_MLOPS_MODEL=false
PROMOTE_MODEL=false
DEPLOY_BENTO=false
DEPLOY_COMPOSE=false
```

### Train and archive model artifacts

Use this to create a new MLflow run and registered model version:

```text
BUILD_ALL_IMAGES=false
BUILD_MLOPS_IMAGE=true
TRAIN_MLOPS_MODEL=true
MLOPS_TRAINING_CSV=
PROMOTE_MODEL=false
DEPLOY_BENTO=false
DEPLOY_COMPOSE=false
```

When `MLOPS_TRAINING_CSV` is empty, Jenkins reads the default path from `.env`.

After training, Jenkins archives:

```text
artifacts/mlops/coinbase_ml_model.joblib
artifacts/mlops/coinbase_ml_model.metadata.json
artifacts/mlops/training_summary.md
artifacts/mlops/training_summary.json
```

Read `training_summary.md` before promoting. It highlights the model metrics and warns when the model underperforms the naive baseline.

### Promote a model version

Use this after reviewing MLflow metrics and Jenkins artifacts:

```text
BUILD_ALL_IMAGES=false
BUILD_MLOPS_IMAGE=false
TRAIN_MLOPS_MODEL=false
PROMOTE_MODEL=true
MODEL_VERSION=4
MODEL_ALIAS=champion
DEPLOY_BENTO=false
DEPLOY_COMPOSE=false
```

This points the MLflow alias at the chosen model version:

```text
models:/coinbase-price-lightgbm@champion
```

### Promote and deploy BentoML

Use this to update `champion` and restart only the BentoML serving container:

```text
BUILD_ALL_IMAGES=false
BUILD_MLOPS_IMAGE=false
TRAIN_MLOPS_MODEL=false
PROMOTE_MODEL=true
MODEL_VERSION=4
MODEL_ALIAS=champion
DEPLOY_BENTO=true
DEPLOY_COMPOSE=false
```

### Deploy BentoML only

Use this when `champion` is already correct and you only need to recreate serving:

```text
BUILD_ALL_IMAGES=false
BUILD_MLOPS_IMAGE=false
TRAIN_MLOPS_MODEL=false
PROMOTE_MODEL=false
DEPLOY_BENTO=true
DEPLOY_COMPOSE=false
```

Verify BentoML after deployment:

```bash
curl -s -X POST http://localhost:3001/health
curl -s -X POST http://localhost:3001/model_info
DATA=/path/to/ohlcv.csv make mlops-test-predict
```

For a real deployment, keep the MLflow registry as the source of promoted model versions. Build or deploy BentoML from a chosen alias or immutable model version, not from whichever training artifact happened to be written last.

### Push BentoML image to Artifact Registry

Use this after the local BentoML image builds successfully and Docker is authenticated to GCP Artifact Registry:

```text
BUILD_ALL_IMAGES=false
BUILD_MLOPS_IMAGE=true
PUSH_BENTO_IMAGE=true
IMAGE_TAG=
TRAIN_MLOPS_MODEL=false
PROMOTE_MODEL=false
DEPLOY_BENTO=false
DEPLOY_COMPOSE=false
```

When `IMAGE_TAG` is empty, Jenkins uses `build-${BUILD_NUMBER}-${GIT_COMMIT_SHORT}`. Jenkins archives the pushed image URI at:

```text
artifacts/mlops/bento_image_uri.txt
```

For local testing, build and push manually:

```bash
COMPOSE_PROFILES=mlops docker compose --env-file .env build bento-price-predictor
make mlops-push-bento
```

Required `.env` values:

```text
GCP_PROJECT_ID=<gcp-project-id>
GAR_LOCATION=asia-southeast1
GAR_REPOSITORY=coinbase-mlops
BENTO_IMAGE_NAME=coinbase-bento-price-predictor
```

### Deploy to GKE from Jenkins

Use this after the image has been pushed and `kubectl` access is configured through a Jenkins GCP service account credential:

```text
BUILD_ALL_IMAGES=false
BUILD_MLOPS_IMAGE=false
PUSH_BENTO_IMAGE=false
TRAIN_MLOPS_MODEL=false
PROMOTE_MODEL=false
DEPLOY_BENTO=false
DEPLOY_GKE=true
GCP_CREDENTIALS_ID=gcp-jenkins-sa-key
GKE_CLUSTER=coinbase-mlops
GKE_REGION=asia-southeast1
DEPLOY_COMPOSE=false
```

For a full image build, push, and GKE deploy run:

```text
BUILD_MLOPS_IMAGE=true
PUSH_BENTO_IMAGE=true
IMAGE_TAG=
DEPLOY_GKE=true
```

The Jenkins credential should be a `Secret file` containing a GCP service account JSON key. For a demo, grant the service account Artifact Registry write access and enough GKE permissions to fetch cluster credentials and deploy the Helm release. Later, replace the key file with Workload Identity or a keyless Jenkins agent.

## Kubernetes path

When moving to Kubernetes, keep the same boundary:

- MLflow server with Postgres backend and object storage artifact root.
- BentoML model server as a Deployment.
- Model artifact from MLflow/BentoML promoted by Jenkins.
- Prometheus scraping BentoML service metrics and health.

### Minimal GKE BentoML deploy

The first GKE step deploys only the BentoML predictor into namespace `app`. It uses the image pushed to Artifact Registry and installs the predictor with the Helm chart in `charts/bento-price-predictor`. The model artifact is packaged into the image during Docker build, so train before building when you want to deploy a fresh model.

Create or connect to a GKE cluster, then deploy:

```bash
make gke-deploy-bento
```

The deploy script runs `helm upgrade --install`. It reads the image URI from:

```text
artifacts/mlops/bento_image_uri.txt
```

or derives it from `.env`:

```text
asia-southeast1-docker.pkg.dev/${GCP_PROJECT_ID}/${GAR_REPOSITORY}/${BENTO_IMAGE_NAME}:${IMAGE_TAG}
```

Check rollout:

```bash
kubectl -n app get pods
kubectl -n app get svc
```

Test locally with port-forward:

```bash
make gke-port-forward-bento
curl -s -X POST http://localhost:3001/readyz
curl -s -X POST http://localhost:3001/health
```

Then test prediction from another terminal:

```bash
DATA=/path/to/ohlcv.csv make mlops-test-predict
```

Validate the Helm chart without a cluster:

```bash
helm lint charts/bento-price-predictor
make helm-template-bento
```

## Roadmap checklist

Use this checklist to keep the project focused on the MLOps path. Do not add the later tools until the earlier phases are working end to end.

### Phase 1: local MLOps

- [ ] Prepare an OHLCV CSV with `timestamp,open,high,low,close,volume`.
- [ ] Install local MLOps dependencies with `pip install -r mlops/requirements.txt`.
- [ ] Train the CPU LightGBM 4-hour forecast model with `DATA=/path/to/ohlcv.csv make mlops-train`.
- [ ] Confirm `artifacts/mlops/coinbase_ml_model.joblib` exists.
- [ ] Confirm `artifacts/mlops/coinbase_ml_model.metadata.json` exists.
- [ ] Create `.env` from `.env.example`.
- [ ] Start MLflow and BentoML with `make mlops-up`.
- [ ] Open MLflow at `http://localhost:5000`.
- [ ] Check BentoML readiness at `http://localhost:3001/readyz`.
- [ ] Call BentoML `/predict` with enough historical OHLCV rows.
- [ ] Compare LightGBM metrics with the naive baseline `future_return = 0`, equivalent to `future_close = current_close`.
- [ ] Record `MAE`, `RMSE`, `SMAPE`, `direction_accuracy`, and improvement versus naive.

### Phase 2: Jenkins local CI/CD

- [ ] Ensure the Jenkins agent has Docker and Docker Compose v2.
- [ ] Ensure the Jenkins user can run Docker.
- [ ] Configure a Jenkins job that pulls this repository.
- [ ] Run `bash scripts/ci_check.sh` in Jenkins.
- [ ] Build the BentoML image in Jenkins with `BUILD_MLOPS_IMAGE=true`.
- [ ] Set `TRAIN_MLOPS_MODEL=true` only when Jenkins should train the CPU model.
- [ ] Keep `MLOPS_TRAINING_CSV` empty to use the default from `.env`, or set it to override the training CSV path.
- [ ] Confirm Jenkins archives `training_summary.md` and `training_summary.json` after training.
- [ ] Promote reviewed model versions with `PROMOTE_MODEL=true`, `MODEL_VERSION=<version>`, and `MODEL_ALIAS=champion`.
- [ ] Restart BentoML serving with `DEPLOY_BENTO=true`.
- [ ] Confirm BentoML reports `model_source=models:/coinbase-price-lightgbm@champion`.

### Phase 3: GCP minimal setup

- [ ] Create a dedicated GCP project.
- [ ] Enable billing with the free trial account.
- [ ] Create a budget alert before creating compute resources.
- [ ] Choose one region, for example `asia-southeast1`.
- [ ] Enable Artifact Registry API.
- [ ] Enable Kubernetes Engine API.
- [ ] Enable IAM API.
- [ ] Enable Compute Engine API.
- [ ] Create one Artifact Registry Docker repository.
- [ ] Configure Docker authentication for Artifact Registry.
- [ ] Create a Jenkins service account.
- [ ] Grant the service account Artifact Registry write access.
- [ ] Grant the service account permission to deploy to GKE.
- [ ] Install and configure `gcloud` and `kubectl` on the Jenkins host.
- [ ] Push the BentoML image with `PUSH_BENTO_IMAGE=true`.

### Phase 4: minimal GKE deploy

- [ ] Create a small zonal or Autopilot GKE cluster.
- [ ] Do not create GPU node pools.
- [ ] Do not keep unused nodes running.
- [ ] Confirm cluster access with `kubectl get nodes`.
- [ ] Create namespaces: `app`, `mlops`, and `monitoring`.
- [ ] Add a Helm chart for the BentoML predictor.
- [ ] Build the BentoML predictor Docker image.
- [ ] Push the image to Artifact Registry.
- [ ] Deploy the BentoML predictor with `make gke-deploy-bento`.
- [ ] Check pods with `kubectl get pods -n app`.
- [ ] Test the service with `kubectl port-forward` before creating Ingress.
- [ ] Call `/readyz`.
- [ ] Call `/predict`.

### Phase 5: Jenkins deploy to GKE

- [ ] Authenticate Jenkins to GCP.
- [ ] Configure Docker authentication for Artifact Registry.
- [ ] Tag images with the Git commit SHA.
- [ ] Push the BentoML image to Artifact Registry.
- [ ] Run `helm upgrade --install` from Jenkins with `DEPLOY_GKE=true`.
- [ ] Deploy only from `main` or `master`.
- [ ] Keep deploy logs in Jenkins.
- [ ] Test rollback with `helm rollback`.

### Phase 6: MLflow on GKE

- [ ] Deploy MLflow into the `mlops` namespace.
- [ ] Start with a simple persistent volume for metadata and artifacts.
- [ ] Expose MLflow with `kubectl port-forward` first.
- [ ] Confirm training can log to the GKE MLflow server.
- [ ] Link model artifacts to MLflow runs.
- [ ] Record model version, metrics, params, and source commit.

### Phase 7: basic monitoring

- [ ] Install Prometheus.
- [ ] Install Grafana.
- [ ] Monitor pod CPU and memory.
- [ ] Monitor BentoML readiness.
- [ ] Add request count, latency, and error metrics when available.
- [ ] Create a minimal Grafana dashboard.
- [ ] Add alerts for pod down, high CPU, high memory, and unhealthy service.

### Phase 8: Terraform later

- [ ] Add Terraform for Artifact Registry.
- [ ] Add Terraform for GKE.
- [ ] Add Terraform for IAM service accounts.
- [ ] Add Terraform for budget alerts if needed.
- [ ] Run `terraform fmt`.
- [ ] Run `terraform validate`.
- [ ] Add Checkov scan for Terraform.

### Defer for now

- [ ] Do not migrate PySpark to Flink yet.
- [ ] Do not install ELK yet.
- [ ] Do not install Airflow yet.
- [ ] Do not install Trino, Hive, or Delta Lake yet.
- [ ] Do not run a multi-broker Kafka production cluster on GKE yet.
- [ ] Do not use GPU.
- [ ] Do not expose public LoadBalancers until they are needed.
- [ ] Do not run the GKE cluster 24/7 during the free trial unless you are actively using it.
