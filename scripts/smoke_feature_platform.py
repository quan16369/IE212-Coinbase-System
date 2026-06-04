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
            for index in range(4)
        ]
    }

    try:
        ingest = request("POST", "/features/ingest", payload)
        latest = request("GET", "/features/latest/BTCUSDT")
    except urllib.error.URLError as exc:
        print(f"Could not reach feature platform at {BASE_URL}: {exc}", file=sys.stderr)
        return 1

    print(json.dumps({"ingest": ingest, "latest": latest}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
