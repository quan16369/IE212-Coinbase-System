from __future__ import annotations

from datetime import datetime, timezone
import json
import logging
import os
from pathlib import Path
import tempfile
from time import monotonic
from uuid import uuid4

from google.cloud import storage
from kafka import KafkaConsumer
import pyarrow as pa
import pyarrow.parquet as pq


logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
LOGGER = logging.getLogger("raw-data-sink")

BOOTSTRAP_SERVERS = os.environ["BOOTSTRAP_SERVERS"]
SOURCE_TOPIC = os.getenv("SOURCE_TOPIC", "coin-data-model")
CONSUMER_GROUP = os.getenv("CONSUMER_GROUP", "coinbase-gcs-raw-sink-v1")
GCS_BUCKET = os.environ["GCS_BUCKET"]
GCS_PREFIX = os.getenv("GCS_PREFIX", "raw")
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "1000"))
FLUSH_INTERVAL_SECONDS = int(os.getenv("FLUSH_INTERVAL_SECONDS", "300"))


def object_name(records: list[dict]) -> str:
    timestamp = records[0].get("timestamp")
    try:
        partition_time = datetime.fromisoformat(str(timestamp).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        partition_time = datetime.now(timezone.utc)
    partition_time = partition_time.astimezone(timezone.utc)
    return (
        f"{GCS_PREFIX}/topic={SOURCE_TOPIC}/date={partition_time:%Y-%m-%d}/"
        f"hour={partition_time:%H}/part-{partition_time:%Y%m%dT%H%M%S}-{uuid4().hex}.parquet"
    )


def flush(storage_client: storage.Client, records: list[dict]) -> None:
    if not records:
        return
    destination = object_name(records)
    table = pa.Table.from_pylist(records)
    with tempfile.TemporaryDirectory() as directory:
        local_path = Path(directory) / "batch.parquet"
        pq.write_table(table, local_path, compression="snappy")
        storage_client.bucket(GCS_BUCKET).blob(destination).upload_from_filename(local_path)
    LOGGER.info("Uploaded %s records to gs://%s/%s", len(records), GCS_BUCKET, destination)


def main() -> None:
    storage_client = storage.Client()
    consumer = KafkaConsumer(
        SOURCE_TOPIC,
        bootstrap_servers=BOOTSTRAP_SERVERS,
        group_id=CONSUMER_GROUP,
        enable_auto_commit=False,
        auto_offset_reset="earliest",
        value_deserializer=lambda value: json.loads(value.decode()),
    )
    records: list[dict] = []
    last_flush = monotonic()
    while True:
        batches = consumer.poll(timeout_ms=1000, max_records=BATCH_SIZE)
        for messages in batches.values():
            for message in messages:
                records.append(
                    {
                        **message.value,
                        "_kafka_topic": message.topic,
                        "_kafka_partition": message.partition,
                        "_kafka_offset": message.offset,
                        "_archived_at": datetime.now(timezone.utc).isoformat(),
                    }
                )
        if len(records) >= BATCH_SIZE or monotonic() - last_flush >= FLUSH_INTERVAL_SECONDS:
            flush(storage_client, records)
            if records:
                consumer.commit()
                records.clear()
                last_flush = monotonic()


if __name__ == "__main__":
    main()
