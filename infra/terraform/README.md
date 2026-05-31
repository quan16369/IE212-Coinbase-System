# Terraform GCP Base Infrastructure

This Terraform module creates the minimal GCP resources used by the Jenkins to GKE BentoML flow:

- required project APIs
- Artifact Registry Docker repository
- GKE Autopilot cluster
- Jenkins deployer service account
- IAM bindings for image push and GKE deploy

It intentionally does not create monitoring, ingress, databases, or MLflow storage yet. Add those as separate steps after the base deployment is stable.

## Usage

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
gcloud auth application-default login
terraform init
terraform plan
terraform apply
```

If you already created the Artifact Registry repository, GKE cluster, or Jenkins service account manually, do not run `terraform apply` blindly against the same names. Either delete the manual demo resources first, or import them into Terraform state.

Example imports for this project:

```bash
terraform import google_artifact_registry_repository.mlops \
  projects/<project-id>/locations/asia-southeast1/repositories/coinbase-mlops

terraform import google_container_cluster.mlops \
  projects/<project-id>/locations/asia-southeast1/clusters/coinbase-mlops

terraform import google_service_account.jenkins_deployer \
  projects/<project-id>/serviceAccounts/jenkins-deployer@<project-id>.iam.gserviceaccount.com
```

After apply:

```bash
gcloud container clusters get-credentials coinbase-mlops --region=asia-southeast1
gcloud auth configure-docker asia-southeast1-docker.pkg.dev
```

## Jenkins Credential

For local demos, set `create_jenkins_key = true`, apply, then decode the sensitive output into a JSON key file:

```bash
terraform output -raw jenkins_service_account_key_json_base64 | base64 -d > jenkins-deployer.json
```

Upload that file to Jenkins as a `Secret file` credential with ID:

```text
gcp-jenkins-sa-key
```

For production, keep `create_jenkins_key = false` and use keyless authentication instead.

## Cleanup

To stop GKE charges:

```bash
terraform destroy
```

From the repository root:

```bash
make terraform-destroy
```

This also removes the Terraform-managed Artifact Registry repository and Jenkins deployer service account. Export or keep any images you still need before destroying the repository.
