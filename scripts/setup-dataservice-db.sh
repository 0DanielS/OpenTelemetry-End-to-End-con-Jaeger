#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-opentelemetry-nrb}"
SQL_INSTANCE="${SQL_INSTANCE:-otel-pg}"
CONN_NAME="${PROJECT_ID}:us-central1:${SQL_INSTANCE}"
RUN_SA="otel-run@${PROJECT_ID}.iam.gserviceaccount.com"
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

PRIVATE_IP="$(gcloud sql instances describe "$SQL_INSTANCE" --project="$PROJECT_ID" \
  --format='value(ipAddresses.filter("type:PRIVATE").extract(ipAddress).flatten())')"

DATA_PASS="$(openssl rand -base64 24 | tr -d '/+=')"

gcloud sql users create dataservice --instance="$SQL_INSTANCE" --project="$PROJECT_ID" \
  --password="$DATA_PASS" \
  || gcloud sql users set-password dataservice --instance="$SQL_INSTANCE" \
       --project="$PROJECT_ID" --password="$DATA_PASS"

printf 'postgresql+asyncpg://dataservice:%s@%s:5432/orders' "$DATA_PASS" "$PRIVATE_IP" \
  | gcloud secrets create data-database-url --project="$PROJECT_ID" --data-file=- \
  || printf 'postgresql+asyncpg://dataservice:%s@%s:5432/orders' "$DATA_PASS" "$PRIVATE_IP" \
  | gcloud secrets versions add data-database-url --project="$PROJECT_ID" --data-file=-

gcloud secrets add-iam-policy-binding data-database-url --project="$PROJECT_ID" \
  --member="serviceAccount:${RUN_SA}" --role="roles/secretmanager.secretAccessor"

ORDERS_URL="$(gcloud secrets versions access latest --secret=orders-database-url --project="$PROJECT_ID")"
export PGPASSWORD="$(sed -E 's#.*//orders:([^@]*)@.*#\1#' <<<"$ORDERS_URL")"

cloud-sql-proxy --port 5434 "$CONN_NAME" >/dev/null 2>&1 &
PROXY_PID=$!
trap 'kill $PROXY_PID' EXIT
for i in $(seq 1 20); do nc -z 127.0.0.1 5434 && break; sleep 1; done

psql -h 127.0.0.1 -p 5434 -U orders -d orders <<'SQL'
GRANT CONNECT ON DATABASE orders TO dataservice;
GRANT USAGE ON SCHEMA public TO dataservice;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO dataservice;
ALTER DEFAULT PRIVILEGES FOR ROLE orders IN SCHEMA public GRANT SELECT ON TABLES TO dataservice;
SQL

echo "dataservice listo: secret data-database-url -> ${PRIVATE_IP}:5432/orders"
