# Fase 3 — AIOps: alertas que entienden lo "normal"

## El problema

Hoy no tenemos **ninguna alerta**. Tenemos dashboards hermosos que nadie mira a las 3 a.m. Y el camino fácil — umbrales estáticos ("alerta si error rate > 1%") — tiene un defecto conocido por cualquier equipo de guardia: o el umbral es tan sensible que grita todo el día (fatiga de alertas, se ignoran), o es tan laxo que calla durante incidentes reales. El umbral correcto además cambia con la hora, el día y el crecimiento del sistema.

**AIOps** ataca esto con estadística: en lugar de un número fijo, el sistema aprende el comportamiento normal de cada métrica (su *baseline*) y alerta cuando el presente se aparta demasiado de esa historia.

## Qué vamos a construir

1. **SLOs formales en Cloud Monitoring** para los 3 servicios: disponibilidad y latencia p99, con su **error budget** — el presupuesto de fallos que podemos gastar sin romper la promesa (99.5% de disponibilidad = 0.5% de requests pueden fallar).
2. **Grupo de control: alertas con umbral estático.** Las creamos a propósito para poder medir cuánto ruido generan — son el "antes" de la comparación.
3. **Anomaly Detection de Cloud Monitoring** sobre `data-service`: la plataforma modela el baseline y su variabilidad (σ) por nosotros.
4. **La regla de correlación** — el corazón del módulo:

   > `error_rate > baseline + 2σ` **Y** `latency_p99 > SLO_threshold` → alerta enriquecida con el `trace_id` del request fallido.

   La conjunción es lo importante: cada condición sola produce falsos positivos (un pico de errores sin impacto en latencia puede ser un cliente roto; latencia alta sin errores puede ser un batch pesado). Las dos juntas casi siempre son un incidente real.
5. **Enriquecimiento con `trace_id`:** la alerta llega con el hilo del que tirar. Nuestros logs de error ya llevan `trace_id`; una log-based alert lo pone en la notificación, y de ahí un clic a la traza completa en Cloud Trace.
6. **La medición del ruido:** misma ventana de carga, dos sistemas de alertas activos, contamos cuántas veces gritó cada uno y cuántas veces tenía razón. Ese número es la "evidencia cuantitativa" que pide la rúbrica para el Excelente.

## Conceptos clave

- **Baseline + 2σ:** si una métrica se comporta normalmente, ~95% de sus valores caen dentro de ±2 desviaciones estándar de su media. Salirse de ahí es, por definición estadística, raro — y lo raro merece atención. El baseline se recalcula solo; el umbral estático no.
- **Error budget:** el complemento del SLO. Con SLO 99.5% mensual, el budget son ~3.6 horas de fallo al mes. Cada incidente lo consume; el chaos de la Fase 5 medirá exactamente cuánto.
- **Alerta accionable:** una alerta que además de "algo está mal" dice *dónde mirar* (el `trace_id`). La diferencia entre despertar a alguien con un síntoma o con un caso armado.
- **Fatiga de alertas:** el fenómeno operativo que justifica todo el módulo — un sistema que grita de más entrena a los humanos a ignorarlo.

## Cómo se ve funcionando

Durante una carga normal, silencio. Cuando la Fase 5 encienda `CHAOS_ERROR_RATE=10` en data-service, el error rate saltará muy por encima de baseline+2σ, la latencia p99 cruzará el SLO, y llegará **una** alerta con el `trace_id` de un request fallido — mientras el sistema de umbrales estáticos habrá gritado varias veces durante la semana por picos sin importancia.

## Evidencia que deja

- SLOs y políticas de alerta como IaC en `deploy/monitoring/`.
- Comparativa cuantitativa: alertas estáticas vs. correlacionadas en la misma ventana.
- Captura de la alerta enriquecida con `trace_id` y su traza en Cloud Trace.
