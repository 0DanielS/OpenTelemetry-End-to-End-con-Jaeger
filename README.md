# Pipeline de Observabilidad End-to-End con OpenTelemetry

Repositorio del módulo de **Observabilidad** (Maestría). Implementa un sistema observable completo sobre **3 microservicios Python/FastAPI**, capturando las **3 señales** (trazas, métricas y logs) con OpenTelemetry y correlacionándolas por `trace_id` (W3C Trace Context) — extendido en el **Laboratorio Integrador** con VPC + Flow Logs, **service mesh sobre Cloud Run (sin GKE)**, SLOs con error budget, detección de anomalías con correlación (AIOps), golden signals de seguridad y chaos engineering con **MTTD medido (19 s y 41 s)**.

> **Laboratorio Integrador:** consigna y plan en [`LAB-INTEGRADOR.md`](LAB-INTEGRADOR.md) · guía por fases en [`docs/fases/`](docs/fases/README.md) · madurez en [`docs/madurez-observabilidad.md`](docs/madurez-observabilidad.md) · experimentos en [`GAMEDAY-2.md`](GAMEDAY-2.md) · reporte ejecutivo en `reporte-final.pdf`.

Corre en **dos entornos equivalentes**:

| Entorno | Servicios | Trazas | Métricas | Logs | Dashboard |
|---|---|---|---|---|---|
| **Local** (Docker Compose) | contenedores | Jaeger + Tempo | Prometheus | stdout JSON | Grafana local (10 paneles) |
| **Nube** (GCP, desplegado) | Cloud Run | Cloud Trace | Managed Prometheus | Cloud Logging | Grafana en Cloud Run (9 paneles) |

## Arquitectura

```
k6 ──▶ orders-api ──(mesh: inventory-api.mesh.internal)──▶ inventory-api ──▶ Postgres (IP privada)
  └──▶ data-service (stats analíticas, DB spans semconv) ──▶ Postgres
          │  │  │                                      │  │  │
          └──┴──┴────── OTLP (gRPC:4317 / HTTP:4318) ──┴──┘  │
                                ▼                            │
                        OTel Collector (gateway) ◀───────────┘
                 ┌──────────────┼────────────────┐
          Jaeger + Tempo    Prometheus      Logs (stdout / Cloud Logging)
                 │              │
               Grafana ◀────────┘
```

En la nube el mismo diagrama se traduce a: Cloud Run (servicios + collector + Grafana), Cloud SQL (Postgres), Cloud Trace (trazas), Managed Prometheus (métricas) y Cloud Logging (logs).

| Componente | Rol | Puerto local |
|---|---|---|
| `orders-api` (service-a) | Crea pedidos, llama a inventory por HTTP, persiste la orden | 8080 |
| `inventory-api` (service-b) | Valida y reserva stock (UPDATE atómico); destino del mesh | 8081 |
| `data-service` (service-c) | Consultas analíticas de solo lectura con DB spans semconv; chaos por error rate | 8082 |
| OTel Collector | Recibe OTLP y enruta las 3 señales | 4317/4318/8889 |
| Jaeger all-in-one | Trazas | 16686 |
| Tempo | Trazas (Grafana stack) + service-graphs / span-metrics | 3200 |
| Prometheus | Métricas | 9090 |
| Grafana | Dashboard 10 paneles SLI/SLO + variables `$service`/`$interval` | 3000 |
| PostgreSQL | Bases `orders` e `inventory` | 5432 |

## Ejecución local

Requisitos: Docker y Docker Compose.

```bash
docker compose up --build -d
```

### Probar el flujo

```bash
curl http://localhost:8080/health
curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{"product_id":"p1","quantity":1,"customer_id":"demo"}'
```

### Verificar las 3 señales

| Señal | Dónde | Qué verificar |
|---|---|---|
| Trazas | http://localhost:16686 (Jaeger) y http://localhost:3200 (Tempo) | Traza `orders-api` → `inventory-api` bajo un único `trace_id` |
| Métricas | http://localhost:9090 | SLIs custom (`http_requests_total`, `http_request_duration_milliseconds_*`, `http_active_requests`) y `db_operation_duration_*`, etiquetadas por `service_name` |
| Logs | `docker compose logs orders-api` | JSON de structlog con `trace_id` y `span_id` |
| Dashboard | http://localhost:3000 → "Observabilidad - Pipeline E2E" | 10 paneles: 4 SLIs con SLOs, burn rate, saturación, DB p99, CPU overhead, salud del collector y tabla de propagación W3C |

> **Requisito crítico**: el `trace_id` debe ser el mismo en logs, trazas y métricas. Copia el `trace_id` de un log y búscalo en Jaeger.

## Despliegue en GCP (implementado y validado)

Proyecto `opentelemetry-nrb`, región `us-central1`. Los 4 servicios corren en **Cloud Run** (escalan a cero):

| Servicio | URL |
|---|---|
| orders-api | https://orders-api-576253872784.us-central1.run.app |
| inventory-api | https://inventory-api-576253872784.us-central1.run.app |
| otel-collector | https://otel-collector-576253872784.us-central1.run.app |
| **Grafana (dashboard cloud)** | https://grafana-576253872784.us-central1.run.app |

Visores nativos: [Cloud Trace](https://console.cloud.google.com/traces/list?project=opentelemetry-nrb) · [Cloud Logging](https://console.cloud.google.com/logs/query?project=opentelemetry-nrb) · [Managed Prometheus](https://console.cloud.google.com/monitoring/prometheus?project=opentelemetry-nrb)

> ⚠️ **La base de datos (Cloud SQL `otel-pg`) se mantiene APAGADA fuera de sesión** para no consumir créditos. Antes de probar los servicios cloud:
> ```bash
> gcloud sql instances patch otel-pg --activation-policy=ALWAYS   # encender (~5 min)
> gcloud sql instances patch otel-pg --activation-policy=NEVER    # apagar al terminar
> ```

### CI/CD — cómo se despliega

1. **Automático**: merge a `main` → GitHub Actions despliega el servicio cuyo código cambió (`service-a/**` o `service-b/**`). Autenticación **Workload Identity Federation** (sin llaves). Secretos (`DATABASE_URL`) en **Secret Manager**.
2. **Manual desde GitHub**: pestaña Actions → *Run workflow*.
3. **Local sin subir código**: `./scripts/deploy.sh all|orders|inventory` (requiere `gcloud` autenticado y la DB encendida — los servicios se conectan a la DB al arrancar).

Detalles completos en [`DEPLOY.md`](DEPLOY.md). Infra reproducible con `./scripts/gcp-bootstrap.sh`.

## Endpoints

| Servicio | Endpoint | Descripción |
|---|---|---|
| orders-api | `POST /orders` | Valida, reserva stock vía HTTP y crea la orden |
| orders-api | `GET /orders/{id}` | Lee una orden |
| inventory-api | `GET /products/{id}/stock` | Consulta stock |
| inventory-api | `POST /products/{id}/reserve` | Descuenta stock |
| ambos | `GET /health` | Healthcheck (excluido de trazas vía `filter/health`) |

## Instrumentación

- **Auto-instrumentación** (`opentelemetry-instrument`): FastAPI, httpx (propagación W3C automática) y SQLAlchemy. Versiones pineadas: SDK `1.29.0`, instrumentaciones `0.50b0`.
- **Spans custom**: `persist_order` (orders), `check_stock` y `reserve_stock` (inventory).
- **Métricas SLI** (middleware propio): `http_requests_total` (por status), `http_request_duration_milliseconds` (histograma), `http_active_requests` (saturación), `service_b_calls_total`, `inventory_requests_total`, más el histograma `db_operation_duration` (ms).
- **Resource enriquecido**: `service.version`, `deployment.environment`, `cloud.provider` vía `OTEL_RESOURCE_ATTRIBUTES`.
- **Logs**: structlog JSON con `trace_id`/`span_id` inyectados desde el span activo.
- **Pool de DB configurable por entorno**: `DB_POOL_SIZE`/`DB_MAX_OVERFLOW` (20/40 local, 5/5 en Cloud Run — ver "Gotchas").

## Benchmark de carga (k6)

Script en `k6/script.js` (escenarios warmup + carga sostenida + spike) y analizador en `benchmark/analyze_overhead.py`.

```bash
# local (con el stack arriba)
cat k6/script.js | docker run --rm -i \
  --network opentelemetry-end-to-end-con-jaeger_default \
  -e BASE_URL=http://orders-api:8080 grafana/k6 run -
```

Resultados documentados:
- **Overhead local** (con vs sin OTel): throughput −38%, p99 +31%, memoria +19–27% → `benchmark-resultados.md`.
- **Pruebas en la nube** (2 min sostenidos): 15 VUs → 100% éxito, p95 326 ms ✅; 80 VUs → saturación con thresholds cruzados y diagnóstico del agotamiento de conexiones vía el propio pipeline → sección 7.1 del reporte y evidencias en `screenshots_gcp/`.

## Game Day — chaos engineering

`inventory-api` puede inyectar latencia artificial controlada en `POST /products/{id}/reserve`, apagada por defecto y gobernada por dos variables de entorno:

| Variable | Default | Efecto |
|---|---|---|
| `CHAOS_ENABLED` | `false` | Habilita la inyección |
| `CHAOS_LATENCY_MS` | `0` | Milisegundos de latencia añadida |

Con el chaos activo el span `reserve_stock` se marca con `chaos.enabled` / `chaos.latency_ms` y se emite un log `chaos.latency.injected` con `trace_id`, de modo que el experimento es distinguible de una degradación real. Con 2.000 ms (bajo el timeout de 10 s de `orders-api`) el fallo es **gris**: mueve SLI-2 y SLI-4 sin romper disponibilidad ni error rate.

```bash
# local: editar CHAOS_ENABLED=true / CHAOS_LATENCY_MS=2000 en docker-compose.yml y recrear
docker compose up -d --build inventory-api

# Cloud Run: activar y hacer rollback
gcloud run services update inventory-api --region us-central1 \
  --update-env-vars CHAOS_ENABLED=true,CHAOS_LATENCY_MS=2000
gcloud run services update inventory-api --region us-central1 \
  --update-env-vars CHAOS_ENABLED=false,CHAOS_LATENCY_MS=0
```

Runbook completo (local + GCP, evidencias, criterio de aborto) en **`GAMEDAY.md`**.

## Estructura del repo

```
docker-compose.yml              # stack local (8 servicios)
docker-compose.baseline.yml     # override sin instrumentación (benchmark)
collector-config.yaml           # collector local (filter/health, resourcedetection, hostmetrics, Jaeger+Tempo)
tempo/tempo.yaml                # Tempo con service-graphs y span-metrics
service-a/  service-b/          # microservicios FastAPI instrumentados
prometheus/  grafana/           # scrape + dashboard local 10 paneles provisionado
k6/  benchmark/                 # carga multi-escenario + análisis de overhead
.github/workflows/              # CI/CD: deploy a Cloud Run con WIF
scripts/deploy.sh               # deploy local sin subir código
scripts/gcp-bootstrap.sh        # provisiona toda la infra GCP (idempotente)
deploy/otel-collector-cloud/    # collector en Cloud Run → Cloud Trace/Logging/GMP
deploy/grafana-cloud/           # Grafana en Cloud Run leyendo Managed Prometheus
screenshots/  screenshots_gcp/  # evidencias local y nube
reporte-tecnico.pdf             # reporte técnico final (11 págs, 6 figuras)
GAMEDAY.md                      # runbook del experimento de chaos (latencia controlada)
```

## Documentación

- `reporte-tecnico.pdf` — **reporte técnico final** (arquitectura, instrumentación, overhead, despliegue GCP, incidente y fix).
- `DEPLOY.md` — guía de despliegue en Cloud Run (CI/CD, WIF, secretos).
- `GAMEDAY.md` — runbook del game day de latencia controlada (local y Cloud Run).
- `benchmark-resultados.md` — resultados del benchmark de overhead local.

## Gotchas (lecciones aprendidas; no reinventar)

- El exporter `jaeger` fue **eliminado** del collector-contrib ≥0.109 → se usa `otlp` hacia el receptor OTLP de Jaeger.
- La imagen del collector es **distroless** (sin shell) → no admite `healthcheck`; el exporter OTLP reintenta solo.
- Métricas con **lag de 60s por defecto** → `OTEL_METRIC_EXPORT_INTERVAL=5000`.
- SQLAlchemy async **no emite** `db.client.operation.duration` → histograma custom.
- **Histogramas en ms, no segundos**: los buckets default de OTel (5, 10, 25…) asumen ms; en segundos los percentiles salen inventados.
- **Pools de DB vs Cloud SQL**: `db-f1-micro` admite ~25 conexiones; pools 20/40 por servicio la agotan (`TooManyConnectionsError`). En Cloud Run se despliega con `DB_POOL_SIZE=5`/`DB_MAX_OVERFLOW=5` — y ojo: el **autoescalado multiplica las conexiones** por instancia.
- Los servicios **se conectan a la DB al arrancar** → cualquier deploy a Cloud Run requiere la DB encendida.
- En Cloud Run, **nunca `:latest`**: la imagen se pinea por digest (revisiones cacheadas).
- El plugin cloud-monitoring de Grafana (≤11.6.x) **pierde las queries PromQL puras** (bug en `migrateRequest`) → cada target lleva un `timeSeriesList` dummy (ver `deploy/grafana-cloud/README.md`).

