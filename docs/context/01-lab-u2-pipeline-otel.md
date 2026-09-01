# Lab U2 — Pipeline de Observabilidad End-to-End con OpenTelemetry

Resumen del reporte técnico entregado en la Unidad 2 (`LAB Pipeline OpenTelemetry End-to-End con Jaeger y Prometheus en GCP U2.pdf`, 13 págs., agosto 2026). Es la base sobre la que se construye el Laboratorio Integrador.

## Qué se construyó

Pipeline de observabilidad end-to-end sobre dos microservicios Python/FastAPI (`orders-api` → `inventory-api`) capturando **trazas, métricas y logs estructurados**, correlacionados por `trace_id` según **W3C Trace Context**. Un OTel Collector desacopla las apps de los backends:

- **Local (Docker Compose):** Jaeger + Tempo (trazas), Prometheus (métricas), stdout JSON (logs), Grafana con 10 paneles.
- **Nube (GCP):** Cloud Trace, Managed Prometheus (GMP), Cloud Logging, Grafana en Cloud Run con 9 paneles.

Flujo de una orden: `POST /orders` → validación Pydantic → llamada HTTP a `inventory-api` (`POST /products/{id}/reserve`) propagando `traceparent` → UPDATE atómico de stock (nunca queda negativo bajo concurrencia) → INSERT de la orden → 201.

## Stack

Python 3.12 · FastAPI · uvicorn · httpx · SQLAlchemy async + asyncpg · Pydantic · structlog · OTel SDK 1.29.0 / instrumentaciones 0.50b0 · OTel Collector contrib 0.109 · Jaeger 1.57 · Tempo 2.5 · Prometheus 2.54 · Grafana 11 · PostgreSQL 16 · Cloud Run + Cloud Build + Artifact Registry · GitHub Actions + WIF + Secret Manager · k6.

## Instrumentación

- **Auto-instrumentación** con `opentelemetry-instrument`: FastAPI (spans server), httpx (spans client + propagación W3C automática), SQLAlchemy (`db.statement`, `db.system`). Resource enriquecido vía `OTEL_RESOURCE_ATTRIBUTES` (`service.version`, `deployment.environment`, `cloud.provider`).
- **Spans custom:** `persist_order` (orders), `check_stock` / `reserve_stock` (inventory).
- **Métricas SLI** (middleware propio, health checks excluidos):
  - `http_requests_total` (disponibilidad/errores, label `status`)
  - `http_request_duration_milliseconds` (histograma p50/p95/p99)
  - `http_active_requests` (saturación, up-down counter)
  - `service_b_calls_total` / `inventory_requests_total` (negocio cross-service)
  - `db_operation_duration` ms (SQLAlchemy async no emite `db.client.operation.duration`)
- **Logs JSON** (structlog) con processor que inyecta `trace_id`/`span_id` del span activo.
- Correlación cross-signal verificada en local (traza de 15 spans en Jaeger) y en nube (traza en Cloud Trace + filtro por `trace_id` en Cloud Logging).

## Collector

- **Local:** receiver OTLP (gRPC+HTTP) + hostmetrics + self-scrape; processors `memory_limiter → resource → resourcedetection → filter/health → batch`; export dual a Jaeger (vía OTLP, el exporter `jaeger` fue eliminado en contrib ≥0.109) y Tempo (que genera service-graphs y span-metrics hacia Prometheus por remote-write); métricas a Prometheus `:8889` con `resource_to_telemetry_conversion: enabled`.
- **Nube:** segundo Collector en Cloud Run, recibe OTLP gRPC sobre TLS/HTTP2; exporta con `googlecloud` (trazas, logs) y `googlemanagedprometheus` (métricas).

## Dashboard (10 paneles, variables `$service`/`$interval`)

SLI-1 Disponibilidad (SLO ≥ 99.5%, gauge) · Burn rate 1h (PAGE si > 14.4) · Saturación (requests en vuelo) · SLI-2 Latencia p50/p95/p99 (SLO p95 < 500 ms) · SLI-3 Error rate + línea SLO 0.5% · SLI-4 Throughput RPS · Latencia DB p99 · CPU overhead (collector+host) · Salud del collector (spans enviados/fallidos/cola) · Propagación W3C (tabla cross-service). El dashboard cloud replica 9 (sin los de CPU/self-metrics del collector).

## Overhead medido (k6 local, 50 VUs)

| Métrica | Sin OTel | Con OTel | Overhead |
|---|---|---|---|
| Throughput | 217 req/s | 135 req/s | −38% |
| Latencia promedio | 229 ms | 368 ms | +61% |
| p95 | 525 ms | 900 ms | +71% |
| p99 | 945 ms | 1240 ms | +31% |
| Memoria orders / inventory | 72 / 64 MiB | 86 / 81 MiB | +19% / +27% |

Causas: span fan-out (~15–16 spans/orden, ~2000 spans/s), export de métricas cada 5 s, sin muestreo. Mitigación recomendada para producción: **tail-based sampling 10–25%**.

## Despliegue GCP

- 4 servicios en Cloud Run (`us-central1`), escala a cero: `orders-api`, `inventory-api`, OTel Collector, Grafana.
- Cloud SQL PostgreSQL 16 `db-f1-micro`, socket Unix (`--add-cloudsql-instances`), bases `orders` e `inventory`.
- CI/CD: merge a `main` → GitHub Actions con filtro de rutas; también `workflow_dispatch` y `scripts/deploy.sh`. Autenticación por **Workload Identity Federation** (sin llaves), secretos en **Secret Manager**, imágenes **pineadas por digest**.
- Guardrail de coste: DB apagada fuera de sesión (`activation-policy=NEVER`) y escala a cero.

## Pruebas de carga en la nube (ingeniería de capacidad guiada por telemetría)

| Prueba | Éxito | RPS | p95 | Conclusión |
|---|---|---|---|---|
| 50 VUs (pools 20/40) | 14.4% | 9 | 10 s | La telemetría identificó el límite de ~25 conexiones de db-f1-micro → pool configurable por entorno |
| 15 VUs (pools 5/5) | 100% | 74 | 326 ms | Dimensionamiento validado, thresholds en verde |
| 80 VUs (pools 5/5, estrés) | 39% | 142 | 1.38 s | El autoescalador (hasta 9 instancias) multiplica conexiones → acotar `max-instances` |

Durante el estrés el dashboard capturó la degradación en tiempo real: disponibilidad 59.1%, burn rate 22.5 (> 14.4 = umbral PAGE).

## Decisiones de diseño clave

- OTLP nativo hacia Jaeger; collector distroless sin healthcheck (resiliencia delegada al protocolo con reintentos del exporter).
- `resource_to_telemetry_conversion: enabled` para labels `service_name` en Prometheus.
- Histograma custom `db_operation_duration` en ms (buckets default de OTel).
- `OTEL_METRIC_EXPORT_INTERVAL=5000` (frescura para dashboards; 60 s sería el default de producción).
- Carga repartida entre 100 productos (evita contención de una fila).
- `httpx.AsyncClient` compartido; pool de DB por entorno (20/40 local, 5/5 nube).
- WIF + Secret Manager + digest pinning; guardrails de coste dentro de la Free Trial.

## Operación

```bash
gcloud sql instances patch otel-pg --activation-policy=ALWAYS   # encender DB
./scripts/deploy.sh all                                          # desplegar
gcloud sql instances patch otel-pg --activation-policy=NEVER    # apagar DB al terminar
```

Dashboard cloud: `grafana-576253872784.us-central1.run.app`. Evidencias en `screenshots_gcp/`.
