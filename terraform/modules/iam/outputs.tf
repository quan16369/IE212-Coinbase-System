output "s3_role_arn" {
  description = "ARN of IAM role for S3 access"
  value       = module.s3_irsa.iam_role_arn
}

output "cassandra_role_arn" {
  description = "ARN of IAM role for Cassandra backup"
  value       = var.enable_cassandra_irsa ? module.cassandra_irsa[0].iam_role_arn : null
}

output "alb_controller_role_arn" {
  description = "ARN of IAM role for ALB controller"
  value       = var.enable_alb_controller ? module.alb_controller_irsa[0].iam_role_arn : null
}
