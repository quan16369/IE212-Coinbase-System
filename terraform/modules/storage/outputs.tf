output "ml_artifacts_bucket_id" {
  description = "ID of S3 bucket for ML artifacts"
  value       = aws_s3_bucket.ml_artifacts.id
}

output "ml_artifacts_bucket_arn" {
  description = "ARN of S3 bucket for ML artifacts"
  value       = aws_s3_bucket.ml_artifacts.arn
}

output "data_lake_bucket_id" {
  description = "ID of S3 bucket for data lake"
  value       = aws_s3_bucket.data_lake.id
}

output "data_lake_bucket_arn" {
  description = "ARN of S3 bucket for data lake"
  value       = aws_s3_bucket.data_lake.arn
}

output "efs_id" {
  description = "ID of EFS file system"
  value       = var.enable_efs ? aws_efs_file_system.models[0].id : null
}

output "efs_dns_name" {
  description = "DNS name of EFS file system"
  value       = var.enable_efs ? aws_efs_file_system.models[0].dns_name : null
}

output "ecr_repository_urls" {
  description = "Map of ECR repository URLs"
  value       = { for k, v in aws_ecr_repository.repositories : k => v.repository_url }
}
