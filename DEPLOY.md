# Despliegue en Cloud Run

Dos microservicios se despliegan como **servicios de Cloud Run independientes** en el proyecto GCP `opentelemetry-nrb` (región `us-central1`):

| Servicio | Cloud Run | Origen | Puerto |
|---|---|---|---|
| orders-api | `orders-api` | `service-a/` | 8080 |
| inventory-api | `inventory-api` | `service-b/` | 8081 |
| data-service | `data-service` | `service-c/` | 8082 |

## Cómo se dispara el despliegue

1. **Al mergear un PR a `main`** (GitHub Actions). Cada servicio tiene su workflow con filtro de ruta:
   - `service-a/**` → `.github/workflows/deploy-orders.yml`
   - `service-b/**` → `.github/workflows/deploy-inventory.yml`
   - `service-c/**` → `.github/workflows/deploy-data.yml`
2. **Manual desde GitHub** (`workflow_dispatch`) en la pestaña Actions.
3. **Local, sin subir código** (`gcloud run deploy --source`):
   ```bash
   ./scripts/deploy.sh all         # los tres
   ./scripts/deploy.sh orders      # solo orders-api
   ./scripts/deploy.sh inventory   # solo inventory-api
   ./scripts/deploy.sh data        # solo data-service
   ```

## Autenticación GitHub → GCP

**Workload Identity Federation** (sin llaves de servicio). El provider y la service account de deploy van como literales en los workflows (no son secretos). El acceso está restringido por condición al repo `0DanielS/OpenTelemetry-End-to-End-con-Jaeger`.

- Provider: `projects/576253872784/locations/global/workloadIdentityPools/github-pool/providers/github-provider`
- Deployer SA: `gh-deploy@opentelemetry-nrb.iam.gserviceaccount.com`
- Runtime SA: `otel-run@opentelemetry-nrb.iam.gserviceaccount.com`

## Variables y secretos

Las cadenas de conexión sensibles viven en **Secret Manager**; Cloud Run las lee en runtime (nunca pasan por GitHub):

| Secret | Consumido por |
|---|---|
| `orders-database-url` | orders-api (`DATABASE_URL`, pineado a la versión socket tras la rotación) |
| `inventory-database-url` | inventory-api (`DATABASE_URL`, IP privada) |
| `data-database-url` | data-service (`DATABASE_URL`, IP privada) |

Las no sensibles van como env vars del servicio: `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_PROTOCOL`, `OTEL_METRIC_EXPORT_INTERVAL`, e `INVENTORY_URL` (solo orders-api).

## Base de datos

Cloud SQL PostgreSQL 16 (`otel-pg`, `db-f1-micro`, single-AZ). Conexión desde Cloud Run por socket Unix (`--add-cloudsql-instances`), dos bases: `orders` e `inventory`.

## Reprovisionar la infraestructura

`./scripts/gcp-bootstrap.sh` recrea todo (APIs, SAs, WIF, Artifact Registry, Cloud SQL, secretos). Es idempotente.

## Red y mesh (Laboratorio Integrador)

Los servicios corren dentro de la VPC `obs-vpc` con Direct VPC egress (Flow Logs activos en las 3 subredes), Cloud SQL expone IP privada vía peering PSA, y `orders-api` es cliente del service mesh `obs-mesh` (llama a inventory por `inventory-api.mesh.internal`). IaC: `scripts/gcp-network-bootstrap.sh` y `scripts/gcp-mesh-bootstrap.sh`. Monitoreo y seguridad como código en `deploy/monitoring/` y `deploy/security/`.
