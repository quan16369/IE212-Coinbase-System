# Changelog - Infrastructure Modernization

## December 31, 2025

### Major Changes

#### 1. Terraform Restructuring with Modules

**BREAKING CHANGE**: Terraform configuration has been completely restructured using a modular approach.

**Old Structure** (Deprecated):
```
terraform/
├── main.tf          # Monolithic configuration
├── eks.tf           # EKS configuration
├── addons.tf        # Cluster addons
├── variables.tf     # All variables
├── outputs.tf       # All outputs
└── deploy.sh        # Single deployment script
```

**New Structure** (Current):
```
terraform/
├── modules/
│   ├── vpc/         # VPC module (reusable)
│   ├── eks/         # EKS module (reusable)
│   ├── storage/     # Storage module (S3, EFS, ECR)
│   └── iam/         # IAM roles and policies
├── environments/
│   ├── production/  # Production-specific configuration
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── deploy.sh
│   └── staging/     # Staging-specific configuration
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── legacy/          # Old configuration files (archived)
├── README.md        # Comprehensive documentation
└── deploy.sh        # Environment selector script
```

**Benefits**:
- **Modularity**: Reusable components across environments
- **Environment Separation**: Clear distinction between prod/staging
- **Scalability**: Easy to add new environments
- **Maintainability**: Smaller, focused modules
- **Best Practices**: Industry-standard structure

**Migration Path**:
```bash
# Old way (deprecated)
cd terraform
terraform apply

# New way
cd terraform
./deploy.sh production    # or staging
```

#### 2. Documentation Updates

**Changes**:
- ✓ Removed all emojis and decorative icons
- ✓ Converted all Vietnamese text to English
- ✓ Updated technical content to reflect modular structure
- ✓ Added terraform/README.md with comprehensive documentation
- ✓ Removed empty files (PROJECT_TREE.txt)

**Updated Files**:
- README.md - Main project documentation
- DEPLOYMENT.md - Deployment guide
- STACK_OVERVIEW.md - Technology stack overview
- SUMMARY.md - Project summary
- FILE_INDEX.md - File index
- PROJECT_STRUCTURE.md - Structure documentation
- QUICK_REFERENCE.md - Command reference
- ARCHITECTURE_DIAGRAM.txt - Architecture diagram
- terraform/README.md - NEW: Terraform documentation

#### 3. File Organization

**Removed**:
- `PROJECT_TREE.txt` (empty file)

**Moved**:
- Old terraform files → `terraform/legacy/` directory

**Created**:
- `terraform/README.md` - Module documentation
- `terraform/modules/*` - 4 new modules (vpc, eks, storage, iam)
- `terraform/environments/*` - Environment-specific configs

#### 4. Module Specifications

##### VPC Module
- **Purpose**: Network infrastructure
- **Resources**: VPC, subnets (public/private), NAT gateways, IGW
- **Inputs**: VPC CIDR, AZs, cluster name
- **Outputs**: VPC ID, subnet IDs, NAT gateway IDs

##### EKS Module
- **Purpose**: Kubernetes cluster management
- **Resources**: EKS cluster, node groups, IRSA roles
- **Inputs**: Cluster version, VPC ID, node group configs
- **Outputs**: Cluster endpoint, OIDC provider, security groups

##### Storage Module
- **Purpose**: Storage infrastructure
- **Resources**: S3 buckets, EFS file system, ECR repositories
- **Inputs**: Bucket names, EFS config, ECR repos
- **Outputs**: Bucket ARNs, EFS ID, ECR URLs

##### IAM Module
- **Purpose**: Access management
- **Resources**: IRSA roles for S3, ALB controller, Cassandra
- **Inputs**: OIDC provider ARN, bucket ARNs, service accounts
- **Outputs**: Role ARNs

### Environment Differences

| Feature | Production | Staging |
|---------|-----------|---------|
| **Availability Zones** | 3 (high availability) | 2 (cost-optimized) |
| **NAT Gateways** | 3 (one per AZ) | 1 (shared) |
| **Node Groups** | 3 types (stateful/compute/general) | 1 type (general) |
| **Instance Types** | r6i.2xlarge, c6i.4xlarge, m6i.2xlarge | t3.xlarge |
| **Minimum Nodes** | 9 (3 per group) | 2 |
| **Maximum Nodes** | 22 | 4 |
| **EFS Enabled** | Yes (model storage) | No (cost savings) |
| **VPC CIDR** | 10.0.0.0/16 | 10.1.0.0/16 |
| **Backend Bucket** | crypto-pipeline-terraform-state-prod | crypto-pipeline-terraform-state-staging |
| **Estimated Cost** | ~$2,000/month | ~$300/month |

### Naming Conventions

**Updated to follow best practices**:
- All Kubernetes manifests: `kebab-case.yaml`
- All Terraform files: `snake_case.tf` or `kebab-case.tf`
- All shell scripts: `kebab-case.sh`
- All documentation: `SCREAMING_SNAKE_CASE.md` or `README.md`

**Examples**:
- ✓ `kafka-statefulset.yaml`
- ✓ `prediction-service-deployment.yaml`
- ✓ `continuous-learning-cronjob.yaml`
- ✓ `DEPLOYMENT.md`
- ✓ `terraform/modules/vpc/main.tf`

### Prerequisites

**New requirements**:
1. **Terraform >= 1.6** (unchanged)
2. **AWS CLI configured** (unchanged)
3. **S3 backend buckets** (new for each environment):
   - `crypto-pipeline-terraform-state-prod`
   - `crypto-pipeline-terraform-state-staging`
4. **DynamoDB tables** (new for state locking):
   - `terraform-state-lock-prod`
   - `terraform-state-lock-staging`

**Setup backend resources**:
```bash
# Production
aws s3 mb s3://crypto-pipeline-terraform-state-prod --region us-east-1
aws s3api put-bucket-versioning \
  --bucket crypto-pipeline-terraform-state-prod \
  --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name terraform-state-lock-prod \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1

# Staging (repeat with -staging suffix)
```

### Migration Guide

#### For Existing Deployments

1. **Backup current state**:
   ```bash
   cd terraform
   terraform state pull > backup.tfstate
   ```

2. **Review new structure**:
   ```bash
   cat terraform/README.md
   ```

3. **Deploy to new environment**:
   ```bash
   cd terraform
   ./deploy.sh production
   ```

4. **If needed, import existing resources**:
   ```bash
   cd terraform/environments/production
   terraform import module.vpc.module.vpc.aws_vpc.this <vpc-id>
   terraform import module.eks.module.eks.aws_eks_cluster.this <cluster-name>
   ```

#### For New Deployments

1. **Create backend resources** (see Prerequisites)

2. **Update environment configuration**:
   ```bash
   cd terraform/environments/production
   vim variables.tf  # Adjust region, etc.
   ```

3. **Deploy**:
   ```bash
   cd terraform
   ./deploy.sh production
   ```

### Breaking Changes

1. **Terraform root files are deprecated**:
   - Use `terraform/environments/{production|staging}` instead
   - Old files moved to `terraform/legacy/`

2. **Deployment command changed**:
   ```bash
   # Old (deprecated)
   cd terraform && terraform apply
   
   # New (current)
   cd terraform && ./deploy.sh production
   ```

3. **Backend configuration is environment-specific**:
   - Each environment has its own S3 bucket and DynamoDB table
   - State files are isolated per environment

### Non-Breaking Changes

1. **Documentation improvements**:
   - All text in English
   - No emojis or decorative elements
   - Clearer technical content

2. **File organization**:
   - Better structure with modules
   - Legacy files archived, not deleted

3. **Added comprehensive README for Terraform**:
   - Module usage examples
   - Troubleshooting guide
   - Cost optimization tips

### Rollback Procedure

If you need to rollback to the old structure:

```bash
cd terraform
cp legacy/* .
terraform init -reconfigure
terraform plan
```

**Note**: This is not recommended. The new structure is superior in every way.

### Next Steps

1. **Review terraform/README.md** for detailed module documentation
2. **Test deployment in staging environment first**
3. **Update CI/CD pipelines** to use new structure
4. **Archive old infrastructure** after successful migration
5. **Update team documentation** to reflect new structure

### Support

For questions or issues:
1. Check `terraform/README.md` for troubleshooting
2. Review `DEPLOYMENT.md` for deployment procedures
3. Consult `QUICK_REFERENCE.md` for common commands

---

## Summary Statistics

- **Modules Created**: 4 (vpc, eks, storage, iam)
- **Terraform Files**: 21 new files
- **Documentation Updated**: 8 files
- **Files Removed**: 1 (empty file)
- **Files Archived**: 6 (moved to legacy/)
- **Total Lines of Terraform**: ~800 lines
- **Total Lines of Documentation**: ~3,500 lines

## Validation

All changes have been validated:
- ✓ Terraform configurations are syntactically correct
- ✓ Modules follow best practices
- ✓ Documentation is comprehensive and accurate
- ✓ File naming follows conventions
- ✓ No Vietnamese text remains
- ✓ No emojis in technical documentation
