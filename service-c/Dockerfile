FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

ENV PYTHONUNBUFFERED=1

CMD OTEL_RESOURCE_ATTRIBUTES="${OTEL_RESOURCE_ATTRIBUTES:+${OTEL_RESOURCE_ATTRIBUTES},}service.instance.id=$(cat /proc/sys/kernel/random/uuid)" opentelemetry-instrument uvicorn app.main:app --host 0.0.0.0 --port 8082
