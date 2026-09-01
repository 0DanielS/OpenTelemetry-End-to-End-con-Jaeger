#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-opentelemetry-nrb}"
NOTIFY_EMAIL="${NOTIFY_EMAIL:-nestorx211@gmail.com}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SERVICES=(orders-api inventory-api data-service)

CHANNEL="$(gcloud alpha monitoring channels list --project="$PROJECT_ID" \
  --filter="type=\"email\" AND labels.email_address=\"${NOTIFY_EMAIL}\"" \
  --format="value(name)" | head -1)"
if [[ -z "$CHANNEL" ]]; then
  CHANNEL="$(gcloud alpha monitoring channels create --project="$PROJECT_ID" \
    --display-name="Email observabilidad" --type=email \
    --channel-labels="email_address=${NOTIFY_EMAIL}" --format="value(name)")"
fi
echo "canal: $CHANNEL"

existing_policies="$(gcloud alpha monitoring policies list --project="$PROJECT_ID" --format="value(displayName)")"

apply_policy() {
  local tpl="$1" svc="${2:-}"
  local tmp
  tmp="$(mktemp)"
  sed -e "s|__CHANNEL__|${CHANNEL}|g" -e "s|__SVC__|${svc}|g" "$tpl" > "$tmp"
  local name
  name="$(python3 -c "import json,sys; print(json.load(open('$tmp'))['displayName'])")"
  if grep -qF "$name" <<<"$existing_policies"; then
    echo "ya existe: $name"
  else
    gcloud alpha monitoring policies create --project="$PROJECT_ID" --policy-from-file="$tmp" >/dev/null
    echo "creada: $name"
  fi
  rm -f "$tmp"
}

for svc in "${SERVICES[@]}"; do
  apply_policy "$HERE/policy-estatico-error-rate.json.tpl" "$svc"
  apply_policy "$HERE/policy-estatico-latencia.json.tpl" "$svc"
done
apply_policy "$HERE/policy-correlacion-data-service.json.tpl"
apply_policy "$HERE/policy-log-trace-id.json.tpl"

TOKEN="$(gcloud auth print-access-token)"
API="https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}"

for svc in "${SERVICES[@]}"; do
  curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    "${API}/services?serviceId=${svc}" \
    -d "{\"displayName\": \"${svc}\", \"custom\": {}}" | grep -q "\"name\"\|ALREADY_EXISTS" || true

  curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    "${API}/services/${svc}/serviceLevelObjectives?serviceLevelObjectiveId=disponibilidad-99-5" \
    -d "{
      \"displayName\": \"Disponibilidad 99.5% (7d rolling)\",
      \"goal\": 0.995,
      \"rollingPeriod\": \"604800s\",
      \"serviceLevelIndicator\": {
        \"requestBased\": {
          \"goodTotalRatio\": {
            \"goodServiceFilter\": \"metric.type=\\\"prometheus.googleapis.com/http_requests_total/counter\\\" resource.type=\\\"prometheus_target\\\" metric.labels.status=\\\"2xx\\\" resource.labels.job=\\\"observabilidad/${svc}\\\"\",
            \"totalServiceFilter\": \"metric.type=\\\"prometheus.googleapis.com/http_requests_total/counter\\\" resource.type=\\\"prometheus_target\\\" resource.labels.job=\\\"observabilidad/${svc}\\\"\"
          }
        }
      }
    }" | python3 -c "import json,sys; d=json.load(sys.stdin); print('${svc} SLO disponibilidad:', d.get('name','ERROR: '+json.dumps(d)[:200]))"

  curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    "${API}/services/${svc}/serviceLevelObjectives?serviceLevelObjectiveId=latencia-500ms-95" \
    -d "{
      \"displayName\": \"95% de requests < 500ms (7d rolling)\",
      \"goal\": 0.95,
      \"rollingPeriod\": \"604800s\",
      \"serviceLevelIndicator\": {
        \"requestBased\": {
          \"distributionCut\": {
            \"distributionFilter\": \"metric.type=\\\"prometheus.googleapis.com/http_request_duration_milliseconds/histogram\\\" resource.type=\\\"prometheus_target\\\" resource.labels.job=\\\"observabilidad/${svc}\\\"\",
            \"range\": { \"min\": 0, \"max\": 500 }
          }
        }
      }
    }" | python3 -c "import json,sys; d=json.load(sys.stdin); print('${svc} SLO latencia:', d.get('name','ERROR: '+json.dumps(d)[:200]))"
done

echo "listo"
