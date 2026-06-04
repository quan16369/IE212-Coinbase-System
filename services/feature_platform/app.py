from __future__ import annotations

from collections import defaultdict, deque
from datetime import datetime
import math
import os
from typing import Deque

from fastapi import FastAPI, HTTPException, Query
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


class FeatureRecord(BaseModel):
    timestamp: datetime
    symbol: str
    open: float
    high: float
    low: float
    close: float
    volume: float
    returns: float
    log_returns: float
    high_low_spread: float
    open_close_spread: float
    volume_change: float
    close_mean_3: float
    close_mean_6: float
    close_mean_12: float


class IngestRequest(BaseModel):
    records: list[Candle] = Field(min_length=1)


class IngestResponse(BaseModel):
    accepted_count: int
    symbols: list[str]
    online_store: str
    offline_store: str
    latest: dict[str, FeatureRecord]


MAX_HISTORY = int(os.environ.get("FEATURE_HISTORY_LIMIT", "200"))
ONLINE_STORE = os.environ.get("FEATURE_ONLINE_STORE", "memory")
OFFLINE_STORE = os.environ.get("FEATURE_OFFLINE_STORE", "memory")

app = FastAPI(title="Coinbase Feature Platform", version="0.1.0")

_features: dict[str, Deque[FeatureRecord]] = defaultdict(lambda: deque(maxlen=MAX_HISTORY))
_raw: dict[str, Deque[Candle]] = defaultdict(lambda: deque(maxlen=MAX_HISTORY))


@app.get("/readyz")
def readyz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/livez")
def livez() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/features/ingest", response_model=IngestResponse)
def ingest(payload: IngestRequest) -> IngestResponse:
    latest: dict[str, FeatureRecord] = {}

    for record in sorted(payload.records, key=lambda item: item.timestamp):
        history = _raw[record.symbol]
        previous = history[-1] if history else None
        feature = _build_feature(record, list(history), previous)

        history.append(record)
        _features[record.symbol].append(feature)
        latest[record.symbol] = feature

    return IngestResponse(
        accepted_count=len(payload.records),
        symbols=sorted(latest),
        online_store=ONLINE_STORE,
        offline_store=OFFLINE_STORE,
        latest=latest,
    )


@app.get("/features/latest/{symbol}", response_model=FeatureRecord)
def latest(symbol: str) -> FeatureRecord:
    normalized = symbol.strip().upper()
    if not _features[normalized]:
        raise HTTPException(status_code=404, detail=f"No features for symbol {normalized}")
    return _features[normalized][-1]


@app.get("/features/history/{symbol}", response_model=list[FeatureRecord])
def history(symbol: str, limit: int = Query(default=50, ge=1, le=MAX_HISTORY)) -> list[FeatureRecord]:
    normalized = symbol.strip().upper()
    if not _features[normalized]:
        raise HTTPException(status_code=404, detail=f"No features for symbol {normalized}")
    return list(_features[normalized])[-limit:]


def _build_feature(record: Candle, history: list[Candle], previous: Candle | None) -> FeatureRecord:
    if previous is None:
        returns = 0.0
        volume_change = 0.0
    else:
        returns = (record.close - previous.close) / previous.close
        volume_change = 0.0 if previous.volume == 0 else (record.volume - previous.volume) / previous.volume

    closes = [item.close for item in history] + [record.close]

    return FeatureRecord(
        timestamp=record.timestamp,
        symbol=record.symbol,
        open=record.open,
        high=record.high,
        low=record.low,
        close=record.close,
        volume=record.volume,
        returns=returns,
        log_returns=math.log1p(returns),
        high_low_spread=record.high - record.low,
        open_close_spread=record.close - record.open,
        volume_change=volume_change,
        close_mean_3=_rolling_mean(closes, 3),
        close_mean_6=_rolling_mean(closes, 6),
        close_mean_12=_rolling_mean(closes, 12),
    )


def _rolling_mean(values: list[float], window: int) -> float:
    tail = values[-window:]
    return sum(tail) / len(tail)
