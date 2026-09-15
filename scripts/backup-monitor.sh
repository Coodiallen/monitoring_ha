#!/usr/bin/env bash

set -u -o pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BACKUP_DIR="${PROJECT_DIR}/backups"
PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-http://127.0.0.1:9091}"

INSTANCE_NAME="${INSTANCE_NAME:-$(hostname -s)}"

# Keep grouping-key value URL-safe.
INSTANCE_NAME="$(
    printf '%s' "$INSTANCE_NAME" |
    tr -c '[:alnum:]_.-' '_'
)"

mkdir -p "$BACKUP_DIR"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"

BACKUP_FILE="${BACKUP_DIR}/monitoring-config-${TIMESTAMP}.tar.gz"

START_TIME="$(date +%s)"

echo "==> Starting monitoring configuration backup"
echo "Destination: ${BACKUP_FILE}"

BACKUP_STATUS=0

if tar \
    -czf "$BACKUP_FILE" \
    -C "$PROJECT_DIR" \
    compose.yaml \
    bootstrap.sh \
    .env.example \
    alertmanager/alertmanager.yml \
    nginx \
    prometheus/prometheus.yml \
    prometheus/rules \
    prometheus/targets \
    grafana/Dockerfile \
    grafana/grafana.ini \
    grafana/provisioning \
    grafana/dashboards
then
    BACKUP_STATUS=1
    echo "Backup completed successfully."
else
    echo "Backup failed." >&2
    rm -f "$BACKUP_FILE"
fi

END_TIME="$(date +%s)"
DURATION="$((END_TIME - START_TIME))"

PAYLOAD="$(mktemp)"

cleanup() {
    rm -f "$PAYLOAD"
}

trap cleanup EXIT


cat > "$PAYLOAD" <<EOF
# HELP monitoring_backup_status Last backup execution status (1=success, 0=failure).
# TYPE monitoring_backup_status gauge
monitoring_backup_status ${BACKUP_STATUS}

# HELP monitoring_backup_duration_seconds Duration of the last backup execution.
# TYPE monitoring_backup_duration_seconds gauge
monitoring_backup_duration_seconds ${DURATION}
EOF


if [[ "$BACKUP_STATUS" -eq 1 ]]; then

    LAST_SUCCESS="$(date +%s)"
    BACKUP_SIZE="$(stat -c '%s' "$BACKUP_FILE")"

    cat >> "$PAYLOAD" <<EOF

# HELP monitoring_backup_last_success_timestamp_seconds Unix timestamp of the last successful backup.
# TYPE monitoring_backup_last_success_timestamp_seconds gauge
monitoring_backup_last_success_timestamp_seconds ${LAST_SUCCESS}

# HELP monitoring_backup_size_bytes Size of the last successful backup.
# TYPE monitoring_backup_size_bytes gauge
monitoring_backup_size_bytes ${BACKUP_SIZE}
EOF

fi


echo "==> Pushing metrics to Pushgateway..."

curl \
    --fail \
    --silent \
    --show-error \
    --request POST \
    --data-binary "@${PAYLOAD}" \
    "${PUSHGATEWAY_URL}/metrics/job/monitoring_backup/instance/${INSTANCE_NAME}"

echo
echo "Metrics pushed."

if [[ "$BACKUP_STATUS" -ne 1 ]]; then
    exit 1
fi
