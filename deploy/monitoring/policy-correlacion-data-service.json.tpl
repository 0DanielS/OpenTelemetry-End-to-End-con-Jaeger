{
  "displayName": "CORRELACION anomalia error rate + latencia SLO — data-service",
  "combiner": "OR",
  "severity": "CRITICAL",
  "documentation": {
    "content": "Regla de correlacion AIOps: error_rate > baseline + 2 sigma (aprendido de la ultima hora) Y latencia p99 sobre el umbral del SLO (500 ms). Buscar el trace_id del fallo en: Cloud Logging con filtro resource.labels.service_name=\"data-service\" jsonPayload.event=\"chaos.error.injected\" (o severity>=ERROR), y abrir la traza en Cloud Trace.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "error_rate > baseline+2sigma Y p99 > SLO",
      "conditionPrometheusQueryLanguage": {
        "query": "(((sum(rate(http_requests_total{job=\"observabilidad/data-service\",status=\"5xx\"}[2m])) or on() vector(0)) / (sum(rate(http_requests_total{job=\"observabilidad/data-service\"}[2m])) > 0)) > (avg_over_time(((sum(rate(http_requests_total{job=\"observabilidad/data-service\",status=\"5xx\"}[5m])) or on() vector(0)) / (sum(rate(http_requests_total{job=\"observabilidad/data-service\"}[5m])) > 0))[20m:1m]) + 2 * stddev_over_time(((sum(rate(http_requests_total{job=\"observabilidad/data-service\",status=\"5xx\"}[5m])) or on() vector(0)) / (sum(rate(http_requests_total{job=\"observabilidad/data-service\"}[5m])) > 0))[20m:1m]) + 0.005)) and (histogram_quantile(0.99, sum by (le) (rate(http_request_duration_milliseconds_bucket{job=\"observabilidad/data-service\"}[2m]))) > 500)",
        "duration": "0s",
        "evaluationInterval": "30s"
      }
    }
  ],
  "alertStrategy": { "autoClose": "1800s" },
  "notificationChannels": ["__CHANNEL__"]
}
