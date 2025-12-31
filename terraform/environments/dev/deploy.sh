#!/bin/bash
# Development Environment Deployment Script

set -e

echo "Starting Terraform deployment for Development environment..."
echo ""
echo "WARNING: This is a minimal dev environment."
echo "For local development, consider using docker-compose.yml instead."
echo ""

read -p "Continue with Kubernetes dev deployment? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Deployment cancelled. Use 'docker-compose up -d' for local development."
    exit 0
fi

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
echo "Applying Terraform plan..."
terraform apply tfplan

echo ""
echo "Development deployment complete!"
echo ""
echo "Next steps:"
echo "1. Configure kubectl:"
terraform output -raw configure_kubectl
echo ""
echo "2. Verify cluster access:"
echo "   kubectl get nodes"
echo ""
echo "Note: For local development, docker-compose is more cost-effective."
