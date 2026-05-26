FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

COPY mlops/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY mlops/ ./mlops/

ENV PYTHONPATH=/app
ENV MLOPS_MODEL_PATH=/models/coinbase_ml_model.joblib

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:3000/readyz || exit 1

CMD ["bentoml", "serve", "mlops.service:CoinbasePriceService", "--host", "0.0.0.0", "--port", "3000"]
