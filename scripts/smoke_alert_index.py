#!/usr/bin/env python
from __future__ import annotations

from datetime import datetime, timezone
import argparse
import json
import os
from uuid import uuid4
from urllib.request import Request, urlopen


DEFAULT_URL = "http://localhost:8093"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Smoke test alert index.")
    parser.add_argument(
        "--url",
        default=os.environ.get("ALERT_INDEX_URL", DEFAULT_URL),
        help=f"Alert index base URL. Defaults to {DEFAULT_URL}.",
    )
    return parser.parse_args()


def request_json(url: str, method: str = "GET", payload: dict[str, object] | None = None) -> dict[str, object]:
    data = json.dumps(payload).encode() if payload is not None else None
    request = Request(url, data=data, headers={"Content-Type": "application/json"}, method=method)
    with urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode())


def main() -> None:
    args = parse_args()
    base_url = args.url.rstrip("/")
    alert = {
        "id": str(uuid4()),
        "created_at": datetime.now(timezone.utc).isoformat(),
        "symbol": "BTCUSDT",
        "severity": "warning",
        "rule": "smoke_test",
        "threshold": 0.005,
        "predicted_return": 0.01,
        "predicted_close": 93930.0,
        "target_time": "2026-01-01T04:00:00Z",
        "message": "smoke alert",
    }
    stored = request_json(f"{base_url}/alerts", "POST", alert)
    listed = request_json(f"{base_url}/alerts?symbol=BTCUSDT")
    print(json.dumps({"stored": stored, "listed": listed}, indent=2))


if __name__ == "__main__":
    main()
