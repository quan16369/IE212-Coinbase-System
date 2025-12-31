# Environment Comparison

## Overview

This project supports multiple deployment environments, each optimized for different use cases and budgets.

## Quick Reference

| Environment | Command | Cost/Month | Use Case |
|------------|---------|------------|----------|
| **Local Docker** | `docker-compose up -d` | $0 | Local development, testing |
| **Dev (K8s)** | `./terraform/deploy.sh dev` | ~$100 | Kubernetes config testing |
| **Staging** | `./terraform/deploy.sh staging` | ~$300 | Pre-production validation |
| **Production** | `./terraform/deploy.sh production` | ~$2000 | Live production workload |

## Detailed Comparison

### Local Development (Docker Compose)

**Infrastructure**:
- Single host (your machine or EC2)
- All services in Docker containers
- No Kubernetes, no load balancing

**Resources**:
- CPU: 4-8 cores recommended
- RAM: 16GB minimum
- Storage: 50GB

**Features**:
- Quick startup (5 minutes)
- Full stack available locally
- Easy debugging
- No cloud costs

**Limitations**:
- Not scalable
- No high availability
- Manual restart on failure
- Single point of failure

**Best For**:
- Feature development
- Bug fixing
- Local testing
- Learning the system

**Command**:
```bash
docker-compose up -d
```

---

### Development (Kubernetes)

**Infrastructure**:
- AWS EKS cluster (managed control plane)
- 1 availability zone
- 1 NAT gateway
- 1-3 worker nodes (t3.medium)

**Resources**:
- Min: 1 node (2 vCPU, 4GB RAM)
- Max: 3 nodes (6 vCPU, 12GB RAM)
- Storage: 30GB per node

**Features**:
- Kubernetes-based
- Test K8s manifests
- Similar to production structure
- Auto-restart pods

**Limitations**:
- No high availability
- Single AZ (can go down)
- Limited resources
- No autoscaling

**Best For**:
- Testing Kubernetes configurations
- Validating Helm charts
- CI/CD pipeline development
- Not for regular development (use Docker Compose)

**Cost Breakdown**:
- EKS Control Plane: $73/month
- EC2 (1x t3.medium): $30/month
- EBS Storage: $10/month
- NAT Gateway: $32/month
- **Total**: ~$100/month

**Command**:
```bash
cd terraform
./deploy.sh dev
```

---

### Staging

**Infrastructure**:
- AWS EKS cluster (managed control plane)
- 2 availability zones
- 1 shared NAT gateway
- 2-4 worker nodes (t3.xlarge)

**Resources**:
- Min: 2 nodes (8 vCPU, 16GB RAM)
- Max: 4 nodes (16 vCPU, 32GB RAM)
- Storage: 50GB per node

**Features**:
- Multi-AZ (more reliable)
- Auto-scaling enabled
- ALB for load balancing
- Similar to production
- Cluster autoscaler

**Limitations**:
- Smaller instances than prod
- Single NAT gateway (cost optimization)
- No EFS (uses EBS only)
- Lower resource limits

**Best For**:
- Pre-production testing
- Integration testing
- Performance testing (light)
- Stakeholder demos

**Cost Breakdown**:
- EKS Control Plane: $73/month
- EC2 (2-4x t3.xlarge): $150-300/month
- EBS Storage: $30/month
- NAT Gateway: $32/month
- ALB: $20/month
- **Total**: ~$300/month

**Command**:
```bash
cd terraform
./deploy.sh staging
```

---

### Production

**Infrastructure**:
- AWS EKS cluster (managed control plane)
- 3 availability zones (high availability)
- 3 NAT gateways (one per AZ)
- 9-22 worker nodes (mixed instance types)

**Node Groups**:
1. **Stateful** (3x r6i.2xlarge):
   - Kafka, Zookeeper, Cassandra
   - Memory-optimized
   - 8 vCPU, 64GB RAM each

2. **Compute** (3x c6i.4xlarge):
   - Spark processing
   - CPU-optimized
   - 16 vCPU, 32GB RAM each

3. **General** (3-10x m6i.2xlarge):
   - API services, MLflow, monitoring
   - Balanced compute/memory
   - 8 vCPU, 32GB RAM each
   - Auto-scales based on load

**Resources**:
- Min: 9 nodes (84 vCPU, 336GB RAM)
- Max: 22 nodes (220 vCPU, 880GB RAM)
- Storage: 200GB (stateful), 100GB (others)

**Features**:
- Full high availability
- Multi-AZ deployment
- Horizontal pod autoscaling
- Cluster autoscaling
- EFS for shared model storage
- Multiple load balancers
- Complete monitoring stack
- GitOps with ArgoCD
- Continuous learning pipeline

**Service Level**:
- Uptime: 99.95%
- RTO (Recovery Time): < 3 minutes
- RPO (Data Loss): < 1 minute

**Best For**:
- Production workloads
- High traffic (1000+ req/s)
- Mission-critical applications
- SLA requirements
- Compliance needs

**Cost Breakdown**:
- EKS Control Plane: $73/month
- EC2 Instances:
  - 3x r6i.2xlarge: $540/month
  - 3x c6i.4xlarge: $540/month
  - 3x m6i.2xlarge: $420/month
- EBS Storage (600GB): $200/month
- EFS (50GB): $50/month
- NAT Gateways (3): $100/month
- ALB: $20/month
- S3: $10/month
- Data Transfer: $50/month
- **Total**: ~$2,000/month

**Command**:
```bash
cd terraform
./deploy.sh production
```

---

## Feature Matrix

| Feature | Docker Compose | Dev (K8s) | Staging | Production |
|---------|---------------|-----------|---------|------------|
| **Deployment Time** | 5 min | 20 min | 25 min | 30 min |
| **Startup Time** | 2 min | 5 min | 5 min | 5 min |
| **High Availability** | No | No | Partial | Yes |
| **Auto-Scaling** | No | No | Yes | Yes |
| **Auto-Healing** | No | Yes | Yes | Yes |
| **Load Balancing** | No | K8s Service | ALB | ALB |
| **Rolling Updates** | Manual | Yes | Yes | Yes |
| **Canary Deployment** | No | No | Yes | Yes |
| **Blue-Green** | No | No | Possible | Yes |
| **EFS Storage** | No | No | No | Yes |
| **S3 Integration** | No | Yes | Yes | Yes |
| **ECR Integration** | No | Yes | Yes | Yes |
| **Monitoring** | Basic | Basic | Full | Full |
| **Alerting** | No | No | Yes | Yes |
| **GitOps** | No | No | Optional | Yes |
| **MLOps** | Basic | Basic | Yes | Yes |
| **Continuous Learning** | No | No | Yes | Yes |
| **Multi-Region** | No | No | No | Possible |

## Scaling Comparison

### Docker Compose
- **Vertical only**: Upgrade host machine
- **Max limit**: Single host capacity
- **Downtime**: Required for scaling

### Dev (Kubernetes)
- **Horizontal**: 1-3 nodes
- **Pod scaling**: Limited by node resources
- **Automatic**: No cluster autoscaler

### Staging
- **Horizontal**: 2-4 nodes
- **Pod scaling**: HPA enabled
- **Automatic**: Yes (cluster autoscaler)

### Production
- **Horizontal**: 9-22 nodes
- **Pod scaling**: HPA enabled (3-10 replicas)
- **Automatic**: Yes (cluster + pod autoscaling)
- **Multi-dimensional**: By node group type

## Cost Optimization Tips

### For Development
- Use Docker Compose instead of K8s dev environment
- Turn off staging when not in use
- Use spot instances for non-critical testing

### For Staging
- Schedule downtime (nights/weekends)
- Use single NAT gateway
- Use smaller instance types
- Disable EFS

### For Production
- Reserved instances (1-year): Save 30-40%
- Spot instances for compute nodes: Save 70%
- Optimize node group sizing
- Enable cluster autoscaler
- Review S3 lifecycle policies

## Migration Path

```
1. Development
   ├─> Docker Compose (Local)
   └─> Dev K8s (Optional, for K8s testing)
        │
2. Testing
   └─> Staging (Pre-production validation)
        │
3. Production
   └─> Production (Live workload)
```

## When to Use Each

### Use Docker Compose When:
- Developing new features
- Debugging issues locally
- Learning the system
- Running on local machine
- Budget: $0

### Use Dev (K8s) When:
- Testing Kubernetes manifests
- Validating Helm charts
- Testing operators/controllers
- CI/CD development
- Budget: ~$100/month

### Use Staging When:
- Pre-production testing
- Integration testing
- Load testing (moderate)
- Stakeholder demos
- Budget: ~$300/month

### Use Production When:
- Serving real users
- Need high availability
- Traffic > 1000 req/s
- SLA requirements
- Budget: ~$2000/month

## Recommendation

**For most developers**: Start with Docker Compose for development, then deploy directly to staging for testing.

**Skip the K8s dev environment** unless you specifically need to test Kubernetes configurations. It adds cost without much benefit for regular development work.
