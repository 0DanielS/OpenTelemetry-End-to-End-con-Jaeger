{
  "displayName": "ANOMALIA latencia p99 vs baseline — inventory-api",
  "combiner": "OR",
  "severity": "WARNING",
  "documentation": {
    "content": "Deteccion de degradacion gris: p99 actual (ventana 2m) por encima del baseline + 2 sigma aprendidos de la ultima hora, mas un piso de 20 ms. Detecta latencias que el umbral estatico de 500 ms no ve. Correlacionar con trazas de inventory-api en Cloud Trace (span reserve_stock).",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "p99 > baseline+2sigma+20ms",
      "conditionPrometheusQueryLanguage": {
        "query": "histogram_quantile(0.99, sum by (le) (rate(http_request_duration_milliseconds_bucket{job=\"observabilidad/inventory-api\"}[2m]))) > (avg_over_time((histogram_quantile(0.99, sum by (le) (rate(http_request_duration_milliseconds_bucket{job=\"observabilidad/inventory-api\"}[5m]))))[20m:1m]) + 2 * stddev_over_time((histogram_quantile(0.99, sum by (le) (rate(http_request_duration_milliseconds_bucket{job=\"observabilidad/inventory-api\"}[5m]))))[20m:1m]) + 20)",
        "duration": "0s",
        "evaluationInterval": "30s"
      }
    }
  ],
  "alertStrategy": { "autoClose": "1800s" },
  "notificationChannels": ["__CHANNEL__"]
}
