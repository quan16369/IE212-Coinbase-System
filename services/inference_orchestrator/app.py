from __future__ import annotations

from datetime import datetime, timezone
from hashlib import sha256
import json
import os
from pathlib import Path
import sqlite3
from tempfile import NamedTemporaryFile
from threading import Lock
from time import perf_counter
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen
from uuid import uuid4

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field, field_validator


BENTO_PREDICT_URL = os.environ.get(
    "BENTO_PREDICT_URL",
    "http://bento-price-predictor.app.svc.cluster.local/predict",
)
FEATURE_PLATFORM_URL = os.environ.get(
    "FEATURE_PLATFORM_URL",
    "http://feature-platform.feature-platform.svc.cluster.local",
).rstrip("/")
ALERT_RETURN_THRESHOLD = float(os.environ.get("ALERT_RETURN_THRESHOLD", "0.005"))
ALERT_HISTORY_LIMIT = int(os.environ.get("ALERT_HISTORY_LIMIT", "200"))
ALERT_INDEX_PATH = Path(os.environ.get("ALERT_INDEX_PATH", "/data/alerts.jsonl"))
GOVERNANCE_HISTORY_LIMIT = int(os.environ.get("GOVERNANCE_HISTORY_LIMIT", "1000"))
GOVERNANCE_INDEX_PATH = Path(os.environ.get("GOVERNANCE_INDEX_PATH", "/data/governance_decisions.jsonl"))
OUTCOME_DB_PATH = Path(os.environ.get("OUTCOME_DB_PATH", "/data/outcomes.db"))
HTTP_TIMEOUT_SECONDS = float(os.environ.get("ORCHESTRATOR_HTTP_TIMEOUT_SECONDS", "30"))
_alert_lock = Lock()
_governance_lock = Lock()

app = FastAPI(title="Coinbase Inference Orchestrator", version="0.1.0")


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


class PredictRequest(BaseModel):
    records: list[Candle] = Field(min_length=1)


class AlertRecord(BaseModel):
    id: str
    created_at: datetime
    symbol: str
    severity: str
    rule: str
    threshold: float
    predicted_return: float
    predicted_close: float | None = None
    target_time: str | None = None
    message: str


class GovernanceDecisionRecord(BaseModel):
    decision_id: str
    captured_at: datetime
    symbol: str
    model_name: str | None = None
    model_family: str | None = None
    model_version: str | None = None
    decision: dict[str, Any]
    confidence: float | None = None
    latency_ms: dict[str, float]
    drift: dict[str, Any] | None = None
    operational_health: dict[str, str]
    previous_hash: str | None = None
    record_hash: str


class OutcomeRecord(BaseModel):
    decision_id: str
    observed_at: datetime
    actual_close: float = Field(gt=0)


@app.get("/readyz")
def readyz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/livez")
def livez() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/config")
def config() -> dict[str, str]:
    return {
        "bento_predict_url": BENTO_PREDICT_URL,
        "feature_platform_url": FEATURE_PLATFORM_URL,
        "alert_return_threshold": str(ALERT_RETURN_THRESHOLD),
        "alert_index_path": str(ALERT_INDEX_PATH),
        "governance_index_path": str(GOVERNANCE_INDEX_PATH),
    }


@app.post("/orchestrate/predict")
def predict(payload: PredictRequest) -> dict[str, Any]:
    started_at = perf_counter()
    records = [record.model_dump(mode="json") for record in payload.records]
    symbol = records[-1]["symbol"]

    bento_started_at = perf_counter()
    prediction = _post_json(BENTO_PREDICT_URL, {"records": records})
    bento_latency_ms = _elapsed_ms(bento_started_at)
    feature_started_at = perf_counter()
    latest_feature = _get_latest_feature(symbol)
    drift = _get_drift(symbol)
    feature_latency_ms = _elapsed_ms(feature_started_at)
    alert_evaluation = _evaluate_alert(symbol, prediction, latest_feature)
    governance_record = _build_governance_record(
        symbol=symbol,
        prediction=prediction,
        drift=drift,
        bento_latency_ms=bento_latency_ms,
        feature_latency_ms=feature_latency_ms,
        end_to_end_latency_ms=_elapsed_ms(started_at),
    )
    _store_governance_record(governance_record)

    return {
        "decision_id": governance_record["decision_id"],
        "symbol": symbol,
        "feature_context": latest_feature,
        "prediction": prediction,
        "governance": governance_record,
        "alert_evaluation": alert_evaluation,
        "sources": {
            "bento_predict_url": BENTO_PREDICT_URL,
            "feature_platform_url": FEATURE_PLATFORM_URL,
            "alert_evaluation": "internal",
            "alert_index": str(ALERT_INDEX_PATH),
        },
    }


@app.get("/governance/decisions")
def list_governance_decisions(
    symbol: str | None = None,
    limit: int = Query(default=50, ge=1, le=GOVERNANCE_HISTORY_LIMIT),
) -> dict[str, Any]:
    decisions = _read_governance_records()
    if symbol:
        normalized = symbol.strip().upper()
        decisions = [decision for decision in decisions if decision.get("symbol") == normalized]
    return {"count": len(decisions), "decisions": decisions[-limit:]}


@app.get("/governance/decisions/{decision_id}")
def get_governance_decision(decision_id: str) -> dict[str, Any]:
    for decision in _read_governance_records():
        if decision.get("decision_id") == decision_id:
            return decision
    raise HTTPException(status_code=404, detail=f"Governance decision not found: {decision_id}")


@app.get("/governance/integrity")
def governance_integrity() -> dict[str, Any]:
    decisions = _read_governance_records()
    valid, broken_at = _verify_governance_chain(decisions)
    return {"valid": valid, "record_count": len(decisions), "broken_at": broken_at}


@app.post("/outcomes")
def record_outcome(outcome: OutcomeRecord) -> dict[str, Any]:
    decision = get_governance_decision(outcome.decision_id)
    predicted_close = decision.get("decision", {}).get("predicted_close")
    if predicted_close is None:
        raise HTTPException(status_code=409, detail="Decision does not contain predicted_close")
    error = float(outcome.actual_close) - float(predicted_close)
    row = {
        **outcome.model_dump(mode="json"),
        "symbol": decision["symbol"],
        "predicted_close": float(predicted_close),
        "absolute_error": abs(error),
        "percentage_error": abs(error) / float(outcome.actual_close),
    }
    _store_outcome(row)
    return row


@app.get("/outcomes")
def list_outcomes(limit: int = Query(default=50, ge=1, le=1000)) -> dict[str, Any]:
    rows = _read_outcomes(limit)
    return {"count": len(rows), "outcomes": rows}


@app.get("/outcomes/performance")
def outcome_performance() -> dict[str, Any]:
    rows = _read_outcomes(1000)
    if not rows:
        return {"count": 0, "mae": None, "mape": None}
    return {
        "count": len(rows),
        "mae": sum(row["absolute_error"] for row in rows) / len(rows),
        "mape": sum(row["percentage_error"] for row in rows) / len(rows),
    }


@app.get("/orchestrate/latest/{symbol}")
def latest(symbol: str) -> dict[str, Any]:
    normalized = symbol.strip().upper()
    latest_feature = _get_latest_feature(normalized)
    if latest_feature is None:
        raise HTTPException(status_code=404, detail=f"No features for symbol {normalized}")
    return latest_feature


@app.get("/alerts")
def list_alerts(
    symbol: str | None = None,
    limit: int = Query(default=50, ge=1, le=ALERT_HISTORY_LIMIT),
) -> dict[str, Any]:
    alerts = _read_alerts()
    if symbol:
        normalized = symbol.strip().upper()
        alerts = [alert for alert in alerts if alert.get("symbol") == normalized]
    return {"count": len(alerts), "alerts": alerts[-limit:]}


@app.get("/alerts/{alert_id}")
def get_alert(alert_id: str) -> dict[str, Any]:
    for alert in _read_alerts():
        if alert.get("id") == alert_id:
            return alert
    raise HTTPException(status_code=404, detail=f"Alert not found: {alert_id}")


def _post_json(url: str, payload: dict[str, Any]) -> dict[str, Any]:
    request = Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
            return json.loads(response.read().decode())
    except HTTPError as exc:
        body = exc.read().decode(errors="replace")
        raise HTTPException(status_code=502, detail=f"Bento returned HTTP {exc.code}: {body}") from exc
    except URLError as exc:
        raise HTTPException(status_code=502, detail=f"Could not reach Bento: {exc.reason}") from exc


def _get_latest_feature(symbol: str) -> dict[str, Any] | None:
    url = f"{FEATURE_PLATFORM_URL}/features/latest/{quote(symbol)}"
    try:
        with urlopen(url, timeout=HTTP_TIMEOUT_SECONDS) as response:
            return json.loads(response.read().decode())
    except HTTPError as exc:
        if exc.code == 404:
            return None
        body = exc.read().decode(errors="replace")
        raise HTTPException(status_code=502, detail=f"Feature platform returned HTTP {exc.code}: {body}") from exc
    except URLError as exc:
        raise HTTPException(status_code=502, detail=f"Could not reach feature platform: {exc.reason}") from exc


def _get_drift(symbol: str) -> dict[str, Any] | None:
    url = f"{FEATURE_PLATFORM_URL}/features/drift/{quote(symbol)}"
    try:
        with urlopen(url, timeout=HTTP_TIMEOUT_SECONDS) as response:
            return json.loads(response.read().decode())
    except HTTPError as exc:
        if exc.code in {404, 409}:
            return None
        body = exc.read().decode(errors="replace")
        raise HTTPException(status_code=502, detail=f"Feature platform returned HTTP {exc.code}: {body}") from exc
    except URLError as exc:
        raise HTTPException(status_code=502, detail=f"Could not reach feature platform: {exc.reason}") from exc


def _build_governance_record(
    symbol: str,
    prediction: dict[str, Any],
    drift: dict[str, Any] | None,
    bento_latency_ms: float,
    feature_latency_ms: float,
    end_to_end_latency_ms: float,
) -> dict[str, Any]:
    result = prediction.get("prediction", {})
    model_version = prediction.get("model_version") or prediction.get("model_uri") or prediction.get("model_source")
    record = {
        "decision_id": f"dec_{uuid4().hex}",
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "symbol": symbol,
        "model_name": prediction.get("model_name"),
        "model_family": prediction.get("model_family"),
        "model_version": str(model_version) if model_version is not None else None,
        "decision": {
            "predicted_return": result.get("predicted_return"),
            "predicted_close": result.get("predicted_close"),
            "target_time": result.get("target_time"),
        },
        "confidence": prediction.get("confidence"),
        "latency_ms": {
            "bento": round(bento_latency_ms, 3),
            "feature_platform": round(feature_latency_ms, 3),
            "end_to_end": round(end_to_end_latency_ms, 3),
        },
        "drift": drift,
        "operational_health": {
            "orchestrator": "healthy",
            "bento": "healthy",
            "feature_platform": "healthy",
        },
        "previous_hash": None,
    }
    record["record_hash"] = _governance_hash(record)
    return GovernanceDecisionRecord.model_validate(record).model_dump(mode="json")


def _elapsed_ms(started_at: float) -> float:
    return (perf_counter() - started_at) * 1000


def _evaluate_alert(symbol: str, prediction: dict[str, Any], feature_context: dict[str, Any] | None) -> dict[str, Any] | None:
    del feature_context
    result = prediction.get("prediction", {})
    predicted_return = float(result.get("predicted_return", 0.0))
    triggered = abs(predicted_return) >= ALERT_RETURN_THRESHOLD
    alert: dict[str, Any] | None = None

    if triggered:
        alert = AlertRecord(
            id=str(uuid4()),
            created_at=datetime.now(timezone.utc),
            symbol=symbol,
            severity="warning",
            rule="absolute_predicted_return_threshold",
            threshold=ALERT_RETURN_THRESHOLD,
            predicted_return=predicted_return,
            predicted_close=result.get("predicted_close"),
            target_time=result.get("target_time"),
            message=f"{symbol} predicted return {predicted_return:.6f} crossed threshold {ALERT_RETURN_THRESHOLD:.6f}",
        ).model_dump(mode="json")
        _store_alert(alert)

    return {
        "triggered": triggered,
        "threshold": ALERT_RETURN_THRESHOLD,
        "alert": alert,
        "alert_count": len(_read_alerts()),
        "indexed": triggered,
        "index_error": None,
    }


def _read_alerts() -> list[dict[str, Any]]:
    with _alert_lock:
        if not ALERT_INDEX_PATH.exists():
            return []
        with ALERT_INDEX_PATH.open("r", encoding="utf-8") as handle:
            alerts = [json.loads(line) for line in handle if line.strip()]
        return alerts[-ALERT_HISTORY_LIMIT:]


def _store_alert(alert: dict[str, Any]) -> None:
    with _alert_lock:
        alerts: list[dict[str, Any]] = []
        if ALERT_INDEX_PATH.exists():
            with ALERT_INDEX_PATH.open("r", encoding="utf-8") as handle:
                alerts = [json.loads(line) for line in handle if line.strip()]
        alerts = [item for item in alerts if item.get("id") != alert["id"]]
        alerts.append(alert)

        ALERT_INDEX_PATH.parent.mkdir(parents=True, exist_ok=True)
        with NamedTemporaryFile("w", encoding="utf-8", dir=ALERT_INDEX_PATH.parent, delete=False) as handle:
            tmp_path = Path(handle.name)
            for item in alerts[-ALERT_HISTORY_LIMIT:]:
                handle.write(json.dumps(item, sort_keys=True))
                handle.write("\n")
        tmp_path.replace(ALERT_INDEX_PATH)


def _governance_hash(record: dict[str, Any]) -> str:
    unsigned = {key: value for key, value in record.items() if key != "record_hash"}
    canonical = json.dumps(unsigned, sort_keys=True, separators=(",", ":"), default=str)
    return f"sha256:{sha256(canonical.encode()).hexdigest()}"


def _read_governance_records_unlocked() -> list[dict[str, Any]]:
    if not GOVERNANCE_INDEX_PATH.exists():
        return []
    with GOVERNANCE_INDEX_PATH.open("r", encoding="utf-8") as handle:
        records = [json.loads(line) for line in handle if line.strip()]
    return records[-GOVERNANCE_HISTORY_LIMIT:]


def _read_governance_records() -> list[dict[str, Any]]:
    with _governance_lock:
        return _read_governance_records_unlocked()


def _store_governance_record(record: dict[str, Any]) -> None:
    with _governance_lock:
        records = _read_governance_records_unlocked()
        record["previous_hash"] = records[-1]["record_hash"] if records else None
        record["record_hash"] = _governance_hash(record)
        records.append(record)
        GOVERNANCE_INDEX_PATH.parent.mkdir(parents=True, exist_ok=True)
        with NamedTemporaryFile("w", encoding="utf-8", dir=GOVERNANCE_INDEX_PATH.parent, delete=False) as handle:
            tmp_path = Path(handle.name)
            for item in records[-GOVERNANCE_HISTORY_LIMIT:]:
                handle.write(json.dumps(item, sort_keys=True))
                handle.write("\n")
        tmp_path.replace(GOVERNANCE_INDEX_PATH)


def _verify_governance_chain(records: list[dict[str, Any]]) -> tuple[bool, str | None]:
    previous_hash: str | None = records[0].get("previous_hash") if records else None
    for record in records:
        if record.get("previous_hash") != previous_hash or record.get("record_hash") != _governance_hash(record):
            return False, record.get("decision_id")
        previous_hash = record.get("record_hash")
    return True, None


def _outcome_connection() -> sqlite3.Connection:
    OUTCOME_DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(OUTCOME_DB_PATH)
    connection.row_factory = sqlite3.Row
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS outcomes (
          decision_id TEXT PRIMARY KEY,
          observed_at TEXT NOT NULL,
          symbol TEXT NOT NULL,
          actual_close REAL NOT NULL,
          predicted_close REAL NOT NULL,
          absolute_error REAL NOT NULL,
          percentage_error REAL NOT NULL
        )
        """
    )
    return connection


def _store_outcome(row: dict[str, Any]) -> None:
    with _outcome_connection() as connection:
        connection.execute(
            """
            INSERT INTO outcomes VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(decision_id) DO UPDATE SET
              observed_at=excluded.observed_at,
              actual_close=excluded.actual_close,
              absolute_error=excluded.absolute_error,
              percentage_error=excluded.percentage_error
            """,
            tuple(row[key] for key in (
                "decision_id", "observed_at", "symbol", "actual_close",
                "predicted_close", "absolute_error", "percentage_error",
            )),
        )


def _read_outcomes(limit: int) -> list[dict[str, Any]]:
    with _outcome_connection() as connection:
        rows = connection.execute(
            "SELECT * FROM outcomes ORDER BY observed_at DESC LIMIT ?", (limit,)
        ).fetchall()
    return [dict(row) for row in rows]
