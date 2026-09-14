#!/bin/sh
set -eu

DASHBOARD_FILE="${1:-}"

if [ -z "$DASHBOARD_FILE" ]; then
    echo "Usage: upload-dashboard.sh <dashboard.json>"
    exit 1
fi

if [ ! -f "$DASHBOARD_FILE" ]; then
    echo "Dashboard file not found: $DASHBOARD_FILE"
    exit 1
fi

if [ -z "${GRAFANA_API_TOKEN:-}" ]; then
    echo "GRAFANA_API_TOKEN is not set"
    exit 1
fi

echo "Preparing Grafana API payload..."

jq '{
  dashboard: .,
  overwrite: true
}' "$DASHBOARD_FILE" > /tmp/payload.json

echo "Uploading dashboard to Grafana..."

curl \
  --fail-with-body \
  --silent \
  --show-error \
  --cacert /certs/ca.crt \
  -H "Authorization: Bearer ${GRAFANA_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST \
  --data-binary @/tmp/payload.json \
  https://grafana.local/api/dashboards/db

echo
