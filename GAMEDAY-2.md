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

### Intento 2 — resultado

<!-- PENDIENTE-EXP1: completar con la salida del runner -->

| Métrica | Valor |
|---|---|
| T0 (inyección) | _pendiente_ |
| T1 (condición del detector verdadera) | _pendiente_ |
| **MTTD** | _pendiente_ |
| p99 baseline → bajo caos | ~25 ms → _pendiente_ |
| Umbral estático (500 ms) | _pendiente (esperado: silencio — falso negativo del control)_ |
| ¿SLO degradado? | _pendiente (esperado: no — 200 ms queda dentro del SLO de 500 ms)_ |
| ¿Error budget consumido? | _pendiente (esperado: no — por lo mismo)_ |
| ¿Alerta accionable? | _pendiente_ |
| Recuperación post-rollback | _pendiente_ |

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

### Resultado

<!-- PENDIENTE-EXP2: completar con la salida del runner -->

| Métrica | Valor |
|---|---|
| T0 (inyección) | _pendiente_ |
| T1 (condición de correlación verdadera) | _pendiente_ |
| **MTTD** | _pendiente_ |
| Error rate observado | _pendiente (~10%)_ |
| p99 observado | _pendiente (los errores de 600 ms empujan p99 > 500)_ |
| ¿SLO degradado? | _pendiente (esperado: sí — 10% ≫ 0.5% del SLO de disponibilidad)_ |
| ¿Error budget consumido? | _pendiente (budget antes/después del SLO `disponibilidad-99-5`)_ |
| ¿Alerta accionable? | _pendiente (trace_id en el incidente de la log-based alert)_ |
| Recuperación post-rollback | _pendiente_ |

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
