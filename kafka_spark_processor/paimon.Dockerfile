FROM apache/spark-py:3.3.2

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements
COPY requirements_paimon.txt .

# Install Python packages
RUN pip install --no-cache-dir -r requirements_paimon.txt

# Download Paimon jars
RUN wget -P /opt/spark/jars/ \
    https://repo1.maven.org/maven2/org/apache/paimon/paimon-spark-3.3/0.6.0/paimon-spark-3.3-0.6.0.jar

# Download AWS/S3 jars for Spark
RUN wget -P /opt/spark/jars/ \
    https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.2/hadoop-aws-3.3.2.jar && \
    wget -P /opt/spark/jars/ \
    https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.262/aws-java-sdk-bundle-1.12.262.jar

# Copy application code
COPY paimon_processor.py .
COPY spark_processor.py .

# Set Spark configurations
ENV SPARK_HOME=/opt/spark
ENV PYSPARK_PYTHON=python3
ENV PYSPARK_DRIVER_PYTHON=python3

# Expose Spark UI port
EXPOSE 4040

USER 185

CMD ["python", "paimon_processor.py", "process"]
