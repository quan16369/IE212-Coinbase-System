from __future__ import annotations

from datetime import datetime
import json
import os
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field, field_validator


BENTO_PREDICT_URL = os.environ.get(
    "BENTO_PREDICT_URL",
    "http://bento-price-predictor.app.svc.cluster.local/predict",
)
FEATURE_PLATFORM_URL = os.environ.get(
    "FEATURE_PLATFORM_URL",
    "http://feature-platform.feature-platform.svc.cluster.local",
).rstrip("/")
ALERT_RULE_ENGINE_URL = os.environ.get("ALERT_RULE_ENGINE_URL", "").rstrip("/")
HTTP_TIMEOUT_SECONDS = float(os.environ.get("ORCHESTRATOR_HTTP_TIMEOUT_SECONDS", "30"))

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
        "alert_rule_engine_url": ALERT_RULE_ENGINE_URL,
    }


@app.post("/orchestrate/predict")
def predict(payload: PredictRequest) -> dict[str, Any]:
    records = [record.model_dump(mode="json") for record in payload.records]
    symbol = records[-1]["symbol"]

    prediction = _post_json(BENTO_PREDICT_URL, {"records": records})
    latest_feature = _get_latest_feature(symbol)
    alert_evaluation = _evaluate_alert(symbol, prediction, latest_feature)

    return {
        "symbol": symbol,
        "feature_context": latest_feature,
        "prediction": prediction,
        "alert_evaluation": alert_evaluation,
        "sources": {
            "bento_predict_url": BENTO_PREDICT_URL,
            "feature_platform_url": FEATURE_PLATFORM_URL,
            "alert_rule_engine_url": ALERT_RULE_ENGINE_URL,
        },
    }


@app.get("/orchestrate/latest/{symbol}")
def latest(symbol: str) -> dict[str, Any]:
    normalized = symbol.strip().upper()
    latest_feature = _get_latest_feature(normalized)
    if latest_feature is None:
        raise HTTPException(status_code=404, detail=f"No features for symbol {normalized}")
    return latest_feature


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


def _evaluate_alert(symbol: str, prediction: dict[str, Any], feature_context: dict[str, Any] | None) -> dict[str, Any] | None:
    if not ALERT_RULE_ENGINE_URL:
        return None
    return _post_json(
        f"{ALERT_RULE_ENGINE_URL}/alerts/evaluate",
        {
            "symbol": symbol,
            "prediction": prediction,
            "feature_context": feature_context,
        },
    )
