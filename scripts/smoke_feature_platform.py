from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
import os
import sys
import urllib.error
import urllib.request


BASE_URL = os.environ.get("FEATURE_PLATFORM_URL", "http://localhost:8090").rstrip("/")


def request(method: str, path: str, payload: dict | None = None) -> dict:
    data = None
    headers = {}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(f"{BASE_URL}{path}", data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


def main() -> int:
    start = datetime(2026, 1, 1, tzinfo=timezone.utc)
    payload = {
        "source": "smoke-test",
        "data_version": "smoke-2026-01-01",
        "records": [
            {
                "timestamp": (start + timedelta(minutes=5 * index)).isoformat(),
                "symbol": "BTCUSDT",
                "open": 93000 + index * 10,
                "high": 93100 + index * 10,
                "low": 92900 + index * 10,
                "close": 93050 + index * 12,
                "volume": 100 + index,
            }
            for index in range(36)
        ]
    }

    try:
        status = request("GET", "/store/status")
        ingest = request("POST", "/features/ingest", payload)
        latest = request("GET", "/features/latest/BTCUSDT")
        history = request("GET", "/features/history/BTCUSDT?limit=5")
        retraining = request("GET", "/feedback/retraining-signal/BTCUSDT")
    except urllib.error.URLError as exc:
        print(f"Could not reach feature platform at {BASE_URL}: {exc}", file=sys.stderr)
        return 1

    if ingest["online_store"] not in {"memory", "redis"}:
        print(f"Unexpected online store: {ingest['online_store']}", file=sys.stderr)
        return 1
    if ingest["offline_store"] not in {"memory", "postgres"}:
        print(f"Unexpected offline store: {ingest['offline_store']}", file=sys.stderr)
        return 1
    if ingest["data_version"] != "smoke-2026-01-01":
        print(f"Unexpected data version: {ingest['data_version']}", file=sys.stderr)
        return 1

    print(
        json.dumps(
            {
                "status": status,
                "ingest": ingest,
                "latest": latest,
                "history_tail": history,
                "retraining_signal": retraining,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
