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

  remove_default_node_pool = true
  initial_node_count       = 1
  node_locations           = var.gke_node_zones

  networking_mode   = "VPC_NATIVE"
  datapath_provider = "ADVANCED_DATAPATH"

  ip_allocation_policy {}

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  enable_shielded_nodes = true
  deletion_protection   = var.gke_deletion_protection

  release_channel {
    channel = "REGULAR"
  }

  maintenance_policy {
    recurring_window {
      start_time = "2026-01-04T18:00:00Z"
      end_time   = "2026-01-04T22:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SU"
    }
  }

  resource_labels = var.labels

  depends_on = [
    google_project_service.required,
  ]
}

resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = "coinbase-gke-nodes"
  display_name = "Coinbase GKE Standard node service account"
}

locals {
  gke_node_roles = toset([
    "roles/artifactregistry.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
  ])
}

resource "google_project_iam_member" "gke_nodes" {
  for_each = local.gke_node_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_container_node_pool" "application" {
  name       = "application"
  location   = var.region
  project    = var.project_id
  cluster    = google_container_cluster.mlops.name
  node_count = var.gke_min_nodes_per_zone

  node_locations = var.gke_node_zones

  autoscaling {
    min_node_count = var.gke_min_nodes_per_zone
    max_node_count = var.gke_max_nodes_per_zone
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = var.gke_machine_type
    disk_type    = "pd-balanced"
    disk_size_gb = var.gke_node_disk_size_gb
    image_type   = "COS_CONTAINERD"

    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      workload = "application"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  depends_on = [
    google_project_iam_member.gke_nodes,
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
