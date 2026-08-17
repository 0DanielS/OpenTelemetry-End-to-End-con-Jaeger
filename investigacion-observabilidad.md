# Investigación de Observabilidad: OpenTelemetry, Jaeger, Grafana, k6 y W3C Trace Context

> Documento de investigación basado en fuentes oficiales y confiables.
> Fecha de elaboración: agosto 2026.

---

## Tabla de contenidos

1. [OpenTelemetry Python SDK](#1-opentelemetry-python-sdk)
2. [Jaeger — Documentación de Arquitectura](#2-jaeger--documentación-de-arquitectura)
3. [Grafana — Observabilidad Unificada (Traces, Logs y Metrics)](#3-grafana--observabilidad-unificada-traces-logs-y-metrics)
4. [k6 — Load Testing](#4-k6--load-testing)
5. [W3C — Trace Context Specification](#5-w3c--trace-context-specification)
6. [Referencias](#6-referencias)

---

## 1. OpenTelemetry Python SDK

**Fuente:** https://opentelemetry-python.readthedocs.io/ y https://opentelemetry.io/docs/instrumentation/python/

### 1.1 ¿Qué es?

OpenTelemetry (OTel) es un conjunto de APIs, SDKs y herramientas para instrumentar, generar, recolectar y exportar datos de telemetría (traces, métricas y logs) de aplicaciones y servicios. Es el estándar de facto de la CNCF para observabilidad. La implementación Python provee:

- **API**: interfaces para tracers, meters y loggers.
- **SDK**: implementación real de esas interfaces con configuraciones de procesamiento, muestreo y exportación.
- **Exporters**: componentes que envían la telemetría a backends (OTLP, Prometheus, Zipkin, OpenCensus, consola).
- **Instrumentaciones automáticas**: bibliotecas que generan telemetría sin cambiar código.
- **Shims**: compatibilidad con OpenCensus y OpenTracing.

### 1.2 ¿Para qué sirve?

- Observar el comportamiento de aplicaciones distribuidas de forma estandarizada y neutral respecto al vendor (no te ata a un backend específico).
- Correlacionar traces, métricas y logs con identificadores comunes.
- Facilitar la migración entre backends (Jaeger, Tempo, Zipkin, Prometheus, etc.) sin re-instrumentar.
- Proporcionar instrumentación automática de frameworks web (Flask, Django, FastAPI) y clientes HTTP/DB.

### 1.3 Componentes clave (paquetes)

| Paquete | Función |
|---------|---------|
| `opentelemetry-api` | Interfaces abstractas (Tracer, Meter, Logger, Context). |
| `opentelemetry-sdk` | Implementación del SDK: TracerProvider, MeterProvider, LoggerProvider, procesadores y samplers. |
| `opentelemetry-distro` | Distribución que agrupa API + SDK + herramientas `opentelemetry-bootstrap` y `opentelemetry-instrument`. |
| `opentelemetry-exporter-otlp` | Exportación vía OTLP (gRPC/HTTP) hacia el Collector o backends. |
| `opentelemetry-exporter-prometheus` | Exporta métricas en formato Prometheus. |
| `opentelemetry-exporter-zipkin` | Exporta traces en formato Zipkin. |
| Instrumentaciones (`opentelemetry-instrumentation-flask`, `-django`, `-fastapi`, etc.) | Auto-instrumentación de librerías. |
| Shims (`opentelemetry-opencensus-shim`, `opentelemetry-opentracing-shim`) | Compatibilidad con APIs antiguas. |

### 1.4 ¿Cómo se usa e implementa?

#### Instalación

```powershell
pip install opentelemetry-distro
opentelemetry-bootstrap -a install   # instala instrumentaciones detectadas
```

#### Instrumentación automática (zero-code)

Se ejecuta la aplicación bajo el agente `opentelemetry-instrument`:

```powershell
opentelemetry-instrument `
    --traces_exporter console `
    --metrics_exporter console `
    --logs_exporter console `
    --service_name dice-server `
    flask run -p 8080
```

#### Instrumentación manual (traces)

```python
from opentelemetry import trace

tracer = trace.get_tracer("diceroller.tracer")

def roll():
    with tracer.start_as_current_span("roll") as rollspan:
        res = randint(1, 6)
        rollspan.set_attribute("roll.value", res)
        return res
```

#### Instrumentación manual (métricas)

```python
from opentelemetry import metrics

meter = metrics.get_meter("diceroller.meter")
roll_counter = meter.create_counter(
    "dice.rolls", description="The number of rolls by roll value")

roll_counter.add(1, {"roll.value": result})
```

#### Exportación vía OTLP (producción)

Configuración mínima del OpenTelemetry Collector (`otel-collector-config.yaml`):

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
exporters:
  debug:
    verbosity: detailed
service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [debug]
    metrics:
      receivers: [otlp]
      exporters: [debug]
    logs:
      receivers: [otlp]
      exporters: [debug]
```

Ejecutar el Collector y apuntar la app a él:

```powershell
docker run -p 4317:4317 -v "${env:TEMP}\otel-collector-config.yaml:/etc/otel-collector-config.yaml" `
    otel/opentelemetry-collector:latest --config=/etc/otel-collector-config.yaml

pip install opentelemetry-exporter-otlp
opentelemetry-instrument --logs_exporter otlp flask run -p 8080
```

### 1.5 Datos clave

- **Señales soportadas**: Traces, Metrics, Logs (con correlación por `trace_id`/`span_id`).
- **Protocolo estándar de exportación**: OTLP (gRPC puerto 4317, HTTP puerto 4318).
- **Identificadores**: `trace_id` (128 bits), `span_id` (64 bits), conforme a W3C Trace Context.
- **Contexto**: propaga el contexto entre servicios automáticamente (HTTP, gRPC, colas).
- **Sampling**: soporta muestreo (head-based, remote, adaptive).
- **Ejemplos incluidos**: auto-instrumentación, Django, Fork process model, Logs SDK, Metrics SDK, Prometheus+Grafana, multi-destination export, sqlcommenter, etc.
- El agente `opentelemetry-instrument` detecta automáticamente el paquete OTLP instalado y exporta por defecto a `localhost:4317`.

---

## 2. Jaeger — Documentación de Arquitectura

**Fuente:** https://www.jaegertracing.io/docs/architecture/ (versión 2.20)

### 2.1 ¿Qué es?

Jaeger es una plataforma de trazado distribuido de código abierto (CNCF) para monitorear y solucionar problemas en microservicios. **Jaeger v2** es una distribución personalizada del OpenTelemetry Collector, desplegable como un único binario configurable en distintos roles.

### 2.2 Roles (componentes)

| Rol | Función |
|-----|---------|
| **collector** | Recibe los datos de trace de las aplicaciones y los escribe en el storage backend. |
| **query** | Sirve las APIs y la interfaz de usuario para consultar y visualizar traces. |
| **ingester** | Lee spans desde Kafka y los escribe en storage; útil en configuración collector-Kafka-ingester. |
| **all-in-one** | Combina collector y query en un solo proceso (ideal para desarrollo/pruebas; con Badger puede usarse en producción con volúmenes modestos). |
| **agent** | Agente de host o sidecar que reenvía datos al collector. Se recomienda usar el OpenTelemetry Collector estándar en su lugar. |

### 2.3 Opciones de arquitectura

**Directo a storage**
Los collectors reciben datos y escriben directamente al storage. El storage debe soportar tráfico promedio y pico. Los collectors usan colas en memoria para suavizar picos cortos, pero un pico sostenido puede causar pérdida de datos.

**Vía Kafka**
Kafka actúa como cola persistente intermedia entre collectors y storage para evitar pérdida de datos. Los collectors usan exportadores Kafka; se añade un componente **ingester** para leer de Kafka y guardar. Múltiples ingesters escalan el ingreso particionando la carga.

### 2.4 Integración con OpenTelemetry Collector

No es obligatorio usar el OpenTelemetry Collector para operar Jaeger (Jaeger ya es una distribución del mismo). Pero puede colocarse *delante* de Jaeger para:
- **Sidecar / host agent**: simplifica la configuración del SDK (endpoints locales), enriquece datos con info del entorno (ej. pod de k8s), distribuye el costo de enriquecimiento. Contraparte: capa extra de marshal/unmarshal.
- **Cluster remoto**: habilita sharding (ej. tail-based sampling). Contraparte: capa extra de serialización.

### 2.5 Componentes del binario Jaeger

**Componentes propios de Jaeger:**
- *Jaeger Storage Extension/Exporter*: hub extensible de backends de storage y escritura de spans.
- *Jaeger Query Extension*: APIs de consulta y UI.
- *Adaptive Sampling Processor*: cálculo de probabilidades para muestreo adaptativo.
- *Remote Sampling Extension*: endpoints de muestreo remoto (config estática o adaptativa).

**Componentes de OpenTelemetry:**
- **Receivers**: OTLP, Jaeger (gRPC/Thrift), Kafka, Zipkin (v1/v2), No-op.
- **Processors**: Batch, Tail Sampling, Memory Limiter, Attributes (redacción/enriquecimiento), Filter.
- **Exporters**: OTLP (gRPC/HTTP), Kafka, Prometheus, Debug, No-op.
- **Connectors**: Span Metrics (genera métricas desde spans), Forward.
- **Extensions**: Health Check v2, zPages, Performance Profiler (pprof).

### 2.6 Datos clave

- **Storage backends soportados**: Badger, Cassandra, ClickHouse, Elasticsearch, Kafka, Memory, OpenSearch.
- **Personalización**: se pueden construir distribuciones custom con OpenTelemetry Collector Builder (`ocb`).
- **all-in-one con memoria**: solo desarrollo/pruebas (los datos se pierden al reiniciar).
- **collector/query separados**: permite escalar lectura/escritura independientemente y aplicar políticas de seguridad distintas.
- La versión 1.x (archivo) sigue existiendo; v2.x es la versión vigente.

---

## 3. Grafana — Observabilidad Unificada (Traces, Logs y Metrics)

**Fuente:** https://grafana.com/docs/grafana/latest/explore/trace-integration/

### 3.1 ¿Qué es?

Grafana es una plataforma de observabilidad y visualización que unifica métricas, logs y traces en un solo panel. El módulo **Explore** permite consultar y visualizar traces desde múltiples fuentes de datos de tracing.

**Data sources de tracing soportadas:** Tempo, Jaeger, Zipkin, X-Ray, Azure Monitor, ClickHouse, New Relic e Infinity.

### 3.2 ¿Para qué sirve?

- Visualizar el recorrido de una solicitud a través de un sistema distribuido.
- Navegar desde un span a los logs y métricas relacionados (correlación de señales).
- Identificar el *critical path* que domina la latencia de extremo a extremo.
- Analizar dependencias entre servicios con service graph.

### 3.3 Elementos de la Trace view

| Elemento | Descripción |
|----------|-------------|
| **Header** | Título (span raíz y trace ID), búsqueda de spans y metadatos. |
| **Minimap** | Vista condensada del timeline; permite zoom en rangos de tiempo. |
| **Timeline** | Lista de spans: nombre de servicio, nombre de operación, barra de duración. |
| **Span details** | Atributos de span y de recurso, eventos y enlaces (links). |
| **Span filters** | Filtros por service name, span name, duración (ns, us, ms, s, m, h) y tags. |
| **Node graph** | Spans como nodos en un grafo (o service graph del trace actual). |
| **Service graph** | Tasas, errores y duraciones (RED) + relaciones entre servicios. |

### 3.4 Conceptos clave

- **Span**: unidad de trabajo con start time, duración y nombre de operación; referencia a un span padre (excepto el root). Incluye atributos clave/valor (ej. `http.url`, `http.status_code`), eventos y links.
- **Span attributes**: metadatos de una operación específica (request, response).
- **Resource attributes**: metadatos estáticos del origen (nombre de la app, versión del servicio).
- **Events**: registros tipo log adjuntos a un span (errores, warnings, checkpoints) con timestamp, nombre y atributos.
- **Links**: relaciones entre spans no padre-hijo (p. ej. procesos asíncronos o colas).
- **Critical path**: algoritmo CRISP (Critical Path for Service Performance) resalta los spans que impulsan la latencia de extremo a extremo.

### 3.5 Correlación unificada (el valor central)

- **Trace to logs**: desde un span saltar a los logs relevantes (Tempo, Jaeger, Zipkin).
- **Trace to metrics**: saltar desde un span a métricas relevantes (Tempo, Jaeger, Zipkin).
- **Trace to profiles**: vincular traces con perfiles de CPU/memoria (Tempo).
- **Trace correlations**: links personalizados según información del trace/span.

### 3.6 Datos clave

- Cada data source tiene su propio query editor.
- La barra de duración resalta el critical path con un segmento más oscuro.
- El node graph requiere que el data source devuelva los datos en un formato específico (Data API, estructura de data frame).
- El service graph está disponible inmediatamente tras configurar los requisitos (metrics-generator en Tempo).

---

## 4. k6 — Load Testing

**Fuente:** https://k6.io/docs/

### 4.1 ¿Qué es?

Grafana k6 es una herramienta de pruebas de rendimiento de código abierto, amigable para desarrolladores y extensible, que ayuda a detectar problemas de rendimiento temprano y mejorar la confiabilidad de forma proactiva.

### 4.2 ¿Para qué sirve?

Equipos (Devs, QA, SDETs, SREs) usan k6 para:

- **Pruebas de carga y rendimiento**: optimizado para bajo consumo de recursos y alto rendimiento (spike, stress, soak tests).
- **Browser performance testing**: a través del k6 browser API para métricas del navegador.
- **Monitoreo de rendimiento y sintético**: tests con carga mínima ejecutados con alta frecuencia (Grafana Cloud Synthetic Monitoring).
- **Automatización de pruebas**: integración con CI/CD.
- **Chaos y resiliencia**: simular tráfico en experimentos de caos e inyectar fallos en Kubernetes con `xk6-disruptor`.
- **Infrastructure testing**: extensiones para nuevos protocolos.

### 4.3 ¿Cómo se usa?

Los scripts de prueba se escriben en **JavaScript**, usando la CLI de k6 para ejecutarlos. Conceptos fundamentales:

- **Options**: configuración de VUs (virtual users), duración, stages, thresholds.
- **Thresholds**: criterios de aprobación/reprobación (p. ej. `http_req_duration < 200`).
- **Metrics**: métricas integradas (`http_req_duration`, `http_reqs`, `vus`, etc.) y custom.
- **Lifecycle hooks**: setup/teardown, init, etc.
- **Checks**: aserciones funcionales durante la prueba.

Ejemplo conceptual de script:

```javascript
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  vus: 10,
  duration: '30s',
  thresholds: { http_req_duration: ['p(95)<200'] },
};

export default function () {
  const res = http.get('https://test.k6.io');
  check(res, { 'status is 200': (r) => r.status === 200 });
}
```

### 4.4 Tipos de prueba

- **Spike testing**: aumento abrupto de carga.
- **Stress testing**: carga creciente hasta el límite del sistema.
- **Soak testing**: carga sostenida en el tiempo para detectar fugas/degradação.

### 4.5 Datos clave

- **Ecosistema**: k6 OSS, Grafana Cloud k6 (dashboards y análisis), k6 Studio (generación visual de scripts).
- **Extensiones**: se amplían capacidades vía `xk6` (p. ej. `xk6-disruptor` para inyección de fallos).
- **Integraciones**: CI/CD y automatización, Kubernetes (chaos).
- **Resultados**: pueden verse en terminal o exportarse a Grafana Cloud/Prometheus para análisis.
- Distribuido como binario CLI; lenguaje de scripting es JavaScript (no Python/Go).

---

## 5. W3C — Trace Context Specification

**Fuente:** https://www.w3.org/TR/trace-context/ (W3C Recommendation, 23 noviembre 2021)

### 5.1 ¿Qué es?

Es el estándar de la W3C que define cabeceras HTTP y un formato de valor para propagar *contexto de trace* entre servicios, habilitando escenarios de **trazado distribuido** interoperable entre múltiples vendors.

### 5.2 ¿Para qué sirve?

Resuelve problemas de interoperabilidad multi-vendor:

- Correlacionar traces recolectados por distintos vendors (identificador único compartido).
- Propagar traces a través de límites entre vendors sin romperlos.
- Permitir que intermediarios (proxies, plataformas cloud) soporten propagación estándar.

### 5.3 Los dos campos de propagación

1. **`traceparent`**: describe la posición de la request en su grafo de trace en un formato portátil y de longitud fija (optimizado para parsing rápido). Todo vendor DEBE configurarlo.
2. **`tracestate`**: extiende `traceparent` con datos específicos del vendor (pares clave/valor). Su uso es opcional.

### 5.4 Formato del header `traceparent`

```
traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
             └┬┘ └──────────────────────────────┘ └────────────────┘ └┬┘
          version         trace-id (32 hex)       parent-id (16 hex)  flags
```

| Campo | Tamaño | Descripción |
|-------|--------|-------------|
| `version` | 2 hex (1 byte) | Versión del formato. Actual `00`; `ff` prohibido. |
| `trace-id` | 32 hex (16 bytes) | Identifica el trace completo. Todo ceros es inválido. |
| `parent-id` | 16 hex (8 bytes) | ID del request tal como lo conoce el llamador (span-id). Todo ceros es inválido. |
| `trace-flags` | 2 hex (8 bits) | Banderas; solo el bit menos significativo (`sampled`) está definido. |

#### Flag `sampled`

- `01`: el llamador puede haber grabado datos de trace (recomendación de grabación).
- `00`: el llamador no grabó datos out-of-band.
- Es una recomendación, no regla estricta (por confianza/abuso, bugs y carga diferente entre servicios).

#### Ejemplos válidos

```
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01  # sampled
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00  # not sampled
```

### 5.5 Formato del header `tracestate`

```
tracestate: rojo=00f067aa0ba902b7,congo=t61rcWkgMzE
```

| Regla | Detalle |
|-------|---------|
| Estructura | Lista de pares `clave=valor` separados por comas. |
| Clave (key) | `simple-key` (letras minúsculas, dígitos, `_`, `-`, `*`, `/`) o `multi-tenant-key` (`tenant-id@system-id`). |
| Valor | Cadena opaca de hasta 256 caracteres ASCII imprimibles, excepto `,` y `=`. |
| Límites | Máximo 32 list-members; se DEBE propagar al menos 512 caracteres. |
| Posición | La entrada más a la izquierda indica qué sistema corresponde a `traceparent`. |
| Una entrada por clave | Al reentrar, se sobrescribe la entrada anterior del mismo vendor (no se duplica). |

### 5.6 Mutaciones permitidas

**`traceparent`** (solo estas):
- Actualizar `parent-id` (más típica).
- Actualizar `sampled` (junto con `parent-id`).
- Reiniciar el trace (regenerar todos los campos; típico en fronteras de red seguras).
- Degradar la versión.

**`tracestate`**:
- Añadir nuevo par clave/valor (a la izquierda).
- Actualizar valor existente (movido a la izquierda).
- Eliminar par clave/valor (preferiblemente solo los propios).

### 5.7 Modelo de procesamiento (resumen)

- **Sin `traceparent`**: crear nuevo `trace-id`/`parent-id`; descartar `tracestate` si viene sin `traceparent`.
- **Con `traceparent`**: parsear versión; si no se puede parsear o es inválida, reiniciar trace y borrar `tracestate`; si versión mayor, parsear lo conocido y poner flags desconocidos a 0.
- Los proxies passthrough pueden no modificar headers pero sí eliminar inválidos o enriquecer `tracestate`.

### 5.8 Consideraciones de seguridad y privacidad

- **Privacidad**: NO usar `traceparent`/`tracestate` para información personal o sensible; generadores de números aleatorios no deben derivar de datos identificables.
- **Seguridad (info exposure)**: correlacionar requests puede revelar datos; evitar info confidencial en `tracestate`.
- **Denegación de servicio**: un atacante puede abusar del flag `sampled` (forzar overhead de trazado); implementar rate limiting y tratos distintos para requests autenticados/no autenticados.
- **CORS**: verificar `Access-Control-Allow-Headers` en requests cross-origin.

### 5.9 Recomendaciones para generar `trace-id`

- Debe ser **globalmente único**.
- Preferir generación **aleatoria** (mejora seguridad/privacidad y permite sampling basado en trace-id).
- Sistemas con IDs internos más cortos: incorporar el ID interno en la parte más a la derecha del `trace-id` y/o propagar el ID interno vía `tracestate`.

---

## 6. Referencias

1. OpenTelemetry Python API Reference — https://opentelemetry-python.readthedocs.io/
2. OpenTelemetry Python — Getting Started — https://opentelemetry.io/docs/instrumentation/python/getting-started/
3. Jaeger — Architecture Documentation — https://www.jaegertracing.io/docs/architecture/
4. Grafana — Unified Observability: Linking Traces, Logs and Metrics — https://grafana.com/docs/grafana/latest/explore/trace-integration/
5. k6 — Load Testing Documentation — https://k6.io/docs/
6. W3C — Trace Context Specification (Recommendation, 23 Nov 2021) — https://www.w3.org/TR/trace-context/
