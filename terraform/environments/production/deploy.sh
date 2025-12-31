#!/bin/bash
# Production Environment Deployment Script

set -e

echo "Starting Terraform deployment for Production environment..."

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Validate configuration
echo "Validating Terraform configuration..."
terraform validate

# Plan deployment
echo "Creating deployment plan..."
terraform plan -out=tfplan

# Apply deployment
read -p "Do you want to apply this plan? (yes/no): " confirm
if [ "$confirm" == "yes" ]; then
    echo "Applying Terraform plan..."
    terraform apply tfplan
    
    echo "Deployment complete!"
    echo ""
    echo "Next steps:"
    echo "1. Configure kubectl:"
    terraform output -raw configure_kubectl
    echo ""
    echo "2. Verify cluster access:"
    echo "   kubectl get nodes"
    echo ""
    echo "3. Deploy applications using Helm or kubectl"
else
    echo "Deployment cancelled"
    exit 1
fi
