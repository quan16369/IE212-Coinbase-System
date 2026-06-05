from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request


def main() -> int:
    base_url = os.environ.get("FEATURE_PLATFORM_URL", "http://localhost:8090").rstrip("/")
    symbol = os.environ.get("FEATURE_DRIFT_SYMBOL", "BTCUSDT").strip().upper()
    fail_on_drift = os.environ.get("FEATURE_DRIFT_FAIL_ON_DRIFT", "false").lower() == "true"
    url = f"{base_url}/feedback/retraining-signal/{symbol}"

    try:
        with urllib.request.urlopen(url, timeout=15) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        print(f"Feature drift check failed with HTTP {exc.code}: {detail}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"Could not reach feature platform at {url}: {exc}", file=sys.stderr)
        return 1

    print(json.dumps(payload, indent=2))
    if fail_on_drift and payload.get("should_retrain"):
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
