# OTel Collector en Cloud Run (hub de observabilidad)

Despliega el OTel Collector como servicio de Cloud Run. Recibe OTLP (gRPC sobre TLS)
de `orders-api` e `inventory-api` y exporta las 3 señales a los backends nativos de GCP:

| Señal | Exporter | Destino |
|---|---|---|
| Trazas | `googlecloud` | Cloud Trace |
| Logs | `googlecloud` | Cloud Logging |
| Métricas | `googlemanagedprometheus` | Managed Service for Prometheus |

## Requisitos (una vez)

APIs: `run`, `cloudbuild`, `artifactregistry`, `cloudtrace`, `monitoring`, `logging`.

Service account runtime del collector con roles de escritura:

```bash
gcloud iam service-accounts create otel-collector-run --project opentelemetry-nrb
COL_SA=otel-collector-run@opentelemetry-nrb.iam.gserviceaccount.com
for r in roles/cloudtrace.agent roles/logging.logWriter roles/monitoring.metricWriter; do
  gcloud projects add-iam-policy-binding opentelemetry-nrb --member="serviceAccount:${COL_SA}" --role="$r"
done
```

## Desplegar

```bash
./deploy.sh
```

Usa `--use-http2` (necesario para OTLP gRPC en Cloud Run) y `--allow-unauthenticated`
(el endpoint OTLP queda público; para producción, autenticar servicio-a-servicio).

## Conectar los servicios

```bash
COL=https://otel-collector-<PROJECT_NUMBER>.us-central1.run.app:443
for svc in orders-api inventory-api; do
  gcloud run services update "$svc" --region us-central1 \
    --update-env-vars "OTEL_EXPORTER_OTLP_ENDPOINT=$COL"
done
```

## Verificar

- Trazas: Cloud Trace (`https://console.cloud.google.com/traces`).
- Logs: Cloud Logging, filtrando por `jsonPayload.trace_id`.
- Métricas: Managed Prometheus / Metrics Explorer.

## Nota

El exporter `googlemanagedprometheus` puede emitir un warning benigno en `target_info`
("Points must be written in order") cuando varias instancias de Cloud Run publican el
mismo punto; no afecta a las métricas de la aplicación.
