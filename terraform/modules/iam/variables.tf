variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  type        = string
}

variable "s3_bucket_arns" {
  description = "List of S3 bucket ARNs to grant access to"
  type        = list(string)
}

variable "s3_service_accounts" {
  description = "List of service accounts that need S3 access"
  type        = list(string)
  default     = [
    "crypto-pipeline:producer",
    "crypto-pipeline:processor",
    "crypto-mlops:mlflow"
  ]
}

variable "enable_cassandra_irsa" {
  description = "Enable IRSA for Cassandra"
  type        = bool
  default     = false
}

variable "cassandra_service_accounts" {
  description = "List of service accounts that need Cassandra backup access"
  type        = list(string)
  default     = ["crypto-pipeline:cassandra"]
}

variable "backup_bucket_arn" {
  description = "ARN of backup S3 bucket"
  type        = string
  default     = ""
}

variable "enable_alb_controller" {
  description = "Enable IRSA for ALB controller"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
