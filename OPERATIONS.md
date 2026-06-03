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
- `CI Checks`: validates Compose, checks Python syntax, and runs Go tests when Go is installed.
- `Build Images`: builds all Docker images.
- `Train CPU ML Model`: trains the LightGBM model, logs to MLflow, and archives model artifacts when enabled.
- `Build BentoML Image`: builds only the BentoML predictor image when enabled.
- `Trivy Image Scan`: scans the BentoML Docker image for HIGH/CRITICAL vulnerabilities when enabled.
- `Generate Image SBOM`: creates a CycloneDX SBOM for the BentoML Docker image when enabled.
- `Push BentoML Image`: tags and pushes the BentoML image to GCP Artifact Registry when enabled.
- `Promote Model`: points an MLflow model alias, usually `champion`, at a reviewed model version.
- `Deploy BentoML`: recreates only the BentoML predictor service.
- `Deploy`: runs `scripts/deploy_compose.sh` only on `main` or `master`.

Optional MLOps stages are controlled by Jenkins build parameters:

- `BUILD_ALL_IMAGES=true` builds every Docker Compose image.
- `BUILD_MLOPS_IMAGE=true` builds the BentoML service image.
- `RUN_TRIVY_IMAGE_SCAN=true` scans the built BentoML image with Trivy.
- `TRIVY_FAIL_ON_FINDINGS=true` makes HIGH/CRITICAL Trivy findings fail the build. Keep it `false` while establishing the baseline.
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
RUN_TRIVY_IMAGE_SCAN=true
TRIVY_FAIL_ON_FINDINGS=false
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

## SonarQube

SonarQube is optional and runs locally with the CI profile:

```bash
COMPOSE_PROFILES=ci docker compose --env-file .env up -d sonarqube
```

Open `http://localhost:${SONARQUBE_PORT:-9002}`, log in with `admin/admin`, change the password, create a local project, and create a token.

Run a scan from your machine:

```bash
SONAR_TOKEN=your-token make sonar-scan
```

In Jenkins, add the token as a Secret text credential with ID `sonarqube-token`, then run the pipeline with `RUN_SONARQUBE_SCAN=true`. Jenkins uses `SONAR_HOST_URL` from `.env` unless the `SONARQUBE_URL` parameter is set.

The project Jenkins image installs Checkov, so Jenkins CI runs this scan as part of `scripts/ci_check.sh`.

## Image vulnerability scan

Run Trivy against the local BentoML image after building it:

```bash
COMPOSE_PROFILES=mlops docker compose --env-file .env build bento-price-predictor
make trivy-image-scan
```

By default the script reports HIGH and CRITICAL findings without failing:

```text
TRIVY_EXIT_CODE=0
```

To turn it into a blocking gate:

```bash
TRIVY_EXIT_CODE=1 make trivy-image-scan
```

In Jenkins, use:

```text
RUN_TRIVY_IMAGE_SCAN=true
TRIVY_FAIL_ON_FINDINGS=false
TRIVY_SEVERITY=HIGH,CRITICAL
```

After the baseline is clean, set `TRIVY_FAIL_ON_FINDINGS=true`.

## Image SBOM

Generate a CycloneDX SBOM for the local BentoML image:

```bash
COMPOSE_PROFILES=mlops docker compose --env-file .env build bento-price-predictor
make image-sbom
```

The SBOM lists the OS and application packages included in the image. Archive it with every pushed image so a future vulnerability advisory can be mapped back to the exact deployed artifact.

In Jenkins, use:

```text
GENERATE_IMAGE_SBOM=true
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

Remove the monitoring stack when the demo is done:

```bash
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
RUN_TRIVY_IMAGE_SCAN=true
TRIVY_FAIL_ON_FINDINGS=false
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
