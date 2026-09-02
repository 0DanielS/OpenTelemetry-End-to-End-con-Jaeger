#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-opentelemetry-nrb}"
PROJECT_NUMBER="${PROJECT_NUMBER:-576253872784}"
REGION="${REGION:-us-central1}"
REPO="${REPO:-0DanielS/OpenTelemetry-End-to-End-con-Jaeger}"
SQL_INSTANCE="${SQL_INSTANCE:-otel-pg}"
RUN_SA="otel-run@${PROJECT_ID}.iam.gserviceaccount.com"
DEP_SA="gh-deploy@${PROJECT_ID}.iam.gserviceaccount.com"
CONN_NAME="${PROJECT_ID}:${REGION}:${SQL_INSTANCE}"

gcloud services enable \
  run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  secretmanager.googleapis.com sqladmin.googleapis.com iam.googleapis.com \
  iamcredentials.googleapis.com sts.googleapis.com --project="$PROJECT_ID"

gcloud iam service-accounts create otel-run --project="$PROJECT_ID" \
  --display-name="Cloud Run runtime" || true
gcloud iam service-accounts create gh-deploy --project="$PROJECT_ID" \
  --display-name="GitHub Actions deployer" || true

for r in roles/secretmanager.secretAccessor roles/cloudsql.client; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${RUN_SA}" --role="$r" --condition=None -q
done
for r in roles/run.admin roles/iam.serviceAccountUser roles/cloudbuild.builds.editor \
         roles/artifactregistry.writer roles/storage.admin; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${DEP_SA}" --role="$r" --condition=None -q
done

gcloud artifacts repositories create cloud-run-source-deploy \
  --project="$PROJECT_ID" --location="$REGION" --repository-format=docker || true

gcloud iam workload-identity-pools create github-pool \
  --project="$PROJECT_ID" --location=global --display-name="GitHub Actions" || true
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --project="$PROJECT_ID" --location=global --workload-identity-pool=github-pool \
  --display-name="GitHub OIDC" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
  --attribute-condition="assertion.repository=='${REPO}'" || true
gcloud iam service-accounts add-iam-policy-binding "$DEP_SA" \
  --project="$PROJECT_ID" --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/${REPO}"

gcloud sql instances create "$SQL_INSTANCE" --project="$PROJECT_ID" \
  --database-version=POSTGRES_16 --edition=ENTERPRISE --tier=db-f1-micro \
  --region="$REGION" --storage-size=10GB --availability-type=zonal \
  --root-password="$(openssl rand -base64 18)" || true

ORDERS_PASS="$(openssl rand -base64 24 | tr -d '/+=')"
INV_PASS="$(openssl rand -base64 24 | tr -d '/+=')"

gcloud sql databases create orders --instance="$SQL_INSTANCE" --project="$PROJECT_ID" || true
gcloud sql databases create inventory --instance="$SQL_INSTANCE" --project="$PROJECT_ID" || true
gcloud sql users create orders --instance="$SQL_INSTANCE" --project="$PROJECT_ID" --password="$ORDERS_PASS"
gcloud sql users create inventory --instance="$SQL_INSTANCE" --project="$PROJECT_ID" --password="$INV_PASS"

printf 'postgresql+asyncpg://orders:%s@/orders?host=/cloudsql/%s' "$ORDERS_PASS" "$CONN_NAME" \
  | gcloud secrets create orders-database-url --project="$PROJECT_ID" --data-file=- \
  || printf 'postgresql+asyncpg://orders:%s@/orders?host=/cloudsql/%s' "$ORDERS_PASS" "$CONN_NAME" \
  | gcloud secrets versions add orders-database-url --project="$PROJECT_ID" --data-file=-
printf 'postgresql+asyncpg://inventory:%s@/inventory?host=/cloudsql/%s' "$INV_PASS" "$CONN_NAME" \
  | gcloud secrets create inventory-database-url --project="$PROJECT_ID" --data-file=- \
  || printf 'postgresql+asyncpg://inventory:%s@/inventory?host=/cloudsql/%s' "$INV_PASS" "$CONN_NAME" \
  | gcloud secrets versions add inventory-database-url --project="$PROJECT_ID" --data-file=-

gcloud secrets add-iam-policy-binding orders-database-url --project="$PROJECT_ID" \
  --member="serviceAccount:${RUN_SA}" --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding inventory-database-url --project="$PROJECT_ID" \
  --member="serviceAccount:${RUN_SA}" --role="roles/secretmanager.secretAccessor"

./scripts/setup-dataservice-db.sh
