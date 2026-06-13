FROM python:3.12-slim

WORKDIR /app

COPY services/raw_data_replay/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY services/raw_data_replay/replay.py .

CMD ["python", "replay.py"]
