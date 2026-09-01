#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-opentelemetry-nrb}"
SQL_INSTANCE="${SQL_INSTANCE:-otel-pg}"

PRIVATE_IP="$(gcloud sql instances describe "$SQL_INSTANCE" --project="$PROJECT_ID" \
  --format='value(ipAddresses.filter("type:PRIVATE").extract(ipAddress).flatten())')"

if [[ -z "$PRIVATE_IP" ]]; then
  echo "La instancia $SQL_INSTANCE no tiene IP privada" >&2
  exit 1
fi

for db in orders inventory; do
  secret="${db}-database-url"
  gcloud secrets versions access latest --secret="$secret" --project="$PROJECT_ID" \
    | sed -E "s#@/${db}\?host=.*#@${PRIVATE_IP}:5432/${db}#" \
    | gcloud secrets versions add "$secret" --project="$PROJECT_ID" --data-file=-
  matches="$(gcloud secrets versions access latest --secret="$secret" --project="$PROJECT_ID" \
    | grep -c "${PRIVATE_IP}:5432/${db}")"
  echo "${secret}: ${matches} coincidencia(s) con ${PRIVATE_IP}:5432/${db}"
done
