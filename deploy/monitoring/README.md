# Monitoreo como código (Fase 3 — AIOps)

Aplica todo con:

```bash
./deploy/monitoring/apply.sh
```

Idempotente: no duplica canales, políticas ni SLOs existentes. `NOTIFY_EMAIL` (default `nestorx211@gmail.com`) controla el canal de notificación.

## Qué crea

### SLOs con error budget (por cada uno de los 3 servicios)

| SLO | Objetivo | Ventana | Error budget |
|---|---|---|---|
| `disponibilidad-99-5` | 99.5% de requests 2xx | 7 días rolling | 0.5% de los requests |
| `latencia-500ms-95` | 95% de requests < 500 ms | 7 días rolling | 5% de los requests |

Se calculan sobre las métricas SLI propias (`http_requests_total`, `http_request_duration_milliseconds`) vía Managed Prometheus. El error budget restante se consulta en Cloud Monitoring → SLOs.

### Alertas con umbral estático (grupo de control)

`ESTATICO error rate > 1%` y `ESTATICO latencia p99 > 500ms` por servicio (6 políticas). Existen a propósito para la comparación de ruido del Módulo B: son el "antes".

### La regla de correlación (data-service)

`CORRELACION anomalia error rate + latencia SLO`:

```
error_rate > baseline + 2σ + 0.5pp   Y   latencia p99 > 500 ms (umbral del SLO)
```

- El baseline y σ se **aprenden solos** de la última hora (`avg_over_time`/`stddev_over_time` sobre subqueries PromQL de 1h con paso de 5m) — umbral dinámico, no fijo.
- El piso de 0.5 puntos porcentuales evita disparos cuando σ≈0 (historial perfecto).
- El `and` exige que ambas condiciones se cumplan a la vez: un pico de errores sin impacto en latencia, o latencia alta sin errores, no despierta a nadie.
- La documentación de la política guía al on-call a encontrar el `trace_id` del fallo.

### Alerta basada en logs con trace_id

`LOG errores inyectados con trace_id`: se dispara con el evento `chaos.error.injected` y el incidente incluye el log completo — `trace_id` y `span_id` adentro — para saltar directo a la traza. Rate limit de 1 notificación / 5 min.

## Decisión de diseño: baseline+2σ en PromQL

La consigna pide "Cloud Monitoring Anomaly Detection". Se implementó la detección de anomalías como **umbral dinámico estadístico en PromQL** (baseline + 2σ aprendidos de la ventana móvil), que es exactamente la regla `error_rate > baseline + 2σ` que la consigna define, con la ventaja de ser transparente, reproducible como código y evaluable cada 30 s (clave para el MTTD < 2 min de la Fase 5).
