from __future__ import annotations

import json
import logging
import os
import time
from urllib.request import Request, urlopen

from kafka import KafkaConsumer


LOGGER = logging.getLogger(__name__)
BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "streaming-platform-kafka.data-streaming.svc.cluster.local:9092")
INPUT_TOPIC = os.getenv("KAFKA_INPUT_TOPIC", "coin-data-validated")
GROUP_ID = os.getenv("KAFKA_CONSUMER_GROUP", "coinbase-feature-platform-v1")
INGEST_URL = os.getenv("FEATURE_INGEST_URL", "http://feature-platform.feature-platform.svc.cluster.local/features/ingest")


def connect() -> KafkaConsumer:
    while True:
        try:
            return KafkaConsumer(
                INPUT_TOPIC,
                bootstrap_servers=BOOTSTRAP_SERVERS,
                group_id=GROUP_ID,
                enable_auto_commit=False,
                auto_offset_reset="earliest",
                value_deserializer=lambda value: json.loads(value.decode()),
            )
        except Exception as exc:
            LOGGER.warning("Kafka unavailable: %s; retrying", exc)
            time.sleep(5)


def main() -> None:
    logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
    consumer = connect()
    for message in consumer:
        request = Request(
            INGEST_URL,
            data=json.dumps({"events": [message.value], "source": "kafka"}).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urlopen(request, timeout=30) as response:
                LOGGER.info("Ingested offset=%s response=%s", message.offset, response.read().decode())
            consumer.commit()
        except Exception:
            LOGGER.exception("Feature ingest failed; offset will be retried")
            time.sleep(5)


if __name__ == "__main__":
    main()
