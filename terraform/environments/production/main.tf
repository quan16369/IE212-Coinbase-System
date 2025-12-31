# Production Environment Configuration
terraform {
  required_version = ">= 1.6"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }

  backend "s3" {
    bucket         = "crypto-pipeline-terraform-state-prod"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock-prod"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "production"
      Project     = "crypto-pipeline"
      ManagedBy   = "terraform"
    }
  }
}

locals {
  cluster_name = "crypto-pipeline-prod"
  environment  = "production"
  
  common_tags = {
    Environment = local.environment
    Project     = "crypto-pipeline"
    ManagedBy   = "terraform"
  }
}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"

  vpc_name           = "${local.cluster_name}-vpc"
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  cluster_name       = local.cluster_name
  
  enable_nat_gateway = true
  single_nat_gateway = false

  tags = local.common_tags
}

# EKS Module
module "eks" {
  source = "../../modules/eks"

  cluster_name    = local.cluster_name
  cluster_version = "1.28"
  
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
  
  enable_ebs_csi            = true
  enable_efs                = true
  enable_cluster_autoscaler = true
  ebs_csi_role_arn          = null

  node_groups = {
    stateful = {
      instance_types = ["r6i.2xlarge"]
      min_size       = 3
      max_size       = 6
      desired_size   = 3
      disk_size      = 200
      taints = [{
        key    = "stateful"
        value  = "true"
        effect = "NoSchedule"
      }]
      tags = {
        "k8s.io/cluster-autoscaler/enabled"                      = "true"
        "k8s.io/cluster-autoscaler/${local.cluster_name}"        = "owned"
        "k8s.io/cluster-autoscaler/node-template/label/role"    = "stateful"
      }
    }
    
    compute = {
      instance_types = ["c6i.4xlarge"]
      min_size       = 3
      max_size       = 6
      desired_size   = 3
      disk_size      = 100
      tags = {
        "k8s.io/cluster-autoscaler/enabled"                   = "true"
        "k8s.io/cluster-autoscaler/${local.cluster_name}"     = "owned"
        "k8s.io/cluster-autoscaler/node-template/label/role" = "compute"
      }
    }
    
    general = {
      instance_types = ["m6i.2xlarge"]
      min_size       = 3
      max_size       = 10
      desired_size   = 3
      disk_size      = 100
      tags = {
        "k8s.io/cluster-autoscaler/enabled"                   = "true"
        "k8s.io/cluster-autoscaler/${local.cluster_name}"     = "owned"
        "k8s.io/cluster-autoscaler/node-template/label/role" = "general"
      }
    }
  }

  tags = local.common_tags
}

# Storage Module
module "storage" {
  source = "../../modules/storage"

  cluster_name = local.cluster_name
  
  ml_artifacts_bucket_name = "${local.cluster_name}-ml-artifacts"
  data_lake_bucket_name    = "${local.cluster_name}-data-lake"
  
  enable_efs = true
  
  vpc_id                 = module.vpc.vpc_id
  private_subnets        = module.vpc.private_subnets
  node_security_group_id = module.eks.node_security_group_id
  
  ecr_repositories = ["producer", "processor", "prediction-service", "go-consumer"]

  tags = local.common_tags
}

# IAM Module
module "iam" {
  source = "../../modules/iam"

  cluster_name = local.cluster_name
  
  oidc_provider_arn = module.eks.oidc_provider_arn
  
  s3_bucket_arns = [
    module.storage.ml_artifacts_bucket_arn,
    module.storage.data_lake_bucket_arn
  ]
  
  enable_cassandra_irsa   = false
  enable_alb_controller   = true

  tags = local.common_tags
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}
