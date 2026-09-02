# Game Day — Experimento de latencia controlada sobre `inventory-api`

Validación local y despliegue controlado en Google Cloud Run.
Rama de trabajo: `feature/chaos-gameday`.

**Objetivo.** Reproducir de forma controlada un experimento de latencia sobre `inventory-api`, primero en local (opcional) y luego en Cloud Run, dejando evidencia de tres estados: **estable → inyección de 2.000 ms → rollback**. No es necesario ejecutar el spike de 150 VUs de `k6/script.js` para esta validación.

## Ficha del experimento

| Parámetro | Valor |
|---|---|
| Servicio afectado | `inventory-api` (service-b) |
| Falla | Latencia artificial controlada |
| Latencia | 2000 ms |
| Timeout `orders-api` | 10 s (`httpx.AsyncClient(timeout=10.0)`) |
| Blast radius | Solo `POST /products/{id}/reserve`; `/health` no se altera |
| Rollback | `CHAOS_ENABLED=false` / `CHAOS_LATENCY_MS=0` |

Con 2.000 ms sobre un timeout de 10 s el fallo es **gris**: la latencia se degrada de forma observable pero el flujo sigue devolviendo 201/200. Se golpean SLI-2 (latencia) y SLI-4 (throughput) sin mover disponibilidad ni error rate.

## Cómo está implementado

`service-b/app/main.py` lee dos variables de entorno al arrancar:

```python
CHAOS_ENABLED = os.getenv("CHAOS_ENABLED", "false").lower() == "true"
CHAOS_LATENCY_MS = int(os.getenv("CHAOS_LATENCY_MS", "0"))
```

Dentro del span `reserve_stock`, antes de tocar la base de datos, si ambas están activas:

- marca el span con `chaos.enabled=true` y `chaos.latency_ms=2000`;
- emite `log.warning("chaos.latency.injected", latency_ms=..., product_id=...)`, que sale en JSON con `trace_id` y `span_id` gracias a `inject_trace_context` de `service-b/app/telemetry.py`;
- espera con `await asyncio.sleep(...)` — dormida asíncrona, no bloquea el event loop, así que degrada latencia sin falsear la saturación del worker.

Los defaults son `false` / `0`: **sin las variables el chaos está apagado**.

## 1. Ejecución local (opcional, para validar antes de GCP)

Actualizar la rama y comprobar que se trabaja sobre `feature/chaos-gameday`:

```bash
git fetch origin
git checkout feature/chaos-gameday
git pull
```

Levantar el stack:

```bash
docker compose up -d --build
```

Validar estado estable con chaos apagado:

```bash
curl http://localhost:8081/health

time curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{"product_id":"p1","quantity":1,"customer_id":"gameday-local"}'
```

Configuración estable esperada en `docker-compose.yml` (servicio `inventory-api`):

```yaml
- CHAOS_ENABLED=false
- CHAOS_LATENCY_MS=0
```

Activar el experimento cambiando esas dos líneas y recreando el servicio:

```yaml
- CHAOS_ENABLED=true
- CHAOS_LATENCY_MS=2000
```

```bash
docker compose up -d --build inventory-api
```

Medir una petición. Debe subir ~2 s y **seguir siendo exitosa**:

```bash
time curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{"product_id":"p1","quantity":1,"customer_id":"gameday-chaos"}'
```

Revisar evidencia en logs:

```bash
docker compose logs --tail=80 inventory-api
```

Buscar: `chaos.latency.injected`, `latency_ms=2000`, `trace_id`, `span_id` y respuestas 200 OK.

Opcional: abrir Jaeger en http://localhost:16686 y revisar un span de `inventory-api` con `chaos.enabled=true` y `chaos.latency_ms=2000`. El dashboard de Grafana (http://localhost:3000) debería mostrar el salto en **SLI-2: Latencia p50/p95/p99**.

**Rollback local:** volver a `false`/`0`, recrear `inventory-api` y repetir `/health` + `time curl` para comprobar la recuperación.

## 2. Validación en Google Cloud Run

Proyecto `opentelemetry-nrb`, región `us-central1`, servicio `inventory-api` (los mismos de `scripts/deploy.sh` y `.github/workflows/deploy-inventory.yml`).

### Desplegar la rama

El workflow de GitHub Actions solo dispara en push a `main`, así que para desplegar la rama del experimento se usa el script local desde el checkout de `feature/chaos-gameday`:

```bash
./scripts/deploy.sh inventory
```

> Alternativa: `gh workflow run deploy-inventory.yml --ref feature/chaos-gameday`.

La base de datos debe estar encendida: los servicios se conectan a Postgres al arrancar y un deploy con Cloud SQL apagado falla el arranque de la revisión.

### Estado estable

`scripts/deploy.sh` usa `--set-env-vars`, que **reemplaza** el conjunto completo de variables y por tanto deja el servicio sin las de chaos — que es exactamente el estado estable (defaults `false`/`0`). Para dejarlo explícito y capturable en pantalla:

```bash
gcloud run services update inventory-api \
  --region us-central1 \
  --update-env-vars CHAOS_ENABLED=false,CHAOS_LATENCY_MS=0
```

Esperar a que la revisión esté lista y validar:

```bash
curl https://inventory-api-576253872784.us-central1.run.app/health

time curl -X POST https://orders-api-576253872784.us-central1.run.app/orders \
  -H "Content-Type: application/json" \
  -d '{"product_id":"p1","quantity":1,"customer_id":"gameday-gcp-estable"}'
```

Capturar la revisión estable.

### Activación controlada del Game Day

```bash
gcloud run services update inventory-api \
  --region us-central1 \
  --update-env-vars CHAOS_ENABLED=true,CHAOS_LATENCY_MS=2000
```

Esperar a que la nueva revisión reciba tráfico y confirmar en Cloud Run que **las dos variables quedaron activas**:

```bash
gcloud run services describe inventory-api --region us-central1 \
  --format='value(spec.template.spec.containers[0].env)'
```

Ejecutar una petición contra `orders-api` y medir su duración. El objetivo es ver el incremento de latencia **manteniendo respuesta exitosa**:

```bash
time curl -X POST https://orders-api-576253872784.us-central1.run.app/orders \
  -H "Content-Type: application/json" \
  -d '{"product_id":"p1","quantity":1,"customer_id":"gameday-gcp-chaos"}'
```

Consultar los logs en Cloud Logging y buscar `chaos.latency.injected` con `latency_ms=2000`. Si aparecen `trace_id`/`span_id`, conservarlos como evidencia de correlación:

```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="inventory-api" AND jsonPayload.event="chaos.latency.injected"' \
  --limit 10 --format json
```

Capturar también, si están disponibles, la traza en Cloud Trace con la mayor duración en `inventory-api`, y el panel de latencia en el Grafana cloud (https://grafana-576253872784.us-central1.run.app). Si alguna de esas visualizaciones no existe en GCP, **no inventarla**: logs + tiempo de respuesta + revisión de Cloud Run son evidencia suficiente.

### Rollback en Cloud Run

```bash
gcloud run services update inventory-api \
  --region us-central1 \
  --update-env-vars CHAOS_ENABLED=false,CHAOS_LATENCY_MS=0
```

Esperar la nueva revisión y repetir una petición para comprobar que la latencia baja de nuevo.

## 3. Evidencias a recolectar

- [ ] Captura de Cloud Run con la revisión estable o servicio desplegado.
- [ ] Captura donde se vean `CHAOS_ENABLED=true` y `CHAOS_LATENCY_MS=2000`.
- [ ] Resultado de una petición durante el chaos con su tiempo de respuesta.
- [ ] Logs de `inventory-api` con `chaos.latency.injected` y `latency_ms=2000`.
- [ ] Captura de traza/telemetría en GCP, solo si está disponible.
- [ ] Captura o resultado del rollback con chaos apagado y latencia reducida.
- [ ] Cualquier error, timeout o diferencia frente al comportamiento local, **sin ocultarlo**.

Las capturas de este game day se conservan en el historial de git; las evidencias vigentes del laboratorio integrador viven en `evidencias/`.

## 4. Criterio de éxito y condición de aborto

**Éxito.** La latencia end-to-end aumenta de forma observable con los 2.000 ms inyectados, `inventory-api` registra la inyección y el flujo continúa disponible; tras el rollback la latencia vuelve a bajar.

**Abortar.** Si `orders-api` presenta 5xx sostenidos, `inventory-api` deja de responder, aparecen timeouts no controlados o la revisión de Cloud Run queda inestable. En ese caso ejecutar el rollback de inmediato y conservar la evidencia del comportamiento observado.

## Notas operativas

- **Nunca dejar el chaos encendido.** El rollback es parte del experimento, no un paso opcional.
- Con `CHAOS_LATENCY_MS` por encima de 10000 se supera el timeout de `httpx` en `orders-api` y el experimento deja de ser gris: se convierte en 5xx y dispara SLI-1, SLI-3 y el burn rate. Es otro experimento válido, pero no es este.
- Un redeploy posterior con `scripts/deploy.sh` o con el workflow de Actions borra las variables de chaos (usan `--set-env-vars`, no `--update-env-vars`), dejando el servicio en estado seguro.

---

## Ejecución registrada — 2026-08-30 (GCP)

Proyecto `opentelemetry-nrb`, región `us-central1`. Código desplegado desde `feature/chaos-gameday` con `./scripts/deploy.sh inventory`.

### Secuencia de revisiones

| Revisión | Estado | `CHAOS_ENABLED` | `CHAOS_LATENCY_MS` |
|---|---|---|
| `inventory-api-00006-qv4` | Deploy del código del experimento | (ausente) | (ausente) |
| `inventory-api-00007-hhq` | Estable explícito | `false` | `0` |
| `inventory-api-00008-qv6` | **Game Day activo** | `true` | `2000` |
| `inventory-api-00009-9gr` | Rollback | `false` | `0` |

### Latencia end-to-end (`POST /orders` contra `orders-api`)

| Fase | Intento 1 | Intento 2 | Intento 3 | Status |
|---|---|---|---|
| Estable (chaos OFF) | 0.252 s | 0.269 s | 0.239 s | 201 |
| **Chaos ON (2000 ms)** | **2.318 s** | **2.290 s** | **2.285 s** | **201** |
| Post-rollback | 0.240 s | 0.249 s | 0.272 s | 201 |

Delta medido: **+2.04 s**, consistente con los 2.000 ms inyectados. Las tres peticiones bajo chaos devolvieron **201**: la degradación no se convirtió en error, que es exactamente el comportamiento buscado con un timeout de 10 s en `orders-api`.

**Blast radius confirmado:** `GET /health` de `inventory-api` respondió en 0.246 s con el chaos activo, sin degradación.

> Nota de medición: la primera petición tras cada nueva revisión incluye el cold start de Cloud Run (10.2 s en el primer caso, servicios escalados a cero). Se descartó como warmup en las tres fases; los números de la tabla son de instancia caliente.

### Evidencia en Cloud Logging

```json
{
  "event": "chaos.latency.injected",
  "latency_ms": 2000,
  "level": "warning",
  "product_id": "p1",
  "span_id": "7ce40fa1442468b2",
  "trace_id": "c5f654eed8abfc5ed5cec52d7f18c8c2",
  "timestamp": "2026-08-30T01:42:52.453526Z"
}
```

Cada evento `chaos.latency.injected` aparece ~2,0 s antes de su `POST /products/p1/reserve 200 OK` correspondiente, lo que confirma que la espera ocurre donde se diseñó: dentro del span, antes del acceso a la base de datos.

Query usada:

```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="inventory-api" AND jsonPayload.event="chaos.latency.injected"' \
  --project opentelemetry-nrb --limit 5 --freshness=15m --format=json
```

Capturas de la consola de Cloud Logging:

| Vista | Qué muestra | Captura |
|---|---|
| Resultados de la consulta | **4 eventos** `chaos.latency.injected`, todos con `latency_ms:2000` y `product_id:"p1"`, agrupados en la ventana 21:42:45–21:42:52 EDT |
| Entrada expandida | `jsonPayload` completo con `event`, `latency_ms`, `level: warning`, `product_id`, `span_id` y `trace_id` |

**Correlación log ↔ traza verificada en la consola.** El `span_id` del primer evento de log, `6f1f5998f3e2a77b`, es exactamente el del span `reserve_stock` abierto en Cloud Trace (visible en la URL como `spanId=6f1f5998f3e2a77b`). Es decir: el log que registra la inyección y el span que la ejecuta son la misma unidad de trabajo, comprobado en dos productos distintos de GCP.

### Evidencia en Cloud Trace

Traza distribuida completa del experimento: **`88cd90ee3a29f4a6ac0e480963f9f707`** (01:42:45Z). Recuperada con la API v1 de Cloud Trace, ya que `gcloud` no expone lectura de trazas:

```
/orders                                     2085.2 ms
  POST /orders                              2076.7 ms
    POST                                    2059.7 ms
      /products/p1/reserve                  2042.5 ms   <- salto cross-service (W3C traceparent)
        POST /products/{product_id}/reserve 2027.4 ms
          reserve_stock                     2021.1 ms   <- span con los atributos del chaos
                chaos.enabled     = true
                chaos.latency_ms  = 2000
                product.id        = p1
                reserve.quantity  = 1
          UPDATE inventory                    12.5 ms   <- el trabajo real de BD
      persist_order                           13.3 ms
        INSERT orders                          7.8 ms
```

Esta traza es la evidencia más fuerte del experimento: de los 2085 ms totales, **2021 ms son la espera inyectada** y el `UPDATE` real a la base tarda **12.5 ms**. La atribución del tiempo queda demostrada dentro de la propia telemetría, sin necesidad de razonar desde fuera.

```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://cloudtrace.googleapis.com/v1/projects/opentelemetry-nrb/traces/88cd90ee3a29f4a6ac0e480963f9f707"
```

Capturas de la consola de Cloud Trace:

| Vista | Qué muestra | Captura |
|---|---|
| Explorador, lista de intervalos | Los spans del experimento a las 21:42:45 EDT con duraciones de **2.085 s / 2.077 s / 2.06 s / 2.048 s**, contra el resto de tráfico en milisegundos |
| Cronograma de la traza | Cascada completa `orders-api → inventory-api` con los 17 intervalos y el `UPDATE inventory` de 12.526 ms al fondo |
| Span `reserve_stock` + atributos | **La evidencia central**: la cascada y el panel de atributos con `chaos.enabled=true` y `chaos.latency_ms=2000` en la misma pantalla |

### Evidencia en Grafana (Managed Prometheus)

Ventana `2026-08-30T01:35:00Z` a `01:55:00Z` en el dashboard `observabilidad-gcp`:

| Panel | Qué muestra |
|---|---|
| SLI-2 Latencia | Onda cuadrada de ~24 ms a **~2.4 s** entre 01:42 y 01:47, en `inventory-api` y `orders-api` |
| Latencia DB p99 | Sube solo de 24 ms a **48 ms**: la base nunca fue el cuello de botella |
| SLI-3 Error Rate | Plano en **0%** durante todo el experimento (la línea de 0.5% es el umbral del SLO) |
| SLI-4 Throughput | El tráfico continúa; no hubo caída de servicio |
| Propagación W3C | Llamadas `orders → inventory` con `result="ok"` durante la ventana |

Serie p95 de `inventory-api` consultada directamente a Managed Prometheus:

| Hora (UTC) | p95 |
|---|---|
| 01:42 | 23.5 ms |
| 01:43 – 01:47 | **2275 – 2350 ms** |
| 01:48 en adelante | 24.2 ms |

```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer $TOKEN" --get \
  "https://monitoring.googleapis.com/v1/projects/opentelemetry-nrb/location/global/prometheus/api/v1/query_range" \
  --data-urlencode 'query=histogram_quantile(0.95, sum(rate(http_request_duration_milliseconds_bucket{job="observabilidad/inventory-api"}[5m])) by (le))' \
  --data-urlencode "start=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' '2026-08-30T01:35:00Z' +%s)" \
  --data-urlencode "end=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' '2026-08-30T01:55:00Z' +%s)" \
  --data-urlencode "step=60"
```

### Observaciones no ocultadas

- **`gcloud` no permite leer trazas.** No existe `gcloud trace traces describe`; el grupo `alpha trace` solo expone `sinks`. Se usó la **API REST v1 de Cloud Trace** directamente (ver arriba), que sí funciona.
- **No todas las trazas llegaron a Cloud Trace.** El `trace_id` `c5f654eed8abfc5ed5cec52d7f18c8c2` aparece en Cloud Logging pero devuelve `Trace not found` en la API de Trace, coherente con el `DEADLINE_EXCEEDED` del collector. De los 4 eventos de log, la traza `88cd90ee...` sí llegó completa y es la que se documenta. Vale la pena tenerlo presente: **con el collector escalando desde cero, la correlación log→traza no está garantizada al 100%** en las primeras peticiones.
- **La grilla completa del dashboard de Grafana no renderiza.** El plugin `grafana-lokiexplore-app` devuelve 404 al precargarse (`failed to resolve 'react/jsx-runtime'`) y la excepción corta el render de los paneles de series. Workaround usado para las capturas: abrir cada panel individualmente con `&viewPanel=<id>`, que sí funciona. Los paneles `gauge`/`stat` sí renderizan en la grilla.
- **La consola de GCP requirió sesión con `authuser=1`.** La cuenta `nestorx211@gmail.com` no es la primera del navegador, así que los enlaces sin `&authuser=1` redirigen al login aunque haya sesión activa. Los deep links de este documento la incluyen.
- **El collector reportó `DEADLINE_EXCEEDED` exportando trazas** hacia `otel-collector-...run.app:443` durante la ventana del experimento, con reintento a 2 s. Es el collector escalando desde cero, no un efecto del chaos; pero implica que la traza correspondiente puede haber llegado con retraso o incompleta a Cloud Trace.
- **`textPayload` vs `jsonPayload`.** Los logs de structlog llegan como `jsonPayload` estructurado; filtrar por `textPayload:"chaos.latency.injected"` no devuelve nada. Usar `jsonPayload.event=` como en la query de arriba.

### Criterio de éxito

Cumplido. La latencia end-to-end subió de forma observable con los 2.000 ms inyectados, `inventory-api` registró la inyección con correlación `trace_id`/`span_id`, el flujo se mantuvo disponible (201 en todos los intentos) y tras el rollback la latencia volvió a la línea base. No se cumplió ninguna condición de aborto.
