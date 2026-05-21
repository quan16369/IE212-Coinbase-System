#!/usr/bin/env bash
set -euo pipefail

ARCHIVE=${1:-}
ENV_FILE=${ENV_FILE:-.env}
CONTAINER=${CASSANDRA_CONTAINER:-cassandra}

if [[ -z "$ARCHIVE" ]]; then
  echo "Usage: bash scripts/restore_cassandra.sh backups/cassandra/<snapshot>.tar.gz"
  exit 1
fi

if [[ ! -f "$ARCHIVE" ]]; then
  echo "Backup archive not found: $ARCHIVE"
  exit 1
fi

echo "Stopping Cassandra for cold restore"
docker compose --env-file "$ENV_FILE" stop cassandra

echo "Restoring $ARCHIVE into Cassandra data volume"
docker run --rm \
  --volumes-from "$CONTAINER" \
  -v "$PWD/$ARCHIVE:/restore/backup.tar.gz:ro" \
  busybox \
  sh -c "cd / && tar xzf /restore/backup.tar.gz"

echo "Starting Cassandra"
docker compose --env-file "$ENV_FILE" start cassandra

echo "Restore submitted. Check Cassandra logs and run repair/validation before accepting traffic."
