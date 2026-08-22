#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-opentelemetry-nrb}"
REGION="${REGION:-us-central1}"
COLLECTOR_SA="${COLLECTOR_SA:-otel-collector-run@opentelemetry-nrb.iam.gserviceaccount.com}"
HERE="$(cd "$(dirname "$0")" && pwd)"

gcloud run deploy otel-collector \
  --source "$HERE" \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --service-account "$COLLECTOR_SA" \
  --use-http2 \
  --allow-unauthenticated \
  --port 8080 \
  --memory 512Mi \
  --quiet

URL="$(gcloud run services describe otel-collector --project "$PROJECT_ID" --region "$REGION" --format='value(status.url)')"
echo "Collector desplegado: ${URL}"
echo "Apunta los servicios con: OTEL_EXPORTER_OTLP_ENDPOINT=${URL}:443"
