# Benchmark de Overhead (Fase 4)

> Resultados locales (Docker Desktop Windows, 50 VUs, 30s por corrida). La medición definitiva de CPU/memoria en AWS se hace vía Container Insights/CloudWatch.

## Metodología

- **Con instrumentación**: servicios con `opentelemetry-instrument` (auto-instrumentación FastAPI/httpx/SQLAlchemy + spans custom + métricas OTLP cada 5s).
- **Sin instrumentación**: mismos servicios con `uvicorn` directo (override `docker-compose.baseline.yml`); el código de telemetría usa no-ops.
- k6: `constant-vus` 50 VUs, `POST /orders`, `product_id` rotado entre 100 productos para evitar contención de fila.
- Latencia desde k6; CPU/memoria desde `docker stats`.

## Resultados

| Métrica | Sin OTel | Con OTel | Overhead |
|---|---|---|---|
| Throughput | 217 req/s | 135 req/s | **−38%** |
| Latencia promedio | 229 ms | 368 ms | +61% |
| Latencia p95 | 525 ms | 900 ms | +71% |
| Latencia p99 | 945 ms | 1240 ms | +31% |
| Memoria `orders-api` | 72 MiB | 86 MiB | +19% |
| Memoria `inventory-api` | 64 MiB | 81 MiB | +27% |
| CPU (1 worker, saturado) | ~97% | ~98% | similar (ver nota) |

## Observaciones

- **CPU**: ambos saturan el único worker de uvicorn; el overhead real de CPU se evidencia en la **caída de throughput** a CPU comparable (más CPU por request).
- **Span fan-out alto**: cada `POST /orders` genera ~16 spans (HTTP recv/send, httpx client, SQLAlchemy `connect`/`execute`, spans custom). A 135 req/s son ~2000 spans/s exportados por OTLP.
- **Export de métricas cada 5s** (`OTEL_METRIC_EXPORT_INTERVAL=5000`) suma overhead de serialización bajo carga.
- **Sin sampling** (default siempre-muestrea). Con tail-based sampling (p. ej. 10-25%) el overhead de export de trazas cae drásticamente.
- Entorno local Docker Desktop (WSL2) infla las latencias absolutas; el overhead **relativo** es la señal útil.
- Trazas de Jaeger permitieron aislar los cuellos de botella (contención de fila en `p1`, luego conexiones httpx por request).

## Lecciones para el reporte

1. La correlación por `trace_id` fue clave para diagnosticar los cuellos de botella durante el benchmark.
2. El overhead es medible y aceptable a baja carga, pero bajo carga alta sin sampling se nota en latencia y throughput.
3. Mitigaciones: sampling de trazas, `BatchSpanProcessor` (ya activo), y relajar `OTEL_METRIC_EXPORT_INTERVAL` a 30-60s en producción.
