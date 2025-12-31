output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "ml_artifacts_bucket" {
  description = "S3 bucket for ML artifacts"
  value       = module.storage.ml_artifacts_bucket_id
}

output "data_lake_bucket" {
  description = "S3 bucket for data lake"
  value       = module.storage.data_lake_bucket_id
}

output "efs_id" {
  description = "EFS file system ID"
  value       = module.storage.efs_id
}

output "ecr_repositories" {
  description = "ECR repository URLs"
  value       = module.storage.ecr_repository_urls
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
