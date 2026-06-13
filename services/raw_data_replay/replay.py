from __future__ import annotations

import json
import logging
import os
from pathlib import Path
import tempfile
from typing import Any

from google.api_core.exceptions import NotFound
from google.cloud import storage
from kafka import KafkaProducer
import pyarrow.parquet as pq


logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
LOGGER = logging.getLogger("raw-data-replay")

BOOTSTRAP_SERVERS = os.environ["BOOTSTRAP_SERVERS"]
GCS_BUCKET = os.environ["GCS_BUCKET"]
GCS_PREFIX = os.getenv("GCS_PREFIX", "raw")
SOURCE_TOPIC = os.getenv("SOURCE_TOPIC", "coin-data-model")
TARGET_TOPIC = os.getenv("TARGET_TOPIC", "coin-data-replay")
REPLAY_ID = os.getenv("REPLAY_ID", "default")
STATE_OBJECT = os.getenv("STATE_OBJECT", f"replay-state/{REPLAY_ID}/high-watermarks.json")

METADATA_FIELDS = {"_kafka_topic", "_kafka_partition", "_kafka_offset", "_archived_at"}


def load_state(bucket: storage.Bucket) -> dict[str, int]:
    try:
        payload = bucket.blob(STATE_OBJECT).download_as_text()
    except NotFound:
        return {}
    return {str(key): int(value) for key, value in json.loads(payload).items()}


def save_state(bucket: storage.Bucket, state: dict[str, int]) -> None:
    bucket.blob(STATE_OBJECT).upload_from_string(
        json.dumps(state, indent=2, sort_keys=True),
        content_type="application/json",
    )


def source_objects(client: storage.Client) -> list[storage.Blob]:
    prefix = f"{GCS_PREFIX}/topic={SOURCE_TOPIC}/"
    return sorted(
        (blob for blob in client.list_blobs(GCS_BUCKET, prefix=prefix) if blob.name.endswith(".parquet")),
        key=lambda blob: blob.name,
    )


def read_rows(blob: storage.Blob) -> list[dict[str, Any]]:
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "batch.parquet"
        blob.download_to_filename(path)
        return pq.read_table(path).to_pylist()


def main() -> None:
    storage_client = storage.Client()
    bucket = storage_client.bucket(GCS_BUCKET)
    state = load_state(bucket)
    pending: list[tuple[str, int, dict[str, Any]]] = []

    for blob in source_objects(storage_client):
        for row in read_rows(blob):
            topic = str(row.get("_kafka_topic", SOURCE_TOPIC))
            partition = int(row["_kafka_partition"])
            offset = int(row["_kafka_offset"])
            state_key = f"{topic}:{partition}"
            if offset <= state.get(state_key, -1):
                continue
            pending.append((state_key, offset, {key: value for key, value in row.items() if key not in METADATA_FIELDS}))

    pending.sort(key=lambda item: (item[0], item[1]))
    producer = KafkaProducer(
        bootstrap_servers=BOOTSTRAP_SERVERS,
        value_serializer=lambda value: json.dumps(value, default=str).encode(),
        key_serializer=lambda value: str(value).encode(),
        acks="all",
    )
    published = 0
    for state_key, offset, payload in pending:
        producer.send(TARGET_TOPIC, key=payload.get("event_id") or payload.get("symbol") or state_key, value=payload).get(
            timeout=30
        )
        state[state_key] = max(offset, state.get(state_key, -1))
        published += 1
    producer.flush()
    save_state(bucket, state)
    LOGGER.info(
        "Replay %s published %s records to %s; checkpoint gs://%s/%s",
        REPLAY_ID,
        published,
        TARGET_TOPIC,
        GCS_BUCKET,
        STATE_OBJECT,
    )


if __name__ == "__main__":
    main()
