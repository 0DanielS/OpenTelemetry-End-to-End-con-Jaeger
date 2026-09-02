{
  "displayName": "LOG errores inyectados con trace_id — data-service",
  "combiner": "OR",
  "severity": "WARNING",
  "documentation": {
    "content": "Alerta basada en logs: cada incidente incluye el log del error con su trace_id y span_id para saltar directo a la traza en Cloud Trace.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "log chaos.error.injected en data-service",
      "conditionMatchedLog": {
        "filter": "resource.type=\"cloud_run_revision\" resource.labels.service_name=\"data-service\" jsonPayload.event=\"chaos.error.injected\""
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s",
    "notificationRateLimit": { "period": "300s" }
  },
  "notificationChannels": ["__CHANNEL__"]
}
