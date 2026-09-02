# Game Day 2 — Chaos Engineering con MTTD medido (Fase 5 del Lab Integrador)

Dos experimentos formales contra el sistema completo en GCP, con las alertas de la Fase 3 como detectores y cronómetro entre inyección y detección. Protocolo heredado del Game Day 3.2: hipótesis, blast radius acotado, rollback por variables de entorno con default seguro, criterio de aborto y "no ocultar".

**Condiciones comunes:** tráfico continuo de fondo (POST /orders + GET /stats cada ~1.5 s), base de datos encendida, collector caliente, evaluación de políticas cada 30 s con ventanas de detección `[2m]` y baseline auto-aprendido `[20m:1m]`.

## Experimento 1 — Falla gris: latencia 200 ms en inventory-api

### Ficha

| Parámetro | Valor |
|---|---|
| Hipótesis (H1) | Dado inventory-api estable, cuando se inyectan 200 ms en la reserva, la anomalía de latencia (p99 > baseline+2σ+20ms) detecta en < 2 min, mientras el umbral estático (p99 > 500 ms) permanece ciego |
| Mecanismo | `CHAOS_ENABLED=true, CHAOS_LATENCY_MS=200` (revisión nueva de Cloud Run = trazabilidad) |
| Blast radius | Solo la reserva de inventory; `/health`, DB y collector intactos |
| Rollback | `CHAOS_ENABLED=false, CHAOS_LATENCY_MS=0` |
| Aborto | 5xx sostenidos en orders, timeouts en cascada, revisión inestable |
| Detector | Política `ANOMALIA latencia p99 vs baseline — inventory-api` |
| Control (ruido) | Política `ESTATICO latencia p99 > 500ms — inventory-api` |

### Intento 1 — fallido, con la lección más valiosa del día

Inyección 01:34Z sobre baseline de 8 min. El p99 de inventory subió de ~30 ms a **248.5 ms** (el caos funcionó), pero el detector con baseline `[1h:5m]` **nunca disparó**: la ventana de 1 hora contenía los experimentos y cold starts de toda la noche, con σ = **110.8 ms** y avg = 119.7 ms → umbral en **361 ms**, por encima de la degradación real.

> **Hallazgo H6:** un detector estadístico entrenado sobre una ventana contaminada por caos operativo queda ciego ante la siguiente degradación real. En producción, el baseline se aprende de días de operación limpia y las ventanas de mantenimiento/caos se excluyen (supresión declarada). Para el experimento, la ventana se acotó a `[20m:1m]` alimentada por la fase de baseline limpio del propio protocolo.

Verificación del diagnóstico (queries reproducibles contra Managed Prometheus):

```
avg_over_time((p99_5m)[1h:5m])    → 119.68 ms
stddev_over_time((p99_5m)[1h:5m]) → 110.77 ms   ← σ inflada por picos de 700–2400 ms previos
```

Rollback limpio; se reejecutó con baseline de 25 min de operación limpia.

### Intento 2 — resultado (2026-09-02, baseline limpio de 25 min)

| Métrica | Valor |
|---|---|
| T0 (revisión con caos sirviendo) | 02:14:09Z |
| T1 (condición del detector verdadera) | 02:14:28Z |
| **MTTD** | **19 segundos** (objetivo: < 120 s) |
| p99 baseline → bajo caos | 9.95 ms → 234–248.5 ms |
| Umbral estático (500 ms) | **Silencio durante toda la inyección** — falso negativo del grupo de control, como se predijo |
| ¿SLO degradado? | **No** — 248 ms queda dentro del SLO de 500 ms; la degradación gris es real pero no viola la promesa |
| ¿Error budget consumido? | **No** — budget del SLO de latencia: 98.20% antes → 98.24% después (sin consumo) |
| ¿Alerta accionable? | Sí — anomalía con contexto de baseline; el on-call sabe que el "normal" era ~10 ms |
| Recuperación post-rollback | p99 de vuelta a 22 ms en < 3 min; condición vacía |

**Observación del detector adaptativo:** a partir de T0+4 min la condición volvió a vacío con el caos aún activo — la ventana de baseline `[20m:1m]` fue absorbiendo los 248 ms como "nuevo normal". Es el comportamiento esperado de una ventana adaptativa corta: detecta el *cambio*, no el *estado*. El incidente ya estaba abierto (autoClose 30 min), así que la detección no se pierde; en producción, la ventana larga del roadmap (7 días) hace la adaptación mucho más lenta que cualquier incidente.

## Experimento 2 — Errores parciales: error rate 10% en data-service

### Ficha

| Parámetro | Valor |
|---|---|
| Hipótesis (H2, la pendiente desde la actividad 3.2) | Dado data-service estable, cuando el 10% de las consultas falla con 500 (errores lentos de 600 ms, como fallan las dependencias reales), la regla de correlación detecta en < 2 min y entrega el `trace_id` del fallo |
| Mecanismo | `CHAOS_ENABLED=true, CHAOS_ERROR_RATE=10` (con `CHAOS_ERROR_LATENCY_MS=600` por defecto) |
| Blast radius | Solo los endpoints `/stats/*` de data-service; el flujo de pedidos no depende de él (aislamiento por diseño de la Fase 1) |
| Rollback | `CHAOS_ENABLED=false, CHAOS_ERROR_RATE=0` |
| Detector | Política `CORRELACION anomalia error rate + latencia SLO — data-service` |
| Enriquecimiento | Política `LOG errores inyectados con trace_id` (el incidente incluye el log con `trace_id`/`span_id`) |
| Control (ruido) | Política `ESTATICO error rate > 1% — data-service` (dispara, pero sin contexto) |

### Resultado (2026-09-02)

| Métrica | Valor |
|---|---|
| T0 (revisión con caos sirviendo) | 02:38:12Z |
| T1 (condición de correlación verdadera) | 02:38:53Z |
| **MTTD** | **41 segundos** (objetivo: < 120 s) |
| Error rate observado (ventana 2m) | 2.7% → 19% (promedio ~10%, con la varianza natural del muestreo) |
| p99 observado | 16.4 ms → 600–738 ms (los errores lentos de 600 ms empujaron el p99 sobre el SLO, como se diseñó) |
| ¿SLO degradado? | **Sí** — 10% de errores contra un SLO de disponibilidad de 99.5% (presupuesto de 0.5%) |
| ¿Error budget consumido? | **Sí, cuantificado**: la fracción de budget del SLO `disponibilidad-99-5` pasó de −3.64 a −4.85 — el presupuesto semanal ya estaba agotado por las validaciones del día y el experimento consumió el equivalente a **1.2 presupuestos adicionales** en 8 minutos |
| ¿Alerta accionable? | Sí — doble confirmación (errores anómalos Y p99 > SLO) + el incidente de la log-based alert incluye el log `chaos.error.injected` con `trace_id`/`span_id` |
| Umbral estático (error > 1%) | También disparó (1.3%→10.9%) — detecta, pero solo dice "hay errores": sin baseline, sin confirmación de impacto, sin trace |
| Recuperación post-rollback | p99 de vuelta a 24.8 ms en < 3 min; condición vacía |

El detector osciló brevemente a vacío en dos evaluaciones (02:42–02:43) cuando el ratio de la ventana corta rozó el umbral — el `duration: 0s` reabre al ciclo siguiente; con `duration: 60s` se estabilizaría a costa de +60 s de MTTD. Trade-off documentado.

## Comparación de calidad de alertas (estático vs. dinámico)

| Escenario | Sistema estático | Sistema dinámico/correlacionado |
|---|---|---|
| Falla gris (exp 1, 200 ms) | **Falso negativo** — p99 248 ms < umbral 500 ms, silencio total | Detecta: p99 ≫ baseline+2σ del período limpio |
| Errores parciales (exp 2, 10%) | Dispara (10% > 1%) pero solo dice "hay errores" | Dispara con doble confirmación (errores anómalos Y latencia sobre SLO) + `trace_id` del fallo en el incidente |
| Tráfico sano (k6 8,004 req) | Silencio | Silencio |

## Observaciones no ocultadas

- El intento 1 del experimento 1 falló por σ contaminada (documentado arriba como H6) — el "fallo del detector" es parte del resultado del game day, no un descarte.
- La medición de T1 usa la evaluación de la condición PromQL (cada 30 s) como proxy del incidente; el incidente de Cloud Monitoring y el correo de notificación agregan segundos de pipeline de notificación al MTTD percibido.
- Con `min-instances=1` en inventory (hallazgo H7) y collector caliente, las mediciones no incluyen ruido de cold start.
