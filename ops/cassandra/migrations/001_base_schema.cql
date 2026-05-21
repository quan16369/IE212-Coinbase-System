CREATE KEYSPACE IF NOT EXISTS coinbase
WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};

CREATE TABLE IF NOT EXISTS coinbase.prices (
    product_id TEXT,
    time TIMESTAMP,
    price DOUBLE,
    PRIMARY KEY (product_id, time)
) WITH CLUSTERING ORDER BY (time DESC);

CREATE TABLE IF NOT EXISTS coinbase.candles (
    product_id TEXT,
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    open DOUBLE,
    high DOUBLE,
    low DOUBLE,
    close DOUBLE,
    volume DOUBLE,
    candle_size TEXT,
    channel TEXT,
    PRIMARY KEY (product_id, start_time)
) WITH CLUSTERING ORDER BY (start_time DESC);
