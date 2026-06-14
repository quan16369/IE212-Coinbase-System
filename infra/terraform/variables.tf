variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region for regional resources."
  type        = string
  default     = "asia-southeast1"
}

variable "artifact_repository_id" {
  description = "Artifact Registry Docker repository ID."
  type        = string
  default     = "coinbase-mlops"
}

variable "gke_cluster_name" {
  description = "GKE Standard cluster name."
  type        = string
  default     = "coinbase-mlops"
}

variable "gke_node_zones" {
  description = "Zones used by the regional GKE Standard node pool."
  type        = list(string)
  default = [
    "asia-southeast1-a",
    "asia-southeast1-b",
  ]
}

variable "gke_machine_type" {
  description = "Machine type for application nodes."
  type        = string
  default     = "e2-standard-4"
}

variable "gke_node_disk_size_gb" {
  description = "Boot disk size for each GKE node."
  type        = number
  default     = 50
}

variable "gke_min_nodes_per_zone" {
  description = "Minimum nodes per configured zone."
  type        = number
  default     = 1
}

variable "gke_max_nodes_per_zone" {
  description = "Maximum nodes per configured zone."
  type        = number
  default     = 2
}

variable "gke_deletion_protection" {
  description = "Protect the cluster from accidental deletion. Keep false for the daily demo teardown workflow."
  type        = bool
  default     = false
}

variable "jenkins_service_account_id" {
  description = "Jenkins deployer service account ID."
  type        = string
  default     = "jenkins-deployer"
}

variable "create_jenkins_key" {
  description = "Create a Jenkins service account JSON key. Use only for local demos; prefer keyless auth for production."
  type        = bool
  default     = false
}

variable "raw_data_bucket_name" {
  description = "Optional globally unique GCS bucket name for raw Kafka events."
  type        = string
  default     = null
}

variable "raw_data_retention_days" {
  description = "Days to retain raw Parquet objects."
  type        = number
  default     = 30
}

variable "raw_data_bucket_force_destroy" {
  description = "Delete raw objects with the bucket during terraform destroy. Suitable for this demo environment."
  type        = bool
  default     = true
}

variable "raw_data_sink_service_account_id" {
  description = "GCP service account used by the GKE raw-data sink."
  type        = string
  default     = "raw-data-sink"
}

variable "raw_data_replay_service_account_id" {
  description = "GCP service account used by the GKE raw-data replay workflow."
  type        = string
  default     = "raw-data-replay"
}

variable "labels" {
  description = "Labels applied to supported resources."
  type        = map(string)
  default = {
    app       = "coinbase-streaming"
    component = "mlops"
  }
}
