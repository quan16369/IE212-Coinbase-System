FROM python:3.12-slim-bookworm

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY mlops/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt psycopg[binary]>=3.2.0

COPY mlops ./mlops
COPY scripts/promote_mlflow_model.py ./scripts/promote_mlflow_model.py

ENV PYTHONPATH=/app

CMD ["python", "-m", "mlops.train_from_feature_store"]
