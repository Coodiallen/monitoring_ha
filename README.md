# Monitoring HA Stack

Docker-based monitoring and observability pet project with Grafana HA, Prometheus HA/federation, alerting, exporters, TLS and automated deployment.

## Architecture

```text
    PostgreSQL
        │
    ┌───┴────┐
    │        │
Grafana-1 Grafana-2
    │        │
    └───┬────┘
        │
      nginx
        │
 https://grafana.local


Targets
├── node_exporter
├── cAdvisor
├── nginx exporter
├── postgres exporter
├── Grafana
├── Pushgateway
└── Alertmanager
        │
   ┌────┴────┐
   │         │
Prometheus  Prometheus
 Primary     Replica
   │
   └── /federate ──> Federation Prometheus

Prometheus ──> Alertmanager ──> Telegram
```

## Stack

- Grafana 13.2.1 x2
- Prometheus 3.14.0
- Alertmanager 0.34.0
- PostgreSQL 17
- nginx
- Pushgateway
- node_exporter
- cAdvisor
- nginx / PostgreSQL exporters
- Grafana Image Renderer
- InfluxDB
- Docker Compose

## Features

- Grafana active-active HA behind nginx
- Shared PostgreSQL backend
- Prometheus primary + independent replica
- Prometheus federation
- `file_sd` service discovery
- recording and alerting rules
- Alertmanager + Telegram
- alert deduplication between Prometheus replicas
- Pushgateway batch-job metrics
- host and container monitoring
- TSDB snapshots
- GitLab OAuth
- TLS and Prometheus Basic Auth
- automated bootstrap from a clean clone

## Quick Start

```bash
git clone git@github.com:Coodiallen/monitoring_ha.git
cd monitoring_ha

chmod +x bootstrap.sh
./bootstrap.sh
```

Check the stack:

```bash
docker compose ps
```

The bootstrap script generates local secrets, TLS certificates, runtime directories, Prometheus authentication and starts the complete stack.

## Access

```text
Grafana                 https://grafana.local
Prometheus Primary      https://prometheus.local:9090
Prometheus Replica      https://prometheus-replica.local:9094
Prometheus Federation   http://127.0.0.1:9092
Alertmanager            http://127.0.0.1:9093
Pushgateway             http://127.0.0.1:9091
InfluxDB                http://127.0.0.1:8086
```

Local hostnames are added automatically to `/etc/hosts`.

## Monitoring

Main provisioned dashboard:

```text
HA Monitoring Cluster
```

It includes Prometheus, PostgreSQL, Grafana and nginx metrics together with CPU, memory, filesystem, network and disk I/O monitoring.

Prometheus configuration:

```text
prometheus/
├── rules/
├── targets/
├── replica/
└── federation/
```

## Backup

Configuration backup:

```bash
./scripts/backup-monitor.sh
```

Backup metrics are pushed to Pushgateway and monitored by Prometheus.

Prometheus Primary and Replica also support TSDB snapshots.

## Security

Secrets and runtime data are excluded from Git.

The stack uses TLS, Prometheus Basic Auth, GitLab OAuth, Docker secrets for Telegram and dedicated PostgreSQL monitoring credentials.

## Project Structure

```text
.
├── alertmanager/
├── grafana/
├── nginx/
├── prometheus/
├── scripts/
├── bootstrap.sh
├── compose.yaml
└── .env.example
```