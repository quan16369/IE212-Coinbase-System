FROM python:3.13-slim

WORKDIR /app

# Basic setup
RUN apt-get update && \
    apt-get install -y curl netcat-traditional dnsutils iputils-ping && \
    rm -rf /var/lib/apt/lists/*

# Copy source code
COPY coinbase_kafka_producer/producer.py .
COPY coinbase_kafka_producer/requirements.txt .
COPY contracts ./contracts

# Install python dependencies
RUN pip install -r requirements.txt

# Start script + logs
RUN echo '#!/bin/bash\n\
echo "=== Starting environment checks ==="\n\
echo "Current date and time: $(date)"\n\
echo "Working directory: $(pwd)"\n\
\n\
# Check Python version\n\
echo "Python version:"\n\
python --version 2>&1 || { echo "Error: Python is not installed or cannot run"; exit 1; }\n\
\n\
# Check required Python libraries\n\
echo "Checking Python libraries..."\n\
pip list | grep -E "kafka-python|websocket-client|coinbase" || echo "Warning: Some libraries (kafka-python, websocket-client, coinbase) may not be installed"\n\
echo "Installed libraries:"\n\
pip list\n\
\n\
# Check that producer.py exists\n\
echo "Checking producer.py..."\n\
if [ -f /app/producer.py ]; then\n\
    echo "producer.py exists"\n\
    ls -l /app/producer.py\n\
else\n\
    echo "Error: producer.py does not exist in /app"\n\
    exit 1\n\
fi\n\
\n\
# Check environment variables\n\
echo "=== Checking environment variables ==="\n\
echo "BOOTSTRAP_SERVERS: ${BOOTSTRAP_SERVERS:-Not set}"\n\
echo "COINBASE_API_KEY: ${COINBASE_API_KEY:-Not set}"\n\
echo "COINBASE_API_SECRET: ${COINBASE_API_SECRET:-Not set}"\n\
\n\
# Check Kafka connection\n\
echo "=== Checking Kafka connection ==="\n\
echo "Trying to connect to: $BOOTSTRAP_SERVERS"\n\
KAFKA_HOST=$(echo $BOOTSTRAP_SERVERS | cut -d: -f1)\n\
KAFKA_PORT=$(echo $BOOTSTRAP_SERVERS | cut -d: -f2)\n\
echo "Checking connection to $KAFKA_HOST:$KAFKA_PORT..."\n\
timeout 60 bash -c "until nc -z $KAFKA_HOST $KAFKA_PORT 2>/dev/null; do echo \"Waiting for Kafka to start...\"; sleep 5; done"\n\
if [ $? -eq 0 ]; then\n\
    echo "Connected to Kafka successfully."\n\
else\n\
    echo "Warning: Could not connect to Kafka after 60 seconds!"\n\
    echo "Continuing to start the producer, but it may not connect successfully."\n\
fi\n\
\n\
# Run producer.py with detailed logs\n\
echo "=== Starting Producer ==="\n\
echo "Running python /app/producer.py..."\n\
python /app/producer.py 2>&1 | tee /app/producer.log\n\
EXIT_CODE=$?\n\
echo "producer.py exit code: $EXIT_CODE"\n\
if [ $EXIT_CODE -ne 0 ]; then\n\
    echo "Error: producer.py did not run successfully. Check /app/producer.log for details."\n\
    cat /app/producer.log\n\
    exit $EXIT_CODE\n\
else\n\
    echo "producer.py ran successfully."\n\
fi\n' > /app/start.sh && chmod +x /app/start.sh

ENTRYPOINT ["/app/start.sh"]
