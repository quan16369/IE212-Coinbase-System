locals {
  required_services = toset([
    "artifactregistry.googleapis.com",
    "container.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
  ])

  jenkins_roles = toset([
    "roles/artifactregistry.writer",
    "roles/container.admin",
  ])
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
