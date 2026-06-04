from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request


def post_json(url: str, payload: dict) -> dict:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.loads(response.read().decode("utf-8"))


def main() -> int:
    url = os.environ.get("DATA_VALIDATION_URL", "http://localhost:8089/validate")
    valid_payload = {
        "records": [
            {
                "timestamp": "2024-01-01T00:00:00Z",
                "symbol": "BTCUSDT",
                "open": 42000.0,
                "high": 42100.0,
                "low": 41900.0,
                "close": 42050.0,
                "volume": 12.5,
            },
            {
                "timestamp": "2024-01-01T00:05:00Z",
                "symbol": "BTCUSDT",
                "open": 42050.0,
                "high": 42200.0,
                "low": 42000.0,
                "close": 42150.0,
                "volume": 8.0,
            },
        ]
    }
    mixed_payload = {
        "records": [
            valid_payload["records"][0],
            {
                "timestamp": "2024-01-01T00:05:00Z",
                "symbol": "BTCUSDT",
                "open": 42050.0,
                "high": 42020.0,
                "low": 42000.0,
                "close": 42150.0,
                "volume": 8.0,
            },
        ]
    }

    try:
        valid_result = post_json(url, valid_payload)
        mixed_result = post_json(url, mixed_payload)
    except urllib.error.URLError as exc:
        print(f"Could not reach data validation service at {url}: {exc}", file=sys.stderr)
        return 1

    print("Valid payload result:")
    print(json.dumps(valid_result, indent=2))
    if not valid_result.get("valid"):
        print("Expected validation smoke payload to be valid.", file=sys.stderr)
        return 1

    print("Mixed payload result:")
    print(json.dumps(mixed_result, indent=2))
    if mixed_result.get("valid"):
        print("Expected mixed validation smoke payload to be invalid.", file=sys.stderr)
        return 1
    if mixed_result.get("accepted_count") != 1 or mixed_result.get("rejected_count") != 1:
        print("Expected mixed payload to route one record to each target.", file=sys.stderr)
        return 1
    if mixed_result.get("validated_target") != "validated-candles":
        print("Unexpected validated target.", file=sys.stderr)
        return 1
    if mixed_result.get("quality_target") != "quality-candles":
        print("Unexpected quality target.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
