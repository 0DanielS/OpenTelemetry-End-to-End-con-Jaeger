# Inventario de infraestructura GCP actual

Estado real del proyecto en la nube al inicio del Laboratorio Integrador. Fuentes: `scripts/gcp-bootstrap.sh`, `DEPLOY.md`, `deploy/`, `.github/workflows/`.

## Proyecto

| Dato | Valor |
|---|---|
| Proyecto | `opentelemetry-nrb` |
| Número | `576253872784` |
| Región | `us-central1` |
| Repo GitHub | `0DanielS/OpenTelemetry-End-to-End-con-Jaeger` |

## Servicios en Cloud Run (escala a cero)

| Servicio | Origen | Notas |
|---|---|---|
| `orders-api` | `service-a/` | Puerto 8080; env `INVENTORY_URL`; secret `orders-database-url` → `DATABASE_URL` |
| `inventory-api` | `service-b/` | Puerto 8081; secret `inventory-database-url`; mecanismo de chaos por env vars |
| `otel-collector` | `deploy/otel-collector-cloud/` | OTLP gRPC sobre TLS/HTTP2 (`--use-http2`); hoy `--allow-unauthenticated` (endpoint OTLP público — pendiente cerrar) |
| `grafana` | `deploy/grafana-cloud/` | Dashboard 9 paneles sobre Managed Prometheus; URL `grafana-576253872784.us-central1.run.app` |

## Base de datos

- Cloud SQL PostgreSQL 16: instancia `otel-pg`, `db-f1-micro`, zonal, 10 GB.
- Bases: `orders`, `inventory` (el Lab Integrador agrega `analytics` para `data-service`).
- Conexión por **socket Unix** (`--add-cloudsql-instances`), sin IP privada de VPC todavía.
- **Guardrail de coste:** `activation-policy=NEVER` fuera de sesión; encender con `ALWAYS` antes de trabajar.

## Identidades y seguridad

| Service Account | Rol |
|---|---|
| `otel-run@opentelemetry-nrb.iam` | Runtime de Cloud Run (secretmanager.secretAccessor, cloudsql.client) |
| `gh-deploy@opentelemetry-nrb.iam` | Deployer de GitHub Actions (run.admin, serviceAccountUser, cloudbuild, artifactregistry.writer, storage.admin) |
| `otel-collector-run@opentelemetry-nrb.iam` | Runtime del Collector (cloudtrace.agent, logging.logWriter, monitoring.metricWriter) |

- **Workload Identity Federation** (sin llaves): pool `github-pool`, provider `github-provider`, condición restringida al repo. Provider: `projects/576253872784/locations/global/workloadIdentityPools/github-pool/providers/github-provider`.
- Secretos en **Secret Manager**: `orders-database-url`, `inventory-database-url` (cadenas `postgresql+asyncpg://...?host=/cloudsql/...`). Nunca pasan por GitHub.
- Artifact Registry: repo `cloud-run-source-deploy` (docker). Imágenes pineadas por digest.

## Telemetría (backends nativos)

| Señal | Exporter del Collector | Destino |
|---|---|---|
| Trazas | `googlecloud` | Cloud Trace |
| Logs | `googlecloud` | Cloud Logging |
| Métricas | `googlemanagedprometheus` | Managed Prometheus (jobs `observabilidad/<servicio>`) |

Query directa a GMP (ejemplo real usado en el Game Day):

```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer $TOKEN" --get \
  "https://monitoring.googleapis.com/v1/projects/opentelemetry-nrb/location/global/prometheus/api/v1/query_range" \
  --data-urlencode 'query=histogram_quantile(0.95, sum(rate(http_request_duration_milliseconds_bucket{job="observabilidad/inventory-api"}[5m])) by (le))'
```

## Mecanismos de despliegue

1. Merge a `main` → GitHub Actions con filtro de rutas (`service-a/**` → `deploy-orders.yml`, `service-b/**` → `deploy-inventory.yml`).
2. `workflow_dispatch` manual.
3. `./scripts/deploy.sh [all|orders|inventory]` (gcloud run deploy `--source`). **Ojo:** usa `--set-env-vars`, que reemplaza todas las variables (borra las de chaos).
4. `./scripts/gcp-bootstrap.sh` reprovisiona todo (APIs, SAs, WIF, Artifact Registry, Cloud SQL, secretos); idempotente.

## APIs habilitadas

`run`, `cloudbuild`, `artifactregistry`, `secretmanager`, `sqladmin`, `iam`, `iamcredentials`, `sts`, `cloudtrace`, `monitoring`, `logging`.

Pendientes de habilitar para el Lab Integrador: `mesh.googleapis.com` (Cloud Service Mesh), `compute.googleapis.com` (VPC/subnets/flow logs), `securitycenter.googleapis.com`, `containeranalysis.googleapis.com`, `containerscanning.googleapis.com`.

## Lo que NO existe todavía

- VPC propia (los servicios no pasan por VPC; Cloud SQL va por socket, no por IP privada).
- Alert policies / SLOs en Cloud Monitoring.
- Anomaly Detection.
- Service mesh.
- VPC Flow Logs, Security Command Center, escaneo de CVEs referenciado.
- `data-service` y su base `analytics`.

## Notas operativas

- Consola GCP con `&authuser=1` (la cuenta del proyecto no es la primera sesión del navegador).
- Collector escalando desde cero puede perder los primeros exports (`DEADLINE_EXCEEDED`): considerar `min-instances=1` durante experimentos con MTTD.
- Dashboard cloud: la grilla completa no renderiza por el plugin `grafana-lokiexplore-app`; abrir paneles con `&viewPanel=<id>`.
