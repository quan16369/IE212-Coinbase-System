from __future__ import annotations

import json
import os
from pathlib import Path

import pandas as pd
import psycopg

from mlops.train import main as train_main


def export_training_csv() -> Path:
    dsn = os.environ["FEATURE_POSTGRES_DSN"]
    symbol = os.getenv("MLOPS_TRAINING_SYMBOL", "BTC-USD").upper()
    output = Path(os.getenv("MLOPS_TRAINING_CSV", "/tmp/feature-store-training.csv"))
    rows: list[dict] = []
    with psycopg.connect(dsn) as connection, connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT payload
            FROM feature_records
            WHERE symbol = %s
            ORDER BY timestamp ASC
            """,
            (symbol,),
        )
        for (payload,) in cursor.fetchall():
            if isinstance(payload, str):
                payload = json.loads(payload)
            rows.append({key: payload[key] for key in ("timestamp", "open", "high", "low", "close", "volume")})
    if not rows:
        raise RuntimeError(f"No feature-store records found for {symbol}")
    output.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(output, index=False)
    return output


if __name__ == "__main__":
    export_training_csv()
    train_main()
