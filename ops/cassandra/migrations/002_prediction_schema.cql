CREATE TABLE IF NOT EXISTS coinbase.predictions (
    product_id TEXT,
    model_name TEXT,
    prediction_time TIMESTAMP,
    target_time TIMESTAMP,
    predicted_price DOUBLE,
    confidence_lower DOUBLE,
    confidence_upper DOUBLE,
    model_version TEXT,
    metadata TEXT,
    PRIMARY KEY ((product_id, model_name), prediction_time, target_time)
) WITH CLUSTERING ORDER BY (prediction_time DESC, target_time ASC);

CREATE TABLE IF NOT EXISTS coinbase.predictions_by_horizon (
    product_id TEXT,
    model_name TEXT,
    prediction_horizon INT,
    prediction_time TIMESTAMP,
    target_time TIMESTAMP,
    predicted_price DOUBLE,
    confidence_lower DOUBLE,
    confidence_upper DOUBLE,
    PRIMARY KEY ((product_id, model_name, prediction_horizon), prediction_time)
) WITH CLUSTERING ORDER BY (prediction_time DESC);

CREATE TABLE IF NOT EXISTS coinbase.model_metrics (
    product_id TEXT,
    model_name TEXT,
    evaluation_time TIMESTAMP,
    horizon INT,
    mae DOUBLE,
    rmse DOUBLE,
    mape DOUBLE,
    directional_accuracy DOUBLE,
    sample_count INT,
    PRIMARY KEY ((product_id, model_name), evaluation_time, horizon)
) WITH CLUSTERING ORDER BY (evaluation_time DESC, horizon ASC);
