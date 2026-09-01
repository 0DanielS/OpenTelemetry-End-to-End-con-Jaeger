{
  "displayName": "ESTATICO error rate > 1% — __SVC__",
  "combiner": "OR",
  "severity": "WARNING",
  "conditions": [
    {
      "displayName": "error rate 5xx > 1% (umbral fijo)",
      "conditionPrometheusQueryLanguage": {
        "query": "(sum(rate(http_requests_total{job=\"observabilidad/__SVC__\",status=\"5xx\"}[5m])) or on() vector(0)) / sum(rate(http_requests_total{job=\"observabilidad/__SVC__\"}[5m])) > 0.01",
        "duration": "0s",
        "evaluationInterval": "30s"
      }
    }
  ],
  "alertStrategy": { "autoClose": "1800s" },
  "notificationChannels": ["__CHANNEL__"]
}
