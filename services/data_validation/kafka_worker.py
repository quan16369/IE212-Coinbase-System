from __future__ import annotations

import json
import logging
import os
import time

from kafka import KafkaConsumer, KafkaProducer
from pydantic import ValidationError

from contracts.events import CandleEvent
from services.data_validation.app import ValidationRequest, validate


LOGGER = logging.getLogger(__name__)
BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "streaming-platform-kafka.data-streaming.svc.cluster.local:9092")
INPUT_TOPIC = os.getenv("KAFKA_INPUT_TOPIC", "coin-data-model")
VALIDATED_TOPIC = os.getenv("KAFKA_VALIDATED_TOPIC", "coin-data-validated")
QUALITY_TOPIC = os.getenv("KAFKA_QUALITY_TOPIC", "coin-data-quality")
GROUP_ID = os.getenv("KAFKA_CONSUMER_GROUP", "coinbase-data-validation-v1")


def connect() -> tuple[KafkaConsumer, KafkaProducer]:
    while True:
        try:
            consumer = KafkaConsumer(
                INPUT_TOPIC,
                bootstrap_servers=BOOTSTRAP_SERVERS,
                group_id=GROUP_ID,
                enable_auto_commit=False,
                auto_offset_reset="earliest",
                value_deserializer=lambda value: json.loads(value.decode()),
            )
            producer = KafkaProducer(
                bootstrap_servers=BOOTSTRAP_SERVERS,
                value_serializer=lambda value: json.dumps(value, separators=(",", ":")).encode(),
            )
            return consumer, producer
        except Exception as exc:
            LOGGER.warning("Kafka unavailable: %s; retrying", exc)
            time.sleep(5)


def main() -> None:
    logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
    consumer, producer = connect()
    for message in consumer:
        raw_event = message.value
        try:
            event = CandleEvent.model_validate(raw_event)
            result = validate(ValidationRequest(events=[event]))
            if result.accepted_count:
                producer.send(VALIDATED_TOPIC, raw_event).get(timeout=30)
            elif result.rejected_count:
                producer.send(
                    QUALITY_TOPIC,
                    {"event": raw_event, "errors": result.errors, "reason": "validation_failed"},
                ).get(timeout=30)
            consumer.commit()
        except ValidationError as exc:
            producer.send(
                QUALITY_TOPIC,
                {"event": raw_event, "errors": exc.errors(), "reason": "schema_invalid"},
            ).get(timeout=30)
            consumer.commit()
        except Exception:
            LOGGER.exception("Failed processing Kafka message; offset will be retried")


if __name__ == "__main__":
    main()
