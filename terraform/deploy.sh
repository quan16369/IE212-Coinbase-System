#!/bin/bash
# Terraform Deployment Script - Redirects to environment-specific deployment

set -e

echo "=================================="
echo " Crypto Pipeline Infrastructure  "
echo "=================================="
echo ""

# Check if environment argument is provided
if [ -z "$1" ]; then
    echo "Usage: ./deploy.sh [dev|staging|production]"
    echo ""
    echo "Examples:"
    echo "  ./deploy.sh dev           # Deploy to development (minimal K8s)"
    echo "  ./deploy.sh staging       # Deploy to staging"
    echo "  ./deploy.sh production    # Deploy to production"
    echo ""
    echo "Note: For local development, use 'docker-compose up -d' instead"
    exit 1
fi

ENVIRONMENT=$1

# Validate environment
if [ "$ENVIRONMENT" != "dev" ] && [ "$ENVIRONMENT" != "staging" ] && [ "$ENVIRONMENT" != "production" ]; then
    echo "Error: Invalid environment '$ENVIRONMENT'"
    echo "Valid options: dev, staging, production"
    exit 1
fi

# Check if environment directory exists
ENV_DIR="environments/$ENVIRONMENT"
if [ ! -d "$ENV_DIR" ]; then
    echo "Error: Environment directory '$ENV_DIR' not found"
    exit 1
fi

echo "Deploying to $ENVIRONMENT environment..."
echo ""

# Change to environment directory
cd "$ENV_DIR"

# Run environment-specific deployment
if [ -f "deploy.sh" ]; then
    ./deploy.sh
else
    echo "Running manual deployment..."
    terraform init
    terraform validate
    terraform plan -out=tfplan
    
    read -p "Apply this plan? (yes/no): " confirm
    if [ "$confirm" == "yes" ]; then
        terraform apply tfplan
        echo ""
        echo "Deployment complete!"
        echo ""
        echo "Configure kubectl:"
        terraform output -raw configure_kubectl
    else
        echo "Deployment cancelled"
        exit 1
    fi
fi
