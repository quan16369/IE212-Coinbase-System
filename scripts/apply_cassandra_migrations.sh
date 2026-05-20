#!/usr/bin/env bash
set -euo pipefail

CONTAINER=${CASSANDRA_CONTAINER:-cassandra}
MIGRATIONS_DIR=${MIGRATIONS_DIR:-ops/cassandra/migrations}

if [[ ! -d "$MIGRATIONS_DIR" ]]; then
  echo "Missing migrations directory: $MIGRATIONS_DIR"
  exit 1
fi

echo "Waiting for Cassandra in container $CONTAINER"
until docker exec "$CONTAINER" cqlsh -e "DESCRIBE KEYSPACES" >/dev/null 2>&1; do
  sleep 5
done

for migration in "$MIGRATIONS_DIR"/*.cql; do
  [[ -e "$migration" ]] || continue
  echo "Applying Cassandra migration: $migration"
  docker exec -i "$CONTAINER" cqlsh < "$migration"
done

echo "Cassandra migrations applied"
