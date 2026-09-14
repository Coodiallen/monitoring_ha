# Monitoring Stack

Docker-based monitoring lab with Grafana high availability, Prometheus, InfluxDB, PostgreSQL, nginx load balancing, Jsonnet/grafonnet dashboards, GitLab OAuth and local TLS.

## Architecture

```text
                     PostgreSQL
                    /          \
             Grafana-1        Grafana-2
                    \          /
                       nginx
                         |
                  https://grafana.local

Prometheus ---> node_exporter
InfluxDB ----> Grafana
```

Both Grafana instances use the same PostgreSQL database.
nginx distributes requests between the two Grafana instances.

## Technologies

- Grafana 13.2.1 x2
- PostgreSQL 17
- nginx
- Prometheus 3.14.0
- node_exporter 1.9.1
- InfluxDB 2.7
- Docker Compose
- Jsonnet / grafonnet
- GitLab OAuth
- TLS with a local CA


## Quick Start

Clone the repository:

```bash
git clone <repository-url>
cd monitoring
```

Run the bootstrap script:

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

The script prepares:

- `.env`
- local secrets
- TLS certificates
- `prometheus/web.yml`
- runtime directories
- Docker Compose services

GitLab OAuth credentials can be added to `.env` when required.

## Start Manually

If the environment is already prepared:

```bash
docker compose up -d --build
```

Check the stack:

```bash
docker compose ps
```

Expected services:

```text
grafana-1
grafana-2
postgres
nginx
prometheus
node-exporter
influxdb
```

## Access

Grafana:

```text
https://grafana.local
```

Prometheus:

```text
https://prometheus.local:9090
```

InfluxDB:

```text
http://127.0.0.1:8086
```

Local hostnames are added through `/etc/hosts`.

## Grafana HA

Grafana runs in active-active mode behind nginx.

Both instances use the same PostgreSQL database, so users, dashboards, datasources and other shared state are stored centrally.

Failover test:

```bash
docker compose stop grafana-1
curl --cacert certs/ca.crt -I https://grafana.local

docker compose start grafana-1
docker compose stop grafana-2
curl --cacert certs/ca.crt -I https://grafana.local

docker compose start grafana-2
```

The Grafana endpoint should remain available while one instance is stopped.

## Dashboards

Provisioned dashboards are stored in:

```text
grafana/dashboards/
├── Infrastructure/
├── Network/
└── Plugins/
```

Jsonnet/grafonnet sources are stored in:

```text
grafana/jsonnet/
```

Generated JSON files are written to:

```text
grafana/generated/
```

and are excluded from Git.

## Grafana Plugins

The custom Grafana image includes:

- Google Sheets datasource
- D3 Gauge panel

The image is built automatically by Docker Compose.

## Security

The project keeps sensitive and runtime files out of Git, including:

- `.env`
- `secrets/*`
- TLS certificates and private keys
- `prometheus/web.yml`
- PostgreSQL, Prometheus and InfluxDB runtime data
- generated Jsonnet files

Prometheus uses TLS and Basic Auth.
Grafana supports GitLab OAuth.

## Useful Commands

View logs:

```bash
docker compose logs -f
```

Grafana logs:

```bash
docker compose logs -f grafana-1 grafana-2
```

Check nginx configuration:

```bash
docker compose exec nginx nginx -t
```

Check PostgreSQL:

```bash
docker compose exec postgres   psql -U grafana -d grafana -c '\dt'
```

Stop the stack:

```bash
docker compose down
```
