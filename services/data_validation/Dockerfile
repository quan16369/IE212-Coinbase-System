FROM python:3.12-slim

WORKDIR /app

COPY services/data_validation/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY services/data_validation ./services/data_validation
COPY contracts ./contracts

ENV PYTHONPATH=/app
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/readyz', timeout=3).read()" || exit 1

CMD ["uvicorn", "services.data_validation.app:app", "--host", "0.0.0.0", "--port", "8080"]
