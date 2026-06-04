#!/usr/bin/env python
from __future__ import annotations

import argparse
import json
import os
from urllib.request import Request, urlopen


DEFAULT_URL = "http://localhost:8092"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Smoke test alert rule engine.")
    parser.add_argument(
        "--url",
        default=os.environ.get("ALERT_RULE_ENGINE_URL", DEFAULT_URL),
        help=f"Alert rule engine base URL. Defaults to {DEFAULT_URL}.",
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
    payload = {
        "symbol": "BTCUSDT",
        "prediction": {
            "prediction": {
                "target_time": "2026-01-01T04:00:00Z",
                "current_close": 93000.0,
                "predicted_return": 0.01,
                "predicted_close": 93930.0,
            }
        },
        "feature_context": {"close": 93000.0},
    }
    result = request_json(f"{base_url}/alerts/evaluate", "POST", payload)
    alerts = request_json(f"{base_url}/alerts")
    print(json.dumps({"evaluation": result, "alerts": alerts}, indent=2))


if __name__ == "__main__":
    main()
