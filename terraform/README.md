# Terraform Infrastructure

This directory contains Terraform configurations for deploying the Crypto Pipeline infrastructure on AWS using a modular structure.

## Directory Structure

```
terraform/
├── modules/                    # Reusable Terraform modules
│   ├── vpc/                   # VPC configuration
│   ├── eks/                   # EKS cluster configuration
│   ├── storage/               # S3, EFS, ECR configuration
│   └── iam/                   # IAM roles and policies
├── environments/              # Environment-specific configurations
│   ├── dev/                  # Development environment (minimal K8s)
│   ├── staging/              # Staging environment
│   └── production/           # Production environment
└── legacy/                   # Archived old configuration files
```

## Module Overview

### VPC Module
Creates a VPC with public and private subnets across multiple availability zones.

**Resources:**
- VPC with configurable CIDR
- Public and private subnets
- NAT Gateways
- Internet Gateway
- Route tables

### EKS Module
Creates an EKS cluster with managed node groups.

**Resources:**
- EKS cluster
- Managed node groups (stateful, compute, general)
- Cluster addons (CoreDNS, kube-proxy, VPC CNI, EBS CSI, EFS CSI)
- IRSA roles for cluster autoscaler and CSI drivers

### Storage Module
Creates storage resources for the application.

**Resources:**
- S3 buckets (ML artifacts, data lake)
- EFS file system for shared model storage
- ECR repositories for container images
- Lifecycle policies and encryption

### IAM Module
Creates IAM roles and policies using IRSA (IAM Roles for Service Accounts).

**Resources:**
- S3 access roles for pods
- ALB controller role
- Cassandra backup role (optional)

## Usage

### Development Deployment

**Note**: For local development, `docker-compose` is recommended. Use this only if you need a Kubernetes dev environment.

```bash
cd terraform
./deploy.sh dev
```

### Staging Deployment

```bash
cd terraform
./deploy.sh staging
```

### Production Deployment

```bash
cd terraform
./deploy.sh production
```

## Environment Differences

| Feature | Development | Staging | Production |
|---------|------------|---------|-----------|
| **Use Case** | Testing K8s configs | Pre-production testing | Live production |
| **Availability Zones** | 1 | 2 | 3 |
| **NAT Gateways** | 1 | 1 (shared) | 3 (one per AZ) |
| **Node Groups** | 1 (general) | 1 (general) | 3 (stateful/compute/general) |
| **Instance Types** | t3.medium | t3.xlarge | r6i.2xlarge, c6i.4xlarge, m6i.2xlarge |
| **Min Nodes** | 1 | 2 | 9 |
| **Max Nodes** | 3 | 4 | 22 |
| **EFS Enabled** | No | No | Yes |
| **Cluster Autoscaler** | No | Yes | Yes |
| **ALB Controller** | No | Yes | Yes |
| **Cost (estimated)** | ~$100/month | ~$300/month | ~$2000/month |
| **Recommended For** | K8s testing only | Integration testing | Production workloads |

**Note**: For local development, use `docker-compose.yml` instead of the dev environment (free, faster).

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.6
3. **kubectl** for cluster access
4. **S3 backend** buckets created:
   - `crypto-pipeline-terraform-state-dev` (development)
   - `crypto-pipeline-terraform-state-staging` (staging)
   - `crypto-pipeline-terraform-state-prod` (production)
5. **DynamoDB tables** for state locking:
   - `terraform-state-lock-dev`
   - `terraform-state-lock-staging`
   - `terraform-state-lock-prod`

## Creating Backend Resources

```bash
# Create S3 bucket for state
aws s3 mb s3://crypto-pipeline-terraform-state-prod --region us-east-1
aws s3api put-bucket-versioning \
  --bucket crypto-pipeline-terraform-state-prod \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name terraform-state-lock-prod \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

## Module Development

### Adding a New Module

1. Create module directory: `mkdir -p modules/my-module`
2. Add required files:
   - `main.tf` - Resource definitions
   - `variables.tf` - Input variables
   - `outputs.tf` - Output values
3. Use in environment: Reference in `environments/*/main.tf`

### Module Best Practices

- Keep modules focused on a single responsibility
- Use semantic versioning for module releases
- Document all variables and outputs
- Include examples in module README
- Use variable validation where appropriate

## Common Commands

```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Format code
terraform fmt -recursive

# Plan changes
terraform plan

# Apply changes
terraform apply

# Show current state
terraform show

# Destroy infrastructure
terraform destroy

# List workspaces
terraform workspace list

# Switch workspace
terraform workspace select staging
```

## Outputs

After successful deployment, use these commands:

```bash
# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name <cluster-name>

# Verify cluster access
kubectl get nodes

# Get ECR repository URLs
terraform output ecr_repositories

# Get EFS ID
terraform output efs_id
```

## Troubleshooting

### Issue: "Error creating EKS cluster"
- Check if service quotas are sufficient
- Verify IAM permissions
- Ensure VPC CIDR doesn't conflict

### Issue: "Failed to acquire state lock"
- Check DynamoDB table exists
- Verify table name in backend configuration
- Force unlock if previous operation failed:
  ```bash
  terraform force-unlock <lock-id>
  ```

### Issue: "Module not found"
- Run `terraform init` to download modules
- Check module source paths
- Verify Git repository access for remote modules

## Migration from Legacy Configuration

The root-level Terraform files (main.tf, eks.tf, etc.) are deprecated. To migrate:

1. Back up current state:
   ```bash
   terraform state pull > backup.tfstate
   ```

2. Deploy using new structure:
   ```bash
   cd environments/production
   terraform init
   ```

3. Import existing resources if needed:
   ```bash
   terraform import module.vpc.module.vpc.aws_vpc.this <vpc-id>
   ```

## Security Considerations

- State files are encrypted in S3
- All secrets should be managed via AWS Secrets Manager
- IRSA is used instead of static credentials
- Security groups follow least privilege principle
- Regular security scanning via Trivy

## Cost Optimization

- Use t3/t4g instances for non-production
- Enable cluster autoscaler
- Use single NAT gateway for staging
- Implement lifecycle policies for S3
- Schedule non-production resources to shut down

## References

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Terraform Modules](https://www.terraform.io/docs/language/modules/index.html)
