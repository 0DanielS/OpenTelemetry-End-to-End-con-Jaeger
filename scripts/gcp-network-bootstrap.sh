#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-opentelemetry-nrb}"
REGION="${REGION:-us-central1}"
VPC="${VPC:-obs-vpc}"
SUBNET_PUBLIC_RANGE="10.10.0.0/24"
SUBNET_APIS_RANGE="10.10.1.0/24"
SUBNET_DATA_RANGE="10.10.2.0/24"
PSA_RANGE_NAME="psa-cloudsql"

gcloud services enable \
  compute.googleapis.com servicenetworking.googleapis.com \
  networkservices.googleapis.com trafficdirector.googleapis.com mesh.googleapis.com \
  securitycenter.googleapis.com containeranalysis.googleapis.com \
  containerscanning.googleapis.com --project="$PROJECT_ID"

gcloud compute networks create "$VPC" --project="$PROJECT_ID" \
  --subnet-mode=custom || true

gcloud compute networks subnets create subnet-public --project="$PROJECT_ID" \
  --network="$VPC" --region="$REGION" --range="$SUBNET_PUBLIC_RANGE" \
  --enable-flow-logs --logging-aggregation-interval=interval-5-sec \
  --logging-flow-sampling=0.5 --logging-metadata=include-all || true

gcloud compute networks subnets create subnet-apis --project="$PROJECT_ID" \
  --network="$VPC" --region="$REGION" --range="$SUBNET_APIS_RANGE" \
  --enable-private-ip-google-access \
  --enable-flow-logs --logging-aggregation-interval=interval-5-sec \
  --logging-flow-sampling=0.5 --logging-metadata=include-all || true

gcloud compute networks subnets create subnet-data --project="$PROJECT_ID" \
  --network="$VPC" --region="$REGION" --range="$SUBNET_DATA_RANGE" \
  --enable-private-ip-google-access \
  --enable-flow-logs --logging-aggregation-interval=interval-5-sec \
  --logging-flow-sampling=0.5 --logging-metadata=include-all || true

gcloud compute firewall-rules create allow-apis-to-data --project="$PROJECT_ID" \
  --network="$VPC" --direction=INGRESS --action=ALLOW --rules=tcp:5432 \
  --source-ranges="$SUBNET_APIS_RANGE" --priority=1000 || true

gcloud compute firewall-rules create allow-apis-internal --project="$PROJECT_ID" \
  --network="$VPC" --direction=INGRESS --action=ALLOW \
  --rules=tcp:443,tcp:8080,tcp:8081,tcp:8082,tcp:4317,tcp:4318 \
  --source-ranges="$SUBNET_APIS_RANGE" --priority=1000 || true

gcloud compute firewall-rules create deny-public-to-data --project="$PROJECT_ID" \
  --network="$VPC" --direction=INGRESS --action=DENY --rules=tcp:5432 \
  --source-ranges="$SUBNET_PUBLIC_RANGE" --priority=900 || true

gcloud compute addresses create "$PSA_RANGE_NAME" --project="$PROJECT_ID" \
  --global --purpose=VPC_PEERING --addresses=10.30.0.0 --prefix-length=20 \
  --network="$VPC" || true

gcloud services vpc-peerings connect --project="$PROJECT_ID" \
  --service=servicenetworking.googleapis.com \
  --ranges="$PSA_RANGE_NAME" --network="$VPC" || \
gcloud services vpc-peerings update --project="$PROJECT_ID" \
  --service=servicenetworking.googleapis.com \
  --ranges="$PSA_RANGE_NAME" --network="$VPC" --force

gcloud compute networks subnets list --project="$PROJECT_ID" \
  --filter="network:$VPC" \
  --format="table(name,region.basename(),ipCidrRange,logConfig.enable)"
