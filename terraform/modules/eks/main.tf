# EKS Module for Crypto Pipeline
# This module creates an EKS cluster with managed node groups

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnets

  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = var.cluster_endpoint_private_access

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent              = var.enable_ebs_csi
      service_account_role_arn = var.ebs_csi_role_arn
    }
    aws-efs-csi-driver = {
      most_recent = var.enable_efs
    }
  }

  eks_managed_node_groups = {
    for name, config in var.node_groups : name => {
      name           = "${var.cluster_name}-${name}"
      instance_types = config.instance_types
      
      min_size     = config.min_size
      max_size     = config.max_size
      desired_size = config.desired_size
      
      disk_size = config.disk_size
      
      labels = {
        role = name
      }
      
      taints = lookup(config, "taints", [])
      
      tags = merge(
        var.tags,
        lookup(config, "tags", {})
      )
    }
  }

  manage_aws_auth_configmap = true

  tags = merge(
    var.tags,
    {
      Module = "eks"
    }
  )
}

# IRSA for EBS CSI Driver
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  count = var.enable_ebs_csi ? 1 : 0

  role_name = "${var.cluster_name}-ebs-csi-driver"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}

# IRSA for EFS CSI Driver
module "efs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  count = var.enable_efs ? 1 : 0

  role_name = "${var.cluster_name}-efs-csi-driver"

  attach_efs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:efs-csi-controller-sa"]
    }
  }

  tags = var.tags
}

# IRSA for Cluster Autoscaler
module "cluster_autoscaler_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  count = var.enable_cluster_autoscaler ? 1 : 0

  role_name = "${var.cluster_name}-cluster-autoscaler"

  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [var.cluster_name]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }

  tags = var.tags
}
