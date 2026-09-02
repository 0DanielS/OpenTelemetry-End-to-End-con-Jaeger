# Autoevaluación de Madurez de Observabilidad

Evaluación del sistema contra el **Observability Foundation Blueprint** (8 dominios), escala 1–5. Cada calificación se justifica con evidencia verificable del repositorio y del proyecto GCP `opentelemetry-nrb` — el mismo principio de "no ocultar" de los Game Days aplicado a la autoevaluación.

**Escala:** 1 = Inicial (ad-hoc) · 2 = Repetible (manual, parcial) · 3 = Definido (implementado y documentado) · 4 = Gestionado (medido, validado con evidencia) · 5 = Optimizado (automatizado, mejora continua)

## Resumen

| # | Dominio | Nivel | En una frase |
|---|---|---|---|
| 1 | Tres Pilares | **4** | Tres señales correlacionadas por `trace_id` en 3 servicios, verificadas en local y nube |
| 2 | OpenTelemetry | **4** | SDK + semconv + collector gateway, con hallazgos de operación resueltos y documentados |
| 3 | AIOps | **3** | Umbrales dinámicos con correlación y `trace_id`, validados con fuego real; baseline aún frágil |
| 4 | Network Observability | **3** | Flow logs + mesh L7 parcial + análisis N-S/E-W; métricas por par incompletas (preview) |
| 5 | Security Observability | **3** | Golden signals + detección de intruso demostrada + CVE scanning; SCC bloqueado por entorno |
| 6 | DataOps | **3** | DB spans semconv completos y capa de datos visible en red; sin linaje ni calidad de datos |
| 7 | SRE | **3** | SLOs formales con error budget y guardrails; sin runbooks ni proceso on-call |
| 8 | Chaos Engineering | **4** | Game Days con protocolo formal, mecanismos reversibles y MTTD medido |

**Madurez global: 3.4 / 5** — un sistema *gestionado* en sus fundamentos (pilares, instrumentación, caos) con dominios operativos (AIOps, seguridad, SRE) en nivel *definido*.

## Evaluación por dominio

### 1. Tres Pilares (trazas, métricas, logs) — Nivel 4

**Evidencia:** los 3 microservicios emiten las 3 señales correlacionadas por `trace_id` W3C (verificado: log `stats.orders.served` ↔ traza en Cloud Trace con el mismo id). Métricas SLI propias (disponibilidad, latencia, saturación, throughput) + histograma DB custom. Dashboards en Grafana local (10 paneles) y cloud (9). Pipeline validado bajo carga (k6: 8,004 req, 0 errores, todas las señales fluyendo).
**Para nivel 5:** logs por OTLP (hoy van por stdout→Cloud Logging, no por el collector), estrategia de sampling formal (tail-based), y exemplars conectando métricas→trazas en todos los paneles.

### 2. OpenTelemetry — Nivel 4

**Evidencia:** auto-instrumentación + spans custom de negocio, **DB Semantic Conventions completas** en data-service (`db.system.name`, `db.namespace`, `db.operation.name`, `db.query.text`, `server.address` — visibles en Cloud Trace). Collector como gateway dual (local→Jaeger/Tempo/Prometheus; cloud→Cloud Trace/GMP/Logging). Tres hallazgos de operación resueltos con evidencia: CPU throttling que congelaba el export de spans (fix: `no-cpu-throttling` + BSP 1 s), identidad de instancia (`service.instance.id` por proceso), y mutación de labels que generaba cardinalidad y duplicados en GMP.
**Para nivel 5:** tail-based sampling (el benchmark local midió −38% throughput sin muestreo), OTLP autenticado hacia el collector, y gestión de versiones de semconv.

### 3. AIOps — Nivel 3

**Evidencia:** regla de correlación `error_rate > baseline+2σ` **Y** `p99 > SLO` como política PromQL evaluada cada 30 s, con baseline auto-aprendido; alerta enriquecida con `trace_id` vía log-based alert; grupo de control de umbrales estáticos para comparación de ruido. Validada con fuego real (chaos 30%: dispara durante la inyección, calla fuera).
**Por qué no 4:** el baseline demostró fragilidad ante ruido histórico — la σ contaminada por los propios experimentos dejó ciego al detector (intento 1 del experimento de latencia), y hubo que acotar la ventana de aprendizaje. La detección nativa de la plataforma (Anomaly Detection gestionado) no se usó. La lección quedó documentada: *un detector estadístico vale lo que valga la limpieza de su ventana de entrenamiento*.
**Para nivel 4-5:** baselines estacionales largos sobre operación limpia, detección multivariable, supresión de alertas durante ventanas de mantenimiento/caos declaradas.

### 4. Network Observability — Nivel 3

**Evidencia:** VPC `obs-vpc` con Flow Logs en las 3 subredes (sampling 0.5) capturando el tráfico real apis↔DB por IP privada; Cloud Service Mesh sobre Cloud Run **sin GKE** (mesh `obs-mesh`, rutas HTTPRoute, Envoy en orders-api) con el hop del mesh visible dentro de la traza distribuida y `xds/connected_clients=1`; análisis N-S vs E-W en dashboard.
**Por qué no 4:** la telemetría L7 por par origen→destino quedó incompleta — las métricas del LB interno no se emiten para rutas mesh con NEG serverless (limitación del preview), y dos incompatibilidades acotaron el alcance (sidecar captura todo RFC-1918 → cliente mesh no convive con DB por IP privada; sidecar no arranca con egress all-traffic).
**Para nivel 4-5:** mesh GA con métricas por par, mTLS estricto, y correlación automática flow-logs↔trazas.

### 5. Security Observability — Nivel 3

**Evidencia:** dashboard "Golden Signals de Seguridad" (auth fallidos, tráfico anómalo, N-S/E-W, CVEs) como código; detección de tráfico anómalo **demostrada con un intruso real** (VM en subnet-public → Postgres: 5/5 conexiones TCP registradas por flow logs, métrica contó, alerta disparó) — que además reveló que el peering PSA no atraviesa el firewall de subred, convirtiendo la detección en la línea de defensa efectiva; escaneo de CVEs habilitado en Artifact Registry.
**Por qué no 4:** Security Command Center no es activable (requiere Organización; proyecto en cuenta personal — verificado en consola), así que la postura de configuración se cubre parcialmente; el panel de auth fallidos no tiene datos porque la superficie actual es pública.
**Para nivel 4-5:** migrar a una Organización y activar SCC Standard, endurecer ingress (encendiendo el panel de auth), y respuesta automatizada a hallazgos.

### 6. DataOps — Nivel 3

**Evidencia:** `data-service` trata el acceso a datos como ciudadano de primera: spans de DB con semconv completas (query, namespace, operación, servidor), histograma `db.operation.duration`, usuario de solo lectura con grants mínimos, y la conversación app↔DB visible en flow logs por IP privada. Las trazas separan el costo de conexión (68 ms en frío) del costo de query (7.5 ms) — diagnóstico real de capa de datos.
**Para nivel 4-5:** monitoreo de queries lentas con umbrales propios, linaje de datos, métricas de calidad/frescura de datos, y presupuestos de latencia por consulta.

### 7. SRE — Nivel 3

**Evidencia:** 6 SLOs formales en Cloud Monitoring (disponibilidad 99.5%, latencia <500 ms al 95%, rolling 7d) con error budget calculado por la plataforma; panel de burn rate (umbral PAGE 14.4); guardrails de coste operados como práctica (DB apagada fuera de sesión, escala a cero); ingeniería de capacidad guiada por telemetría (pools dimensionados con evidencia del lab anterior).
**Por qué no 4:** no hay runbooks por alerta, ni proceso on-call, ni postmortems formales (los Game Days documentados son lo más cercano). El análisis de error budget se hace ad-hoc, no como política de freeze/release.
**Para nivel 4-5:** runbook por política de alerta, burn-rate multiventana como criterio de paging, y decisiones de release atadas al budget.

### 8. Chaos Engineering — Nivel 4

**Evidencia:** protocolo formal heredado y refinado del Game Day 3.2 (hipótesis Given/When/Then, blast radius, rollback, criterio de aborto, "no ocultar"); mecanismos de inyección reversibles por env vars con default seguro (latencia y error rate con errores lentos realistas); experimentos ejecutados en local y nube con evidencia en las 3 señales; **MTTD medido con cronómetro contra las alertas reales** (Fase 5: latencia gris de 200 ms y error rate 10%) <!-- PENDIENTE: MTTD medidos -->; el intento fallido de detección (σ contaminada) documentado como parte del experimento, no ocultado.
**Para nivel 5:** experimentos programados y automatizados (no manuales), inyección en la capa de datos, y verificación continua de los detectores como parte del CI.

## Roadmap de mejora — 3 meses

Objetivo: subir la madurez global de **3.4 a ~4.0**, priorizando lo que reduce riesgo operativo real.

### Mes 1 — Confiabilidad de la detección (AIOps 3→4, SRE 3→4)

1. **Baselines limpios y estacionales:** ventana de aprendizaje de 7 días sobre operación normal, con exclusión declarada de ventanas de mantenimiento/caos (etiqueta de supresión en las políticas). Criterio de éxito: cero falsos negativos en un game day de regresión mensual.
2. **Runbook por alerta:** cada política enlaza un procedimiento (qué mirar, qué trazas, qué rollback). Criterio: MTTR simulado < 15 min en game day.
3. **Burn-rate multiventana** (1h+6h) como criterio de paging, reemplazando umbrales por síntoma.

### Mes 2 — Costo y seguridad del pipeline (OTel 4→5, Security 3→4)

4. **Tail-based sampling 10–25%** en el collector: cierra la brecha de overhead medida en el benchmark (−38% throughput) manteniendo trazas de errores al 100%. Criterio: overhead de CPU por request < 10%.
5. **OTLP autenticado** (token de identidad en el exporter o ruta por el mesh) y collector con ingress interno — cierra el pendiente de la Fase 2.
6. **Organización de GCP + SCC Standard:** migrar el proyecto, activar SCC y triage inicial de findings. Criterio: cero findings de severidad alta sin justificar.

### Mes 3 — Automatización y datos (Chaos 4→5, DataOps 3→4)

7. **Chaos como verificación continua:** experimento de latencia mensual automatizado (Cloud Scheduler → env vars → verificación de MTTD → rollback), con reporte automático.
8. **Observabilidad de queries:** monitoreo de queries lentas (log de Cloud SQL + métrica), presupuesto de latencia por endpoint de datos.
9. **Madurez del mesh:** re-evaluar la integración Cloud Run + Cloud Service Mesh (las métricas por par y el soporte all-traffic maduran rápido); si sale de preview, completar mTLS y telemetría por par.

## Limitaciones del entorno (declaradas)

- **SCC:** requiere Organización de Google Cloud; el proyecto vive en cuenta personal. En roadmap (mes 2).
- **Métricas L7 por par del mesh:** no emitidas en la integración preview de Cloud Run; evidencia L7 por trazas y xds.
- **Baseline de anomalías:** entrenado sobre ventanas cortas controladas durante los experimentos; en producción requeriría historia limpia larga.
- **Presupuesto:** el diseño opera dentro de créditos de prueba (guardrails de coste activos); algunos niveles 5 (min-instances permanentes, SCC Premium) implican coste sostenido.
