#!/usr/bin/env python
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import argparse
import json
import os
from urllib.request import Request, urlopen


DEFAULT_URL = "http://localhost:8091"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Smoke test inference orchestrator.")
    parser.add_argument(
        "--url",
        default=os.environ.get("INFERENCE_ORCHESTRATOR_URL", DEFAULT_URL),
        help=f"Inference orchestrator base URL. Defaults to {DEFAULT_URL}.",
    )
    parser.add_argument(
        "--symbol",
        default=os.environ.get("SYMBOL", "BTCUSDT"),
        help="Symbol to generate sample candles for.",
    )
    return parser.parse_args()


def build_records(symbol: str) -> list[dict[str, object]]:
    start = datetime(2026, 1, 1, tzinfo=timezone.utc)
    records: list[dict[str, object]] = []
    for index in range(30):
        close = 93000.0 + index * 12.0
        records.append(
            {
                "timestamp": (start + timedelta(hours=index)).isoformat().replace("+00:00", "Z"),
                "symbol": symbol,
                "open": close - 18.0,
                "high": close + 85.0,
                "low": close - 95.0,
                "close": close,
                "volume": 100.0 + index,
            }
        )
    return records


def request_json(url: str, method: str = "GET", payload: dict[str, object] | None = None) -> dict[str, object]:
    data = json.dumps(payload).encode() if payload is not None else None
    request = Request(url, data=data, headers={"Content-Type": "application/json"}, method=method)
    with urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode())


def main() -> None:
    args = parse_args()
    base_url = args.url.rstrip("/")
    records = build_records(args.symbol.upper())
    result = request_json(f"{base_url}/orchestrate/predict", "POST", {"records": records})
    alerts = request_json(f"{base_url}/alerts")
    decisions = request_json(f"{base_url}/governance/decisions")
    integrity = request_json(f"{base_url}/governance/integrity")
    if not result.get("decision_id") or not decisions.get("count"):
        raise RuntimeError("Governance decision telemetry was not persisted.")
    if not integrity.get("valid"):
        raise RuntimeError(f"Governance decision hash chain is invalid: {integrity}")
    result["alert_history"] = alerts
    result["governance_history"] = decisions
    result["governance_integrity"] = integrity
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
