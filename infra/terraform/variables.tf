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
  description = "GKE Autopilot cluster name."
  type        = string
  default     = "coinbase-mlops"
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

variable "labels" {
  description = "Labels applied to supported resources."
  type        = map(string)
  default = {
    app       = "coinbase-streaming"
    component = "mlops"
  }
}
