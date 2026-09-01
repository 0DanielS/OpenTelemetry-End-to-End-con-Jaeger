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
| `data-service` | `service-c/` | Puerto 8082; stats analíticas de solo lectura sobre la base `orders` (usuario `dataservice`, secret `data-database-url`); chaos por `CHAOS_ERROR_RATE`; en VPC `subnet-apis` |
| `otel-collector` | `deploy/otel-collector-cloud/` | OTLP gRPC sobre TLS/HTTP2 (`--use-http2`); hoy `--allow-unauthenticated` (endpoint OTLP público — pendiente cerrar) |
| `grafana` | `deploy/grafana-cloud/` | Dashboard 9 paneles sobre Managed Prometheus; URL `grafana-576253872784.us-central1.run.app` |

## Base de datos

- Cloud SQL PostgreSQL 16: instancia `otel-pg`, `db-f1-micro`, zonal, 10 GB.
- Bases: `orders`, `inventory` (el Lab Integrador agrega `analytics` para `data-service`).
- **IP privada `10.30.0.3`** en `obs-vpc` vía peering PSA (`psa-cloudsql`, 10.30.0.0/20); conserva la IP pública `34.68.109.109` y el socket Unix como respaldo.
- Los secretos `*-database-url` (versión 2) apuntan a la IP privada: `postgresql+asyncpg://<user>:<pass>@10.30.0.3:5432/<db>`. Migración reproducible con `scripts/migrate-db-secrets-private-ip.sh`.
- **Guardrail de coste:** `activation-policy=NEVER` fuera de sesión; encender con `ALWAYS` antes de trabajar.

## Red (creada en Fase 0 del Lab Integrador)

- VPC `obs-vpc` (subnets custom), región `us-central1`. IaC: `scripts/gcp-network-bootstrap.sh` (idempotente).

| Subred | Rango | Cargas | Flow Logs |
|---|---|---|---|
| `subnet-public` | 10.10.0.0/24 | Grafana (Direct VPC egress) | ✅ sampling 0.5, agregación 5 s |
| `subnet-apis` | 10.10.1.0/24 | orders-api, inventory-api, otel-collector (Direct VPC egress) | ✅ |
| `subnet-data` | 10.10.2.0/24 | (reservada capa de datos) | ✅ |

- Cloud SQL vive en el rango PSA `10.30.0.0/20` (peering con `servicenetworking`), no dentro de `subnet-data`; la subred queda reservada para futuras cargas de datos.
- Firewall: `allow-apis-to-data` (tcp:5432 desde 10.10.1.0/24), `allow-apis-internal` (443/8080/8081/8082/4317/4318 desde 10.10.1.0/24), `deny-public-to-data` (tcp:5432 desde 10.10.0.0/24, prioridad 900).
- Cloud Run con `--vpc-egress=private-ranges-only`: solo el tráfico a rangos privados (la DB) pasa por la VPC; el resto sale normal.

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

`run`, `cloudbuild`, `artifactregistry`, `secretmanager`, `sqladmin`, `iam`, `iamcredentials`, `sts`, `cloudtrace`, `monitoring`, `logging`, y desde la Fase 0 del Lab Integrador: `compute`, `servicenetworking`, `networkservices`, `trafficdirector`, `mesh`, `securitycenter`, `containeranalysis`, `containerscanning`.

## Lo que NO existe todavía

- Alert policies / SLOs en Cloud Monitoring.
- Anomaly Detection.
- Service mesh.
- VPC Flow Logs, Security Command Center, escaneo de CVEs referenciado.
- `data-service` y su base `analytics`.

## Notas operativas

### Hallazgo Fase 1: CPU throttling de Cloud Run mata el export de trazas

Con la asignación de CPU por defecto (solo durante requests), el hilo en background del `BatchSpanProcessor` del SDK se congela entre requests: los spans quedan encolados y llegan al collector hasta **25 minutos tarde**, o se pierden si la instancia escala a cero antes. Las **métricas sobreviven** porque son acumulativas (cualquier export exitoso lleva los totales) — por eso el síntoma es traicionero: métricas y logs fluyen, trazas desaparecen sin ningún error visible. Servicios con requests largos (orders-api: ~300 ms con llamada HTTP + DB) casi no lo sufren; servicios con requests de ~10 ms (data-service) lo sufren siempre.

**Fix aplicado a data-service** (persistido en `deploy.sh` y `deploy-data.yml`): `--no-cpu-throttling` (CPU siempre asignada mientras la instancia vive) + `OTEL_BSP_SCHEDULE_DELAY=1000` (flush del batch cada 1 s). Resultado: traza en Cloud Trace en ~25 s. Considerar el mismo fix en orders/inventory antes de la Fase 5 si el MTTD lo requiere.

- Consola GCP con `&authuser=1` (la cuenta del proyecto no es la primera sesión del navegador).
- Collector escalando desde cero puede perder los primeros exports (`DEADLINE_EXCEEDED`): considerar `min-instances=1` durante experimentos con MTTD.
- Dashboard cloud: la grilla completa no renderiza por el plugin `grafana-lokiexplore-app`; abrir paneles con `&viewPanel=<id>`.
