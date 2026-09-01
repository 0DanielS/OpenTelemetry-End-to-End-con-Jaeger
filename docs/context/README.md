# Contexto del proyecto

Carpeta de contexto para trabajar el **Laboratorio Integrador** (consigna y plan en [`../../LAB-INTEGRADOR.md`](../../LAB-INTEGRADOR.md)). Consolida todo lo entregado en los momentos anteriores del módulo de Observabilidad para no depender de documentos externos (PDF/DOCX).

| Archivo | Contenido | Fuente |
|---|---|---|
| [`01-lab-u2-pipeline-otel.md`](01-lab-u2-pipeline-otel.md) | Laboratorio base U2: pipeline OTel end-to-end, instrumentación, overhead, despliegue GCP y dimensionamiento | `LAB Pipeline OpenTelemetry End-to-End con Jaeger y Prometheus en GCP U2.pdf` |
| [`02-gameday-chaos-3.2.md`](02-gameday-chaos-3.2.md) | Game Day de Chaos Engineering (actividad 3.2): hipótesis, experimentos, resultados local y GCP, remediaciones | `Game_Day_Chaos_Engineering_Actividad_3.2.docx` + `Guia_Ejecucion_Game_Day_Local_y_GCP.docx` + `GAMEDAY.md` |
| [`03-infraestructura-gcp.md`](03-infraestructura-gcp.md) | Inventario de la infraestructura GCP actual: proyecto, servicios, SAs, WIF, secretos, guardrails y notas operativas | `scripts/gcp-bootstrap.sh`, `DEPLOY.md`, `deploy/` |
| [`04-decisiones-red-y-mesh.md`](04-decisiones-red-y-mesh.md) | Decisiones del lab integrador: solo GCP, mesh sobre Cloud Run sin GKE, diseño de VPC y subnets | Decisiones del equipo + docs de Cloud Service Mesh |

## Contexto en una frase

Sistema de 2 microservicios FastAPI (`orders-api` → `inventory-api`) instrumentado con OpenTelemetry (3 señales correlacionadas por `trace_id` W3C), desplegado en Cloud Run + Cloud SQL con CI/CD sin llaves (WIF), telemetría en Cloud Trace / Managed Prometheus / Cloud Logging, con un Game Day de latencia ya ejecutado; el Laboratorio Integrador agrega `data-service`, service mesh, AIOps, observabilidad de red/seguridad, dos experimentos de caos con MTTD < 2 min y reporte de madurez — todo únicamente en GCP.

## Datos del equipo

- Nestor Alejandro Rodriguez Benavides — nestorrobe@unisabana.edu.co
- Carlos Daniel Sandoval — carlossandpar@unisabana.edu.co
- Peter Alexander Palacios Garnica — peterpaga@unisabana.edu.co
- Maestría en Arquitectura de Software, Universidad de La Sabana — Observabilidad en Ambientes Productivos
- Docente: María Fernanda Ochoa Paipilla
- Repositorio: `github.com/0DanielS/OpenTelemetry-End-to-End-con-Jaeger`
