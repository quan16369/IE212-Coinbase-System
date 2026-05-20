#!/usr/bin/env bash
set -euo pipefail

CONTAINER=${CASSANDRA_CONTAINER:-cassandra}
KEYSPACE=${CASSANDRA_KEYSPACE:-coinbase}
BACKUP_DIR=${BACKUP_DIR:-backups/cassandra}
SNAPSHOT_NAME=${SNAPSHOT_NAME:-coinbase_$(date -u +%Y%m%dT%H%M%SZ)}

mkdir -p "$BACKUP_DIR"

echo "Creating Cassandra snapshot $SNAPSHOT_NAME for keyspace $KEYSPACE"
docker exec "$CONTAINER" nodetool snapshot -t "$SNAPSHOT_NAME" "$KEYSPACE"

ARCHIVE="$BACKUP_DIR/$SNAPSHOT_NAME.tar.gz"
echo "Packing snapshot into $ARCHIVE"
docker run --rm \
  --volumes-from "$CONTAINER":ro \
  -v "$PWD/$BACKUP_DIR:/backup" \
  busybox \
  tar czf "/backup/$SNAPSHOT_NAME.tar.gz" "/var/lib/cassandra/data/$KEYSPACE"

echo "Clearing Cassandra snapshot marker"
docker exec "$CONTAINER" nodetool clearsnapshot -t "$SNAPSHOT_NAME" "$KEYSPACE"

echo "Backup created: $ARCHIVE"
