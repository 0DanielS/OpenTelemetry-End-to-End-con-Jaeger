# Plan de Implementación: Pipeline de Observabilidad End-to-End en AWS

> Especificación técnica del laboratorio. Fuente de verdad para la implementación.
> Cloud: AWS (ECS Fargate + RDS PostgreSQL). Presupuesto: free tier (~$100 USD).

---

## 1. Objetivo

Implementar 2 microservicios Python/FastAPI (`orders-api` → `inventory-api`) instrumentados con OpenTelemetry, emitiendo las 3 señales (trazas, métricas, logs) hacia un OTel Collector que enruta a **Jaeger** (trazas), **Prometheus** (métricas) y **CloudWatch Logs** (logs). Visualización en Grafana con correlación cross-signal por `trace_id`, y benchmark k6 para medir overhead. Despliegue en ECS Fargate + RDS PostgreSQL con Terraform, de forma **efímera** para respetar el presupuesto.

---

## 2. Arquitectura

```
k6 ──> orders-api ──(HTTP, W3C traceparent)──> inventory-api ──> RDS Postgres (orders / inventory)
          │  │  │                                    │  │  │
          └──┴──┴────── OTLP (gRPC:4317 / HTTP:4318) ─┴──┴──┘
                                 │
                         OTel Collector (Fargate)
                     ┌───────────┼────────────────┐
                   Jaeger    Prometheus    CloudWatch Logs
                     │          │
                   Grafana ◄────┘
```

### Componentes

| Componente | Rol | Puerto |
|---|---|---|
| `orders-api` (service-a) | Crea pedidos, llama a inventory por HTTP | 8080 |
| `inventory-api` (service-b) | Valida y reserva stock | 8081 |
| OTel Collector | Recibe OTLP, enruta las 3 señales | 4317/4318, 8889 |
| Jaeger all-in-one | Trazas (storage en memoria) | 16686 |
| Prometheus | Métricas (scrape al collector :8889) | 9090 |
| Grafana | Dashboards + correlación | 3000 |
| CloudWatch Logs | Logs JSON (free tier 5 GB/mes) | — |
| RDS PostgreSQL | 2 bases: `orders`, `inventory` | 5432 |

---

## 3. Decisiones de diseño

- **Lenguaje**: Python 3.12 + FastAPI (reglas globales: async, `httpx`, structlog, Pydantic).
- **Propagación W3C Trace Context** (`traceparent`/`tracestate`): crítica. El `trace_id` debe ser consistente entre logs, trazas y métricas del mismo request. Auto-propagación vía instrumentación de `httpx`.
- **Cómputo efímero**: Fargate solo durante sesiones; `terraform destroy` al terminar.
- **Sin NAT Gateway**: subnets públicas + VPC endpoint para ECR (evita ~$32/mes).
- **RDS `t4g.micro` single-AZ** (free tier), `skip_final_snapshot`.
- **Backends efímeros**: Jaeger/Prometheus/Grafana sin volumen persistente; solo capturas como evidencia.
- **Logs a CloudWatch Logs** (no Loki): menos contenedores, free tier.

---

## 4. Fases de trabajo

### Fase 0 — Setup local (`docker-compose`)
Stack completo local (apps + collector + Jaeger + Prometheus + Grafana + Postgres) para desarrollar y capturar evidencia sin gastar AWS. Replica exacta de lo que se desplegará en ECS.

### Fase 1 — Instrumentación (ambos servicios)
- Auto-instrumentación (`opentelemetry-bootstrap`): `fastapi`, `httpx`, `sqlalchemy`.
- Spans custom: `persist_order` (A); `check_stock`, `reserve_stock` (B).
- Logs JSON (structlog) con `trace_id`/`span_id`.
- Métricas: `http_server_duration` (histogram), `orders_created_total`, `stock_level`.

**Endpoints**

| Servicio | Endpoint | Descripción |
|---|---|---|
| orders-api | `POST /orders` | Valida input, llama a inventory reserve, inserta orden |
| orders-api | `GET /orders/{id}` | Lee una orden |
| orders-api | `GET /health` | Healthcheck |
| inventory-api | `GET /products/{id}/stock` | Consulta stock |
| inventory-api | `POST /products/{id}/reserve` | Descuenta stock (custom span) |
| inventory-api | `GET /health` | Healthcheck |

### Fase 2 — OTel Collector
`collector-config.yaml`: receivers OTLP (gRPC + HTTP); processors `batch` + `memory_limiter` + `resource`; exporters `jaeger` (trazas), `prometheus` (:8889), `awscloudwatchlogs` (logs).

### Fase 3 — Backends y visualización
Jaeger all-in-one, Prometheus, Grafana. Dashboard de **6 paneles**: 4 SLIs (latencia p99, error rate, throughput RPS, saturación/latencia DB) + CPU de contenedores + errores del collector. Verificar `trace_id` consistente en las 3 señales.

### Fase 4 — Benchmark de overhead (k6)
Script contra `POST /orders`, 50–100 VUs, 5 min. Dos corridas: `OTEL_SDK_DISABLED=true` vs instrumentado. Medir p99, CPU, memoria (CloudWatch/Container Insights). Tabla comparativa.

> Resultados locales ya capturados en `benchmark-resultados.md` (overhead medido: throughput −38%, p99 +31%, memoria +19–27%).

### Fase 5 — IaC Terraform + deploy efímero
VPC, subnets públicas, SGs, IAM, ECR, ECS Fargate (task defs + services), RDS `t4g.micro`. Flujo: `terraform apply` → capturas/benchmark → `terraform destroy`.

### Fase 6 — Reporte
PDF ≥5 páginas: arquitectura, decisiones de diseño, análisis de overhead, capturas.

> Reporte generado: `reporte-tecnico.pdf` (fuente editable en `reporte-tecnico.html`, capturas en `screenshots/`).

---

## 5. Estructura del repo (a crear)

```
docker-compose.yml
collector-config.yaml
prometheus/prometheus.yml
grafana/provisioning/datasources/datasources.yml
grafana/provisioning/dashboards/dashboards.yml
grafana/dashboards/observabilidad.json
k6/script.js
terraform/            # main.tf + modules (ecs, rds, vpc, iam, ecr)
service-a/            # orders-api: app/, Dockerfile, requirements.txt
service-b/            # inventory-api: app/, Dockerfile, requirements.txt
```

---

## 6. Guardrails de coste

- Fargate solo durante sesiones; `terraform destroy` al terminar.
- Sin NAT Gateway; subnets públicas + VPC endpoint ECR.
- Backends sin volumen persistente; RDS `skip_final_snapshot`.
- Tamaños mínimos de task (0.25 vCPU / 0.5 GB).
