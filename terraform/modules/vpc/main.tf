# VPC Module for Crypto Pipeline
# This module creates a VPC with public and private subnets across multiple AZs

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = [for k, v in var.availability_zones : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in var.availability_zones : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                 = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"        = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = merge(
    var.tags,
    {
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
      Module = "vpc"
    }
  )
}
