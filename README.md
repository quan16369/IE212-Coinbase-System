# "IE212 Final: Coinbase Streaming Data Pipeline for Cryptocurrency Price Forecasting"

## Project Overview

This project is a production-oriented Coinbase streaming and MLOps pipeline.
The current GKE path uses Terraform for cloud infrastructure, Helm for
application deployment, Kafka for streaming, FastAPI services for validation,
feature serving, and inference orchestration, MLflow/BentoML for model
management and serving, and Grafana/Prometheus/Loki for observability.

## Screenshot

![plot](https://i.imgur.com/arNNfss.png)
## Architecture

![{AD7AE35E-EC1F-4F9B-8EF1-8655E2C71E7F} png](https://github.com/user-attachments/assets/4a08a193-8f50-4d1f-a1b4-93fc904ea557)

The real-time data pipeline project facilitates the collection, processing,
storage, forecasting, and visualization of cryptocurrency market data from
Coinbase. The current architecture is organized around these components:

- **Coinbase WebSocket producer**: streams market data into Kafka.

- **Kafka on GKE**: buffers raw, validated, quality, and model-ready data topics.

- **Raw data sink and replay**: persists raw streaming data and supports replay
  into Kafka when recovery is needed.

- **Data validation service**: validates event schema, ordering, and null/range
  constraints before routing valid and invalid records.

- **Feature platform**: stores online features in Redis and offline features in
  PostgreSQL, with idempotency checks using event IDs and Kafka offsets.

- **Model training and validation**: trains the forecasting model, logs metadata
  to MLflow, and validates promotion gates before serving.

- **BentoML predictor and inference orchestrator**: serves predictions, stores
  decision-bound governance telemetry, evaluates simple alert rules, and exposes
  Prometheus metrics.

- **Observability**: Grafana dashboards show live streaming prices, predictions,
  workload health, logs, and alert status.

## Deployment
<!--
![kubernetes-pods](https://i.imgur.com/LacnL5c.png)
-->

## How to use
<p align="center">
  <img src="https://i.imgur.com/LU2iYUF.png" style="width: 600px"/>
</p>

For the local Compose stack:

```bash
docker compose --env-file .env up -d
```

For Jenkins CI/CD, monitoring, logs, migrations, and backup/restore, see [OPERATIONS.md](OPERATIONS.md).
For the CPU ML model, MLflow tracking, and BentoML serving path, see [MLOPS.md](MLOPS.md).
For repository layout and deployment ownership boundaries, see [ARCHITECTURE.md](ARCHITECTURE.md).
## Future Work
* Move the current GKE development cluster from Autopilot to a tuned Standard cluster when cost and node-level control matter.
* Add stronger end-to-end tests around Kafka replay, model promotion, and rollback.
* Improve model quality and add richer multi-symbol prediction panels.
* Replace demo secrets with a managed secret workflow for non-local environments.

## [Demo](https://drive.google.com/file/d/1HRBCcF42rRFbDxIWq7ECk3Xm1ykzOiP_/view?usp=sharing)


![Screenshot 2025-05-28 215935](https://github.com/user-attachments/assets/75c04d07-2d63-44bd-9a3c-6bc1ae967ea2)
