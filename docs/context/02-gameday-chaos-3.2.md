# Actividad 3.2 — Game Day de Chaos Engineering

Resumen del informe `Game_Day_Chaos_Engineering_Actividad_3.2.docx` (28 de agosto de 2026) y de la `Guia_Ejecucion_Game_Day_Local_y_GCP.docx`. Complementa a `GAMEDAY.md` (versión en repo del mismo experimento). Rama de trabajo original: `feature/chaos-gameday` (mergeada en PR #14).

## Hipótesis planteadas

| ID | Given / When / Then |
|---|---|
| H1 | Dado `inventory-api` estable, cuando se inyectan 2000 ms de latencia, aumentará la latencia end-to-end de forma observable sin pérdida de disponibilidad. |
| H2 | Dadas reservas correctas, cuando `inventory-api` responde 500/503 controlados, aumentarán los errores de `orders-api`, correlacionables con telemetría. |
| H3 | Dado tráfico normal, cuando aumenta la concurrencia con k6, se observará degradación de latencia o errores cerca del límite de capacidad. |

## Experimentos diseñados

| Exp. | Fallo / blast radius | Control y rollback | SLI |
|---|---|---|---|
| E1 | Latencia 2000 ms solo en la reserva de `inventory-api`; `/health`, DB y Collector fuera | Duración acotada; desactivar CHAOS | Latencia e2e, éxito, throughput |
| E2 | 500/503 controlados solo en la reserva | Ventana corta; desactivar inyección | Error rate, disponibilidad |
| E3 | Sobrecarga k6 contra `orders-api` | 2–5 min; detener tráfico | Throughput, p95/p99, error rate |

**Solo E1 se ejecutó.** E2 (errores controlados) quedó diseñado pero no implementado ni ejecutado — es exactamente lo que el Laboratorio Integrador pide como experimento de error rate 10% (ahora sobre `data-service`).

## Mecanismo de inyección

`inventory-api` lee `CHAOS_ENABLED` / `CHAOS_LATENCY_MS` al arrancar; dentro del span `reserve_stock`, antes de tocar la DB, ejecuta `await asyncio.sleep(...)`, agrega atributos `chaos.enabled` / `chaos.latency_ms` al span y emite el evento de log `chaos.latency.injected` con `latency_ms`, `product_id`, `trace_id`, `span_id`. Default `false/0` = comportamiento normal.

## Resultados E1 en local (k6 spike hasta 150 VUs)

| Métrica | Baseline | Chaos 2000 ms |
|---|---|---|
| Requests | 18 810 | 5 939 |
| Throughput | 72.32 req/s | 22.67 req/s (−69%) |
| Promedio | 752.67 ms | 2.40 s |
| Mediana | 489.58 ms | 2.05 s |
| p95 | 2.19 s | 3.67 s |
| p99 | 5.36 s | 4.12 s (variabilidad del spike; no se interpreta aislado) |
| Errores / checks | 0% / 100% | 0% / 100% |

Jaeger mostró la traza e2e de ~2.02 s con el span de reserva de 2 s y los atributos de chaos; los spans de persistencia siguieron en milisegundos (DB descartada como causa). Rollback: petición manual pasó de 2.059 s a ~0.301 s.

Hallazgo del baseline: el threshold p99 < 500 ms ya se incumplía sin chaos bajo spike — sensibilidad a alta concurrencia.

## Resultados E1 en GCP (Cloud Run, instancia caliente)

Activación/rollback sin rebuild: solo `gcloud run services update --update-env-vars`, cada cambio deja una revisión como trazabilidad:

| Revisión | Estado | CHAOS_ENABLED / LATENCY_MS |
|---|---|---|
| `inventory-api-00006-qv4` | Despliegue del mecanismo | (ausentes) |
| `inventory-api-00007-hhq` | Estable explícito | false / 0 |
| `inventory-api-00008-qv6` | Game Day activo | true / 2000 |
| `inventory-api-00009-9gr` | Rollback | false / 0 |

| Fase | Tiempos (3 intentos) | Status |
|---|---|---|
| Estable | 0.252 / 0.269 / 0.239 s | 201 |
| Chaos 2000 ms | 2.318 / 2.290 / 2.285 s | 201 |
| Post-rollback | 0.240 / 0.249 / 0.272 s | 201 |

Delta +2.04 s, consistente con la inyección. `/health` respondió 0.246 s con chaos activo (blast radius acotado). La primera petición tras cada revisión se descartó por cold start (hasta 10.2 s con escala a cero).

Evidencia de correlación: traza `88cd90ee3a29f4a6ac0e480963f9f707` en Cloud Trace con span `reserve_stock` de 2.021 s (el UPDATE contra Cloud SQL tomó 12.5 ms); Cloud Logging registró 4 eventos `chaos.latency.injected`; el `span_id` `6f1f5998f3e2a77b` del primer evento coincide con el span de Cloud Trace. En Managed Prometheus el p95 hizo onda cuadrada: 23.5 ms → 2275–2350 ms (01:43–01:47 UTC) → 24.2 ms. DB p99 solo subió de 24 a 48 ms.

## Caveats operativos documentados (no ocultar)

- El Collector en Cloud Run reportó `DEADLINE_EXCEEDED` exportando trazas al escalar desde cero: la traza `c5f654eed8...` está en Cloud Logging pero no en Cloud Trace. **La correlación log→traza no está garantizada en las primeras peticiones con el collector frío.**
- `scripts/deploy.sh` usa `--set-env-vars` (reemplaza TODAS las variables): cualquier redespliegue borra las variables de chaos y devuelve el servicio a estado seguro por defecto.
- No existe `gcloud trace traces describe`; hay que usar la API REST v1 de Cloud Trace.
- Logs de structlog llegan como `jsonPayload`: filtrar con `jsonPayload.event="chaos.latency.injected"`, no con `textPayload`.
- La consola GCP requiere `&authuser=1` (la cuenta del proyecto no es la primera del navegador).
- El plugin `grafana-lokiexplore-app` rompe el render de la grilla del dashboard cloud; workaround: abrir paneles individuales con `&viewPanel=<id>`.

## Análisis y remediaciones propuestas

- **H1 confirmada** (local y nube): una dependencia síncrona lenta degrada la experiencia e2e y reduce capacidad sin indisponibilidad inmediata; mecanismo totalmente reversible.
- **Debilidad sistémica: acoplamiento temporal** — `orders-api` espera síncronamente a `inventory-api` (timeout 10 s); una dependencia lenta propaga latencia aguas arriba.
- Remediaciones: timeouts alineados con el SLO + **circuit breaker**; retries limitados con backoff/jitter solo ante fallos transitorios; bulkhead/límites de concurrencia; **SLOs y alertas sobre p95/p99, error rate, throughput y duración de llamadas a inventory-api** (todavía no existen — los crea el Lab Integrador, Fase 3).

## Criterios de la guía de ejecución (reutilizables en los nuevos experimentos)

- **Éxito:** la latencia e2e aumenta de forma observable, el servicio registra la inyección con `trace_id`/`span_id`, el flujo sigue disponible y tras el rollback vuelve al baseline.
- **Abortar:** 5xx sostenidos en `orders-api`, `inventory-api` sin responder, timeouts no controlados o revisión de Cloud Run inestable → rollback inmediato conservando la evidencia.
- Evidencias mínimas: captura de revisión estable, captura de env vars de chaos activas, tiempos de respuesta durante chaos, logs con el evento de inyección, traza (si está disponible), resultado del rollback y cualquier diferencia frente a lo esperado sin ocultarla.
