output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = module.eks.node_security_group_id
}

output "ebs_csi_role_arn" {
  description = "ARN of IAM role for EBS CSI driver"
  value       = var.enable_ebs_csi ? module.ebs_csi_irsa[0].iam_role_arn : null
}

output "efs_csi_role_arn" {
  description = "ARN of IAM role for EFS CSI driver"
  value       = var.enable_efs ? module.efs_csi_irsa[0].iam_role_arn : null
}

output "cluster_autoscaler_role_arn" {
  description = "ARN of IAM role for Cluster Autoscaler"
  value       = var.enable_cluster_autoscaler ? module.cluster_autoscaler_irsa[0].iam_role_arn : null
}
