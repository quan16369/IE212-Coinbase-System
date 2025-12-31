# Apache Paimon Integration for Crypto Pipeline
# Paimon provides a streaming data lakehouse with:
# - Real-time streaming updates
# - ACID transactions
# - Time travel queries
# - Schema evolution
# - Both batch and streaming reads

from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.types import *
import logging

logger = logging.getLogger(__name__)


class PaimonDataLake:
    """
    Apache Paimon integration for cryptocurrency data lakehouse.
    
    Benefits over Cassandra alone:
    - Unified batch and streaming
    - Time travel capabilities (query historical data)
    - Better compression and storage efficiency
    - ACID transactions
    - Schema evolution
    """
    
    def __init__(self, warehouse_path: str = "s3a://crypto-pipeline-data-lake/paimon"):
        """
        Initialize Paimon data lakehouse
        
        Args:
            warehouse_path: S3 path for Paimon warehouse
        """
        self.warehouse_path = warehouse_path
        self.spark = self._create_spark_session()
        
    def _create_spark_session(self) -> SparkSession:
        """Create Spark session with Paimon catalog"""
        spark = SparkSession.builder \
            .appName("CryptoPaimonLakehouse") \
            .config("spark.sql.catalog.paimon", "org.apache.paimon.spark.SparkCatalog") \
            .config("spark.sql.catalog.paimon.warehouse", self.warehouse_path) \
            .config("spark.sql.extensions", "org.apache.paimon.spark.extensions.PaimonSparkSessionExtensions") \
            .config("spark.sql.adaptive.enabled", "true") \
            .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
            .getOrCreate()
        
        logger.info(f"Initialized Paimon lakehouse at {self.warehouse_path}")
        return spark
    
    def create_price_table(self):
        """Create Paimon table for raw cryptocurrency prices"""
        self.spark.sql("""
            CREATE TABLE IF NOT EXISTS paimon.crypto_db.raw_prices (
                product_id STRING,
                timestamp TIMESTAMP,
                price DOUBLE,
                size DOUBLE,
                side STRING,
                bid DOUBLE,
                ask DOUBLE,
                volume DOUBLE,
                market_cap DOUBLE,
                event_time TIMESTAMP,
                processing_time TIMESTAMP,
                dt STRING
            ) PARTITIONED BY (product_id, dt)
            TBLPROPERTIES (
                'primary-key' = 'product_id,timestamp',
                'bucket' = '8',
                'write-mode' = 'append-only',
                'changelog-mode' = 'append-only',
                'snapshot.time-retained' = '7d',
                'snapshot.num-retained.min' = '10',
                'snapshot.num-retained.max' = '100',
                'compaction.min-file-num' = '5',
                'compaction.max-file-num' = '50'
            )
        """)
        logger.info("Created raw_prices table")
    
    def create_ohlcv_table(self):
        """Create Paimon table for aggregated OHLCV data"""
        self.spark.sql("""
            CREATE TABLE IF NOT EXISTS paimon.crypto_db.ohlcv_1m (
                product_id STRING,
                window_start TIMESTAMP,
                window_end TIMESTAMP,
                open DOUBLE,
                high DOUBLE,
                low DOUBLE,
                close DOUBLE,
                volume DOUBLE,
                trade_count BIGINT,
                vwap DOUBLE,
                dt STRING
            ) PARTITIONED BY (product_id, dt)
            TBLPROPERTIES (
                'primary-key' = 'product_id,window_start',
                'bucket' = '4',
                'merge-engine' = 'deduplicate',
                'changelog-mode' = 'upsert',
                'snapshot.time-retained' = '30d'
            )
        """)
        logger.info("Created ohlcv_1m table")
    
    def create_features_table(self):
        """Create Paimon table for ML features"""
        self.spark.sql("""
            CREATE TABLE IF NOT EXISTS paimon.crypto_db.ml_features (
                product_id STRING,
                timestamp TIMESTAMP,
                close DOUBLE,
                volume DOUBLE,
                rsi_14 DOUBLE,
                macd DOUBLE,
                macd_signal DOUBLE,
                macd_hist DOUBLE,
                bb_upper DOUBLE,
                bb_middle DOUBLE,
                bb_lower DOUBLE,
                atr_14 DOUBLE,
                obv DOUBLE,
                volatility DOUBLE,
                returns_1h DOUBLE,
                returns_24h DOUBLE,
                volume_ma_24h DOUBLE,
                price_momentum DOUBLE,
                dt STRING
            ) PARTITIONED BY (product_id, dt)
            TBLPROPERTIES (
                'primary-key' = 'product_id,timestamp',
                'bucket' = '4',
                'merge-engine' = 'deduplicate',
                'changelog-mode' = 'upsert'
            )
        """)
        logger.info("Created ml_features table")
    
    def create_predictions_table(self):
        """Create Paimon table for model predictions"""
        self.spark.sql("""
            CREATE TABLE IF NOT EXISTS paimon.crypto_db.predictions (
                product_id STRING,
                prediction_time TIMESTAMP,
                model_name STRING,
                model_version STRING,
                horizon STRING,
                predicted_price DOUBLE,
                confidence_lower DOUBLE,
                confidence_upper DOUBLE,
                actual_price DOUBLE,
                error DOUBLE,
                mae DOUBLE,
                mse DOUBLE,
                dt STRING
            ) PARTITIONED BY (product_id, dt)
            TBLPROPERTIES (
                'primary-key' = 'product_id,prediction_time,model_name,horizon',
                'bucket' = '4',
                'merge-engine' = 'deduplicate'
            )
        """)
        logger.info("Created predictions table")
    
    def write_streaming_data(self, stream_df, table_name: str, checkpoint_location: str):
        """
        Write streaming data to Paimon table
        
        Args:
            stream_df: Streaming DataFrame from Kafka
            table_name: Target Paimon table
            checkpoint_location: Checkpoint location for streaming query
        """
        query = stream_df.writeStream \
            .format("paimon") \
            .option("table", f"paimon.crypto_db.{table_name}") \
            .option("checkpointLocation", checkpoint_location) \
            .outputMode("append") \
            .start()
        
        logger.info(f"Started streaming write to {table_name}")
        return query
    
    def read_batch(self, table_name: str, start_date: str = None, end_date: str = None):
        """
        Read batch data from Paimon table
        
        Args:
            table_name: Table name
            start_date: Optional start date filter (YYYY-MM-DD)
            end_date: Optional end date filter (YYYY-MM-DD)
        
        Returns:
            DataFrame
        """
        df = self.spark.table(f"paimon.crypto_db.{table_name}")
        
        if start_date and end_date:
            df = df.filter(
                (col("dt") >= start_date) & (col("dt") <= end_date)
            )
        
        return df
    
    def time_travel_query(self, table_name: str, snapshot_id: int = None, timestamp: str = None):
        """
        Query historical data using time travel
        
        Args:
            table_name: Table name
            snapshot_id: Specific snapshot ID
            timestamp: Specific timestamp (ISO format)
        
        Returns:
            DataFrame
        """
        if snapshot_id:
            df = self.spark.read \
                .format("paimon") \
                .option("scan.snapshot-id", snapshot_id) \
                .table(f"paimon.crypto_db.{table_name}")
        elif timestamp:
            df = self.spark.read \
                .format("paimon") \
                .option("scan.timestamp-millis", timestamp) \
                .table(f"paimon.crypto_db.{table_name}")
        else:
            raise ValueError("Must provide either snapshot_id or timestamp")
        
        return df
    
    def compact_table(self, table_name: str):
        """
        Manually trigger table compaction for better query performance
        
        Args:
            table_name: Table to compact
        """
        self.spark.sql(f"""
            CALL paimon.sys.compact(
                table => 'crypto_db.{table_name}',
                order_strategy => 'zorder',
                order_columns => 'timestamp'
            )
        """)
        logger.info(f"Compacted table {table_name}")
    
    def get_table_statistics(self, table_name: str):
        """Get table statistics"""
        stats = self.spark.sql(f"""
            SELECT * FROM paimon.crypto_db.{table_name}$snapshots
            ORDER BY snapshot_id DESC
            LIMIT 10
        """)
        return stats
    
    def cleanup_old_snapshots(self, table_name: str, retain_days: int = 7):
        """
        Clean up old snapshots to save storage
        
        Args:
            table_name: Table name
            retain_days: Days to retain
        """
        self.spark.sql(f"""
            CALL paimon.sys.expire_snapshots(
                table => 'crypto_db.{table_name}',
                older_than => '{retain_days} days'
            )
        """)
        logger.info(f"Cleaned up snapshots older than {retain_days} days for {table_name}")


class PaimonProcessor:
    """
    Spark Structured Streaming processor with Paimon integration
    """
    
    def __init__(self, kafka_bootstrap_servers: str, paimon_warehouse: str):
        self.kafka_bootstrap_servers = kafka_bootstrap_servers
        self.paimon = PaimonDataLake(paimon_warehouse)
        
    def process_kafka_to_paimon(self):
        """Process Kafka stream and write to Paimon"""
        
        # Read from Kafka
        kafka_df = self.paimon.spark.readStream \
            .format("kafka") \
            .option("kafka.bootstrap.servers", self.kafka_bootstrap_servers) \
            .option("subscribe", "crypto-prices") \
            .option("startingOffsets", "latest") \
            .load()
        
        # Parse JSON and transform
        schema = StructType([
            StructField("product_id", StringType()),
            StructField("price", DoubleType()),
            StructField("size", DoubleType()),
            StructField("side", StringType()),
            StructField("timestamp", TimestampType())
        ])
        
        parsed_df = kafka_df.select(
            from_json(col("value").cast("string"), schema).alias("data")
        ).select("data.*")
        
        # Add processing metadata
        enriched_df = parsed_df \
            .withColumn("event_time", col("timestamp")) \
            .withColumn("processing_time", current_timestamp()) \
            .withColumn("dt", date_format(col("timestamp"), "yyyy-MM-dd"))
        
        # Write to Paimon (raw prices)
        query_raw = self.paimon.write_streaming_data(
            enriched_df,
            "raw_prices",
            "s3a://crypto-pipeline-checkpoints/raw_prices"
        )
        
        # Aggregate to OHLCV (1 minute window)
        ohlcv_df = enriched_df \
            .withWatermark("timestamp", "5 minutes") \
            .groupBy(
                col("product_id"),
                window(col("timestamp"), "1 minute").alias("window")
            ).agg(
                first("price").alias("open"),
                max("price").alias("high"),
                min("price").alias("low"),
                last("price").alias("close"),
                sum("size").alias("volume"),
                count("*").alias("trade_count"),
                sum(col("price") * col("size")).alias("volume_weighted_price")
            ).select(
                col("product_id"),
                col("window.start").alias("window_start"),
                col("window.end").alias("window_end"),
                col("open"),
                col("high"),
                col("low"),
                col("close"),
                col("volume"),
                col("trade_count"),
                (col("volume_weighted_price") / col("volume")).alias("vwap"),
                date_format(col("window.start"), "yyyy-MM-dd").alias("dt")
            )
        
        # Write to Paimon (OHLCV)
        query_ohlcv = self.paimon.write_streaming_data(
            ohlcv_df,
            "ohlcv_1m",
            "s3a://crypto-pipeline-checkpoints/ohlcv_1m"
        )
        
        return query_raw, query_ohlcv


if __name__ == "__main__":
    # Example usage
    import sys
    
    logging.basicConfig(level=logging.INFO)
    
    # Initialize Paimon lakehouse
    paimon = PaimonDataLake("s3a://crypto-pipeline-data-lake/paimon")
    
    # Create tables
    paimon.create_price_table()
    paimon.create_ohlcv_table()
    paimon.create_features_table()
    paimon.create_predictions_table()
    
    # Start processing
    if len(sys.argv) > 1 and sys.argv[1] == "process":
        processor = PaimonProcessor(
            kafka_bootstrap_servers="kafka:9092",
            paimon_warehouse="s3a://crypto-pipeline-data-lake/paimon"
        )
        
        query_raw, query_ohlcv = processor.process_kafka_to_paimon()
        
        # Wait for termination
        query_raw.awaitTermination()
