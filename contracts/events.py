from __future__ import annotations

from datetime import datetime
from typing import Generic, TypeVar

from pydantic import BaseModel, ConfigDict, Field, field_validator


SCHEMA_VERSION = "1.0"
EVENT_TYPE_CANDLE = "coinbase.candle"


class CandlePayload(BaseModel):
    timestamp: datetime
    symbol: str = Field(min_length=1)
    open: float = Field(gt=0)
    high: float = Field(gt=0)
    low: float = Field(gt=0)
    close: float = Field(gt=0)
    volume: float = Field(ge=0)

    @field_validator("symbol")
    @classmethod
    def normalize_symbol(cls, value: str) -> str:
        return value.strip().upper()


PayloadT = TypeVar("PayloadT", bound=BaseModel)


class EventEnvelope(BaseModel, Generic[PayloadT]):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    event_id: str = Field(min_length=1)
    schema_version: str = SCHEMA_VERSION
    event_type: str = Field(min_length=1)
    timestamp: datetime
    source: str = Field(min_length=1)
    kafka_topic: str | None = Field(default=None, alias="_kafka_topic")
    kafka_partition: int | None = Field(default=None, alias="_kafka_partition", ge=0)
    kafka_offset: int | None = Field(default=None, alias="_kafka_offset", ge=0)
    payload: PayloadT

    @field_validator("schema_version")
    @classmethod
    def supported_schema_version(cls, value: str) -> str:
        if value != SCHEMA_VERSION:
            raise ValueError(f"unsupported schema_version: {value}")
        return value


CandleEvent = EventEnvelope[CandlePayload]
