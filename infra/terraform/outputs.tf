output "artifact_registry_repository" {
  description = "Artifact Registry repository resource name."
  value       = google_artifact_registry_repository.mlops.name
}

output "artifact_registry_host" {
  description = "Artifact Registry Docker registry host."
  value       = "${var.region}-docker.pkg.dev"
}

output "bento_image_repository" {
  description = "Base Docker image repository for the BentoML predictor."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repository_id}/coinbase-bento-price-predictor"
}

output "gke_cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.mlops.name
}

output "gke_region" {
  description = "GKE cluster region."
  value       = var.region
}

output "jenkins_service_account_email" {
  description = "Jenkins deployer service account email."
  value       = google_service_account.jenkins_deployer.email
}

output "jenkins_service_account_key_json_base64" {
  description = "Base64-encoded Jenkins service account key JSON, only populated when create_jenkins_key=true."
  value       = try(google_service_account_key.jenkins_deployer[0].private_key, null)
  sensitive   = true
}

output "raw_data_bucket_name" {
  description = "GCS bucket receiving raw Kafka events as Parquet."
  value       = google_storage_bucket.raw_data.name
}

output "raw_data_sink_service_account_email" {
  description = "Workload Identity service account for the raw-data sink."
  value       = google_service_account.raw_data_sink.email
}

output "raw_data_replay_service_account_email" {
  description = "Workload Identity service account for the raw-data replay workflow."
  value       = google_service_account.raw_data_replay.email
}
