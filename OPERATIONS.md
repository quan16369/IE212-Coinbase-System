# Operations

## Local or single-host deployment

Create a local env file before starting services:

```bash
cp .env.example .env
```

Review `.env` and replace the MinIO/Grafana passwords before using the stack outside local development.

Run the application with the ops profile:

```bash
COMPOSE_PROFILES=ops bash scripts/deploy_compose.sh
```

Main endpoints:

- Kafka UI: `http://localhost:8080`
- Grafana: `http://localhost:3000`
- Prometheus: `http://localhost:9090`
- Alertmanager: `http://localhost:9093`
- cAdvisor: `http://localhost:8081`
- MinIO Console: `http://localhost:9001`

## Jenkins CI/CD

The repo now uses `Jenkinsfile` for CI/CD. A basic Jenkins host needs:

- Docker Engine and Docker Compose v2 available to the Jenkins agent.
- Permission for the Jenkins user to run Docker.
- A `.env` file on the Jenkins workspace or deployment host. If missing, the pipeline copies `.env.example` for CI/dev.

Pipeline stages:

- `Prepare`: creates `.env` from `.env.example` if needed.
- `CI Checks`: validates Compose, checks Python syntax, and runs Go tests when Go is installed.
- `Build Images`: builds all Docker images.
- `Deploy`: runs `scripts/deploy_compose.sh` only on `main` or `master`.

For production-like usage, keep `.env` out of Git and manage the real values through Jenkins credentials, a protected file credential, or host-level secret management.

## Monitoring and logs

The `ops` Compose profile starts:

- Prometheus for metrics.
- Alertmanager for basic alert routing.
- Blackbox Exporter for HTTP health checks.
- cAdvisor for container metrics.
- Loki and Promtail for Docker container logs.

Alert rules live in `monitoring/prometheus/alerts.yml`. Alertmanager currently uses a local no-op receiver so alerts are visible in the UI but not sent externally. Add Slack, email, or webhook receivers in `monitoring/alertmanager/alertmanager.yml` when you have a destination.

## Cassandra migrations

Schema migrations live in `ops/cassandra/migrations`.

Apply them manually:

```bash
bash scripts/apply_cassandra_migrations.sh
```

Compose also includes a `cassandra-migrate` service that runs the current `.cql` migrations after Cassandra becomes healthy. New schema changes should go into versioned `.cql` files.

## Backup and restore

Create a Cassandra snapshot archive:

```bash
bash scripts/backup_cassandra.sh
```

Restore from an archive:

```bash
bash scripts/restore_cassandra.sh backups/cassandra/<snapshot>.tar.gz
```

The restore script performs a cold restore by stopping Cassandra, unpacking the archive into the Cassandra volume, then starting Cassandra. Validate the database and logs before accepting traffic.

## Current limits

This is still a single-host Docker Compose ops setup. It improves CI/CD, config hygiene, monitoring, logs, and backup basics, but it is not HA. For real production, the next step is Kubernetes or managed services for Kafka, Cassandra, object storage, secrets, and alert delivery.
