# Apache Paimon Integration Guide

## Overview

Apache Paimon is a streaming data lake storage that supports both batch and streaming operations. It provides ACID transactions, time travel queries, and schema evolution while being fully compatible with Spark and Flink.

## Why Paimon?

### Benefits

1. **Unified Batch and Streaming**
   - Single storage layer for both real-time and historical data
   - No need to maintain separate batch and streaming systems
   - Consistent data view across all analytics

2. **ACID Transactions**
   - Guaranteed data consistency
   - Snapshot isolation
   - Safe concurrent reads and writes

3. **Time Travel**
   - Query data at any historical snapshot
   - Reproducible ML training
   - Debug data issues
   - Regulatory compliance

4. **Storage Efficiency**
   - 50-70% storage savings vs raw data
   - Automatic compaction
   - Columnar storage (Parquet)
   - Z-ordering for better query performance

5. **Schema Evolution**
   - Add/remove columns without rewriting data
   - Rename columns
   - Change column types (compatible changes)

## Architecture

### Data Flow

```
Coinbase WebSocket
    ↓
Kafka (coin-data topic)
    ↓
Spark Structured Streaming
    ↓
┌─────────────────────┬───────────────────┐
│   Apache Paimon     │    Cassandra      │
│  (S3/MinIO)         │  (Hot data)       │
│  - Historical data  │  - Recent data    │
│  - Time travel      │  - Fast queries   │
│  - ML training      │  - Grafana source │
└─────────────────────┴───────────────────┘
```

### Storage Layout

```
s3://ie212-coinbase-data/paimon/
├── crypto_db.db/
│   ├── raw_prices/                    # Raw tick data
│   │   ├── product_id=BTC-USD/
│   │   │   ├── dt=2024-01-01/
│   │   │   │   ├── data-00000.parquet
│   │   │   │   ├── data-00001.parquet
│   │   │   │   └── ...
│   │   │   └── dt=2024-01-02/
│   │   ├── product_id=ETH-USD/
│   │   └── ...
│   │
│   ├── ohlcv_1m/                      # 1-minute OHLCV
│   │   ├── product_id=BTC-USD/
│   │   └── ...
│   │
│   ├── ml_features/                   # ML training features
│   │   ├── product_id=BTC-USD/
│   │   └── ...
│   │
│   └── predictions/                   # Model predictions
│       ├── product_id=BTC-USD/
│       └── ...
```

## Table Schemas

### 1. raw_prices

Raw cryptocurrency price data from Coinbase.

```sql
CREATE TABLE IF NOT EXISTS paimon.crypto_db.raw_prices (
    product_id STRING,        -- e.g., "BTC-USD"
    timestamp TIMESTAMP,      -- Trade timestamp
    price DOUBLE,            -- Trade price
    size DOUBLE,             -- Trade size
    side STRING,             -- "buy" or "sell"
    bid DOUBLE,              -- Best bid price
    ask DOUBLE,              -- Best ask price
    volume DOUBLE,           -- 24h volume
    market_cap DOUBLE,       -- Market capitalization
    event_time TIMESTAMP,    -- Event occurrence time
    processing_time TIMESTAMP, -- Processing time
    dt STRING                -- Partition column (YYYY-MM-DD)
) PARTITIONED BY (product_id, dt)
TBLPROPERTIES (
    'primary-key' = 'product_id,timestamp',
    'bucket' = '8',
    'write-mode' = 'append-only',
    'snapshot.time-retained' = '7d',
    'compaction.min-file-num' = '5'
);
```

**Properties:**
- **Append-only**: Fast inserts, no updates/deletes
- **8 buckets**: Parallel processing
- **7-day retention**: Automatic cleanup of old snapshots
- **Compaction**: Automatic file merging for better query performance

### 2. ohlcv_1m

1-minute OHLCV (Open, High, Low, Close, Volume) aggregations.

```sql
CREATE TABLE IF NOT EXISTS paimon.crypto_db.ohlcv_1m (
    product_id STRING,
    window_start TIMESTAMP,   -- Window start time
    window_end TIMESTAMP,     -- Window end time
    open DOUBLE,             -- Opening price
    high DOUBLE,             -- Highest price
    low DOUBLE,              -- Lowest price
    close DOUBLE,            -- Closing price
    volume DOUBLE,           -- Total volume
    trade_count BIGINT,      -- Number of trades
    vwap DOUBLE,             -- Volume-weighted average price
    dt STRING                -- Partition column
) PARTITIONED BY (product_id, dt)
TBLPROPERTIES (
    'primary-key' = 'product_id,window_start',
    'bucket' = '4',
    'merge-engine' = 'deduplicate',
    'changelog-mode' = 'upsert'
);
```

**Properties:**
- **Upsert mode**: Late-arriving data handled automatically
- **Deduplication**: Ensures data quality
- **4 buckets**: Balanced parallelism

### 3. ml_features

Machine learning training features with technical indicators.

```sql
CREATE TABLE IF NOT EXISTS paimon.crypto_db.ml_features (
    product_id STRING,
    timestamp TIMESTAMP,
    
    -- Price and volume
    close DOUBLE,
    volume DOUBLE,
    
    -- Technical indicators
    rsi_14 DOUBLE,           -- Relative Strength Index (14 periods)
    macd DOUBLE,             -- MACD line
    macd_signal DOUBLE,      -- MACD signal line
    macd_hist DOUBLE,        -- MACD histogram
    bb_upper DOUBLE,         -- Bollinger Band upper
    bb_middle DOUBLE,        -- Bollinger Band middle
    bb_lower DOUBLE,         -- Bollinger Band lower
    atr_14 DOUBLE,           -- Average True Range (14 periods)
    obv DOUBLE,              -- On-Balance Volume
    volatility DOUBLE,       -- Historical volatility
    returns_1h DOUBLE,       -- 1-hour returns
    returns_24h DOUBLE,      -- 24-hour returns
    volume_ma_24h DOUBLE,    -- 24-hour volume moving average
    price_momentum DOUBLE,   -- Price momentum
    dt STRING
) PARTITIONED BY (product_id, dt)
TBLPROPERTIES (
    'primary-key' = 'product_id,timestamp',
    'bucket' = '4',
    'merge-engine' = 'deduplicate'
);
```

**Usage:**
- Training data for ML models
- Feature engineering pipeline
- Backtesting and evaluation

### 4. predictions

Model predictions with metadata for tracking and evaluation.

```sql
CREATE TABLE IF NOT EXISTS paimon.crypto_db.predictions (
    product_id STRING,
    prediction_time TIMESTAMP,    -- When prediction was made
    model_name STRING,            -- Model identifier
    model_version STRING,         -- Model version
    horizon STRING,               -- "1h", "3h", "6h", "12h"
    predicted_price DOUBLE,       -- Predicted price
    confidence_lower DOUBLE,      -- Lower confidence bound
    confidence_upper DOUBLE,      -- Upper confidence bound
    actual_price DOUBLE,          -- Actual price (filled later)
    error DOUBLE,                 -- Prediction error
    mae DOUBLE,                   -- Mean absolute error
    mse DOUBLE,                   -- Mean squared error
    dt STRING
) PARTITIONED BY (product_id, dt)
TBLPROPERTIES (
    'primary-key' = 'product_id,prediction_time,model_name,horizon',
    'bucket' = '4',
    'merge-engine' = 'deduplicate'
);
```

**Benefits:**
- Track model performance over time
- Compare different models
- A/B testing support
- Prediction history for auditing

## Usage Examples

### Python API

```python
from paimon_processor import PaimonDataLake

# Initialize
paimon = PaimonDataLake("s3a://ie212-coinbase-data/paimon")

# Create tables
paimon.create_price_table()
paimon.create_ohlcv_table()
paimon.create_features_table()
paimon.create_predictions_table()

# Batch read
df = paimon.read_batch(
    table_name="ml_features",
    start_date="2024-01-01",
    end_date="2024-01-31"
)

# Time travel query
historical_df = paimon.time_travel_query(
    table_name="ml_features",
    timestamp="2024-01-15T12:00:00Z"
)

# Streaming write
query = paimon.write_streaming_data(
    stream_df=kafka_stream,
    table_name="raw_prices",
    checkpoint_location="s3a://checkpoints/raw_prices"
)

# Compaction
paimon.compact_table("raw_prices")

# Cleanup old snapshots
paimon.cleanup_old_snapshots("raw_prices", retain_days=7)
```

### SQL Queries

```sql
-- Query latest data
SELECT * FROM paimon.crypto_db.ml_features
WHERE product_id = 'BTC-USD'
  AND dt >= '2024-01-01'
ORDER BY timestamp DESC
LIMIT 100;

-- Time travel to specific snapshot
SELECT * FROM paimon.crypto_db.ml_features 
FOR SYSTEM_TIME AS OF TIMESTAMP '2024-01-15 12:00:00';

-- Aggregation query
SELECT 
    product_id,
    DATE(timestamp) as date,
    AVG(close) as avg_price,
    MAX(close) as max_price,
    MIN(close) as min_price,
    SUM(volume) as total_volume
FROM paimon.crypto_db.ohlcv_1m
WHERE dt >= '2024-01-01'
GROUP BY product_id, DATE(timestamp);

-- Join predictions with actuals
SELECT 
    p.product_id,
    p.prediction_time,
    p.model_name,
    p.predicted_price,
    p.actual_price,
    ABS(p.predicted_price - p.actual_price) as error
FROM paimon.crypto_db.predictions p
WHERE p.dt = '2024-01-15'
  AND p.actual_price IS NOT NULL
ORDER BY error ASC;
```

## Operations

### Deployment

```bash
# Start Spark with Paimon
docker-compose up -d spark-processor

# Initialize tables
docker-compose exec spark-processor python paimon_processor.py

# Check logs
docker-compose logs -f spark-processor

# Access Spark UI
open http://localhost:4040
```

### Monitoring

```python
# Get table statistics
stats = paimon.get_table_statistics("raw_prices")
stats.show()

# Output:
# +-------------+--------------------+--------+-------+----------+
# | snapshot_id |       commit_time  | schema | files | records  |
# +-------------+--------------------+--------+-------+----------+
# |      12345  | 2024-01-15 12:00:00|     1  |   245 | 1500000  |
# |      12346  | 2024-01-15 13:00:00|     1  |   250 | 1520000  |
# +-------------+--------------------+--------+-------+----------+
```

### Maintenance

```bash
# Compact tables (run daily)
docker-compose exec spark-processor python -c "
from paimon_processor import PaimonDataLake
paimon = PaimonDataLake()
paimon.compact_table('raw_prices')
paimon.compact_table('ohlcv_1m')
paimon.compact_table('ml_features')
"

# Cleanup old snapshots (run weekly)
docker-compose exec spark-processor python -c "
from paimon_processor import PaimonDataLake
paimon = PaimonDataLake()
paimon.cleanup_old_snapshots('raw_prices', retain_days=7)
paimon.cleanup_old_snapshots('ohlcv_1m', retain_days=30)
"
```

## Performance Tuning

### Bucket Configuration

```python
# More buckets = better parallelism but more small files
# Fewer buckets = fewer files but less parallelism

# For high-volume tables (raw_prices)
'bucket' = '8'

# For medium-volume tables (ohlcv_1m, ml_features)
'bucket' = '4'

# For low-volume tables (predictions)
'bucket' = '2'
```

### Compaction Strategy

```python
# Z-ordering for better query performance
paimon.spark.sql("""
    CALL paimon.sys.compact(
        table => 'crypto_db.raw_prices',
        order_strategy => 'zorder',
        order_columns => 'timestamp,product_id'
    )
""")
```

### Partition Pruning

```python
# Efficient query (partition pruning)
df = spark.sql("""
    SELECT * FROM paimon.crypto_db.ml_features
    WHERE product_id = 'BTC-USD'  -- Partition pruning
      AND dt >= '2024-01-01'       -- Partition pruning
      AND timestamp >= '2024-01-01 00:00:00'
""")

# Inefficient query (no partition pruning)
df = spark.sql("""
    SELECT * FROM paimon.crypto_db.ml_features
    WHERE timestamp >= '2024-01-01 00:00:00'  -- Scans all partitions
""")
```

## Troubleshooting

### Issue: Out of Memory

```bash
# Increase Spark memory
docker-compose exec spark-processor spark-submit \
    --driver-memory 4g \
    --executor-memory 8g \
    paimon_processor.py
```

### Issue: Slow Queries

```python
# 1. Check table statistics
stats = paimon.get_table_statistics("ml_features")

# 2. Compact table
paimon.compact_table("ml_features")

# 3. Add more buckets (requires table recreation)
# Edit table properties and recreate
```

### Issue: Too Many Small Files

```python
# Increase compaction frequency
'compaction.min-file-num' = '3'  # Default: 5
'compaction.max-file-num' = '30' # Default: 50
```

## References

- [Apache Paimon Documentation](https://paimon.apache.org/)
- [Paimon Spark Integration](https://paimon.apache.org/docs/master/engines/spark/)
- [Table Properties Reference](https://paimon.apache.org/docs/master/maintenance/configurations/)
