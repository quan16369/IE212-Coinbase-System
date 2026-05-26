#!/usr/bin/env python
from __future__ import annotations

import argparse
import json
import os
import socket
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import pandas as pd


DEFAULT_URL = "http://localhost:3001/predict"
DEFAULT_ROWS = 300


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Test BentoML prediction with recent OHLCV CSV rows.")
    parser.add_argument(
        "--data",
        default=os.getenv("DATA", os.getenv("MLOPS_TEST_CSV", "")),
        help="OHLCV CSV path. Can also be passed with DATA=/path/to/file.csv.",
    )
    parser.add_argument(
        "--url",
        default=os.getenv("MLOPS_PREDICT_URL", DEFAULT_URL),
        help=f"BentoML predict endpoint. Defaults to {DEFAULT_URL}.",
    )
    parser.add_argument(
        "--rows",
        type=int,
        default=int(os.getenv("MLOPS_TEST_ROWS", str(DEFAULT_ROWS))),
        help=f"Number of recent CSV rows to send. Defaults to {DEFAULT_ROWS}.",
    )
    return parser.parse_args()


def load_records(csv_path: Path, rows: int) -> list[dict[str, object]]:
    if rows <= 0:
        raise ValueError("--rows must be greater than zero")

    frame = pd.read_csv(csv_path).tail(rows)
    if frame.empty:
        raise ValueError(f"No rows found in {csv_path}")

    return frame.where(pd.notnull(frame), None).to_dict(orient="records")


def call_predict(url: str, records: list[dict[str, object]]) -> dict[str, object]:
    request = Request(
        url,
        data=json.dumps({"records": records}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode())


def main() -> None:
    args = parse_args()
    if not args.data:
        raise SystemExit("Missing data path. Use DATA=/path/to/ohlcv.csv make mlops-test-predict.")

    csv_path = Path(args.data)
    if not csv_path.is_file():
        raise SystemExit(f"CSV not found: {csv_path}")

    try:
        result = call_predict(args.url, load_records(csv_path, args.rows))
    except HTTPError as exc:
        body = exc.read().decode(errors="replace")
        raise SystemExit(f"Prediction request failed with HTTP {exc.code}: {body}") from exc
    except URLError as exc:
        raise SystemExit(f"Could not reach BentoML at {args.url}: {exc.reason}") from exc
    except (TimeoutError, socket.timeout) as exc:
        raise SystemExit(
            f"BentoML did not answer within 30s at {args.url}. Check `docker compose --env-file .env ps` "
            "and BentoML logs before retrying."
        ) from exc

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
