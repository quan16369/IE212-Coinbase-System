# IAM Module for Crypto Pipeline
# This module creates IAM roles and policies for the infrastructure

# IAM Role for S3 Access (IRSA)
module "s3_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-s3-access"

  role_policy_arns = {
    s3_policy = aws_iam_policy.s3_access.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = var.s3_service_accounts
    }
  }

  tags = var.tags
}

# IAM Policy for S3 Access
resource "aws_iam_policy" "s3_access" {
  name        = "${var.cluster_name}-s3-access"
  description = "Policy for S3 bucket access from EKS pods"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = concat(
          [for bucket in var.s3_bucket_arns : bucket],
          [for bucket in var.s3_bucket_arns : "${bucket}/*"]
        )
      }
    ]
  })

  tags = var.tags
}

# IAM Role for Cassandra Access
module "cassandra_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  count = var.enable_cassandra_irsa ? 1 : 0

  role_name = "${var.cluster_name}-cassandra-access"

  role_policy_arns = {
    cassandra_policy = aws_iam_policy.cassandra_access[0].arn
  }

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = var.cassandra_service_accounts
    }
  }

  tags = var.tags
}

# IAM Policy for Cassandra Access
resource "aws_iam_policy" "cassandra_access" {
  count = var.enable_cassandra_irsa ? 1 : 0

  name        = "${var.cluster_name}-cassandra-access"
  description = "Policy for Cassandra backup to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${var.backup_bucket_arn}",
          "${var.backup_bucket_arn}/*"
        ]
      }
    ]
  })

  tags = var.tags
}

# IAM Role for Load Balancer Controller
module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  count = var.enable_alb_controller ? 1 : 0

  role_name = "${var.cluster_name}-alb-controller"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = var.tags
}
