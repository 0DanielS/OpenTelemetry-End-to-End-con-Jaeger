
## Workaround: bug de migración del plugin cloud-monitoring

`migrateRequest` (pkg/tsdb/cloud-monitoring, Grafana ≤11.6.x) no incluye `promQLQuery`
en su chequeo de campos, por lo que una query con solo `promQLQuery` se trata como
"legacy" y su JSON se reescribe eliminándola → panic nil en `promql_query.go:23`.

Cada target del dashboard incluye un `timeSeriesList` dummy junto al `promQLQuery`
para esquivar la migración. No eliminarlo hasta que Grafana corrija el chequeo.

La imagen se pinea por digest en `service.yaml` (Cloud Run puede resolver `:latest`
a una revisión cacheada).
