#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-opentelemetry-nrb}"
SQL_INSTANCE="${SQL_INSTANCE:-otel-pg}"
CONN_NAME="${PROJECT_ID}:us-central1:${SQL_INSTANCE}"

PRIVATE_IP="$(gcloud sql instances describe "$SQL_INSTANCE" --project="$PROJECT_ID" \
  --format='value(ipAddresses.filter("type:PRIVATE").extract(ipAddress).flatten())')"

NEW_PASS="$(openssl rand -base64 24 | tr -d '/+=')"

gcloud sql users set-password orders --instance="$SQL_INSTANCE" \
  --project="$PROJECT_ID" --password="$NEW_PASS"

printf 'postgresql+asyncpg://orders:%s@%s:5432/orders' "$NEW_PASS" "$PRIVATE_IP" \
  | gcloud secrets versions add orders-database-url --project="$PROJECT_ID" --data-file=-

printf 'postgresql+asyncpg://orders:%s@/orders?host=/cloudsql/%s' "$NEW_PASS" "$CONN_NAME" \
  | gcloud secrets versions add orders-database-url --project="$PROJECT_ID" --data-file=-

LATEST="$(gcloud secrets versions list orders-database-url --project="$PROJECT_ID" \
  --limit=1 --format='value(name)')"
echo "rotada: version socket = ${LATEST} (la TCP es $((LATEST-1)))"
echo "pinnear orders-api a orders-database-url:${LATEST}"
