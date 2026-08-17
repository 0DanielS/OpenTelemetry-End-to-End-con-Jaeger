# AGENTS.md

## Acerca del repo

Repositorio académico del módulo de Observabilidad (Maestría). Documentación en español. Implementa un pipeline de observabilidad end-to-end con OpenTelemetry sobre AWS (ECS Fargate + RDS), con stack local de desarrollo vía Docker Compose.

Documentos de planificación:

- `investigacion-observabilidad.md` — investigación de referencia (OpenTelemetry, Jaeger, Grafana, k6, W3C Trace Context).
- `actividad-pipeline-observabilidad.md` — especificación de la actividad.
- `plan-implementacion-observabilidad-aws.md` — plan de trabajo aprobado (arquitectura, fases, decisiones, guardrails de coste). Cloud objetivo: **AWS ECS Fargate + RDS PostgreSQL**, teardown efímero para respetar el free tier (~$100).
- `benchmark-resultados.md` — resultados del benchmark de overhead (Fase 4) local: throughput, p99, CPU, memoria con vs sin instrumentación.
- `reporte-tecnico.pdf` (fuente `reporte-tecnico.html`) — reporte técnico final (arquitectura, decisiones, overhead, capturas en `screenshots/`).

## Arquitectura (ya implementada, validada localmente)

- **2 microservicios** Python/FastAPI: `service-a` (`orders-api`, :8080) → `service-b` (`inventory-api`, :8081), dependencia HTTP + RDS Postgres (bases `orders` e `inventory`).
- **3 señales**: trazas/métricas vía OTLP gRPC → OTel Collector (:4317) → Jaeger (trazas) + Prometheus (métricas); logs JSON (structlog) con `trace_id`/`span_id` a stdout.
- **Visualización**: Jaeger UI (:16686), Grafana (:3000, dashboard 6 paneles provisionado), Prometheus (:9090).
- Instrumentación con `opentelemetry-instrument` (auto: fastapi/httpx/sqlalchemy) + spans custom (`persist_order`, `check_stock`, `reserve_stock`) + histograma custom `db_operation_duration`.

## Cómo ejecutar y verificar (local)

```
docker compose up --build
```

- Probar flujo: `POST localhost:8080/orders` con body `{"product_id":"p1","quantity":1,"customer_id":"x"}` → reserva stock y crea orden.
- Verificar: Jaeger `localhost:16686`, Prometheus `localhost:9090`, Grafana `localhost:3000`.
- El `trace_id` debe ser el mismo en logs (stdout), trazas (Jaeger) y métricas — requisito crítico W3C.

## Gotchas (hard-earned; no reinventar)

- **Exporter `jaeger` eliminado** en collector-contrib `0.109.0`. Usar exporter `otlp/jaeger` → `jaeger:4317` (Jaeger all-in-one con `COLLECTOR_OTLP_ENABLED=true`).
- **Imagen del collector es distroless** (sin shell/`wget`): no admite `healthcheck` con `CMD`. Usar `depends_on: service_started`; el exporter OTLP reintenta solo.
- **Nombres de métricas**: `http_server_duration_milliseconds_*` (no `_seconds_`). Para etiquetar por servicio, activar `resource_to_telemetry_conversion: enabled` en el exporter `prometheus` (si no, no hay label `service_name`).
- **SQLAlchemy async NO emite** `db.client.operation.duration`; solo `db_client_connections_usage`. La métrica de latencia DB es un histograma custom `db_operation_duration` (unit `ms`) en `app/telemetry.py`.
- **Métricas con lag de 60s por defecto**: fijar `OTEL_METRIC_EXPORT_INTERVAL=5000` en los servicios (necesario para el benchmark y el demo en vivo).
- **Versiones pineadas** en `requirements.txt`: SDK `1.29.0`, instrumentaciones `0.50b0`. El `opentelemetry-instrument` CLI viene de `opentelemetry-distro`.

## Convenciones

- Entregables: **reporte técnico PDF (mín. 5 páginas)** con arquitectura, decisiones y overhead.
- Propagación W3C Trace Context (`traceparent`/`tracestate`) es el requisito crítico.
- Aplicar reglas globales de `~/.config/opencode/AGENTS.md` (FastAPI async, `httpx` en vez de `requests`, structlog, Pydantic, sin credenciales hardcodeadas).
- Guardrails de coste AWS: Fargate solo por sesión + `terraform destroy`; sin NAT Gateway (subnets públicas + VPC endpoint ECR); RDS `t4g.micro` single-AZ `skip_final_snapshot`; backends sin volumen persistente.
