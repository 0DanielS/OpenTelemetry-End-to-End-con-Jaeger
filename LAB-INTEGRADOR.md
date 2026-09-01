# Laboratorio Integrador — Sistema Observable Completo en GCP

Continuación de los laboratorios anteriores (2.2). Este momento integra todos los dominios de Observability (Tres Pilares, OpenTelemetry, AIOps, Network Observability, DataOps, SRE) en un sistema observable de nivel producción, desplegado en producción simulada sobre **Google Cloud Platform**.

> **Alcance refinado:** la consigna original contempla GCP y AWS; este proyecto se implementa **únicamente en GCP**. Cada referencia a AWS (RDS, App Mesh, DevOps Guru, Security Hub) se resuelve con su equivalente de GCP.

## Objetivo

Integrar todos los dominios del Observability en un sistema observable completo desplegado en producción simulada sobre GCP, demostrando:

- Detección automática de anomalías (AIOps).
- Respuesta a incidentes basada en datos (correlación por `trace_id`).
- Validación de resiliencia mediante experimentos de caos controlados.

**Indicador de desempeño:** utilizar herramientas de observabilidad favoreciendo la detección y resolución de problemas en tiempo real, mejorando la resiliencia del sistema.

## Punto de partida (laboratorio 2.2)

| Componente existente | Estado |
|---|---|
| `orders-api` (service-a, FastAPI) | Instrumentado con OTel SDK (3 señales), en Cloud Run |
| `inventory-api` (service-b, FastAPI) | Instrumentado con OTel SDK (3 señales), en Cloud Run, con inyección de caos por env vars |
| OTel Collector (gateway) | Local y en Cloud Run (`deploy/otel-collector-cloud`) |
| Backends | Cloud Trace, Managed Prometheus, Cloud Logging; local: Jaeger/Tempo/Prometheus |
| Grafana | Dashboard SLI/SLO en local (10 paneles) y Cloud Run (9 paneles) |
| Base de datos | Cloud SQL (Postgres: `orders` e `inventory`) |
| Chaos previo | Game Day de latencia 2000 ms sobre `inventory-api` (ver `GAMEDAY.md`) |

## Módulo A — Arquitectura Observable Completa

1. **Tercer microservicio `data-service`** que acceda a **GCP Cloud SQL** (se omite AWS RDS).
2. Instrumentación completa con **OTel SDK (3 pilares)**, incluyendo **database spans** con las [OTel DB Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/database/) (`db.system`, `db.namespace`, `db.operation.name`, `db.query.text`, etc.).
3. **Service mesh básico** con **Cloud Service Mesh** (managed Anthos Service Mesh / Istio) para observabilidad de red L7: métricas de tráfico servicio-a-servicio, mTLS y telemetría L7 sin tocar el código.

Arquitectura objetivo:

```
k6 ──▶ orders-api ──▶ inventory-api ──▶ Cloud SQL (inventory)
            │                │
            └────────────────┴──▶ data-service ──▶ Cloud SQL (analytics)
                             │
                     OTLP ──▶ OTel Collector ──▶ Cloud Trace / Managed Prometheus / Cloud Logging
                             │
                     Cloud Service Mesh (telemetría L7, mTLS)
```

## Módulo B — AIOps: Detección Automática de Anomalías

1. Configurar **GCP Cloud Monitoring Anomaly Detection** sobre `data-service` (se omite AWS DevOps Guru).
2. Implementar la **regla de correlación**:

   > cuando `error_rate > baseline + 2σ` **Y** `latency_p99 > SLO_threshold` → alerta enriquecida con el `trace_id` del request fallido.

3. Demostrar la **reducción de alertas ruidosas** frente a un sistema con umbrales estáticos (evidencia cuantitativa: nº de alertas con umbral estático vs. detección de anomalías durante la misma ventana de carga).

## Módulo C — Network & Security Observability

1. Habilitar **VPC Flow Logs (GCP)** y configurar alertas sobre tráfico anómalo entre servicios.
2. Implementar **Security Command Center (GCP)** para observabilidad de seguridad (se omite AWS Security Hub).
3. Crear el dashboard **"Golden Signals de Seguridad"**:
   - Intentos de autenticación fallidos.
   - Tráfico Norte-Sur / Este-Oeste.
   - CVEs activos (Container Analysis / Artifact Registry vulnerability scanning).

## Módulo D — Chaos Engineering Controlado

Ejecutar **2 experimentos de caos** (siempre en sandbox, nunca en recursos compartidos):

| # | Experimento | Objetivo |
|---|---|---|
| 1 | Inyección de latencia en `service-b` (**200 ms**) | Degradación gris de latencia (reutiliza el mecanismo `CHAOS_ENABLED` / `CHAOS_LATENCY_MS` de `GAMEDAY.md`) |
| 2 | Error rate **10%** en `data-service` | Consumo de error budget y disparo de la alerta correlacionada del Módulo B |

Validaciones:

- El sistema de observabilidad **detecta y alerta en < 2 minutos** (MTTD objetivo).
- Documentar por cada experimento: ¿Se degradó el SLO? ¿El error budget se consumió? ¿La alerta fue accionable (incluyó `trace_id` y contexto)?

## Módulo E — Reporte de Madurez de Observabilidad

1. Autoevaluar la solución contra el **Observability Foundation Blueprint (8 dominios)** con escala de madurez **1–5**.
2. Proponer el **roadmap de mejora** para alcanzar el siguiente nivel de madurez en **3 meses**.

## Entregables

1. **Repositorio GitHub** (público, con tag de versión final **`v1.0`**):
   - Toda la IaC.
   - Código de instrumentación.
   - Configuraciones y scripts.
2. **Video de demostración** en vivo.
3. **Reporte ejecutivo final:** PDF de 10 páginas con arquitectura completa, evidencias de todos los pilares y análisis de madurez de observabilidad.

## Recomendaciones

- El repositorio debe estar público en GitHub con tag de versión final (`v1.0`).
- Los experimentos de caos deben ejecutarse en sandbox, nunca en recursos compartidos.

## Rúbrica

### Arquitectura Observable Completa (máx. 1.25)

| Nivel | Pts. | Criterio |
|---|---|---|
| Excelente | 1.25 | Tres microservicios instrumentados con OTel, service mesh y correlación completa |
| Bueno | 1.00 | Dos microservicios instrumentados y dos pilares implementados |
| Necesita mejorar | 0.75 | Arquitectura funcional en una cloud |
| Deficiente | 0.50 | Instrumentación mínima |
| No cumple | 0.00 | No presenta arquitectura funcional |

### AIOps: Detección de Anomalías y Correlación (máx. 1.00)

| Nivel | Pts. | Criterio |
|---|---|---|
| Excelente | 1.00 | Detección automática funcional con correlación y evidencia cuantitativa |
| Bueno | 0.80 | Detección funcional con alertas básicas |
| Necesita mejorar | 0.50 | Umbrales dinámicos sin correlación |
| Deficiente | 0.25 | Solo umbrales estáticos |
| No cumple | 0.00 | Sin sistema de alertas |

### Network & Security Observability (máx. 1.00)

| Nivel | Pts. | Criterio |
|---|---|---|
| Excelente | 1.00 | Observabilidad de red y seguridad funcional con dashboards y alertas |
| Bueno | 0.80 | Implementación parcial |
| Necesita mejorar | 0.50 | Configuración sin análisis |
| Deficiente | 0.25 | Evidencia insuficiente |
| No cumple | 0.00 | No implementa observabilidad de seguridad |

### Chaos Engineering y Validación de MTTD (máx. 1.00)

| Nivel | Pts. | Criterio |
|---|---|---|
| Excelente | 1.00 | Dos experimentos ejecutados, MTTD ≤ 2 minutos y análisis de SLO/error budget |
| Bueno | 0.70 | Dos experimentos con MTTD superior a 2 minutos |
| Necesita mejorar | 0.50 | Un experimento ejecutado |
| Deficiente | 0.25 | Experimento sin análisis |
| No cumple | 0.00 | No ejecuta experimentos |

### Reporte de Madurez y Presentación Técnica (máx. 0.75)

| Nivel | Pts. | Criterio |
|---|---|---|
| Excelente | 0.75 | Autoevaluación completa, roadmap accionable y demostración técnica en vivo |
| Bueno | 0.25 | Autoevaluación parcial y demostración básica |
| Necesita mejorar | 0.25 | Autoevaluación limitada |
| Deficiente | 0.10 | Presentación superficial |
| No cumple | 0.00 | No presenta informe ni sustentación |

**Total: 5.00 pts.**

## Análisis de brechas — estado actual vs. consigna

Qué ya está resuelto por el laboratorio 2.2 y qué falta construir:

| Requisito | Estado | Detalle |
|---|---|---|
| 2 microservicios instrumentados (OTel, 3 señales) | ✅ Hecho | `orders-api` + `inventory-api`, SDK manual, correlación por `trace_id` |
| Pipeline OTLP → backends GCP | ✅ Hecho | Collector en Cloud Run → Cloud Trace / Managed Prometheus / Cloud Logging |
| Cloud SQL + secretos + WIF + CI/CD | ✅ Hecho | `scripts/gcp-bootstrap.sh`, workflows de deploy por servicio |
| Dashboards Grafana (local y cloud) | ✅ Hecho | 10 paneles local, 9 en Cloud Run |
| Mecanismo de caos por latencia | ✅ Hecho | `CHAOS_ENABLED`/`CHAOS_LATENCY_MS` en service-b, Game Day 2000 ms documentado |
| k6 + benchmark de overhead | ✅ Hecho | `k6/script.js`, `benchmark/` |
| **Tercer microservicio `data-service`** | ❌ Falta | No existe; debe acceder a Cloud SQL con DB spans (semconv) |
| **Service mesh (observabilidad L7)** | ❌ Falta | Cloud Service Mesh directo sobre Cloud Run (anotación/`--mesh`), sin GKE (ver Fase 2) |
| **Alertas (cualquier tipo)** | ❌ Falta | No hay ni una alert policy en el repo ni en Cloud Monitoring |
| **Anomaly Detection + regla de correlación** | ❌ Falta | Sin baseline dinámico, sin alerta enriquecida con `trace_id` |
| **VPC Flow Logs + alertas de tráfico anómalo** | ❌ Falta | Cloud Run no pasa por VPC hoy; la VPC con 3 subredes + Direct VPC egress se crea en Fase 0 |
| **Security Command Center + dashboard de seguridad** | ❌ Falta | Sin SCC, sin golden signals de seguridad, sin escaneo de CVEs referenciado |
| **Mecanismo de caos por error rate** | ❌ Falta | Solo existe latencia; falta `CHAOS_ERROR_RATE` para data-service |
| **Medición de MTTD < 2 min** | ❌ Falta | El Game Day previo no midió MTTD (no había alertas) |
| **Análisis SLO / error budget formal** | ⚠️ Parcial | Hay SLIs y umbrales en dashboards, pero sin error budget calculado |
| **Reporte de madurez (8 dominios, escala 1–5) + roadmap** | ❌ Falta | El `reporte-tecnico.pdf` es del lab anterior, no cubre madurez |
| **IaC completa** | ⚠️ Parcial | Bootstrap en bash idempotente; lo nuevo (mesh, alertas, flow logs) debe quedar también como código |
| **Repo público + tag `v1.0`** | ⚠️ Verificar | Confirmar visibilidad y crear el tag al cierre |
| **Video + PDF ejecutivo (10 págs.)** | ❌ Falta | Se producen al final con las evidencias de todas las fases |

Dos decisiones técnicas ya tomadas (detalle en [`docs/context/04-decisiones-red-y-mesh.md`](docs/context/04-decisiones-red-y-mesh.md)):

1. **Service mesh sin GKE:** Cloud Service Mesh se integra directamente con Cloud Run — la adhesión al mesh se declara con una **anotación a nivel de revisión** (API v1) o con `gcloud beta run deploy --mesh=projects/.../meshes/MESH` + `--network`/`--subnet` (Direct VPC egress). No se migra a GKE.
2. **VPC propia con tres subredes:** `subnet-public` (Grafana), `subnet-apis` (privada: orders, inventory, data-service, collector vía Direct VPC egress) y `subnet-data` (privada: Cloud SQL por IP privada). Los VPC Flow Logs solo capturan tráfico que atraviesa la VPC, así que esta red es prerrequisito de los Módulos A (mesh) y C (flow logs).

> Todo el contexto de los laboratorios anteriores (lab U2, Game Day 3.2, inventario de infra GCP y decisiones) está consolidado en [`docs/context/`](docs/context/README.md).

## Plan de trabajo por fases

Dependencias: la Fase 5 (chaos/MTTD) necesita las alertas de la Fase 3 y el `data-service` de la Fase 1. Las Fases 2, 3 y 4 son independientes entre sí y pueden avanzar en paralelo.

### Fase 0 — Preparación y red base (1 día)

- [x] Confirmar que el repo es público (o hacerlo público) y crear rama `feature/lab-integrador`.
- [ ] Habilitar APIs nuevas: `compute.googleapis.com`, `mesh.googleapis.com`, `securitycenter.googleapis.com`, `containeranalysis.googleapis.com`, `containerscanning.googleapis.com`.
- [ ] Crear la VPC con las tres subredes del diseño ([D3](docs/context/04-decisiones-red-y-mesh.md)): `subnet-public` (Grafana), `subnet-apis` (privada, APIs + collector), `subnet-data` (privada, Cloud SQL) — con Flow Logs habilitados desde la creación.
- [ ] Reglas de firewall: apis→data permitido, público→data denegado; Grafana como único servicio con ingress `all`.
- [ ] Conectar los servicios de Cloud Run existentes a la VPC con **Direct VPC egress** (`--network`/`--subnet=subnet-apis`).
- [ ] Migrar la conexión a Cloud SQL de socket Unix a **IP privada** en `subnet-data`.
- [ ] Verificar presupuesto/billing del proyecto `opentelemetry-nrb` para los servicios nuevos.

### Fase 1 — Módulo A: `data-service` (2–3 días)

- [ ] Crear `service-c/` (FastAPI + asyncpg, mismo patrón que service-a/b): endpoints de consulta analítica sobre Cloud SQL (p. ej. `GET /stats/orders`, `GET /stats/top-products`).
- [ ] Instrumentar las 3 señales reutilizando el patrón `telemetry.py` existente.
- [ ] Database spans con **OTel DB Semantic Conventions**: `db.system.name`, `db.namespace`, `db.operation.name`, `db.query.text`, `server.address`.
- [ ] Integrarlo al flujo: `orders-api` lo invoca (o k6 lo golpea directo) para que aparezca en las trazas end-to-end.
- [ ] Agregar mecanismo de caos: `CHAOS_ERROR_RATE` (0–100) que devuelve 500 en ese porcentaje de requests, logueando `trace_id` (necesario para Fase 5).
- [ ] Local: sumarlo a `docker-compose.yml`, base `analytics` en `init-db.sql`, panel en Grafana local.
- [ ] Cloud: base/usuario/secret en Cloud SQL (extender `gcp-bootstrap.sh`), workflow `.github/workflows/deploy-data.yml`, deploy a Cloud Run conectado al Collector.
- [ ] Actualizar `k6/script.js` para incluir tráfico al data-service.
- [ ] Verificar en Cloud Trace una traza con spans de DB correctamente atributados.

### Fase 2 — Módulo A: Service mesh sobre Cloud Run (1–2 días; requiere la VPC de Fase 0)

- [ ] Crear el recurso `Mesh` (`mesh.googleapis.com`).
- [ ] Adherir `orders-api`, `inventory-api` y `data-service` al mesh: anotación de revisión o `gcloud beta run deploy --mesh=... --network --subnet=subnet-apis`.
- [ ] Definir el enrutamiento servicio-a-servicio con `HTTPRoute` (gateway `external-mesh` para cargas fuera de GKE).
- [ ] Evidenciar telemetría L7 servicio-a-servicio en Cloud Monitoring: latencia, tasa de éxito, volumen por par origen→destino.
- [ ] Autenticación servicio-a-servicio (de paso, cerrar el `--allow-unauthenticated` del Collector con ingress interno).
- [ ] Documentar en el README la topología de red resultante.

### Fase 3 — Módulo B: AIOps (2 días)

- [ ] Crear SLOs formales en Cloud Monitoring (disponibilidad y latencia p99) para los 3 servicios, con error budget.
- [ ] Alertas con umbral estático (grupo de control para la comparación de ruido).
- [ ] Habilitar **Anomaly Detection** de Cloud Monitoring sobre las métricas de `data-service`.
- [ ] Regla de correlación: `error_rate > baseline + 2σ` **Y** `latency_p99 > SLO` → alerta (MQL/PromQL combinado o alerta multi-condición).
- [ ] Enriquecer la alerta con `trace_id`: log-based alert sobre los logs de error (que ya llevan `trace_id`) o documentación de la notificación con link a Cloud Trace.
- [ ] Ejecutar la misma ventana de carga con ambos sistemas y registrar la evidencia cuantitativa: nº de alertas estáticas vs. correlacionadas.
- [ ] Dejar todas las políticas como código (gcloud/Terraform) en `deploy/monitoring/`.

### Fase 4 — Módulo C: Network & Security (2 días; la VPC y los Flow Logs vienen de Fase 0)

- [ ] Validar que los **VPC Flow Logs** de las tres subredes registran el tráfico este-oeste (apis↔apis, apis→data) y crear log-based metric + alerta de tráfico anómalo entre servicios.
- [ ] Activar **Security Command Center** (tier Standard) y revisar findings del proyecto.
- [ ] Activar escaneo de vulnerabilidades en Artifact Registry (CVEs de las imágenes).
- [ ] Dashboard **"Golden Signals de Seguridad"** (Grafana o Cloud Monitoring): auth fallidos (logs de Cloud Run/IAM), tráfico N-S vs E-W (flow logs), CVEs activos (Container Analysis).
- [ ] Dejar la configuración como código en `deploy/security/`.

### Fase 5 — Módulo D: Chaos + MTTD (1–2 días; requiere Fases 1 y 3)

- [ ] Experimento 1: latencia **200 ms** en `inventory-api` (reusar mecanismo del Game Day, nueva ficha con hipótesis/blast radius/rollback).
- [ ] Experimento 2: **error rate 10%** en `data-service` vía `CHAOS_ERROR_RATE`.
- [ ] Medir **MTTD** en ambos: timestamp de inyección vs. timestamp de la alerta disparada; objetivo < 2 min (ajustar alignment/duración de las alert policies si no llega).
- [ ] Documentar por experimento: ¿se degradó el SLO?, ¿cuánto error budget se consumió?, ¿la alerta fue accionable (incluyó `trace_id`)?
- [ ] Escribir `GAMEDAY-2.md` (o extender `GAMEDAY.md`) con capturas y queries reproducibles, como el Game Day anterior.

### Fase 6 — Módulo E y entregables (2 días)

- [ ] Autoevaluación contra el **Observability Foundation Blueprint** (8 dominios, escala 1–5) con justificación por dominio.
- [ ] Roadmap de mejora a 3 meses para subir de nivel de madurez.
- [ ] Reporte ejecutivo PDF (10 págs.): arquitectura completa, evidencias de los 3 pilares + AIOps + seguridad + chaos, análisis de madurez.
- [ ] Grabar el video de demostración en vivo (flujo completo: request → traza → métrica → log → alerta → chaos).
- [ ] Actualizar README con la arquitectura final de 3 servicios.
- [ ] Merge a `main` y crear tag **`v1.0`**.

## Mapeo consigna original → implementación GCP

| Consigna (multi-cloud) | Implementación en este proyecto |
|---|---|
| GCP Cloud SQL **y** AWS RDS | Solo **Cloud SQL** (Postgres) |
| Cloud Service Mesh / AWS App Mesh | **Cloud Service Mesh** |
| Cloud Monitoring Anomaly Detection / AWS DevOps Guru | **Cloud Monitoring Anomaly Detection** |
| VPC Flow Logs (GCP) y VPC Flow Logs (AWS) | **VPC Flow Logs (GCP)** |
| Security Command Center / AWS Security Hub | **Security Command Center** |
