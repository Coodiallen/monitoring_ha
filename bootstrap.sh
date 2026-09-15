#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

ENV_FILE=".env"

PROM_PASSWORD_FILE="secrets/prometheus-basic-auth-password"
INFLUX_PASSWORD_FILE="secrets/influxdb-admin-password"
INFLUX_TOKEN_FILE="secrets/influxdb-admin-token"

CA_KEY="certs/ca.key"
CA_CERT="certs/ca.crt"

GRAFANA_KEY="certs/grafana.key"
GRAFANA_CERT="certs/grafana.crt"

PROMETHEUS_KEY="certs/prometheus.key"
PROMETHEUS_CERT="certs/prometheus.crt"

TELEGRAM_BOT_TOKEN_FILE="secrets/telegram-bot-token"
TELEGRAM_CHAT_ID_FILE="secrets/telegram-chat-id"

echo "==> Monitoring stack bootstrap"
echo


# ============================================================
# Helpers
# ============================================================

die() {
    echo "ERROR: $*" >&2
    exit 1
}

get_env_value() {
    local key="$1"

    if [[ ! -f "$ENV_FILE" ]]; then
        return 0
    fi

    awk -F= -v key="$key" '
        $1 == key {
            sub(/^[^=]*=/, "")
            print
            exit
        }
    ' "$ENV_FILE"
}

set_env_value() {
    local key="$1"
    local value="$2"
    local tmp

    tmp="$(mktemp)"

    awk \
        -v key="$key" \
        -v value="$value" '
        BEGIN {
            found = 0
        }

        $0 ~ "^" key "=" {
            print key "=" value
            found = 1
            next
        }

        {
            print
        }

        END {
            if (!found) {
                print key "=" value
            }
        }
    ' "$ENV_FILE" > "$tmp"

    mv "$tmp" "$ENV_FILE"
}

generate_hex() {
    local bytes="$1"
    openssl rand -hex "$bytes"
}

generate_base64() {
    local bytes="$1"
    openssl rand -base64 "$bytes" | tr -d '\n'
}


# ============================================================
# Required commands
# ============================================================

echo "==> Checking required commands..."

for cmd in docker openssl awk sed grep; do
    command -v "$cmd" >/dev/null 2>&1 \
        || die "Required command not found: $cmd"
done

docker compose version >/dev/null 2>&1 \
    || die "Docker Compose plugin is not available"

docker info >/dev/null 2>&1 \
    || die "Docker daemon is not available"

echo "OK"
echo


# ============================================================
# Directories
# ============================================================

echo "==> Creating required directories..."

mkdir -p \
    certs \
    secrets \
    prometheus/data \
    prometheus/federation/data \
    postgres/data \
    influxdb/data \
    influxdb/config \
    grafana/generated

touch certs/.gitkeep
touch secrets/.gitkeep

echo "OK"
echo


# ============================================================
# .env
# ============================================================

echo "==> Creating .env..."

if [[ ! -f "$ENV_FILE" ]]; then
    if [[ -f ".env.example" ]]; then
        cp .env.example "$ENV_FILE"
    else
        touch "$ENV_FILE"
    fi
fi


# ============================================================
# Grafana DB password
# ============================================================

if [[ -z "$(get_env_value GRAFANA_DB_PASSWORD)" ]]; then
    echo "==> Generating PostgreSQL password for Grafana..."

    GRAFANA_DB_PASSWORD="$(generate_base64 32)"

    set_env_value \
        GRAFANA_DB_PASSWORD \
        "$GRAFANA_DB_PASSWORD"
fi


# ============================================================
# Grafana secret key
# ============================================================

if [[ -z "$(get_env_value GRAFANA_SECRET_KEY)" ]]; then
    echo "==> Generating Grafana secret key..."

    GRAFANA_SECRET_KEY="$(generate_hex 32)"

    set_env_value \
        GRAFANA_SECRET_KEY \
        "$GRAFANA_SECRET_KEY"
fi


# ============================================================
# Grafana admin password
# ============================================================

if [[ -z "$(get_env_value GRAFANA_ADMIN_PASSWORD)" ]]; then
    echo
    echo "==> Configure Grafana admin password"

    while true; do
        read -r -s -p "Grafana admin password: " GRAFANA_ADMIN_PASSWORD
        echo

        read -r -s -p "Confirm Grafana admin password: " GRAFANA_ADMIN_PASSWORD_CONFIRM
        echo

        if [[ -z "$GRAFANA_ADMIN_PASSWORD" ]]; then
            echo "Password cannot be empty."
            continue
        fi

        if [[ "$GRAFANA_ADMIN_PASSWORD" != "$GRAFANA_ADMIN_PASSWORD_CONFIRM" ]]; then
            echo "Passwords do not match."
            continue
        fi

        break
    done

    set_env_value \
        GRAFANA_ADMIN_PASSWORD \
        "$GRAFANA_ADMIN_PASSWORD"

    unset GRAFANA_ADMIN_PASSWORD_CONFIRM
fi


# ============================================================
# Grafana renderer token
# ============================================================

if [[ -z "$(get_env_value GRAFANA_RENDERER_TOKEN)" ]]; then
    echo "==> Generating Grafana renderer token..."

    GRAFANA_RENDERER_TOKEN="$(generate_hex 32)"

    set_env_value \
        GRAFANA_RENDERER_TOKEN \
        "$GRAFANA_RENDERER_TOKEN"
fi


# ============================================================
# PostgreSQL exporter password
# ============================================================

if [[ -z "$(get_env_value POSTGRES_EXPORTER_PASSWORD)" ]]; then
    echo "==> Generating PostgreSQL exporter password..."

    POSTGRES_EXPORTER_PASSWORD="$(generate_hex 24)"

    set_env_value \
        POSTGRES_EXPORTER_PASSWORD \
        "$POSTGRES_EXPORTER_PASSWORD"
fi


# ============================================================
# GitLab OAuth
# ============================================================

if [[ -z "$(get_env_value GITLAB_CLIENT_ID)" ]]; then
    echo

    read -r -p \
        "GitLab OAuth Client ID (leave empty to skip): " \
        GITLAB_CLIENT_ID

    if [[ -n "$GITLAB_CLIENT_ID" ]]; then
        read -r -s -p \
            "GitLab OAuth Client Secret: " \
            GITLAB_CLIENT_SECRET
        echo

        set_env_value \
            GITLAB_CLIENT_ID \
            "$GITLAB_CLIENT_ID"

        set_env_value \
            GITLAB_CLIENT_SECRET \
            "$GITLAB_CLIENT_SECRET"
    fi
fi


# ============================================================
# Grafana API token placeholder
# ============================================================

if ! grep -q '^GRAFANA_API_TOKEN=' "$ENV_FILE"; then
    set_env_value GRAFANA_API_TOKEN ""
fi

echo
echo "==> Environment prepared."


# ============================================================
# Prometheus Basic Auth
# ============================================================

PROM_PASSWORD=""

if [[ -s "$PROM_PASSWORD_FILE" ]]; then
    PROM_PASSWORD="$(cat "$PROM_PASSWORD_FILE")"

elif [[ -n "$(get_env_value PROMETHEUS_BASIC_AUTH_PASSWORD)" ]]; then
    PROM_PASSWORD="$(get_env_value PROMETHEUS_BASIC_AUTH_PASSWORD)"

    printf '%s\n' "$PROM_PASSWORD" \
        > "$PROM_PASSWORD_FILE"

else
    echo "==> Generating Prometheus Basic Auth password..."

    PROM_PASSWORD="$(generate_base64 32)"

    printf '%s\n' "$PROM_PASSWORD" \
        > "$PROM_PASSWORD_FILE"
fi

set_env_value \
    PROMETHEUS_BASIC_AUTH_PASSWORD \
    "$PROM_PASSWORD"


# ============================================================
# Prometheus bcrypt
# ============================================================

echo "==> Generating Prometheus bcrypt hash..."

PROM_BCRYPT="$(
    docker run \
        --rm \
        --entrypoint /bin/sh \
        -e PROM_PASSWORD="$PROM_PASSWORD" \
        httpd:alpine \
        -c '
            htpasswd -nbBC 12 grafana "$PROM_PASSWORD" \
            | cut -d: -f2-
        '
)"

[[ -n "$PROM_BCRYPT" ]] \
    || die "Failed to generate Prometheus bcrypt password"


# ============================================================
# InfluxDB admin password
# ============================================================

if [[ ! -s "$INFLUX_PASSWORD_FILE" ]]; then
    echo "==> Generating InfluxDB admin password..."

    generate_base64 32 \
        > "$INFLUX_PASSWORD_FILE"
fi


# ============================================================
# InfluxDB token
# ============================================================

INFLUX_TOKEN=""

if [[ -s "$INFLUX_TOKEN_FILE" ]]; then
    INFLUX_TOKEN="$(cat "$INFLUX_TOKEN_FILE")"

elif [[ -n "$(get_env_value INFLUXDB_TOKEN)" ]]; then
    INFLUX_TOKEN="$(get_env_value INFLUXDB_TOKEN)"

    printf '%s\n' "$INFLUX_TOKEN" \
        > "$INFLUX_TOKEN_FILE"

else
    echo "==> Generating InfluxDB admin token..."

    INFLUX_TOKEN="$(generate_hex 32)"

    printf '%s\n' "$INFLUX_TOKEN" \
        > "$INFLUX_TOKEN_FILE"
fi

set_env_value \
    INFLUXDB_TOKEN \
    "$INFLUX_TOKEN"

chmod 600 \
    "$INFLUX_PASSWORD_FILE" \
    "$INFLUX_TOKEN_FILE"


# ============================================================
# Telegram Alertmanager credentials
# ============================================================

if [[ ! -s "$TELEGRAM_BOT_TOKEN_FILE" ]]; then
    echo
    echo "==> Configure Telegram alerting"

    while true; do
        read -r -s -p "Telegram bot token: " TELEGRAM_BOT_TOKEN
        echo

        if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
            break
        fi

        echo "Telegram bot token cannot be empty."
    done

    printf '%s\n' "$TELEGRAM_BOT_TOKEN" \
        > "$TELEGRAM_BOT_TOKEN_FILE"

    unset TELEGRAM_BOT_TOKEN
fi

if [[ ! -s "$TELEGRAM_CHAT_ID_FILE" ]]; then
    while true; do
        read -r -p "Telegram chat ID: " TELEGRAM_CHAT_ID

        if [[ "$TELEGRAM_CHAT_ID" =~ ^-?[0-9]+$ ]]; then
            break
        fi

        echo "Telegram chat ID must be an integer."
    done

    printf '%s\n' "$TELEGRAM_CHAT_ID" \
        > "$TELEGRAM_CHAT_ID_FILE"

    unset TELEGRAM_CHAT_ID
fi

chmod 600 \
    "$TELEGRAM_BOT_TOKEN_FILE" \
    "$TELEGRAM_CHAT_ID_FILE"

echo "Telegram alerting credentials prepared."


# ============================================================
# Local Certificate Authority
# ============================================================

if [[ ! -f "$CA_KEY" || ! -f "$CA_CERT" ]]; then
    echo
    echo "==> Generating local Certificate Authority..."

    rm -f "$CA_KEY" "$CA_CERT"

    openssl genrsa \
        -out "$CA_KEY" \
        4096

    openssl req \
        -x509 \
        -new \
        -nodes \
        -key "$CA_KEY" \
        -sha256 \
        -days 3650 \
        -out "$CA_CERT" \
        -subj "/CN=Monitoring Local CA"
fi


# ============================================================
# Grafana TLS certificate
# ============================================================

if [[ ! -f "$GRAFANA_KEY" || ! -f "$GRAFANA_CERT" ]]; then
    echo "==> Generating Grafana TLS certificate..."

    rm -f \
        "$GRAFANA_KEY" \
        "$GRAFANA_CERT" \
        certs/grafana.csr \
        certs/grafana.ext

    openssl genrsa \
        -out "$GRAFANA_KEY" \
        2048

    openssl req \
        -new \
        -key "$GRAFANA_KEY" \
        -out certs/grafana.csr \
        -subj "/CN=grafana.local"

    cat > certs/grafana.ext <<'EOF'
subjectAltName = DNS:grafana.local
extendedKeyUsage = serverAuth
keyUsage = digitalSignature,keyEncipherment
EOF

    openssl x509 \
        -req \
        -in certs/grafana.csr \
        -CA "$CA_CERT" \
        -CAkey "$CA_KEY" \
        -CAcreateserial \
        -out "$GRAFANA_CERT" \
        -days 825 \
        -sha256 \
        -extfile certs/grafana.ext

    rm -f \
        certs/grafana.csr \
        certs/grafana.ext
fi


# ============================================================
# Prometheus TLS certificate
# ============================================================

if [[ ! -f "$PROMETHEUS_KEY" || ! -f "$PROMETHEUS_CERT" ]]; then
    echo "==> Generating Prometheus TLS certificate..."

    rm -f \
        "$PROMETHEUS_KEY" \
        "$PROMETHEUS_CERT" \
        certs/prometheus.csr \
        certs/prometheus.ext

    openssl genrsa \
        -out "$PROMETHEUS_KEY" \
        2048

    openssl req \
        -new \
        -key "$PROMETHEUS_KEY" \
        -out certs/prometheus.csr \
        -subj "/CN=prometheus"

    cat > certs/prometheus.ext <<'EOF'
subjectAltName = DNS:prometheus,DNS:prometheus.local
extendedKeyUsage = serverAuth
keyUsage = digitalSignature,keyEncipherment
EOF

    openssl x509 \
        -req \
        -in certs/prometheus.csr \
        -CA "$CA_CERT" \
        -CAkey "$CA_KEY" \
        -CAcreateserial \
        -out "$PROMETHEUS_CERT" \
        -days 825 \
        -sha256 \
        -extfile certs/prometheus.ext

    rm -f \
        certs/prometheus.csr \
        certs/prometheus.ext
fi


# ============================================================
# Prometheus web config
# ============================================================

echo
echo "==> Creating prometheus/web.yml..."

cat > prometheus/web.yml <<EOF
tls_server_config:
  cert_file: /etc/prometheus/certs/prometheus.crt
  key_file: /etc/prometheus/certs/prometheus.key

basic_auth_users:
  grafana: '${PROM_BCRYPT}'
EOF


# ============================================================
# Linux permissions
# ============================================================

echo
echo "==> Configuring Prometheus filesystem permissions..."

PROMETHEUS_UID="$(
    docker run \
        --rm \
        --entrypoint /bin/sh \
        prom/prometheus:v3.14.0 \
        -c 'id -u'
)"

PROMETHEUS_GID="$(
    docker run \
        --rm \
        --entrypoint /bin/sh \
        prom/prometheus:v3.14.0 \
        -c 'id -g'
)"

ALERTMANAGER_GID="$(
    docker run \
        --rm \
        --entrypoint /bin/sh \
        quay.io/prometheus/alertmanager:v0.34.0 \
        -c 'id -g'
)"

echo "Prometheus container UID:GID = ${PROMETHEUS_UID}:${PROMETHEUS_GID}"
echo "Alertmanager container GID = ${ALERTMANAGER_GID}"

case "$(uname -s)" in

    Linux)
        echo "Applying Linux ownership and permissions..."

        sudo chown -R \
            "${PROMETHEUS_UID}:${PROMETHEUS_GID}" \
            prometheus/data \
            prometheus/federation/data

        sudo chmod 755 \
            prometheus/data \
            prometheus/federation/data

        sudo chown \
            "$(id -u):${PROMETHEUS_GID}" \
            "$PROM_PASSWORD_FILE"

        sudo chmod 640 \
            "$PROM_PASSWORD_FILE"

        sudo chown \
            "root:${PROMETHEUS_GID}" \
            "$PROMETHEUS_KEY"

        sudo chmod 640 \
            "$PROMETHEUS_KEY"

        chmod 644 \
            "$CA_CERT" \
            "$PROMETHEUS_CERT" \
            "$GRAFANA_CERT" \
            prometheus/web.yml

        chmod 600 \
            "$CA_KEY" \
            "$GRAFANA_KEY"

        sudo chown \
            "$(id -u):${ALERTMANAGER_GID}" \
            "$TELEGRAM_BOT_TOKEN_FILE" \
            "$TELEGRAM_CHAT_ID_FILE"

        chmod 640 \
            "$TELEGRAM_BOT_TOKEN_FILE" \
            "$TELEGRAM_CHAT_ID_FILE"

        echo "Prometheus and Alertmanager permissions configured."
        ;;

    Darwin)
        echo "macOS detected. Skipping Linux UID/GID ownership changes."

        chmod 600 \
            "$PROM_PASSWORD_FILE" \
            "$CA_KEY" \
            "$GRAFANA_KEY" \
            "$PROMETHEUS_KEY" \
            "$TELEGRAM_BOT_TOKEN_FILE" \
            "$TELEGRAM_CHAT_ID_FILE"

        chmod 644 \
            "$CA_CERT" \
            "$PROMETHEUS_CERT" \
            "$GRAFANA_CERT" \
            prometheus/web.yml
        ;;

    *)
        echo "Unknown host OS. Skipping ownership changes."
        ;;
esac


# ============================================================
# /etc/hosts
# ============================================================

echo
echo "==> Configuring /etc/hosts..."

set_local_host() {
    local hostname="$1"

    if grep -qE \
        "(^|[[:space:]])${hostname//./\\.}([[:space:]]|$)" \
        /etc/hosts
    then
        echo "Updating existing ${hostname} entry..."

        sudo sed -i.bak \
            "/[[:space:]]${hostname//./\\.}\([[:space:]]\|$\)/d" \
            /etc/hosts
    fi

    echo "127.0.0.1 ${hostname}" \
        | sudo tee -a /etc/hosts >/dev/null

    echo "${hostname} -> 127.0.0.1"
}

set_local_host "grafana.local"
set_local_host "prometheus.local"

sudo rm -f /etc/hosts.bak


# ============================================================
# Compose validation
# ============================================================

echo
echo "==> Validating Docker Compose configuration..."

docker compose config -q

echo "Compose configuration is valid."


# ============================================================
# Start PostgreSQL first
# ============================================================

echo
echo "==> Starting PostgreSQL..."

docker compose up -d postgres


# ============================================================
# Wait for PostgreSQL
# ============================================================

echo
echo "==> Waiting for PostgreSQL..."

POSTGRES_CONTAINER_ID="$(
    docker compose ps -q postgres
)"

[[ -n "$POSTGRES_CONTAINER_ID" ]] \
    || die "PostgreSQL container was not created"

POSTGRES_WAIT_SECONDS=120
POSTGRES_ELAPSED=0

while true; do
    POSTGRES_STATUS="$(
        docker inspect \
            --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
            "$POSTGRES_CONTAINER_ID" \
            2>/dev/null || true
    )"

    if [[ "$POSTGRES_STATUS" == "healthy" ]]; then
        break
    fi

    if [[ "$POSTGRES_STATUS" == "unhealthy" ]]; then
        docker compose logs postgres
        die "PostgreSQL became unhealthy"
    fi

    if (( POSTGRES_ELAPSED >= POSTGRES_WAIT_SECONDS )); then
        docker compose logs postgres
        die "Timed out waiting for PostgreSQL"
    fi

    sleep 2
    POSTGRES_ELAPSED=$((POSTGRES_ELAPSED + 2))
done

echo "PostgreSQL is healthy."


# ============================================================
# PostgreSQL exporter monitoring user
# ============================================================

echo
echo "==> Configuring PostgreSQL exporter user..."

POSTGRES_EXPORTER_PASSWORD="$(
    get_env_value POSTGRES_EXPORTER_PASSWORD
)"

[[ -n "$POSTGRES_EXPORTER_PASSWORD" ]] \
    || die "POSTGRES_EXPORTER_PASSWORD is empty"

docker compose exec -T postgres \
    psql \
    -U grafana \
    -d grafana \
    -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'postgres_exporter'
    ) THEN
        CREATE ROLE postgres_exporter
            LOGIN
            PASSWORD '${POSTGRES_EXPORTER_PASSWORD}';
    ELSE
        ALTER ROLE postgres_exporter
            WITH LOGIN
            PASSWORD '${POSTGRES_EXPORTER_PASSWORD}';
    END IF;
END
\$\$;

GRANT pg_monitor TO postgres_exporter;
GRANT CONNECT ON DATABASE grafana TO postgres_exporter;
SQL

echo "PostgreSQL exporter user configured."


# ============================================================
# Build and start complete stack
# ============================================================

echo
echo "==> Building and starting monitoring stack..."

docker compose up -d --build


# ============================================================
# Wait
# ============================================================

echo
echo "==> Waiting briefly for services..."

sleep 15

docker compose ps


# ============================================================
# Basic status validation
# ============================================================

echo
echo "==> Checking required services..."

REQUIRED_SERVICES=(
    postgres
    postgres-exporter
    grafana-1
    grafana-2
    renderer
    nginx
    nginx-exporter
    prometheus
    alertmanager
    node-exporter
    cadvisor
    influxdb
    pushgateway
    prometheus-federation
)

BOOTSTRAP_FAILED=0

for service in "${REQUIRED_SERVICES[@]}"; do

    CONTAINER_ID="$(
        docker compose ps -q "$service" 2>/dev/null || true
    )"

    if [[ -z "$CONTAINER_ID" ]]; then
        echo "[FAIL] ${service}: container not found"
        BOOTSTRAP_FAILED=1
        continue
    fi

    STATE="$(
        docker inspect \
            --format='{{.State.Status}}' \
            "$CONTAINER_ID" \
            2>/dev/null || true
    )"

    if [[ "$STATE" == "running" ]]; then
        echo "[OK]   ${service}"
    else
        echo "[FAIL] ${service}: ${STATE:-unknown}"
        BOOTSTRAP_FAILED=1
    fi
done


# ============================================================
# Config validation
# ============================================================

echo
echo "==> Checking Prometheus configuration..."

if docker compose exec -T prometheus \
    promtool check config /etc/prometheus/prometheus.yml
then
    echo "Prometheus configuration is valid."
else
    echo "Prometheus configuration validation failed."
    BOOTSTRAP_FAILED=1
fi

echo
echo "==> Checking Federation Prometheus configuration..."

if docker compose exec -T prometheus-federation \
    promtool check config /etc/prometheus/prometheus.yml
then
    echo "Federation Prometheus configuration is valid."
else
    echo "Federation Prometheus configuration validation failed."
    BOOTSTRAP_FAILED=1
fi

echo
echo "==> Checking Prometheus alert rules..."

if docker compose exec -T prometheus \
    promtool check rules /etc/prometheus/rules/alerts.yml
then
    echo "Prometheus alert rules are valid."
else
    echo "Prometheus alert rules validation failed."
    BOOTSTRAP_FAILED=1
fi


echo
echo "==> Checking Alertmanager configuration..."

if docker compose exec -T alertmanager \
    amtool check-config /etc/alertmanager/alertmanager.yml
then
    echo "Alertmanager configuration is valid."
else
    echo "Alertmanager configuration validation failed."
    BOOTSTRAP_FAILED=1
fi


echo
echo "==> Checking nginx configuration..."

if docker compose exec -T nginx nginx -t; then
    echo "nginx configuration is valid."
else
    echo "nginx configuration validation failed."
    BOOTSTRAP_FAILED=1
fi


# ============================================================
# Final
# ============================================================

echo
echo "=================================================="

if [[ "$BOOTSTRAP_FAILED" -ne 0 ]]; then
    echo "Monitoring stack bootstrap completed with errors."
    echo
    echo "Check:"
    echo "  docker compose ps"
    echo "  docker compose logs"
    echo "=================================================="
    exit 1
fi

echo "Monitoring stack bootstrap completed successfully."
echo
echo "Grafana:"
echo "  https://grafana.local"
echo
echo "Prometheus:"
echo "  https://prometheus.local:9090"
echo
echo "Alertmanager:"
echo "  http://127.0.0.1:9093"
echo
echo "InfluxDB:"
echo "  http://127.0.0.1:8086"
echo
echo "Local CA:"
echo "  certs/ca.crt"
echo
echo "IMPORTANT:"
echo "Trust certs/ca.crt in the host/browser if you want"
echo "to remove TLS certificate warnings."
echo
echo "GitLab OAuth:"
echo "If OAuth credentials were not entered, configure"
echo "GITLAB_CLIENT_ID and GITLAB_CLIENT_SECRET in .env."
echo
echo "Grafana API token:"
echo "Create it after Grafana starts and place it in:"
echo "GRAFANA_API_TOKEN in .env"
echo "=================================================="