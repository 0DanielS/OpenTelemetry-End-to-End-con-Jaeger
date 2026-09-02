#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-opentelemetry-nrb}"
PROJECT_NUMBER="${PROJECT_NUMBER:-576253872784}"
REGION="${REGION:-us-central1}"
VPC="${VPC:-obs-vpc}"
MESH_NAME="${MESH_NAME:-obs-mesh}"
MESH_DOMAIN="${MESH_DOMAIN:-mesh.internal}"
RUN_SA="otel-run@${PROJECT_ID}.iam.gserviceaccount.com"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
DESTINATIONS=(inventory-api data-service)
HERE="$(cd "$(dirname "$0")" && pwd)"

gcloud services enable dns.googleapis.com networksecurity.googleapis.com \
  vpcaccess.googleapis.com --project="$PROJECT_ID"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf 'name: %s\n' "$MESH_NAME" > "$TMP/mesh.yaml"
gcloud network-services meshes import "$MESH_NAME" --project="$PROJECT_ID" \
  --source="$TMP/mesh.yaml" --location=global || true

gcloud dns managed-zones create "$MESH_NAME" --project="$PROJECT_ID" \
  --description="Dominio interno del service mesh" \
  --dns-name="${MESH_DOMAIN}." --networks="$VPC" --visibility=private || true

gcloud dns record-sets create "*.${MESH_DOMAIN}." --project="$PROJECT_ID" \
  --type=A --zone="$MESH_NAME" --rrdatas=10.0.0.1 --ttl=3600 || true

for r in roles/trafficdirector.client roles/cloudtrace.agent; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${RUN_SA}" --role="$r" --condition=None -q >/dev/null
done

for svc in "${DESTINATIONS[@]}"; do
  gcloud compute network-endpoint-groups create "${svc}-neg" --project="$PROJECT_ID" \
    --region="$REGION" --network-endpoint-type=serverless \
    --cloud-run-service="$svc" || true

  gcloud compute backend-services create "${svc}-mesh" --project="$PROJECT_ID" \
    --global --load-balancing-scheme=INTERNAL_SELF_MANAGED || true

  gcloud compute backend-services add-backend "${svc}-mesh" --project="$PROJECT_ID" \
    --global --network-endpoint-group="${svc}-neg" \
    --network-endpoint-group-region="$REGION" || true

  cat > "$TMP/route-${svc}.yaml" <<EOF
name: "${svc}-route"
hostnames:
  - "${svc}.${MESH_DOMAIN}"
meshes:
  - "projects/${PROJECT_ID}/locations/global/meshes/${MESH_NAME}"
rules:
  - action:
      destinations:
        - serviceName: "projects/${PROJECT_ID}/locations/global/backendServices/${svc}-mesh"
EOF
  gcloud network-services http-routes import "${svc}-route" --project="$PROJECT_ID" \
    --source="$TMP/route-${svc}.yaml" --location=global || true

  for member in "serviceAccount:${RUN_SA}" "serviceAccount:${COMPUTE_SA}"; do
    gcloud run services add-iam-policy-binding "$svc" --project="$PROJECT_ID" \
      --region="$REGION" --member="$member" --role="roles/run.invoker" -q >/dev/null
  done
done

echo "mesh listo: ${MESH_NAME} / *.${MESH_DOMAIN}"
gcloud network-services http-routes list --project="$PROJECT_ID" --location=global \
  --format="table(name,hostnames.list())"
