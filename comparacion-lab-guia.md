# Comparación con el lab guía (`mafeopa/oTelLabs`)

Análisis de brechas entre **nuestro proyecto** y el **lab guía** (Laboratorio 2 — Observabilidad en Ambientes Productivos), con lista de tareas para alcanzar su nivel.

> Fecha del análisis: 2026-08-21. Repo guía: https://github.com/mafeopa/oTelLabs

---

## Resumen ejecutivo

Ambos proyectos resuelven **lo mismo** (2 microservicios FastAPI → OTel → Jaeger/Prometheus/Grafana, correlación por `trace_id`), pero el lab guía va **más lejos en profundidad de observabilidad** (SLIs/SLOs, burn rate, Tempo, Cloud Logging/Trace, collector avanzado). Nosotros vamos **por delante en CI/CD real** (Cloud Run con GitHub Actions + WIF + Secret Manager, ya desplegado y validado), que el lab no tiene.

> **Decisión de arquitectura:** nuestro despliegue es **Cloud Run + GCP, sin Kubernetes y sin AWS**. Por tanto los manifests **GKE y ECS del lab NO aplican** a nuestro proyecto: no son brechas, son un camino distinto (serverless en vez de k8s multi-cloud). El lab usa GKE+ECS; nosotros Cloud Run — ambos válidos.

**Veredicto:** tenemos la base sólida y CI/CD que ellos no; nos faltan sobre todo **las métricas SLI explícitas, el collector avanzado, Tempo y el análisis de overhead formal**. (Nada de k8s/AWS.)

---

## Tabla comparativa por dimensión

| Dimensión | Lab guía | Nuestro proyecto | Estado |
|---|---|---|---|
| **Instrumentación** | Manual con OTel SDK (TracerProvider/MeterProvider explícitos) | Auto vía `opentelemetry-instrument` CLI | ⚠️ Distinto enfoque |
| **Resource attrs** | `service.version`, `deployment.environment`, `cloud.provider`, `host.name` | Solo `service.namespace` (añadido en collector) | ❌ Falta |
| **Métricas SLI** | 4 SLIs explícitos: disponibilidad (counter), latencia (histogram), saturación (up_down_counter), error rate + métricas de negocio | Solo histograma custom `db_operation_duration` + auto `http_server_duration` | ❌ Falta |
| **Custom spans** | `fetch.order.db`, `call.service-b.inventory`, `inventory.db.fetch` | `persist_order`, `check_stock`, `reserve_stock` | ✅ Equivalente |
| **DB driver** | psycopg2 (sync) + Psycopg2Instrumentor | SQLAlchemy async + asyncpg | ✅ Equivalente (más moderno el nuestro) |
| **Logs correlacionados** | python-json-logger + trace_id/span_id/version/env | structlog + trace_id/span_id | ✅ Equivalente |
| **OTel Collector** | otlp+prometheus+hostmetrics receivers; memory_limiter, resource, **resourcedetection**, **filter/health**, **attributes/cardinalidad**, (tail_sampling comentado); exporters jaeger+tempo+prometheus+**googlecloud**+debug; extensions health/pprof/zpages | otlp receiver; memory_limiter, resource, batch; exporters jaeger+prometheus+debug; extension health_check | ❌ Mucho más simple |
| **Backend trazas** | Jaeger **+ Tempo** (con service-graphs / span-metrics) | Solo Jaeger | ❌ Falta Tempo |
| **Backend métricas** | Prometheus | Prometheus | ✅ |
| **Dashboard Grafana** | 8 paneles (6 SLIs + **burn rate** + **panel de propagación**) + traceToMetrics/traceToLogs | 6 paneles (p99, error rate, throughput, DB p99, CPU collector, errores collector) | ⚠️ Faltan SLOs, burn rate, correlación |
| **SLOs / alerting** | SLOs definidos (≥99.5%, p95<500ms, ≤0.5% err), burn rate multiventana, clases de alerta | No definidos | ❌ Falta |
| **Benchmark overhead** | k6 multi-escenario (warmup+sostenida+spike) + `analyze_overhead.py` (baseline vs OTel) | k6 simple (50 VUs POST) + `benchmark-resultados.md` | ⚠️ Parcial |
| **Despliegue GCP** | GKE (`k8s/gcp/deployment.yaml`: DaemonSet collector + Deployments + HPA) | **Cloud Run** (real, desplegado, CI/CD) | ✅ Decisión propia (serverless, no k8s) |
| **Despliegue AWS** | ECS Fargate (`k8s/aws/ecs-task-definition.json`) | No aplica (decidimos solo GCP) | ✅ Fuera de alcance a propósito |
| **CI/CD** | Manual (kubectl / aws cli en README) | **GitHub Actions + WIF + Secret Manager** (2 workflows, script local) | ✅ Vamos por delante |
| **Cloud Logging/Trace** | Exporter `googlecloud` (logs+trazas+métricas a GCP) | No | ❌ Falta |

---

## Lo que YA tenemos (fortalezas)

- ✅ 2 microservicios FastAPI con propagación W3C funcionando (traza única cruza ambos servicios — validado en local y en Cloud Run).
- ✅ Las 3 señales correlacionadas por `trace_id` (logs structlog, trazas Jaeger, métricas Prometheus).
- ✅ Spans custom + histograma custom de latencia DB.
- ✅ Stack local completo con Docker Compose (Postgres, Collector, Jaeger, Prometheus, Grafana).
- ✅ Dashboard Grafana provisionado (6 paneles) + datasources auto.
- ✅ **Despliegue real en Cloud Run** con CI/CD por PR a main, WIF sin llaves, secretos en Secret Manager y Cloud SQL. (El lab no tiene CI/CD.)
- ✅ Benchmark k6 + resultados de overhead documentados.
- ✅ Reporte técnico PDF.

## Lo que NOS FALTA (brechas)

1. **Métricas SLI explícitas** — no emitimos `http_requests_total` (con label de status), latencia en segundos por endpoint, ni saturación (`up_down_counter`). Sin esto no se pueden calcular SLIs/SLOs/burn rate como el lab.
2. **Resource enriquecido** — falta `service.version`, `deployment.environment`, `cloud.provider`, `host.name`.
3. **Collector avanzado** — sin `resourcedetection`, `filter/health` (excluir health checks), `attributes` (reducir cardinalidad), `hostmetrics`, ni `tail_sampling`. Sin extensions `pprof`/`zpages`.
4. **Tempo** — no está; el lab lo usa como backend alternativo con `service-graphs` y `span-metrics`.
5. **Cloud Logging / Cloud Trace** — no exportamos telemetría a GCP nativo (exporter `googlecloud`).
6. **SLOs + burn rate + alerting** — no definidos ni en dashboard ni en reglas.
7. **Análisis de overhead formal** — nos falta el `analyze_overhead.py` y los escenarios k6 (warmup/sostenida/spike) con comparación baseline vs OTel automatizada.
8. **Correlación en Grafana** — sin `traceToLogs`/`traceToMetrics` ni panel de verificación de propagación.
9. **OTel Collector en la nube** — en Cloud Run los servicios aún apuntan a un endpoint placeholder (no hay hub de observabilidad desplegado).

> ❌ **NO aplican** (decisión de arquitectura Cloud Run + GCP): manifests GKE, ECS task-definition y despliegue AWS. El lab los tiene, nosotros no los necesitamos.

---

## Lista de tareas para alcanzar el nivel del lab

Priorizado: **P0** = imprescindible para paridad, **P1** = importante, **P2** = deseable.

> **Estado de avance (rama `feat/observabilidad-parity-lab`):** ✅ Fases A (SLIs + Resource), B (collector avanzado), C (Tempo + dashboard 8 paneles + SLOs), D (benchmark) — implementadas y validadas en local. ⏳ Pendiente: E (desplegar el Collector en la nube) y afinar docs.

### A. Instrumentación y métricas
- [ ] **P0** Añadir SLIs explícitos en ambos servicios: `http_requests_total` (counter con label `status`), `http_request_duration_seconds` (histogram), `http_active_requests` (up_down_counter para saturación).
- [ ] **P0** Enriquecer el `Resource`: `service.version`, `deployment.environment`, `cloud.provider`, `host.name`.
- [ ] **P1** Añadir métricas de negocio: llamadas entre servicios (`service_b_calls_total` equivalente), latencia DB por operación con labels.
- [ ] **P2** Evaluar migrar de auto-instrumentación a config SDK explícita (o combinar) si el lab lo exige para la nota — decidir con el docente.

### B. OTel Collector
- [ ] **P0** Añadir processor `filter/health` para excluir spans de `/health`.
- [ ] **P1** Añadir `resourcedetection` (detectores gcp/ecs/docker/system) y `attributes` para reducir cardinalidad.
- [ ] **P1** Añadir receiver `hostmetrics` (CPU/mem/disk/network del host).
- [ ] **P1** Añadir exporter `googlecloud` (logs → Cloud Logging, trazas → Cloud Trace) usando el proyecto `opentelemetry-nrb`.
- [ ] **P2** Añadir extensions `pprof` y `zpages` (debug del pipeline).
- [ ] **P2** Dejar `tail_sampling` documentado/comentado para control de costos.

### C. Backends y visualización
- [ ] **P1** Añadir **Tempo** al stack (compose local) con `metrics_generator` (service-graphs, span-metrics) y datasource en Grafana.
- [ ] **P0** Ampliar el dashboard a 8 paneles: añadir **burn rate** y **panel de propagación/correlación**.
- [ ] **P0** Definir **SLOs** explícitos (disponibilidad ≥99.5%, p95<500ms, error rate ≤0.5%) en el dashboard.
- [ ] **P1** Configurar `traceToLogs` / `traceToMetrics` en el datasource de Grafana para saltar traza↔log↔métrica.
- [ ] **P2** Reglas de alerta por burn rate (multiventana) en Prometheus/Grafana.

### D. Benchmark de overhead
- [ ] **P1** Reescribir el script k6 con escenarios warmup + carga sostenida + spike.
- [ ] **P1** Crear `analyze_overhead.py` que compare baseline (sin OTel) vs con OTel y genere la tabla de overhead.
- [ ] **P2** Automatizar el flujo baseline↔otel (parar/levantar collector) y documentar resultados reales.

### E. Nube (Cloud Run + GCP — sin k8s)
- [ ] **P0** Desplegar el **OTel Collector en la nube** (hub de observabilidad) y apuntar `OTEL_EXPORTER_OTLP_ENDPOINT` de los Cloud Run a él (hoy es placeholder). Opciones: Collector como servicio Cloud Run, o exporter `googlecloud` directo a Cloud Trace/Logging.
- [ ] **P2** IaC opcional (Terraform) para reproducibilidad de la infra GCP (Cloud SQL, Secret Manager, WIF, Cloud Run).

> ~~Manifests GKE / ECS task-definition / despliegue AWS~~ — **descartados** por decisión de arquitectura (serverless Cloud Run, solo GCP).

### F. Documentación
- [ ] **P1** Documentar SLIs/SLOs, burn rate y clases de alerta (estilo SRE Workbook) en el reporte.
- [ ] **P2** Añadir sección de troubleshooting (zpages, verificación de propagación, scraping).

---

## Recomendación de orden

1. **Primero lo barato y de alto impacto** (paridad de instrumentación): A (SLIs + Resource) → C (dashboard 8 paneles + SLOs) → B (`filter/health`, `googlecloud`).
2. **Cerrar la nube**: desplegar el Collector (hub) y conectar los Cloud Run → activar Cloud Logging/Trace.
3. **Cierre académico**: benchmark formal + documentación de SLOs/overhead.

> Multi-cloud k8s (GKE/ECS) queda **fuera de alcance** a propósito: nuestro camino es Cloud Run + GCP.

> Nota: nuestro CI/CD (GitHub Actions + WIF + Secret Manager + Cloud Run) es un **plus sobre el lab**; vale la pena destacarlo en el reporte como diferenciador.
