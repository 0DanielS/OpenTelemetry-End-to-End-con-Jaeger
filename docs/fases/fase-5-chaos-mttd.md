# Fase 5 — Chaos Engineering y la prueba del MTTD

## El problema

Después de las Fases 1–4 tendremos un sistema lleno de telemetría, alertas y dashboards. Pero un sistema de observabilidad **no probado es una hipótesis**, no una capacidad. La única forma de saber si detecta incidentes es provocar uno: inyectar una falla conocida, con reloj en mano, y medir cuánto tarda la primera alerta útil.

Ese número tiene nombre: **MTTD** (Mean Time To Detect). La consigna nos exige MTTD < 2 minutos — exigente, porque las alertas de Cloud Monitoring evalúan en ventanas y cada minuto de ventana es un minuto de retraso estructural.

## Qué vamos a construir (y romper)

Dos experimentos formales, cada uno con su ficha (hipótesis, blast radius, rollback, criterio de aborto — el formato del Game Day 3.2):

| | Experimento 1 | Experimento 2 |
|---|---|---|
| Falla | Latencia **200 ms** en `inventory-api` | **Error rate 10%** en `data-service` |
| Mecanismo | `CHAOS_LATENCY_MS=200` (ya existe) | `CHAOS_ERROR_RATE=10` (construido en Fase 1) |
| Tipo de degradación | Gris: todo responde, pero lento | Parcial: 1 de cada 10 requests falla |
| Qué debe detectarlo | SLO de latencia p99 / anomalía de latencia | Regla de correlación de la Fase 3 |
| SLI golpeado | Latencia, throughput | Error rate, disponibilidad |

Nótese el contraste con el Game Day anterior: aquellos 2000 ms eran un mazazo evidente; **200 ms es una degradación sutil** — del orden del propio tiempo de respuesta normal. Detectarla separa un sistema de observabilidad decorativo de uno útil. Y el experimento 2 ejecuta por fin la hipótesis H2 que quedó diseñada y pendiente en la actividad 3.2.

## El protocolo de medición

1. Baseline estable 10+ minutos (con tráfico k6 constante — sin tráfico no hay métricas que se desvíen).
2. Inyección en `T0` exacto (el timestamp del `gcloud run services update` queda en la revisión — trazabilidad gratis).
3. Cronómetro hasta `T1` = timestamp de la primera alerta disparada. **MTTD = T1 − T0.**
4. Rollback, verificación de retorno al baseline, y las tres preguntas de la consigna:
   - ¿Se degradó el SLO? (mirar el SLI contra su objetivo durante la ventana)
   - ¿Cuánto error budget se consumió? (Cloud Monitoring lo calcula por SLO)
   - ¿La alerta fue accionable? (¿llegó con `trace_id`? ¿la traza explicaba la causa?)

## Conceptos clave

- **MTTD vs MTTR:** detectar vs. reparar. Este lab mide detección; pero un MTTD corto es prerrequisito de cualquier MTTR decente — no se arregla lo que no se ve.
- **Falla gris:** la más peligrosa en producción; nada "se cae", todo se degrada. Los umbrales estáticos suelen no verla; las anomalías estadísticas sí.
- **Error budget como moneda:** el experimento 2 gastará presupuesto real del SLO de data-service. Documentar ese gasto convierte el caos en una decisión de ingeniería ("¿nos alcanza el budget para este experimento?") — así se practica en serio.
- **Condición de aborto:** el caos controlado siempre define cuándo parar (5xx sostenidos, timeouts en cascada). El rollback inmediato es parte del experimento, no su fracaso.

## Ajustes que quizá haya que hacer

Para lograr MTTD < 2 min probablemente haya que afinar las alert policies (ventanas de alineación cortas, duración 0, notificación inmediata) y considerar `min-instances=1` en el collector durante la ventana (la lección del Game Day: escalando desde cero pierde los primeros exports). Documentar ese tuning **es parte del entregable** — demuestra entender el pipeline de detección de punta a punta.

## Evidencia que deja

- `GAMEDAY-2.md` con las dos fichas, cronología T0/T1, MTTD medido y las tres respuestas por experimento.
- Capturas: revisiones de Cloud Run, alerta disparada con `trace_id`, dashboards durante la ventana, consumo de error budget.
- Comparativa de ruido estático vs. anomalías durante los experimentos (cierra la evidencia de la Fase 3).
