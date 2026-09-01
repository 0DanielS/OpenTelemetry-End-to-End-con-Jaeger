{
  "displayName": "ESTATICO latencia p99 > 500ms — __SVC__",
  "combiner": "OR",
  "severity": "WARNING",
  "conditions": [
    {
      "displayName": "p99 > 500ms (umbral fijo)",
      "conditionPrometheusQueryLanguage": {
        "query": "histogram_quantile(0.99, sum by (le) (rate(http_request_duration_milliseconds_bucket{job=\"observabilidad/__SVC__\"}[5m]))) > 500",
        "duration": "0s",
        "evaluationInterval": "30s"
      }
    }
  ],
  "alertStrategy": { "autoClose": "1800s" },
  "notificationChannels": ["__CHANNEL__"]
}
