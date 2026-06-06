from __future__ import annotations

from collections import defaultdict, deque
from datetime import datetime, timezone
from hashlib import sha256
import json
import math
import os
import time
from threading import Lock
from typing import Any, Deque, Protocol
from uuid import uuid4

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field, model_validator

from contracts.events import CandleEvent, CandlePayload, EVENT_TYPE_CANDLE, SCHEMA_VERSION


Candle = CandlePayload


class FeatureRecord(BaseModel):
    event_id: str | None = None
    schema_version: str = SCHEMA_VERSION
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
    events: list[CandleEvent] = Field(default_factory=list)
    records: list[Candle] = Field(default_factory=list)
    source: str = "telemetry"
    data_version: str | None = None

    @model_validator(mode="after")
    def require_input(self) -> "IngestRequest":
        if not self.events and not self.records:
            raise ValueError("events or records must contain at least one item")
        return self


class IngestResponse(BaseModel):
    accepted_count: int
    duplicate_count: int
    accepted_event_ids: list[str]
    duplicate_event_ids: list[str]
    symbols: list[str]
    online_store: str
    offline_store: str
    batch_id: str
    data_version: str
    latest: dict[str, FeatureRecord]


class StoreHealth(BaseModel):
    configured: str
    connected: bool
    detail: str = "ok"


class StoreStatus(BaseModel):
    online: StoreHealth
    offline: StoreHealth
    history_limit: int


class DriftReport(BaseModel):
    symbol: str
    baseline_window: int
    recent_window: int
    baseline_mean_return: float
    recent_mean_return: float
    return_mean_delta: float
    baseline_mean_volume: float
    recent_mean_volume: float
    volume_mean_delta_ratio: float
    drift_score: float
    drift_detected: bool


class RetrainingSignal(BaseModel):
    symbol: str
    should_retrain: bool
    reason: str
    drift: DriftReport
    min_records: int
    observed_records: int


class FeatureStore(Protocol):
    online_name: str
    offline_name: str

    def save_batch(self, batch_id: str, payload_hash: str, source: str, data_version: str) -> None:
        ...

    def save_feature(self, batch_id: str, record: FeatureRecord) -> None:
        ...

    def claim_event(self, event_id: str, schema_version: str, event_timestamp: datetime) -> bool:
        ...

    def latest(self, symbol: str) -> FeatureRecord | None:
        ...

    def history(self, symbol: str, limit: int) -> list[FeatureRecord]:
        ...

    def health(self) -> StoreStatus:
        ...


MAX_HISTORY = int(os.environ.get("FEATURE_HISTORY_LIMIT", "200"))
ONLINE_STORE = os.environ.get("FEATURE_ONLINE_STORE", "memory").strip().lower()
OFFLINE_STORE = os.environ.get("FEATURE_OFFLINE_STORE", "memory").strip().lower()
REDIS_URL = os.environ.get("FEATURE_REDIS_URL", "redis://feature-platform-redis:6379/0")
POSTGRES_DSN = os.environ.get(
    "FEATURE_POSTGRES_DSN",
    "postgresql://feature_user:feature_password@feature-platform-postgres:5432/feature_store",
)
DEFAULT_DATA_VERSION = os.environ.get("FEATURE_DATA_VERSION", "local-dev")
DRIFT_RETURN_DELTA_THRESHOLD = float(os.environ.get("FEATURE_DRIFT_RETURN_DELTA_THRESHOLD", "0.005"))
DRIFT_VOLUME_DELTA_RATIO_THRESHOLD = float(os.environ.get("FEATURE_DRIFT_VOLUME_DELTA_RATIO_THRESHOLD", "0.25"))

app = FastAPI(title="Coinbase Feature Platform", version="0.2.0")
store: FeatureStore


@app.on_event("startup")
def startup() -> None:
    global store
    if ONLINE_STORE == "redis" or OFFLINE_STORE == "postgres":
        store = _connect_redis_postgres_with_retry()
    else:
        store = MemoryFeatureStore()


@app.get("/readyz")
def readyz() -> dict[str, Any]:
    status = store.health()
    if not status.online.connected or not status.offline.connected:
        raise HTTPException(status_code=503, detail=status.model_dump())
    return {"status": "ok", "stores": status.model_dump()}


@app.get("/livez")
def livez() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/store/status", response_model=StoreStatus)
def store_status() -> StoreStatus:
    return store.health()


@app.post("/features/ingest", response_model=IngestResponse)
def ingest(payload: IngestRequest) -> IngestResponse:
    latest: dict[str, FeatureRecord] = {}
    data_version = payload.data_version or DEFAULT_DATA_VERSION
    batch_id = str(uuid4())
    payload_hash = _payload_hash(payload)
    events = payload.events or [
        CandleEvent(
            event_id=f"legacy:{record.symbol}:{record.timestamp.isoformat()}",
            schema_version=SCHEMA_VERSION,
            event_type=EVENT_TYPE_CANDLE,
            timestamp=record.timestamp,
            source=payload.source,
            payload=record,
        )
        for record in payload.records
    ]
    accepted_event_ids: list[str] = []
    duplicate_event_ids: list[str] = []

    store.save_batch(batch_id, payload_hash, payload.source, data_version)

    for event in sorted(events, key=lambda item: item.timestamp):
        if not store.claim_event(event.event_id, event.schema_version, event.timestamp):
            duplicate_event_ids.append(event.event_id)
            continue
        record = event.payload
        history = _history_candles(record.symbol)
        previous = history[-1] if history else None
        feature = _build_feature(record, history, previous, event.event_id, event.schema_version)

        store.save_feature(batch_id, feature)
        latest[record.symbol] = feature
        accepted_event_ids.append(event.event_id)

    return IngestResponse(
        accepted_count=len(accepted_event_ids),
        duplicate_count=len(duplicate_event_ids),
        accepted_event_ids=accepted_event_ids,
        duplicate_event_ids=duplicate_event_ids,
        symbols=sorted(latest),
        online_store=store.online_name,
        offline_store=store.offline_name,
        batch_id=batch_id,
        data_version=data_version,
        latest=latest,
    )


@app.get("/features/latest/{symbol}", response_model=FeatureRecord)
def latest(symbol: str) -> FeatureRecord:
    normalized = symbol.strip().upper()
    feature = store.latest(normalized)
    if feature is None:
        raise HTTPException(status_code=404, detail=f"No features for symbol {normalized}")
    return feature


@app.get("/features/history/{symbol}", response_model=list[FeatureRecord])
def history(symbol: str, limit: int = Query(default=50, ge=1, le=MAX_HISTORY)) -> list[FeatureRecord]:
    normalized = symbol.strip().upper()
    records = store.history(normalized, limit)
    if not records:
        raise HTTPException(status_code=404, detail=f"No features for symbol {normalized}")
    return records


@app.get("/features/drift/{symbol}", response_model=DriftReport)
def drift(
    symbol: str,
    baseline_window: int = Query(default=24, ge=3, le=MAX_HISTORY),
    recent_window: int = Query(default=6, ge=2, le=MAX_HISTORY),
) -> DriftReport:
    normalized = symbol.strip().upper()
    records = store.history(normalized, baseline_window + recent_window)
    if len(records) < baseline_window + recent_window:
        raise HTTPException(
            status_code=409,
            detail=f"Need at least {baseline_window + recent_window} records for drift report; found {len(records)}",
        )

    baseline = records[:baseline_window]
    recent = records[-recent_window:]
    baseline_mean_return = _mean([item.returns for item in baseline])
    recent_mean_return = _mean([item.returns for item in recent])
    baseline_mean_volume = _mean([item.volume for item in baseline])
    recent_mean_volume = _mean([item.volume for item in recent])
    return_delta = abs(recent_mean_return - baseline_mean_return)
    volume_delta_ratio = 0.0
    if baseline_mean_volume:
        volume_delta_ratio = abs(recent_mean_volume - baseline_mean_volume) / baseline_mean_volume
    drift_score = max(
        return_delta / DRIFT_RETURN_DELTA_THRESHOLD,
        volume_delta_ratio / DRIFT_VOLUME_DELTA_RATIO_THRESHOLD,
    )

    return DriftReport(
        symbol=normalized,
        baseline_window=baseline_window,
        recent_window=recent_window,
        baseline_mean_return=baseline_mean_return,
        recent_mean_return=recent_mean_return,
        return_mean_delta=return_delta,
        baseline_mean_volume=baseline_mean_volume,
        recent_mean_volume=recent_mean_volume,
        volume_mean_delta_ratio=volume_delta_ratio,
        drift_score=drift_score,
        drift_detected=drift_score >= 1.0,
    )


@app.get("/feedback/retraining-signal/{symbol}", response_model=RetrainingSignal)
def retraining_signal(symbol: str) -> RetrainingSignal:
    baseline_window = int(os.environ.get("FEATURE_RETRAIN_BASELINE_WINDOW", "24"))
    recent_window = int(os.environ.get("FEATURE_RETRAIN_RECENT_WINDOW", "6"))
    min_records = baseline_window + recent_window
    normalized = symbol.strip().upper()
    records = store.history(normalized, min_records)
    if len(records) < min_records:
        empty_report = DriftReport(
            symbol=normalized,
            baseline_window=baseline_window,
            recent_window=recent_window,
            baseline_mean_return=0.0,
            recent_mean_return=0.0,
            return_mean_delta=0.0,
            baseline_mean_volume=0.0,
            recent_mean_volume=0.0,
            volume_mean_delta_ratio=0.0,
            drift_score=0.0,
            drift_detected=False,
        )
        return RetrainingSignal(
            symbol=normalized,
            should_retrain=False,
            reason="not_enough_records",
            drift=empty_report,
            min_records=min_records,
            observed_records=len(records),
        )

    report = drift(normalized, baseline_window, recent_window)
    return RetrainingSignal(
        symbol=normalized,
        should_retrain=report.drift_detected,
        reason="drift_detected" if report.drift_detected else "within_threshold",
        drift=report,
        min_records=min_records,
        observed_records=len(records),
    )


class MemoryFeatureStore:
    online_name = "memory"
    offline_name = "memory"

    def __init__(self) -> None:
        self.features: dict[str, Deque[FeatureRecord]] = defaultdict(lambda: deque(maxlen=MAX_HISTORY))
        self.batches: dict[str, dict[str, Any]] = {}
        self.processed_event_ids: set[str] = set()
        self.event_lock = Lock()

    def save_batch(self, batch_id: str, payload_hash: str, source: str, data_version: str) -> None:
        self.batches[batch_id] = {
            "payload_hash": payload_hash,
            "source": source,
            "data_version": data_version,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }

    def save_feature(self, batch_id: str, record: FeatureRecord) -> None:
        self.features[record.symbol].append(record)

    def claim_event(self, event_id: str, schema_version: str, event_timestamp: datetime) -> bool:
        del schema_version, event_timestamp
        with self.event_lock:
            if event_id in self.processed_event_ids:
                return False
            self.processed_event_ids.add(event_id)
            return True

    def latest(self, symbol: str) -> FeatureRecord | None:
        if not self.features[symbol]:
            return None
        return self.features[symbol][-1]

    def history(self, symbol: str, limit: int) -> list[FeatureRecord]:
        return list(self.features[symbol])[-limit:]

    def health(self) -> StoreStatus:
        return StoreStatus(
            online=StoreHealth(configured=self.online_name, connected=True),
            offline=StoreHealth(configured=self.offline_name, connected=True),
            history_limit=MAX_HISTORY,
        )


class RedisPostgresFeatureStore:
    online_name = "redis"
    offline_name = "postgres"

    def __init__(self) -> None:
        import psycopg
        import redis

        self.redis = redis.Redis.from_url(REDIS_URL, decode_responses=True)
        self.pg = psycopg.connect(POSTGRES_DSN, autocommit=True)
        self._init_schema()

    def _init_schema(self) -> None:
        with self.pg.cursor() as cursor:
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS feature_batches (
                  batch_id TEXT PRIMARY KEY,
                  payload_hash TEXT NOT NULL,
                  source TEXT NOT NULL,
                  data_version TEXT NOT NULL,
                  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
                )
                """
            )
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS processed_feature_events (
                  event_id TEXT PRIMARY KEY,
                  schema_version TEXT NOT NULL,
                  event_timestamp TIMESTAMPTZ NOT NULL,
                  processed_at TIMESTAMPTZ NOT NULL DEFAULT now()
                )
                """
            )
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS feature_records (
                  id BIGSERIAL PRIMARY KEY,
                  batch_id TEXT NOT NULL REFERENCES feature_batches(batch_id),
                  timestamp TIMESTAMPTZ NOT NULL,
                  symbol TEXT NOT NULL,
                  payload JSONB NOT NULL,
                  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                  UNIQUE (symbol, timestamp)
                )
                """
            )
            cursor.execute(
                "CREATE INDEX IF NOT EXISTS idx_feature_records_symbol_timestamp ON feature_records(symbol, timestamp DESC)"
            )

    def save_batch(self, batch_id: str, payload_hash: str, source: str, data_version: str) -> None:
        with self.pg.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO feature_batches (batch_id, payload_hash, source, data_version)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (batch_id) DO NOTHING
                """,
                (batch_id, payload_hash, source, data_version),
            )

    def save_feature(self, batch_id: str, record: FeatureRecord) -> None:
        payload = record.model_dump(mode="json")
        with self.pg.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO feature_records (batch_id, timestamp, symbol, payload)
                VALUES (%s, %s, %s, %s::jsonb)
                ON CONFLICT (symbol, timestamp) DO UPDATE SET
                  batch_id = EXCLUDED.batch_id,
                  payload = EXCLUDED.payload,
                  created_at = now()
                """,
                (batch_id, record.timestamp, record.symbol, json.dumps(payload)),
            )
        self.redis.set(_latest_key(record.symbol), json.dumps(payload))

    def claim_event(self, event_id: str, schema_version: str, event_timestamp: datetime) -> bool:
        with self.pg.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO processed_feature_events (event_id, schema_version, event_timestamp)
                VALUES (%s, %s, %s)
                ON CONFLICT (event_id) DO NOTHING
                RETURNING event_id
                """,
                (event_id, schema_version, event_timestamp),
            )
            return cursor.fetchone() is not None

    def latest(self, symbol: str) -> FeatureRecord | None:
        raw = self.redis.get(_latest_key(symbol))
        if raw:
            return FeatureRecord.model_validate(json.loads(raw))
        records = self.history(symbol, 1)
        return records[-1] if records else None

    def history(self, symbol: str, limit: int) -> list[FeatureRecord]:
        with self.pg.cursor() as cursor:
            cursor.execute(
                """
                SELECT payload
                FROM feature_records
                WHERE symbol = %s
                ORDER BY timestamp DESC
                LIMIT %s
                """,
                (symbol, limit),
            )
            rows = cursor.fetchall()
        records = []
        for row in reversed(rows):
            payload = row[0]
            if isinstance(payload, str):
                payload = json.loads(payload)
            records.append(FeatureRecord.model_validate(payload))
        return records

    def health(self) -> StoreStatus:
        online = StoreHealth(configured=self.online_name, connected=True)
        offline = StoreHealth(configured=self.offline_name, connected=True)
        try:
            self.redis.ping()
        except Exception as exc:  # pragma: no cover - depends on external store
            online = StoreHealth(configured=self.online_name, connected=False, detail=str(exc))
        try:
            with self.pg.cursor() as cursor:
                cursor.execute("SELECT 1")
                cursor.fetchone()
        except Exception as exc:  # pragma: no cover - depends on external store
            offline = StoreHealth(configured=self.offline_name, connected=False, detail=str(exc))
        return StoreStatus(online=online, offline=offline, history_limit=MAX_HISTORY)


def _connect_redis_postgres_with_retry() -> RedisPostgresFeatureStore:
    attempts = int(os.environ.get("FEATURE_STORE_CONNECT_ATTEMPTS", "30"))
    delay = float(os.environ.get("FEATURE_STORE_CONNECT_DELAY_SECONDS", "2"))
    last_error: Exception | None = None
    for _ in range(attempts):
        try:
            return RedisPostgresFeatureStore()
        except Exception as exc:  # pragma: no cover - startup depends on external services
            last_error = exc
            time.sleep(delay)
    raise RuntimeError(f"Could not connect to feature stores after {attempts} attempts: {last_error}")


def _history_candles(symbol: str) -> list[Candle]:
    return [
        Candle(
            timestamp=item.timestamp,
            symbol=item.symbol,
            open=item.open,
            high=item.high,
            low=item.low,
            close=item.close,
            volume=item.volume,
        )
        for item in store.history(symbol, MAX_HISTORY)
    ]


def _build_feature(
    record: Candle,
    history: list[Candle],
    previous: Candle | None,
    event_id: str,
    schema_version: str,
) -> FeatureRecord:
    if previous is None:
        returns = 0.0
        volume_change = 0.0
    else:
        returns = (record.close - previous.close) / previous.close
        volume_change = 0.0 if previous.volume == 0 else (record.volume - previous.volume) / previous.volume

    closes = [item.close for item in history] + [record.close]

    return FeatureRecord(
        event_id=event_id,
        schema_version=schema_version,
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


def _payload_hash(payload: IngestRequest) -> str:
    normalized = payload.model_dump_json()
    return sha256(normalized.encode("utf-8")).hexdigest()


def _latest_key(symbol: str) -> str:
    return f"features:latest:{symbol}"


def _rolling_mean(values: list[float], window: int) -> float:
    tail = values[-window:]
    return sum(tail) / len(tail)


def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0
