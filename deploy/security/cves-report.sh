#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-opentelemetry-nrb}"
REGION="${REGION:-us-central1}"
REPO="cloud-run-source-deploy"

for svc in orders-api inventory-api data-service otel-collector grafana; do
  IMG="$(gcloud artifacts docker images list \
    "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${svc}" \
    --sort-by=~UPDATE_TIME --limit=1 --format="value(format('{0}@{1}',package,version))" 2>/dev/null || true)"
  if [[ -z "$IMG" ]]; then
    echo "${svc}: sin imagen en el repo"
    continue
  fi
  echo "== ${svc}"
  gcloud artifacts docker images describe "$IMG" \
    --show-package-vulnerability --format=json 2>/dev/null \
    | python3 -c "
import json, sys
from collections import Counter
d = json.load(sys.stdin)
occs = d.get('package_vulnerability_summary', {}).get('vulnerabilities', {})
c = Counter()
total = 0
for sev, items in occs.items():
    c[sev] += len(items)
    total += len(items)
if total == 0:
    print('   sin vulnerabilidades reportadas (o escaneo pendiente)')
else:
    for sev in ('CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'MINIMAL'):
        if c.get(sev):
            print(f'   {sev}: {c[sev]}')
    print(f'   TOTAL: {total}')
"
done
