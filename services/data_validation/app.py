from __future__ import annotations

from collections import OrderedDict
from threading import Lock
from typing import Any
import os

from fastapi import FastAPI
from pydantic import BaseModel, Field, model_validator

from contracts.events import CandleEvent, CandlePayload, EVENT_TYPE_CANDLE, SCHEMA_VERSION


class ValidationRequest(BaseModel):
    events: list[CandleEvent] = Field(default_factory=list)
    records: list[CandlePayload] = Field(default_factory=list)

    @model_validator(mode="after")
    def require_input(self) -> "ValidationRequest":
        if not self.events and not self.records:
            raise ValueError("events or records must contain at least one item")
        return self


class ValidationResponse(BaseModel):
    valid: bool
    accepted_count: int
    rejected_count: int
    duplicate_count: int
    validated_target: str
    quality_target: str
    validated_indices: list[int]
    quality_indices: list[int]
    duplicate_indices: list[int]
    accepted_event_ids: list[str]
    errors: list[dict[str, Any]]


app = FastAPI(title="Coinbase Data Validation", version="0.2.0")

VALIDATED_TARGET = os.environ.get("VALIDATED_TARGET", "validated-candles")
QUALITY_TARGET = os.environ.get("QUALITY_TARGET", "quality-candles")
IDEMPOTENCY_CACHE_SIZE = int(os.environ.get("VALIDATION_IDEMPOTENCY_CACHE_SIZE", "10000"))
IDEMPOTENCY_REDIS_URL = os.environ.get("VALIDATION_IDEMPOTENCY_REDIS_URL", "").strip()
IDEMPOTENCY_TTL_SECONDS = int(os.environ.get("VALIDATION_IDEMPOTENCY_TTL_SECONDS", "86400"))
_processed_event_ids: OrderedDict[str, None] = OrderedDict()
_idempotency_lock = Lock()
_redis = None


@app.get("/readyz")
def readyz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/livez")
def livez() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/validate", response_model=ValidationResponse)
def validate(payload: ValidationRequest) -> ValidationResponse:
    events = payload.events or [
        CandleEvent(
            event_id=f"legacy:{record.symbol}:{record.timestamp.isoformat()}",
            schema_version=SCHEMA_VERSION,
            event_type=EVENT_TYPE_CANDLE,
            timestamp=record.timestamp,
            source="legacy-api",
            payload=record,
        )
        for record in payload.records
    ]

    errors: list[dict[str, Any]] = []
    duplicate_indices: list[int] = []
    previous_timestamp = None

    for index, event in enumerate(events):
        record = event.payload
        if _is_duplicate(event.event_id):
            duplicate_indices.append(index)
            continue
        if event.event_type != EVENT_TYPE_CANDLE:
            errors.append({"index": index, "field": "event_type", "message": f"expected {EVENT_TYPE_CANDLE}"})
        if event.timestamp != record.timestamp:
            errors.append({"index": index, "field": "timestamp", "message": "envelope and payload timestamps must match"})
        if record.high < max(record.open, record.close, record.low):
            errors.append({"index": index, "field": "high", "message": "high must be greater than or equal to open, close, and low"})
        if record.low > min(record.open, record.close, record.high):
            errors.append({"index": index, "field": "low", "message": "low must be less than or equal to open, close, and high"})
        if previous_timestamp is not None and record.timestamp <= previous_timestamp:
            errors.append({"index": index, "field": "timestamp", "message": "timestamps must be strictly increasing"})
        previous_timestamp = record.timestamp

    quality_indices = sorted({error["index"] for error in errors})
    candidate_indices = [
        index for index in range(len(events))
        if index not in quality_indices and index not in duplicate_indices
    ]
    validated_indices: list[int] = []
    for index in candidate_indices:
        if _claim_event(events[index].event_id):
            validated_indices.append(index)
        else:
            duplicate_indices.append(index)
    duplicate_indices.sort()
    accepted_event_ids = [events[index].event_id for index in validated_indices]

    return ValidationResponse(
        valid=not errors,
        accepted_count=len(validated_indices),
        rejected_count=len(quality_indices),
        duplicate_count=len(duplicate_indices),
        validated_target=VALIDATED_TARGET,
        quality_target=QUALITY_TARGET,
        validated_indices=validated_indices,
        quality_indices=quality_indices,
        duplicate_indices=duplicate_indices,
        accepted_event_ids=accepted_event_ids,
        errors=errors,
    )


def _claim_event(event_id: str) -> bool:
    redis_client = _redis_client()
    if redis_client is not None:
        return bool(redis_client.set(f"data-validation:event:{event_id}", "1", nx=True, ex=IDEMPOTENCY_TTL_SECONDS))
    with _idempotency_lock:
        if event_id in _processed_event_ids:
            return False
        _processed_event_ids[event_id] = None
        _processed_event_ids.move_to_end(event_id)
        while len(_processed_event_ids) > IDEMPOTENCY_CACHE_SIZE:
            _processed_event_ids.popitem(last=False)
        return True


def _is_duplicate(event_id: str) -> bool:
    redis_client = _redis_client()
    if redis_client is not None:
        return bool(redis_client.exists(f"data-validation:event:{event_id}"))
    with _idempotency_lock:
        return event_id in _processed_event_ids


def _redis_client():
    global _redis
    if not IDEMPOTENCY_REDIS_URL:
        return None
    if _redis is None:
        import redis

        _redis = redis.Redis.from_url(IDEMPOTENCY_REDIS_URL, decode_responses=True)
    return _redis
