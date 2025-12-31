variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "ml_artifacts_bucket_name" {
  description = "Name of S3 bucket for ML artifacts"
  type        = string
}

variable "data_lake_bucket_name" {
  description = "Name of S3 bucket for data lake"
  type        = string
}

variable "enable_efs" {
  description = "Enable EFS file system"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnets" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "node_security_group_id" {
  description = "Security group ID of EKS nodes"
  type        = string
}

variable "ecr_repositories" {
  description = "List of ECR repository names to create"
  type        = list(string)
  default     = ["producer", "processor", "prediction-service"]
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
