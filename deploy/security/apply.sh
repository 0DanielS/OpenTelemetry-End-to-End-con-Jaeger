#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-opentelemetry-nrb}"
NOTIFY_EMAIL="${NOTIFY_EMAIL:-nestorx211@gmail.com}"
HERE="$(cd "$(dirname "$0")" && pwd)"
FLOW_LOG='logName="projects/'"$PROJECT_ID"'/logs/compute.googleapis.com%2Fvpc_flows"'

create_metric() {
  local name="$1" desc="$2" filter="$3"
  if gcloud logging metrics describe "$name" --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud logging metrics update "$name" --project="$PROJECT_ID" \
      --description="$desc" --log-filter="$filter" >/dev/null
    echo "actualizada: $name"
  else
    gcloud logging metrics create "$name" --project="$PROJECT_ID" \
      --description="$desc" --log-filter="$filter" >/dev/null
    echo "creada: $name"
  fi
}

create_metric "trafico-anomalo-a-datos" \
  "Flujos hacia la capa de datos (rango PSA 10.30/20) cuyo origen NO es subnet-apis" \
  "$FLOW_LOG jsonPayload.connection.dest_ip=~\"^10\\.30\\.\" NOT jsonPayload.connection.src_ip=~\"^10\\.10\\.1\\.\""

create_metric "flujos-este-oeste" \
  "Flujos internos de la VPC (destino en rangos privados 10.x)" \
  "$FLOW_LOG jsonPayload.connection.dest_ip=~\"^10\\.\""

create_metric "auth-fallidos" \
  "Requests 401/403 en los servicios de Cloud Run" \
  "resource.type=\"cloud_run_revision\" logName=~\"run.googleapis.com%2Frequests\" (httpRequest.status=401 OR httpRequest.status=403)"

CHANNEL="$(gcloud alpha monitoring channels list --project="$PROJECT_ID" \
  --filter="type=\"email\" AND labels.email_address=\"${NOTIFY_EMAIL}\"" \
  --format="value(name)" | head -1)"

if ! gcloud alpha monitoring policies list --project="$PROJECT_ID" \
  --format="value(displayName)" | grep -qF "SEGURIDAD trafico anomalo a capa de datos"; then
  TMP="$(mktemp)"
  cat > "$TMP" <<EOF
{
  "displayName": "SEGURIDAD trafico anomalo a capa de datos",
  "combiner": "OR",
  "severity": "CRITICAL",
  "documentation": {
    "content": "Un flujo alcanzo el rango PSA de Cloud SQL (10.30.0.0/20) desde un origen distinto de subnet-apis (10.10.1.0/24). Revisar en Logging la metrica trafico-anomalo-a-datos: src_ip, dest_port y bytes. Nota: el peering PSA no atraviesa las reglas de firewall de subred, por lo que esta alerta es la linea de deteccion principal para la capa de datos.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "flujo no autorizado hacia 10.30.0.0/20",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/trafico-anomalo-a-datos\" resource.type=\"gce_subnetwork\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0,
        "duration": "0s",
        "aggregations": [
          { "alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_SUM", "crossSeriesReducer": "REDUCE_SUM" }
        ]
      }
    }
  ],
  "alertStrategy": { "autoClose": "1800s" },
  "notificationChannels": ["${CHANNEL}"]
}
EOF
  gcloud alpha monitoring policies create --project="$PROJECT_ID" --policy-from-file="$TMP" >/dev/null
  rm -f "$TMP"
  echo "creada: SEGURIDAD trafico anomalo a capa de datos"
else
  echo "ya existe: SEGURIDAD trafico anomalo a capa de datos"
fi

EXISTING_DASH="$(gcloud monitoring dashboards list --project="$PROJECT_ID" \
  --filter='displayName="Golden Signals de Seguridad"' --format="value(name)" | head -1)"
if [[ -z "$EXISTING_DASH" ]]; then
  gcloud monitoring dashboards create --project="$PROJECT_ID" \
    --config-from-file="$HERE/dashboard-golden-signals-seguridad.json" >/dev/null
  echo "creado: dashboard Golden Signals de Seguridad"
else
  echo "ya existe: dashboard Golden Signals de Seguridad"
fi

echo "listo"
