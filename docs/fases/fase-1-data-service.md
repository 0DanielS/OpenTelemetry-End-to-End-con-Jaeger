# Fase 1 — `data-service`: el tercer microservicio

## El problema

La rúbrica pide **tres** microservicios instrumentados y un dominio que hoy no cubrimos bien: **DataOps**, la observabilidad del acceso a datos. Nuestros dos servicios actuales usan la base como detalle interno; ninguno la trata como su razón de ser. Además, el experimento de caos #2 ("error rate 10% en data-service") y la detección de anomalías del Módulo B se ejecutan **sobre este servicio** — sin él, media consigna se cae.

## Qué vamos a construir

`data-service` (carpeta `service-c/`): un servicio FastAPI de **consultas analíticas** sobre lo que los otros dos escriben. Mientras `orders-api` e `inventory-api` son transaccionales (escriben pedidos, descuentan stock), `data-service` responde preguntas: cuántos pedidos hubo, qué productos se venden más, cómo viene el volumen por hora.

Tres piezas lo distinguen de sus hermanos:

1. **Database spans con Semantic Conventions de OTel.** Los servicios actuales tienen un histograma custom de latencia de DB, pero sus spans de base de datos son los que la auto-instrumentación regala. En `data-service` los spans de DB se construyen a conciencia con los atributos estándar (`db.system.name`, `db.namespace`, `db.operation.name`, `db.query.text`, `server.address`). ¿Por qué importa un estándar? Porque cualquier herramienta (Cloud Trace, Grafana, un vendor futuro) sabe interpretar esos atributos sin configuración: el estándar es lo que hace a la telemetría portable.
2. **Caos por error rate (`CHAOS_ERROR_RATE`).** El mecanismo gemelo del `CHAOS_LATENCY_MS` que ya existe: un porcentaje configurable de requests devuelve 500, dejando en el log el `trace_id` del request sacrificado. Se construye ahora, apagado por defecto, para que la Fase 5 solo tenga que encenderlo.
3. **Integración al flujo real.** `orders-api` lo llamará (y k6 le pegará directo) para que aparezca en las trazas end-to-end: una traza que muestre `orders → inventory → base` y `orders → data-service → base` bajo un mismo `trace_id`.

## Conceptos clave

- **Semantic Conventions:** el "vocabulario oficial" de OpenTelemetry. Un span que dice `db.operation.name=SELECT, db.namespace=analytics` lo entiende cualquier backend; uno que dice `mi_query=...` solo lo entiendes tú.
- **DataOps observability:** no basta saber que "la API tardó"; hay que poder responder *qué consulta*, *contra qué base*, *cuánto tardó el motor vs. la red*. Los DB spans responden eso por diseño.
- **Blast radius por diseño:** el caos se construye dentro del servicio con switches explícitos y default seguro — la lección del Game Day 3.2 (`--set-env-vars` borra las variables → el servicio siempre vuelve solo a estado seguro).

## Cómo se ve funcionando

- `GET /stats/top-products` responde con datos reales de la base `analytics` (o leyendo `orders` según diseñemos).
- En Cloud Trace, la traza muestra el span HTTP del endpoint y, colgando de él, un span `SELECT analytics` con todos los atributos semconv.
- `CHAOS_ERROR_RATE=10` convierte 1 de cada 10 requests en un 500 con `trace_id` en el log; `CHAOS_ERROR_RATE=0` lo apaga.

## Evidencia que deja

- Código de `service-c/` con instrumentación completa (3 señales).
- Base/usuario/secret nuevos en Cloud SQL (extensión de `gcp-bootstrap.sh`).
- Workflow de CI/CD `deploy-data.yml` y servicio en Cloud Run dentro de la VPC.
- Captura de una traza con DB spans semconv — la evidencia estrella del Módulo A.
