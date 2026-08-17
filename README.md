# Pipeline de Observabilidad End-to-End con OpenTelemetry

Repositorio del módulo de **Observabilidad** (Maestría). Implementa un pipeline de observabilidad end-to-end sobre **2 microservicios Python/FastAPI**, capturando las **3 señales** (trazas, métricas y logs) con OpenTelemetry y correlacionándolas por `trace_id` (W3C Trace Context). Cloud objetivo: **AWS ECS Fargate + RDS PostgreSQL** (free tier, teardown efímero).

## Arquitectura

```
k6 ──▶ orders-api ──(HTTP, W3C traceparent)──▶ inventory-api ──▶ RDS Postgres (orders / inventory)
          │  │  │                                      │  │  │
          └──┴──┴────── OTLP (gRPC:4317 / HTTP:4318) ──┴──┘  │
                                ▼                            │
                        OTel Collector (gateway) ◀───────────┘
                 ┌──────────────┼────────────────┐
              Jaeger        Prometheus      CloudWatch Logs
                 │              │
               Grafana ◀────────┘
```

| Componente | Rol | Puerto |
|---|---|---|
| `orders-api` (service-a) | Crea pedidos, llama a inventory por HTTP, persiste la orden | 8080 |
| `inventory-api` (service-b) | Valida y reserva stock (UPDATE atómico) | 8081 |
| OTel Collector | Recibe OTLP y enruta las 3 señales | 4317/4318/8889 |
| Jaeger all-in-one | Trazas | 16686 |
| Prometheus | Métricas | 9090 |
| Grafana | Dashboard 6 paneles + correlación por `trace_id` | 3000 |
| RDS PostgreSQL | Bases `orders` e `inventory` | 5432 |

## Requisitos previos

- Docker y Docker Compose.
- (Opcional) k6 para el benchmark — se usa vía la imagen `grafana/k6`, no requiere instalación.
- (Solo Fase 5) Terraform y credenciales AWS.

## Ejecución local

```powershell
docker compose up --build
```

Esto levanta Postgres, OTel Collector, Jaeger, Prometheus, Grafana y los dos microservicios (instrumentados con `opentelemetry-instrument`).

### Probar el flujo

```powershell
# Health checks
Invoke-RestMethod http://localhost:8080/health
Invoke-RestMethod http://localhost:8081/health

# Crear una orden (reserva stock en inventory y la persiste en orders)
Invoke-RestMethod -Method Post -Uri http://localhost:8080/orders `
  -ContentType "application/json" `
  -Body '{"product_id":"p1","quantity":1,"customer_id":"carlos"}'
```

### Verificar las 3 señales

| Señal | Dónde | Qué verificar |
|---|---|---|
| Trazas | http://localhost:16686 | Traza con spans de `orders-api` → `inventory-api` bajo un único `trace_id` |
| Métricas | http://localhost:9090 | Métricas `http_server_duration_milliseconds_*` y `db_operation_duration_milliseconds_*` etiquetadas por `service_name` |
| Logs | `docker compose logs orders-api` | JSON de structlog con `trace_id` y `span_id` |
| Dashboard | http://localhost:3000 | Dashboard "Observabilidad - Pipeline E2E" (6 paneles) |

> **Requisito crítico**: el `trace_id` debe ser el mismo en logs (stdout), trazas (Jaeger) y métricas.

## Endpoints

| Servicio | Endpoint | Descripción |
|---|---|---|
| orders-api | `POST /orders` | Valida, reserva stock vía HTTP y crea la orden |
| orders-api | `GET /orders/{id}` | Lee una orden |
| orders-api | `GET /health` | Healthcheck |
| inventory-api | `GET /products/{id}/stock` | Consulta stock |
| inventory-api | `POST /products/{id}/reserve` | Descuenta stock |
| inventory-api | `GET /health` | Healthcheck |

## Instrumentación

- **Auto-instrumentación** (`opentelemetry-instrument`): FastAPI, httpx (con propagación W3C automática) y SQLAlchemy.
- **Spans custom**: `persist_order` (orders-api), `check_stock` y `reserve_stock` (inventory-api).
- **Métrica custom**: histograma `db_operation_duration` (ms) — necesario porque SQLAlchemy async no emite `db.client.operation.duration`.
- **Logs**: structlog JSON con `trace_id`/`span_id` inyectados desde el span activo.
- Versiones pineadas en `requirements.txt`: SDK `1.29.0`, instrumentaciones `0.50b0`.

## Benchmark de overhead (k6)

Script en `k6/script.js` (50 VUs, `POST /orders`, `product_id` rotado entre 100 productos).

```powershell
# Con instrumentación (stack actual)
Get-Content k6/script.js -Raw | docker run --rm -i `
  --network opentelemetryend-to-endconjaeger_default `
  -e BASE_URL=http://orders-api:8080 -e VUS=50 -e DURATION=30s grafana/k6 run -

# Sin instrumentación (override que arranca uvicorn directo)
docker compose -f docker-compose.yml -f docker-compose.baseline.yml up -d
```

Resultados locales capturados en `benchmark-resultados.md` (overhead medido: throughput −38%, p99 +31%, memoria +19–27%).

## Despliegue en AWS (Fase 5)

ECS Fargate + RDS PostgreSQL mediante Terraform (`terraform/`), con guardrails de coste para el free tier (~$100):

- Fargate **efímero**: se levanta por sesión y se destruye con `terraform destroy`.
- RDS `t4g.micro` single-AZ, `skip_final_snapshot`.
- Sin NAT Gateway (subnets públicas + VPC endpoint ECR).
- Backends (Jaeger/Prometheus/Grafana) sin volumen persistente; logs a CloudWatch (free tier).

## Estructura del repo

```
docker-compose.yml              # stack local instrumentado
docker-compose.baseline.yml     # override sin instrumentación (benchmark)
collector-config.yaml           # config OTel Collector
init-db.sql                     # bootstrap de la base inventory
service-a/                      # orders-api (FastAPI)
service-b/                      # inventory-api (FastAPI)
prometheus/prometheus.yml       # scrape del collector
grafana/provisioning/           # datasources + dashboards (6 paneles)
grafana/dashboards/             # dashboard JSON
k6/script.js                    # benchmark
terraform/                      # IaC ECS Fargate + RDS
screenshots/                    # evidencia (Jaeger, Grafana)
```

## Documentación

- `investigacion-observabilidad.md` — investigación (OpenTelemetry, Jaeger, Grafana, k6, W3C).
- `actividad-pipeline-observabilidad.md` — especificación de la actividad.
- `plan-implementacion-observabilidad-aws.md` — plan de trabajo aprobado.
- `benchmark-resultados.md` — resultados del benchmark de overhead.
- `reporte-tecnico.pdf` — reporte técnico final (fuente en `reporte-tecnico.html`).

## Gotchas

- El exporter `jaeger` fue **eliminado** del collector-contrib ≥0.109 → se usa `otlp` hacia el receptor OTLP de Jaeger.
- La imagen del collector es **distroless** (sin shell) → no admite `healthcheck`; el exporter OTLP reintenta solo.
- Métricas con **lag de 60s por defecto** → `OTEL_METRIC_EXPORT_INTERVAL=5000`.
- Ver `AGENTS.md` para el listado completo de decisiones técnicas.
