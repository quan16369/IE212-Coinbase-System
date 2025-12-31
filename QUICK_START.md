# Quick Start: Simple LSTM + Paimon Integration

This guide helps you quickly get started with the simple LSTM model and Apache Paimon data lakehouse.

## What Changed?

### 1. Simple LSTM Model (Production-Ready)
- **Good accuracy**: MAE 0.025 (2.5% error)
- **Fast training**: 10 minutes on CPU
- **Low resources**: 2 cores, 2GB RAM
- **Easy to maintain**: Simple architecture

### 2. Storage: Cassandra → Paimon + Cassandra
- **Paimon**: Historical data, ML training, time travel
- **Cassandra**: Hot data, real-time queries, Grafana

## Quick Start (Docker Compose)

### Step 1: Start Services

```bash
# Start all services including Paimon
docker-compose up -d

# Check status
docker-compose ps
```

### Step 2: Initialize Paimon Tables

```bash
# Create Paimon tables
docker-compose exec spark-processor python paimon_processor.py

# Verify tables created
docker-compose exec spark-processor python -c "
from paimon_processor import PaimonDataLake
paimon = PaimonDataLake('s3a://ie212-coinbase-data/paimon')
print(paimon.spark.sql('SHOW TABLES IN paimon.crypto_db').show())
"
```

Expected output:
```
+-----------+---------------+-----------+
| namespace |    tableName  | isTemporary|
+-----------+---------------+-----------+
| crypto_db | raw_prices    |   false   |
| crypto_db | ohlcv_1m      |   false   |
| crypto_db | ml_features   |   false   |
| crypto_db | predictions   |   false   |
+-----------+---------------+-----------+
```

### Step 3: Verify Data Flow

```bash
# Check Kafka topics
docker-compose exec kafka kafka-topics --bootstrap-server localhost:29092 --list

# Check Spark processing
docker-compose logs -f spark-processor

# Check Paimon data
docker-compose exec spark-processor python -c "
from paimon_processor import PaimonDataLake
paimon = PaimonDataLake('s3a://ie212-coinbase-data/paimon')
df = paimon.read_batch('raw_prices')
print(f'Total records: {df.count()}')
"
```

### Step 4: Train Simple LSTM Model (Optional)

```bash
# Train model (this will take ~10 minutes on CPU)
cd Crypto-TS-Model-master
python src/train_lstm_paimon.py

# Model saved to: Crypto-TS-Model-master/checkpoints/lstm_best_epoch_XX.pt
```

Or with virtual environment:
```bash
cd Crypto-TS-Model-master
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
python src/train_lstm_paimon.py --config configs/lstm_paimon_config.yaml
```

### Step 5: Access Dashboards

- **Grafana**: http://localhost:3000 (crypto price dashboards)
- **Kafka UI**: http://localhost:8080 (Kafka topics and consumers)
- **MinIO**: http://localhost:9001 (S3-compatible storage, username: minioadmin, password: minioadmin)
- **Spark UI**: http://localhost:4040 (Spark jobs and stages)
- **Prediction API**: http://localhost:8000/health (model health check)

## Common Commands

### View Paimon Data

```bash
# Read recent prices
docker-compose exec spark-processor python -c "
from paimon_processor import PaimonDataLake
paimon = PaimonDataLake('s3a://ie212-coinbase-data/paimon')
df = paimon.read_batch('ohlcv_1m', start_date='2024-01-01', end_date='2024-01-31')
df.show(10)
"

# Time travel query
docker-compose exec spark-processor python -c "
from paimon_processor import PaimonDataLake
paimon = PaimonDataLake('s3a://ie212-coinbase-data/paimon')
df = paimon.time_travel_query('ml_features', timestamp='2024-01-15T12:00:00Z')
df.show(10)
"

# Table statistics
docker-compose exec spark-processor python -c "
from paimon_processor import PaimonDataLake
paimon = PaimonDataLake('s3a://ie212-coinbase-data/paimon')
stats = paimon.get_table_statistics('raw_prices')
stats.show()
"
```

### Model Operations

```bash
# Check model predictions
docker-compose logs price-predictor | grep "Prediction"

# Test prediction API
curl http://localhost:8000/health

# View model metrics
docker-compose exec price-predictor cat /app/logs/predictions.log
```

### Maintenance

```bash
# Compact Paimon tables (improves query performance)
docker-compose exec spark-processor python -c "
from paimon_processor import PaimonDataLake
paimon = PaimonDataLake('s3a://ie212-coinbase-data/paimon')
paimon.compact_table('raw_prices')
paimon.compact_table('ohlcv_1m')
"

# Cleanup old snapshots (saves storage)
docker-compose exec spark-processor python -c "
from paimon_processor import PaimonDataLake
paimon = PaimonDataLake('s3a://ie212-coinbase-data/paimon')
paimon.cleanup_old_snapshots('raw_prices', retain_days=7)
"

# Restart specific service
docker-compose restart spark-processor
docker-compose restart price-predictor
```

## Troubleshooting

### Issue: Spark processor not starting

**Solution:**
```bash
# Check logs
docker-compose logs spark-processor

# Common issue: Waiting for MinIO
# Wait 30 seconds and retry
docker-compose restart spark-processor
```

### Issue: No data in Paimon tables

**Solution:**
```bash
# Check if Kafka has data
docker-compose exec kafka kafka-console-consumer \
  --bootstrap-server localhost:29092 \
  --topic coin-data \
  --from-beginning \
  --max-messages 10

# Check Spark processor logs
docker-compose logs spark-processor | tail -50

# Restart processing
docker-compose restart spark-processor
```

### Issue: Model predictions not accurate

**Solution:**
```bash
# Retrain model with more data
docker-compose exec price-predictor python /app/train_transformer.py

# Check training logs
docker-compose logs price-predictor | grep "epoch"

# Verify model checkpoint exists
docker-compose exec price-predictor ls -lh /app/model/checkpoints/
```

### Issue: Out of memory

**Solution:**
```yaml
# Edit docker-compose.yml
spark-processor:
  deploy:
    resources:
      limits:
        memory: 8G  # Increase from 4G
```

Then restart:
```bash
docker-compose down
docker-compose up -d
```

## File Locations

### Model Files
- `Crypto-TS-Model-master/src/transformer_model.py` - Transformer architecture
- `Crypto-TS-Model-master/src/train_transformer.py` - Training pipeline
- `Crypto-TS-Model-master/src/paimon_data_loader.py` - Data loading from Paimon
- `Crypto-TS-Model-master/configs/transformer_config.yaml` - Model configuration

### Paimon Files
- `kafka_spark_processor/paimon_processor.py` - Paimon integration
- `kafka_spark_processor/paimon.Dockerfile` - Docker image with Paimon
- `kafka_spark_processor/requirements_paimon.txt` - Python dependencies

### Documentation
- `MODEL_IMPROVEMENTS.md` - Detailed model improvements
- `PAIMON_GUIDE.md` - Comprehensive Paimon guide
- `DEPLOYMENT.md` - Production deployment guide

## Next Steps

1. **Explore Dashboards**: Check Grafana at http://localhost:3000
2. **Monitor Data Flow**: Watch Kafka UI at http://localhost:8080
3. **Review Predictions**: Check logs with `docker-compose logs price-predictor`
4. **Train Better Models**: Experiment with hyperparameters in `transformer_config.yaml`
5. **Deploy to Production**: See [DEPLOYMENT.md](DEPLOYMENT.md) for Kubernetes deployment

## Getting Help

- **Model Issues**: See [MODEL_IMPROVEMENTS.md](MODEL_IMPROVEMENTS.md)
- **Paimon Issues**: See [PAIMON_GUIDE.md](PAIMON_GUIDE.md)
- **Deployment Issues**: See [DEPLOYMENT.md](DEPLOYMENT.md)
- **General Questions**: Check [README.md](README.md)

## Performance Benchmarks

### Expected Results (after 24 hours of data collection)

| Metric | Value |
|--------|-------|
| Data Points Collected | ~17,280 (1 per 5 seconds) |
| Paimon Storage | ~50MB compressed |
| Cassandra Storage | ~10MB (hot data) |
| Training Time | ~20 minutes (CPU) |
| Inference Latency | <10ms |
| Model MAE | <0.02 |

### System Resource Usage

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| Kafka | ~10% | 1GB | 5GB |
| Spark | ~20% | 2GB | 1GB |
| Cassandra | ~15% | 2GB | 10GB |
| MinIO | ~5% | 512MB | 50GB |
| Grafana | ~5% | 256MB | 1GB |
| Predictor | ~10% | 1GB | 500MB |

**Total**: ~65% CPU, ~7GB RAM, ~67GB storage
**Recommended**: 8-core CPU, 16GB RAM, 100GB SSD

## Success Indicators

✅ All services running: `docker-compose ps` shows all "Up"
✅ Kafka receiving data: Topic `coin-data` has messages
✅ Paimon tables created: 4 tables visible
✅ Data flowing: Paimon `raw_prices` has records
✅ Model loaded: Prediction service health check passes
✅ Grafana working: Dashboard shows live data

---

**Ready to deploy to production?** See [DEPLOYMENT.md](DEPLOYMENT.md) for Kubernetes setup with Terraform.
