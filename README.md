# Monitoring HA Stack

Docker-based monitoring stack with highly available Grafana, Prometheus, PostgreSQL, nginx load balancing, exporters, container monitoring, GitLab OAuth and local TLS.

## Architecture

```text
                    PostgreSQL
                       │
             ┌─────────┴─────────┐
             │                   │
         Grafana-1           Grafana-2
             │                   │
             └─────────┬─────────┘
                       │
                     nginx
                       │
              https://grafana.local


Prometheus
├── Prometheus self-monitoring
├── Grafana-1 / Grafana-2
├── node_exporter
├── nginx-exporter
├── postgres-exporter
└── cAdvisor

Grafana ── InfluxDB
Grafana ── Image Renderer
```

Both Grafana instances use the same PostgreSQL database and run in active-active mode behind nginx.

## Components

- Grafana 13.2.1 x2
- PostgreSQL 17
- Prometheus 3.14.0
- nginx
- nginx-prometheus-exporter 1.5.1
- postgres_exporter 0.20.1
- node_exporter 1.9.1
- cAdvisor 0.60.5
- Grafana Image Renderer 5.12.3
- InfluxDB 2.7
- Docker Compose
- Jsonnet / grafonnet
- GitLab OAuth
- Local TLS CA

## Features

- Grafana active-active HA behind nginx
- Shared PostgreSQL backend
- Prometheus TLS + Basic Auth
- Grafana GitLab OAuth
- Grafana Image Renderer
- Prometheus monitoring of both Grafana instances
- nginx and PostgreSQL exporters
- Container CPU, RAM, network and disk metrics via cAdvisor
- Provisioned dashboards from JSON
- Jsonnet/grafonnet dashboard sources
- Local TLS certificates generated during bootstrap

## Quick Start

```bash
git clone git@github.com:Coodiallen/monitoring_ha.git
cd monitoring_ha

chmod +x bootstrap.sh
./bootstrap.sh
```

The bootstrap script automatically prepares:

- `.env`
- passwords and local secrets
- Grafana renderer token
- PostgreSQL exporter user
- TLS certificates
- Prometheus web configuration
- runtime directories
- Docker Compose stack

Check the stack:

```bash
docker compose ps
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

Local hostnames are added to `/etc/hosts`.

## Dashboards

Provisioned dashboards are stored in:

```text
grafana/dashboards/
```

Main dashboard:

```text
HA Monitoring Cluster
```

It contains dedicated sections for:

- Prometheus
- PostgreSQL
- Grafana
- nginx

The dashboard combines application metrics with container CPU, RAM, network, storage and disk I/O metrics.

## HA Test

Grafana should remain available while either instance is stopped:

```bash
docker compose stop grafana-1
curl --cacert certs/ca.crt -I https://grafana.local
docker compose start grafana-1
```

The same test can be repeated with `grafana-2`.

## Security

Sensitive and runtime files are excluded from Git:

- `.env`
- `secrets/*`
- generated TLS certificates and private keys
- `prometheus/web.yml`
- PostgreSQL data
- Prometheus data
- InfluxDB data

The stack uses:

- TLS
- Prometheus Basic Auth
- GitLab OAuth
- Grafana shared secret key
- authenticated Image Renderer
- dedicated PostgreSQL monitoring user

## Project Structure

```text
.
├── bootstrap.sh
├── compose.yaml
├── .env.example
├── grafana/
│   ├── dashboards/
│   ├── jsonnet/
│   └── provisioning/
├── nginx/
├── prometheus/
├── certs/
├── secrets/
└── scripts/
```

## Useful Commands

```bash
docker compose ps
docker compose logs -f
docker compose logs -f grafana-1 grafana-2
docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml
docker compose exec nginx nginx -t
docker compose down
```

## Planned Improvements

- Telegram alerts
- Grafana teams and permissions
- Dashboard playlist
- Exact pinning of remaining Docker image versions