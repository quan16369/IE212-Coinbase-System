from __future__ import annotations

from datetime import datetime
import json
import os
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field, field_validator


INDEX_PATH = Path(os.environ.get("ALERT_INDEX_PATH", "/data/alerts.jsonl"))
MAX_RESULTS = int(os.environ.get("ALERT_INDEX_MAX_RESULTS", "200"))

app = FastAPI(title="Coinbase Alert Index", version="0.1.0")


class AlertRecord(BaseModel):
    id: str = Field(min_length=1)
    created_at: datetime
    symbol: str = Field(min_length=1)
    severity: str = "warning"
    rule: str
    threshold: float
    predicted_return: float
    predicted_close: float | None = None
    target_time: str | None = None
    message: str

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
def config() -> dict[str, str | int]:
    return {
        "index_path": str(INDEX_PATH),
        "max_results": MAX_RESULTS,
    }


@app.post("/alerts")
def create_alert(alert: AlertRecord) -> dict[str, Any]:
    records = _read_records()
    deduped = [item for item in records if item.get("id") != alert.id]
    deduped.append(alert.model_dump(mode="json"))
    _write_records(deduped)
    return {"stored": True, "alert": alert, "count": len(deduped)}


@app.get("/alerts")
def list_alerts(
    symbol: str | None = None,
    limit: int = Query(default=50, ge=1, le=MAX_RESULTS),
) -> dict[str, Any]:
    records = _read_records()
    if symbol:
        normalized = symbol.strip().upper()
        records = [item for item in records if item.get("symbol") == normalized]
    return {
        "count": len(records),
        "alerts": records[-limit:],
    }


@app.get("/alerts/{alert_id}")
def get_alert(alert_id: str) -> dict[str, Any]:
    for record in _read_records():
        if record.get("id") == alert_id:
            return record
    raise HTTPException(status_code=404, detail=f"Alert not found: {alert_id}")


def _read_records() -> list[dict[str, Any]]:
    if not INDEX_PATH.exists():
        return []
    records: list[dict[str, Any]] = []
    with INDEX_PATH.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    return records[-MAX_RESULTS:]


def _write_records(records: list[dict[str, Any]]) -> None:
    INDEX_PATH.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile("w", encoding="utf-8", dir=INDEX_PATH.parent, delete=False) as handle:
        tmp_path = Path(handle.name)
        for record in records[-MAX_RESULTS:]:
            handle.write(json.dumps(record, sort_keys=True))
            handle.write("\n")
    tmp_path.replace(INDEX_PATH)
