FROM python:3.13-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl netcat-traditional && \
    rm -rf /var/lib/apt/lists/*

COPY services/telemetry_producer/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY services/telemetry_producer/producer.py .
COPY contracts ./contracts

CMD ["python", "/app/producer.py"]
