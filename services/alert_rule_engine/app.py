from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from uuid import uuid4

from fastapi import FastAPI, Query
from pydantic import BaseModel, Field, field_validator


RETURN_THRESHOLD = float(os.environ.get("ALERT_RETURN_THRESHOLD", "0.005"))
MAX_ALERTS = int(os.environ.get("ALERT_HISTORY_LIMIT", "200"))
ALERT_INDEX_URL = os.environ.get("ALERT_INDEX_URL", "").rstrip("/")
HTTP_TIMEOUT_SECONDS = float(os.environ.get("ALERT_HTTP_TIMEOUT_SECONDS", "10"))

app = FastAPI(title="Coinbase Alert Rule Engine", version="0.1.0")
_alerts: list[dict[str, Any]] = []


class PredictionPayload(BaseModel):
    symbol: str = Field(min_length=1)
    prediction: dict[str, Any]
    feature_context: dict[str, Any] | None = None

    @field_validator("symbol")
    @classmethod
    def normalize_symbol(cls, value: str) -> str:
        return value.strip().upper()


@app.get("/readyz")
def readyz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/livez")
def livez() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/config")
def config() -> dict[str, float | int | str]:
    return {
        "return_threshold": RETURN_THRESHOLD,
        "history_limit": MAX_ALERTS,
        "alert_index_url": ALERT_INDEX_URL,
    }


@app.post("/alerts/evaluate")
def evaluate(payload: PredictionPayload) -> dict[str, Any]:
    prediction = payload.prediction.get("prediction", {})
    predicted_return = float(prediction.get("predicted_return", 0.0))
    triggered = abs(predicted_return) >= RETURN_THRESHOLD

    alert: dict[str, Any] | None = None
    if triggered:
        alert = {
            "id": str(uuid4()),
            "created_at": datetime.now(timezone.utc).isoformat(),
            "symbol": payload.symbol,
            "severity": "warning",
            "rule": "absolute_predicted_return_threshold",
            "threshold": RETURN_THRESHOLD,
            "predicted_return": predicted_return,
            "predicted_close": prediction.get("predicted_close"),
            "target_time": prediction.get("target_time"),
            "message": f"{payload.symbol} predicted return {predicted_return:.6f} crossed threshold {RETURN_THRESHOLD:.6f}",
        }
        _alerts.append(alert)
        del _alerts[:-MAX_ALERTS]
        indexed, index_error = _store_alert(alert)

    return {
        "triggered": triggered,
        "threshold": RETURN_THRESHOLD,
        "alert": alert,
        "alert_count": len(_alerts),
        "indexed": indexed if triggered else False,
        "index_error": index_error if triggered else None,
    }


@app.get("/alerts")
def list_alerts(limit: int = Query(default=50, ge=1, le=MAX_ALERTS)) -> dict[str, Any]:
    return {
        "count": len(_alerts),
        "alerts": _alerts[-limit:],
    }


def _store_alert(alert: dict[str, Any]) -> tuple[bool, str | None]:
    if not ALERT_INDEX_URL:
        return False, "ALERT_INDEX_URL is not configured"

    try:
        _post_json(f"{ALERT_INDEX_URL}/alerts", alert)
    except (HTTPError, URLError, TimeoutError, OSError) as exc:
        return False, str(exc)
    return True, None


def _post_json(url: str, payload: dict[str, Any]) -> dict[str, Any]:
    body = json.dumps(payload).encode("utf-8")
    request = Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urlopen(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
        return json.loads(response.read().decode("utf-8"))
