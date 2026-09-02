#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-opentelemetry-nrb}"
REGION="${REGION:-us-central1}"
RUNTIME_SA="${RUNTIME_SA:-otel-run@opentelemetry-nrb.iam.gserviceaccount.com}"
SQL_INSTANCE="${SQL_INSTANCE:-opentelemetry-nrb:us-central1:otel-pg}"
INVENTORY_URL="${INVENTORY_URL:-https://inventory-api-576253872784.us-central1.run.app}"
OTEL_ENDPOINT="${OTEL_ENDPOINT:-https://otel-collector-576253872784.us-central1.run.app:443}"

TARGET="${1:-all}"

deploy_orders() {
  gcloud beta run deploy orders-api \
    --source service-a \
    --network obs-vpc \
    --subnet subnet-apis \
    --vpc-egress private-ranges-only \
    --mesh "projects/${PROJECT_ID}/locations/global/meshes/obs-mesh" \
    --project "$PROJECT_ID" \
    --region "$REGION" \
    --service-account "$RUNTIME_SA" \
    --add-cloudsql-instances "$SQL_INSTANCE" \
    --set-secrets "DATABASE_URL=orders-database-url:4" \
    --set-env-vars "INVENTORY_URL=$INVENTORY_URL,OTEL_SERVICE_NAME=orders-api,OTEL_EXPORTER_OTLP_PROTOCOL=grpc,OTEL_METRIC_EXPORT_INTERVAL=15000,OTEL_EXPORTER_OTLP_ENDPOINT=$OTEL_ENDPOINT,DB_POOL_SIZE=5,DB_MAX_OVERFLOW=5" \
    --port 8080 \
    --allow-unauthenticated \
    --quiet
}

deploy_inventory() {
  gcloud run deploy inventory-api \
    --source service-b \
    --project "$PROJECT_ID" \
    --region "$REGION" \
    --service-account "$RUNTIME_SA" \
    --add-cloudsql-instances "$SQL_INSTANCE" \
    --set-secrets "DATABASE_URL=inventory-database-url:latest" \
    --set-env-vars "OTEL_SERVICE_NAME=inventory-api,OTEL_EXPORTER_OTLP_PROTOCOL=grpc,OTEL_METRIC_EXPORT_INTERVAL=15000,OTEL_EXPORTER_OTLP_ENDPOINT=$OTEL_ENDPOINT,DB_POOL_SIZE=5,DB_MAX_OVERFLOW=5" \
    --port 8081 \
    --allow-unauthenticated \
    --quiet
}

deploy_data() {
  gcloud run deploy data-service \
    --source service-c \
    --project "$PROJECT_ID" \
    --region "$REGION" \
    --service-account "$RUNTIME_SA" \
    --network obs-vpc \
    --subnet subnet-apis \
    --vpc-egress private-ranges-only \
    --no-cpu-throttling \
    --set-secrets "DATABASE_URL=data-database-url:latest" \
    --set-env-vars "OTEL_SERVICE_NAME=data-service,OTEL_BSP_SCHEDULE_DELAY=1000,OTEL_EXPORTER_OTLP_PROTOCOL=grpc,OTEL_METRIC_EXPORT_INTERVAL=15000,OTEL_EXPORTER_OTLP_ENDPOINT=$OTEL_ENDPOINT,DB_POOL_SIZE=5,DB_MAX_OVERFLOW=5" \
    --port 8082 \
    --allow-unauthenticated \
    --quiet
}

case "$TARGET" in
  orders) deploy_orders ;;
  inventory) deploy_inventory ;;
  data) deploy_data ;;
  all) deploy_inventory; deploy_data; deploy_orders ;;
  *) echo "uso: $0 [orders|inventory|data|all]" >&2; exit 1 ;;
esac
