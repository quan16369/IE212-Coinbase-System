# Storage Module for Crypto Pipeline
# This module creates S3 buckets and EFS file systems

# S3 Bucket for ML Artifacts and Data Lake
resource "aws_s3_bucket" "ml_artifacts" {
  bucket = var.ml_artifacts_bucket_name

  tags = merge(
    var.tags,
    {
      Name   = var.ml_artifacts_bucket_name
      Module = "storage"
      Purpose = "ml-artifacts"
    }
  )
}

resource "aws_s3_bucket_versioning" "ml_artifacts" {
  bucket = aws_s3_bucket.ml_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ml_artifacts" {
  bucket = aws_s3_bucket.ml_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ml_artifacts" {
  bucket = aws_s3_bucket.ml_artifacts.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
  }

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# S3 Bucket for Data Lake
resource "aws_s3_bucket" "data_lake" {
  bucket = var.data_lake_bucket_name

  tags = merge(
    var.tags,
    {
      Name    = var.data_lake_bucket_name
      Module  = "storage"
      Purpose = "data-lake"
    }
  )
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# EFS File System for Model Storage
resource "aws_efs_file_system" "models" {
  count = var.enable_efs ? 1 : 0

  creation_token = "${var.cluster_name}-models"
  encrypted      = true

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = merge(
    var.tags,
    {
      Name    = "${var.cluster_name}-models"
      Module  = "storage"
      Purpose = "model-storage"
    }
  )
}

resource "aws_efs_mount_target" "models" {
  for_each = var.enable_efs ? toset(var.private_subnets) : []

  file_system_id  = aws_efs_file_system.models[0].id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs[0].id]
}

# Security Group for EFS
resource "aws_security_group" "efs" {
  count = var.enable_efs ? 1 : 0

  name        = "${var.cluster_name}-efs"
  description = "Security group for EFS mount targets"
  vpc_id      = var.vpc_id

  ingress {
    description     = "NFS from EKS nodes"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [var.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name   = "${var.cluster_name}-efs"
      Module = "storage"
    }
  )
}

# ECR Repositories
resource "aws_ecr_repository" "repositories" {
  for_each = toset(var.ecr_repositories)

  name                 = "${var.cluster_name}-${each.value}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    var.tags,
    {
      Name    = "${var.cluster_name}-${each.value}"
      Module  = "storage"
      Purpose = "container-registry"
    }
  )
}

resource "aws_ecr_lifecycle_policy" "repositories" {
  for_each = toset(var.ecr_repositories)

  repository = aws_ecr_repository.repositories[each.value].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus     = "any"
        countType     = "imageCountMoreThan"
        countNumber   = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
