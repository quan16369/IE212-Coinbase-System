locals {
  required_services = toset([
    "artifactregistry.googleapis.com",
    "container.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "storage.googleapis.com",
  ])

  jenkins_roles = toset([
    "roles/artifactregistry.writer",
    "roles/container.admin",
  ])
}

resource "google_storage_bucket" "raw_data" {
  name                        = coalesce(var.raw_data_bucket_name, "${var.project_id}-coinbase-raw-data")
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.raw_data_bucket_force_destroy
  labels                      = var.labels

  soft_delete_policy {
    retention_duration_seconds = 0
  }

  lifecycle_rule {
    condition {
      age = var.raw_data_retention_days
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_service_account" "raw_data_sink" {
  project      = var.project_id
  account_id   = var.raw_data_sink_service_account_id
  display_name = "Kafka raw-data GCS sink"
}

resource "google_storage_bucket_iam_member" "raw_data_sink_writer" {
  bucket = google_storage_bucket.raw_data.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.raw_data_sink.email}"
}

resource "google_service_account_iam_member" "raw_data_sink_workload_identity" {
  service_account_id = google_service_account.raw_data_sink.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[data-streaming/streaming-platform-raw-data-sink]"
}

resource "google_service_account" "raw_data_replay" {
  project      = var.project_id
  account_id   = var.raw_data_replay_service_account_id
  display_name = "Kafka raw-data GCS replay"
}

resource "google_storage_bucket_iam_member" "raw_data_replay_user" {
  bucket = google_storage_bucket.raw_data.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.raw_data_replay.email}"
}

resource "google_service_account_iam_member" "raw_data_replay_workload_identity" {
  service_account_id = google_service_account.raw_data_replay.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[data-streaming/streaming-platform-raw-data-replay]"
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "mlops" {
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_repository_id
  description   = "Coinbase MLOps Docker images"
  format        = "DOCKER"
  labels        = var.labels

  depends_on = [
    google_project_service.required,
  ]
}

resource "google_container_cluster" "mlops" {
  name     = var.gke_cluster_name
  location = var.region
  project  = var.project_id

  enable_autopilot = true

  release_channel {
    channel = "REGULAR"
  }

  resource_labels = var.labels

  deletion_protection = false

  depends_on = [
    google_project_service.required,
  ]
}

resource "google_service_account" "jenkins_deployer" {
  project      = var.project_id
  account_id   = var.jenkins_service_account_id
  display_name = "Jenkins GKE deployer"
}

resource "google_project_iam_member" "jenkins_deployer" {
  for_each = local.jenkins_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.jenkins_deployer.email}"
}

resource "google_service_account_key" "jenkins_deployer" {
  count = var.create_jenkins_key ? 1 : 0

  service_account_id = google_service_account.jenkins_deployer.name
}
