FROM python:3.12-slim-bookworm AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

COPY mlops/requirements.txt ./requirements.txt
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim-bookworm

WORKDIR /app

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/venv /opt/venv

COPY mlops/ ./mlops/
COPY artifacts/mlops/coinbase_ml_model.joblib /models/coinbase_ml_model.joblib

ENV PATH=/opt/venv/bin:$PATH
ENV PYTHONPATH=/app
ENV MLOPS_MODEL_PATH=/models/coinbase_ml_model.joblib

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:3000/readyz || exit 1

CMD ["bentoml", "serve", "mlops.service:CoinbasePriceService", "--host", "0.0.0.0", "--port", "3000"]
