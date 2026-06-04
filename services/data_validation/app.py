from __future__ import annotations

from datetime import datetime
import os
from typing import Any

from fastapi import FastAPI
from pydantic import BaseModel, Field, field_validator


class Candle(BaseModel):
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


class ValidationRequest(BaseModel):
    records: list[Candle] = Field(min_length=1)


class ValidationResponse(BaseModel):
    valid: bool
    accepted_count: int
    rejected_count: int
    validated_target: str
    quality_target: str
    validated_indices: list[int]
    quality_indices: list[int]
    errors: list[dict[str, Any]]


app = FastAPI(title="Coinbase Data Validation", version="0.1.0")

VALIDATED_TARGET = os.environ.get("VALIDATED_TARGET", "validated-candles")
QUALITY_TARGET = os.environ.get("QUALITY_TARGET", "quality-candles")


@app.get("/readyz")
def readyz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/livez")
def livez() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/validate", response_model=ValidationResponse)
def validate(payload: ValidationRequest) -> ValidationResponse:
    errors: list[dict[str, Any]] = []
    previous_timestamp: datetime | None = None

    for index, record in enumerate(payload.records):
        if record.high < max(record.open, record.close, record.low):
            errors.append(
                {
                    "index": index,
                    "field": "high",
                    "message": "high must be greater than or equal to open, close, and low",
                }
            )

        if record.low > min(record.open, record.close, record.high):
            errors.append(
                {
                    "index": index,
                    "field": "low",
                    "message": "low must be less than or equal to open, close, and high",
                }
            )

        if previous_timestamp is not None and record.timestamp <= previous_timestamp:
            errors.append(
                {
                    "index": index,
                    "field": "timestamp",
                    "message": "timestamps must be strictly increasing",
                }
            )

        previous_timestamp = record.timestamp

    quality_indices = sorted({error["index"] for error in errors})
    validated_indices = [
        index for index in range(len(payload.records)) if index not in quality_indices
    ]
    rejected_count = len(quality_indices)
    accepted_count = len(payload.records) - rejected_count

    return ValidationResponse(
        valid=not errors,
        accepted_count=accepted_count,
        rejected_count=rejected_count,
        validated_target=VALIDATED_TARGET,
        quality_target=QUALITY_TARGET,
        validated_indices=validated_indices,
        quality_indices=quality_indices,
        errors=errors,
    )
