# Actividad: Pipeline de Observabilidad End-to-End con OpenTelemetry

> Actividad a desarrollar en el módulo de Observabilidad.

---

## Introducción al momento

Implementar un pipeline de observabilidad end-to-end basado en **OpenTelemetry** que capture **métricas (Prometheus)**, **logs estructurados** y **trazas distribuidas (Jaeger/Tempo)** desde una aplicación de microservicios desplegada en **GCP GKE** y **AWS ECS**, habilitando la **correlación cross-signal a través de `trace_id`**.

---

## Descripción de la actividad

### Arquitectura objetivo

- **2 microservicios** (`service-a` → `service-b`) con dependencia HTTP + acceso a base de datos.

### Fase 1 — Instrumentación con OTel SDK

- Instrumentar ambos servicios con **OTel SDK** (Python o Go):
  - Auto-instrumentation para HTTP y DB.
  - Custom spans para lógica de negocio crítica.
- Emitir los **3 pilares**:
  - Métricas (OTel → endpoint Prometheus).
  - Logs (JSON estructurado con `trace_id`/`span_id`).
  - Trazas (OTLP → OTel Collector).

### Fase 2 — Despliegue del OTel Collector

- Configurar el OTel Collector con:
  - **Receiver** OTLP (gRPC + HTTP).
  - **Processors**: batch + memory_limiter + resource.
  - **Exporters**:
    - Jaeger (trazas).
    - Prometheus (métricas).
    - Cloud Logging / CloudWatch (logs).
- Despliegue:
  - **GCP**: Cloud Run o GKE.
  - **AWS**: ECS Fargate.

### Fase 3 — Backends y Visualización

- **Trazas**: Jaeger UI (GCP) + AWS X-Ray o Tempo (AWS). Verificar propagación de contexto entre servicios.
- **Métricas**: Prometheus + Grafana dashboard con **6 paneles** (4 SLIs + CPU + errores del OTel Collector).
- **Logs**: correlacionar en Grafana Explorer usando `trace_id` como pivot entre log lines y trazas.

### Fase 4 — Análisis de Overhead

- Ejecutar benchmark (**k6** o **locust**): sin instrumentación vs. con instrumentación OTel.
- Medir:
  - Latencia adicional (p99).
  - CPU overhead %.
  - Memoria adicional.
- Documentar resultados en tabla comparativa.

---

## Entregables

Repositorio GitHub con:

- Código de instrumentación OTel (SDK).
- Configuración del OTel Collector.
- Manifiestos IaC (Terraform/Helm).
- Capturas de Jaeger UI con trazas completas.
- Dashboards Grafana / Cloud Monitoring.
- Reporte técnico **PDF (mín. 5 páginas)** con arquitectura, decisiones de diseño y análisis de overhead.

---

## Recomendaciones

- La **propagación de contexto (W3C TraceContext)** es crítica: verificar que el `trace_id` sea consistente entre logs, trazas y métricas del mismo request.
- El **benchmark** debe ejecutarse con carga realista (50–100 usuarios concurrentes, 5 minutos).
