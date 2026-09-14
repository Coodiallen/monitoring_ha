#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "==> Monitoring stack bootstrap"
echo

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_command() {
    if ! command_exists "$1"; then
        echo "ERROR: required command '$1' is not installed."
        exit 1
    fi
}

echo "==> Checking required commands..."

require_command docker
require_command openssl
require_command sed
require_command grep

if ! docker compose version >/dev/null 2>&1; then
    echo "ERROR: Docker Compose plugin is not available."
    exit 1
fi

echo "OK"
echo

echo "==> Creating required directories..."

mkdir -p \
    certs \
    secrets \
    postgres/data \
    prometheus/data \
    influxdb/data \
    influxdb/config \
    grafana/generated

echo "OK"
echo

# ---------------------------------------------------------
# .env
# ---------------------------------------------------------

if [ ! -f .env ]; then
    echo "==> Creating .env..."

    if [ -f .env.example ]; then
        cp .env.example .env
    else
        touch .env
    fi

    chmod 600 .env
else
    echo "==> .env already exists, keeping it."
fi

set_env_value() {
    local key="$1"
    local value="$2"

    if grep -q "^${key}=" .env; then
        sed -i.bak "s|^${key}=.*|${key}=${value}|" .env
    else
        printf '%s=%s\n' "$key" "$value" >> .env
    fi
}

get_env_value() {
    local key="$1"
    grep "^${key}=" .env 2>/dev/null | head -n1 | cut -d= -f2-
}

echo

# ---------------------------------------------------------
# Grafana DB password
# ---------------------------------------------------------

if [ -z "$(get_env_value GRAFANA_DB_PASSWORD || true)" ]; then
    echo "==> Generating PostgreSQL password for Grafana..."
    GRAFANA_DB_PASSWORD="$(openssl rand -base64 32 | tr -d '\n')"
    set_env_value "GRAFANA_DB_PASSWORD" "$GRAFANA_DB_PASSWORD"
else
    echo "==> GRAFANA_DB_PASSWORD already configured."
fi

# ---------------------------------------------------------
# Grafana secret key
# ---------------------------------------------------------

if [ -z "$(get_env_value GRAFANA_SECRET_KEY || true)" ]; then
    echo "==> Generating Grafana secret key..."
    GRAFANA_SECRET_KEY="$(openssl rand -hex 32)"
    set_env_value "GRAFANA_SECRET_KEY" "$GRAFANA_SECRET_KEY"
else
    echo "==> GRAFANA_SECRET_KEY already configured."
fi

# ---------------------------------------------------------
# Grafana admin password
# ---------------------------------------------------------

if [ -z "$(get_env_value GRAFANA_ADMIN_PASSWORD || true)" ]; then
    echo
    echo "==> Configure Grafana admin password"

    while true; do
        read -r -s -p "Grafana admin password: " GRAFANA_ADMIN_PASSWORD
        echo

        read -r -s -p "Confirm Grafana admin password: " GRAFANA_ADMIN_PASSWORD_CONFIRM
        echo

        if [ -z "$GRAFANA_ADMIN_PASSWORD" ]; then
            echo "Password cannot be empty."
            continue
        fi

        if [ "$GRAFANA_ADMIN_PASSWORD" != "$GRAFANA_ADMIN_PASSWORD_CONFIRM" ]; then
            echo "Passwords do not match."
            continue
        fi

        break
    done

    set_env_value "GRAFANA_ADMIN_PASSWORD" "$GRAFANA_ADMIN_PASSWORD"
else
    echo "==> GRAFANA_ADMIN_PASSWORD already configured."
fi

# ---------------------------------------------------------
# GitLab OAuth
# ---------------------------------------------------------

if [ -z "$(get_env_value GITLAB_CLIENT_ID || true)" ]; then
    echo
    read -r -p "GitLab OAuth Client ID (leave empty to skip): " GITLAB_CLIENT_ID

    if [ -n "$GITLAB_CLIENT_ID" ]; then
        set_env_value "GITLAB_CLIENT_ID" "$GITLAB_CLIENT_ID"
    fi
else
    echo "==> GITLAB_CLIENT_ID already configured."
fi

if [ -z "$(get_env_value GITLAB_CLIENT_SECRET || true)" ]; then
    if [ -n "${GITLAB_CLIENT_ID:-$(get_env_value GITLAB_CLIENT_ID || true)}" ]; then
        read -r -s -p "GitLab OAuth Client Secret: " GITLAB_CLIENT_SECRET
        echo

        if [ -n "$GITLAB_CLIENT_SECRET" ]; then
            set_env_value "GITLAB_CLIENT_SECRET" "$GITLAB_CLIENT_SECRET"
        fi
    fi
else
    echo "==> GITLAB_CLIENT_SECRET already configured."
fi

# ---------------------------------------------------------
# Grafana API token placeholder
# ---------------------------------------------------------

if ! grep -q '^GRAFANA_API_TOKEN=' .env; then
    echo "GRAFANA_API_TOKEN=" >> .env
fi

rm -f .env.bak

echo
echo "==> Environment prepared."

# ---------------------------------------------------------
# Prometheus Basic Auth
# ---------------------------------------------------------

PROM_PASSWORD_FILE="secrets/prometheus-basic-auth-password"

if [ ! -s "$PROM_PASSWORD_FILE" ]; then
    echo "==> Generating Prometheus Basic Auth password..."

    PROMETHEUS_PASSWORD="$(openssl rand -base64 32 | tr -d '\n')"

    printf '%s\n' "$PROMETHEUS_PASSWORD" > "$PROM_PASSWORD_FILE"
    chmod 600 "$PROM_PASSWORD_FILE"
else
    echo "==> Prometheus Basic Auth password already exists."
    PROMETHEUS_PASSWORD="$(cat "$PROM_PASSWORD_FILE")"
fi

# Grafana needs the same password for its Prometheus datasource.
# .env is excluded from Git.
set_env_value \
    "PROMETHEUS_BASIC_AUTH_PASSWORD" \
    "$PROMETHEUS_PASSWORD"

echo "==> Generating Prometheus bcrypt hash..."

PROMETHEUS_BCRYPT_HASH="$(
    docker run --rm httpd:alpine \
        htpasswd -nbB grafana "$PROMETHEUS_PASSWORD" \
        | cut -d: -f2-
)"

# ---------------------------------------------------------
# InfluxDB secrets
# ---------------------------------------------------------

if [ ! -s secrets/influxdb-admin-password ]; then
    echo "==> Generating InfluxDB admin password..."
    openssl rand -base64 32 | tr -d '\n' > secrets/influxdb-admin-password
    printf '\n' >> secrets/influxdb-admin-password
    chmod 600 secrets/influxdb-admin-password
else
    echo "==> InfluxDB admin password already exists."
fi

if [ ! -s secrets/influxdb-admin-token ]; then
    echo "==> Generating InfluxDB admin token..."
    openssl rand -hex 32 > secrets/influxdb-admin-token
    chmod 600 secrets/influxdb-admin-token
else
    echo "==> InfluxDB admin token already exists."
fi

INFLUXDB_TOKEN="$(tr -d '\n' < secrets/influxdb-admin-token)"

set_env_value \
    "INFLUXDB_TOKEN" \
    "$INFLUXDB_TOKEN"

# ---------------------------------------------------------
# CA
# ---------------------------------------------------------

if [ ! -f certs/ca.key ] || [ ! -f certs/ca.crt ]; then
    echo
    echo "==> Generating local Certificate Authority..."

    openssl genrsa \
        -out certs/ca.key \
        4096

    chmod 600 certs/ca.key

    openssl req \
        -x509 \
        -new \
        -nodes \
        -key certs/ca.key \
        -sha256 \
        -days 3650 \
        -out certs/ca.crt \
        -subj "/CN=Monitoring Local CA"
else
    echo
    echo "==> Local CA already exists."
fi

# ---------------------------------------------------------
# Grafana certificate
# ---------------------------------------------------------

if [ ! -f certs/grafana.key ] || [ ! -f certs/grafana.crt ]; then
    echo "==> Generating Grafana TLS certificate..."

    cat > certs/grafana.ext <<'EOF'
subjectAltName = DNS:grafana.local,DNS:localhost,IP:127.0.0.1
EOF

    openssl genrsa \
        -out certs/grafana.key \
        2048

    chmod 600 certs/grafana.key

    openssl req \
        -new \
        -key certs/grafana.key \
        -out certs/grafana.csr \
        -subj "/CN=grafana.local"

    openssl x509 \
        -req \
        -in certs/grafana.csr \
        -CA certs/ca.crt \
        -CAkey certs/ca.key \
        -CAcreateserial \
        -out certs/grafana.crt \
        -days 825 \
        -sha256 \
        -extfile certs/grafana.ext
else
    echo "==> Grafana TLS certificate already exists."
fi

# ---------------------------------------------------------
# Prometheus certificate
# ---------------------------------------------------------

if [ ! -f certs/prometheus.key ] || [ ! -f certs/prometheus.crt ]; then
    echo "==> Generating Prometheus TLS certificate..."

    cat > certs/prometheus.ext <<'EOF'
subjectAltName = DNS:prometheus,DNS:prometheus.local,DNS:localhost,IP:127.0.0.1
EOF

    openssl genrsa \
        -out certs/prometheus.key \
        2048

    chmod 600 certs/prometheus.key

    openssl req \
        -new \
        -key certs/prometheus.key \
        -out certs/prometheus.csr \
        -subj "/CN=prometheus"

    openssl x509 \
        -req \
        -in certs/prometheus.csr \
        -CA certs/ca.crt \
        -CAkey certs/ca.key \
        -CAcreateserial \
        -out certs/prometheus.crt \
        -days 825 \
        -sha256 \
        -extfile certs/prometheus.ext
else
    echo "==> Prometheus TLS certificate already exists."
fi

# ---------------------------------------------------------
# prometheus/web.yml
# ---------------------------------------------------------

echo
echo "==> Creating prometheus/web.yml..."

cat > prometheus/web.yml <<EOF
tls_server_config:
  cert_file: /etc/prometheus/certs/prometheus.crt
  key_file: /etc/prometheus/certs/prometheus.key

basic_auth_users:
  grafana: '${PROMETHEUS_BCRYPT_HASH}'
EOF

chmod 600 prometheus/web.yml

# ---------------------------------------------------------
# Prometheus Linux permissions
# ---------------------------------------------------------

echo
echo "==> Configuring Prometheus filesystem permissions..."

PROMETHEUS_UID="$(
    docker run --rm \
        --entrypoint /bin/sh \
        prom/prometheus:v3.14.0 \
        -c 'id -u'
)"

PROMETHEUS_GID="$(
    docker run --rm \
        --entrypoint /bin/sh \
        prom/prometheus:v3.14.0 \
        -c 'id -g'
)"

echo "Prometheus container UID:GID = ${PROMETHEUS_UID}:${PROMETHEUS_GID}"

if [ "$(uname -s)" = "Linux" ]; then
    echo "Applying Linux ownership and permissions..."

    sudo chown -R \
        "${PROMETHEUS_UID}:${PROMETHEUS_GID}" \
        prometheus/data

    sudo chmod 755 prometheus/data

    sudo chown \
        "$(id -u):${PROMETHEUS_GID}" \
        "$PROM_PASSWORD_FILE"

    sudo chmod 640 "$PROM_PASSWORD_FILE"

    sudo chown \
        root:"${PROMETHEUS_GID}" \
        certs/prometheus.key

    sudo chmod 640 certs/prometheus.key

    chmod 644 \
        certs/prometheus.crt \
        certs/ca.crt \
        prometheus/web.yml

    echo "Prometheus permissions configured."
else
    echo "Non-Linux host detected. Skipping Linux ownership changes."
fi

# ---------------------------------------------------------
# /etc/hosts
# ---------------------------------------------------------

echo
echo "==> Configuring /etc/hosts..."

set_local_host() {
    local hostname="$1"

    if grep -qE "(^|[[:space:]])${hostname//./\\.}([[:space:]]|$)" /etc/hosts; then
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

# ---------------------------------------------------------
# Validation
# ---------------------------------------------------------

echo
echo "==> Validating Docker Compose configuration..."

docker compose config >/dev/null

echo "Compose configuration is valid."

# ---------------------------------------------------------
# Start stack
# ---------------------------------------------------------

echo
echo "==> Building and starting monitoring stack..."

docker compose up -d --build

echo
echo "==> Waiting briefly for services..."
sleep 5

docker compose ps

echo
echo "=================================================="
echo "Monitoring stack bootstrap completed."
echo
echo "Grafana:"
echo "  https://grafana.local"
echo
echo "Prometheus:"
echo "  https://prometheus.local:9090"
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
