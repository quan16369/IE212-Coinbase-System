# ModelPack Integration Guide

## Overview

This project now uses **CNCF ModelPack** specification to package and distribute the LSTM model as OCI artifacts. This provides standardized, cloud-native model management.

## Why ModelPack?

### Traditional Approach Problems
- 🔴 Model files scattered (checkpoints/, configs/, src/)
- 🔴 No standard format
- 🔴 Hard to version
- 🔴 Manual deployment
- 🔴 No metadata tracking

### ModelPack Benefits
- ✅ **Standard Format**: OCI-compliant artifacts
- ✅ **Versioning**: Semantic versioning with tags
- ✅ **Metadata**: Complete model information
- ✅ **Cloud-Native**: Works with K8s, Harbor, MLflow
- ✅ **Reproducible**: Full training context
- ✅ **Portable**: Works across platforms

## Quick Start

### 1. Build Model as OCI Artifact

```bash
cd Crypto-TS-Model-master

# Build and optionally push
./build-modelpack.sh

# Or manually
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f Dockerfile.model \
  -t docker.io/yourregistry/crypto-lstm-btc:1.0.0 \
  .
```

### 2. Push to Registry

```bash
# Docker Hub
docker push docker.io/yourregistry/crypto-lstm-btc:1.0.0

# Harbor (recommended for production)
docker tag docker.io/yourregistry/crypto-lstm-btc:1.0.0 \
  harbor.example.com/crypto/lstm-btc:1.0.0
docker push harbor.example.com/crypto/lstm-btc:1.0.0

# AWS ECR
docker tag docker.io/yourregistry/crypto-lstm-btc:1.0.0 \
  123456789.dkr.ecr.us-east-1.amazonaws.com/crypto-lstm-btc:1.0.0
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/crypto-lstm-btc:1.0.0
```

### 3. Use in Kubernetes

```bash
# Deploy with ModelPack
kubectl apply -f k8s/prediction-service-modelpack.yaml

# Check status
kubectl get pods -n crypto-pipeline -l app=crypto-predictor
kubectl logs -n crypto-pipeline -l app=crypto-predictor
```

## Model Structure

```
crypto-lstm-btc:1.0.0 (OCI artifact)
├── model/
│   ├── model.pt              # PyTorch checkpoint
│   ├── config.yaml           # Model configuration
│   ├── modelpack.yaml        # ModelPack manifest
│   ├── metadata.json         # Model metadata
│   └── src/                  # Source code (for reference)
│       ├── lstm_attention_model.py
│       ├── train_lstm_paimon.py
│       └── paimon_data_loader.py
```

## ModelPack Manifest

The [modelpack.yaml](Crypto-TS-Model-master/modelpack.yaml) contains:

```yaml
apiVersion: modelpack.io/v1alpha1
kind: Model
metadata:
  name: crypto-lstm-btc
  version: "1.0.0"
spec:
  framework:
    name: pytorch
    version: "2.0.0"
  
  training:
    metrics:
      - name: mae
        value: 0.025
      - name: rmse
        value: 0.035
  
  inference:
    input:
      shape: [batch_size, 288, 6]
    output:
      shape: [batch_size, 12, 1]
    performance:
      latency_p95: "10ms"
      throughput: "100 predictions/sec"
```

## Usage Examples

### Pull Model

```bash
# Pull from registry
docker pull docker.io/yourregistry/crypto-lstm-btc:1.0.0

# Extract model files
docker create --name model-tmp docker.io/yourregistry/crypto-lstm-btc:1.0.0
docker cp model-tmp:/model ./extracted-model
docker rm model-tmp

# Now you have:
# ./extracted-model/model.pt
# ./extracted-model/config.yaml
```

### Inspect Model Metadata

```bash
# View labels
docker inspect docker.io/yourregistry/crypto-lstm-btc:1.0.0 | jq '.[0].Config.Labels'

# Output:
# {
#   "io.modelpack.framework": "pytorch",
#   "io.modelpack.metrics.mae": "0.025",
#   "io.modelpack.inference.latency.p95": "10ms",
#   ...
# }
```

### Load Model in Python

```python
import torch
import subprocess

# Pull and extract model
subprocess.run([
    "docker", "pull", "docker.io/yourregistry/crypto-lstm-btc:1.0.0"
])
subprocess.run([
    "docker", "run", "--rm", "-v", f"{os.getcwd()}:/output",
    "docker.io/yourregistry/crypto-lstm-btc:1.0.0",
    "sh", "-c", "cp /model/* /output/"
])

# Load model
model = torch.load("model.pt")
```

### Use in Kubernetes (Method 1: Init Container)

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      initContainers:
      - name: model-loader
        image: docker.io/yourregistry/crypto-lstm-btc:1.0.0
        command: ['sh', '-c', 'cp -r /model/* /shared-model/']
        volumeMounts:
        - name: model
          mountPath: /shared-model
      
      containers:
      - name: predictor
        image: prediction-service:latest
        volumeMounts:
        - name: model
          mountPath: /app/model
      
      volumes:
      - name: model
        emptyDir: {}
```

### Use in Kubernetes (Method 2: OCI Volume Source)

Requires Kubernetes 1.31+ with `ImageVolume` feature gate.

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
      - name: predictor
        image: prediction-service:latest
        volumeMounts:
        - name: model
          mountPath: /app/model
      
      volumes:
      - name: model
        image:
          reference: docker.io/yourregistry/crypto-lstm-btc:1.0.0
          pullPolicy: IfNotPresent
```

## Integration with MLOps

### MLflow

```python
import mlflow

# Log model as artifact
mlflow.log_artifact("modelpack.yaml")
mlflow.log_artifact("metadata.json")

# Register model with OCI reference
mlflow.register_model(
    model_uri=f"models:/crypto-lstm-btc/1",
    name="crypto-lstm-btc",
    tags={
        "oci_reference": "docker.io/yourregistry/crypto-lstm-btc:1.0.0",
        "modelpack_version": "1.0.0"
    }
)
```

### Seldon Core

```yaml
apiVersion: machinelearning.seldon.io/v1
kind: SeldonDeployment
metadata:
  name: crypto-predictor
spec:
  predictors:
  - name: default
    replicas: 3
    graph:
      name: model
      implementation: PYTORCH_SERVER
      modelUri: oci://docker.io/yourregistry/crypto-lstm-btc:1.0.0
      envSecretRefName: model-credentials
```

## Model Versioning

### Semantic Versioning

```bash
# Major version (breaking changes)
docker tag crypto-lstm-btc:1.0.0 crypto-lstm-btc:2.0.0

# Minor version (new features, backward compatible)
docker tag crypto-lstm-btc:1.0.0 crypto-lstm-btc:1.1.0

# Patch version (bug fixes)
docker tag crypto-lstm-btc:1.0.0 crypto-lstm-btc:1.0.1
```

### Tagging Strategy

```bash
# Version tags
crypto-lstm-btc:1.0.0
crypto-lstm-btc:1.0
crypto-lstm-btc:1
crypto-lstm-btc:latest

# Environment tags
crypto-lstm-btc:dev
crypto-lstm-btc:staging
crypto-lstm-btc:production

# Commit SHA tags
crypto-lstm-btc:sha-abc123

# Date tags
crypto-lstm-btc:2025-12-31
```

## Best Practices

### 1. Always Include Metadata

```yaml
# modelpack.yaml
metadata:
  name: crypto-lstm-btc
  version: "1.0.0"
  description: "Detailed description"
  authors: [...]
  created: "2025-12-31T00:00:00Z"
```

### 2. Track Training Metrics

```yaml
training:
  metrics:
    - name: mae
      value: 0.025
    - name: rmse
      value: 0.035
  dataset:
    name: BTC-USD-historical
    location: s3a://bucket/path
```

### 3. Document Inference Specs

```yaml
inference:
  input:
    shape: [batch_size, 288, 6]
    dtype: float32
  output:
    shape: [batch_size, 12, 1]
  performance:
    latency_p95: "10ms"
```

### 4. Use Immutable Tags

```bash
# Good: Versioned tags
docker pull crypto-lstm-btc:1.0.0

# Bad: Mutable tags (use only for development)
docker pull crypto-lstm-btc:latest
```

### 5. Sign Models

```bash
# Sign with Cosign (CNCF project)
cosign sign docker.io/yourregistry/crypto-lstm-btc:1.0.0

# Verify
cosign verify docker.io/yourregistry/crypto-lstm-btc:1.0.0
```

## Troubleshooting

### Issue: Model too large

```bash
# Check size
docker images crypto-lstm-btc:1.0.0

# Optimize:
# 1. Use model quantization
# 2. Remove unnecessary files
# 3. Compress checkpoints
```

### Issue: Pull fails

```bash
# Check registry authentication
docker login docker.io

# Check network
docker pull --debug docker.io/yourregistry/crypto-lstm-btc:1.0.0
```

### Issue: Kubernetes pod fails to start

```bash
# Check events
kubectl describe pod <pod-name> -n crypto-pipeline

# Check logs
kubectl logs <pod-name> -c model-loader -n crypto-pipeline

# Verify image exists
docker pull docker.io/yourregistry/crypto-lstm-btc:1.0.0
```

## Comparison: Before vs After

| Aspect | Before | After (ModelPack) |
|--------|--------|-------------------|
| Format | Scattered files | OCI artifact |
| Versioning | Manual | Semantic + registry |
| Metadata | Minimal | Comprehensive |
| Distribution | Manual copy | Registry pull |
| K8s Integration | ConfigMap/PV | OCI volume source |
| Reproducibility | Hard | Easy |
| Standard | None | CNCF ModelPack |

## Future Enhancements

- [ ] Integrate with Harbor for enterprise registry
- [ ] Add model signing with Cosign
- [ ] Implement model vulnerability scanning
- [ ] Add SBOM (Software Bill of Materials)
- [ ] Support multi-model artifacts
- [ ] Add model provenance tracking

## References

- [CNCF ModelPack Specification](https://github.com/modelpack/model-spec)
- [OCI Image Specification](https://github.com/opencontainers/image-spec)
- [Kubernetes OCI Volume Source](https://github.com/kubernetes/enhancements/issues/4639)
- [Harbor Model Registry](https://goharbor.io/)
- [Seldon Core](https://www.seldon.io/)

---

**ModelPack = OCI + AI Models** 🚀

Standardized. Cloud-native. Production-ready.
