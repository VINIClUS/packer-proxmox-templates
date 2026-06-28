# Extra Monitoring Targets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add centralized observability for CT `110 nginx`, CT `134 esus-pec-minio`, and CT `120 infisical`.

**Architecture:** Reuse the existing CT target agent for node exporter, Alloy log shipping, and Nginx exporter. Extend CT `190` Prometheus with static scrape jobs for the new targets, add Blackbox Exporter for HTTP/TLS health probes, scrape MinIO's native HTTPS Prometheus endpoint, and add local PostgreSQL/Redis exporters to CT `120` without storing credentials. Grafana receives a fifth dense dashboard for platform services.

**Tech Stack:** PowerShell, Bash inside Proxmox/LXC, Prometheus, Grafana, Loki, Grafana Alloy, Blackbox Exporter, Nginx exporter, MinIO Prometheus metrics, PostgreSQL exporter, Redis exporter.

---

## Observed Topology

- CT `110 nginx`: hostname `nginx`, LAN IP `192.168.1.139`, service `nginx.service`, HTTP `80`, expected metrics `9100` and `9113`.
- CT `120 infisical`: hostname `infisical`, LAN IP `192.168.1.226`, Infisical HTTP `8080`, local PostgreSQL `127.0.0.1:5432`, local Redis `127.0.0.1:6379`, expected metrics `9100`, `9187`, and `9121`.
- CT `134 esus-pec-minio`: hostname `esus-pec-minio`, LAN IP `192.168.1.210`, MinIO HTTPS API `9000`, console `9001`, expected metrics `9100` plus native MinIO endpoint `https://192.168.1.210:9000/minio/v2/metrics/cluster`.
- CT `190 monitoring-core`: Prometheus/Grafana/Loki core, Blackbox Exporter will listen locally on `127.0.0.1:9115`.

## File Structure

- Modify `scripts/monitoring/Install-MonitoringTargetAgent.ps1`
  - Add `TargetMetricsHost` parameter and surface it in JSON summaries.
  - Preserve current behavior for CT `133`.
- Create `scripts/monitoring/Install-InfisicalMonitoringExporters.ps1`
  - Install and validate PostgreSQL exporter using local peer authentication as Unix user `postgres`.
  - Install and validate Redis exporter against `redis://127.0.0.1:6379`.
  - Add nftables firewall rules allowing `9187` and `9121` only from CT `190` plus loopback.
- Modify `scripts/monitoring/Provision-MonitoringCore.ps1`
  - Install/manage Blackbox Exporter.
  - Push `/etc/prometheus/blackbox.yml`.
  - Replace target placeholders for CT `110`, `120`, and `134`.
- Modify `scripts/monitoring/templates/prometheus.yml`
  - Add scrape jobs for CT `110`, CT `120`, CT `134`, MinIO native metrics, and Blackbox HTTP probes.
- Create `scripts/monitoring/templates/blackbox.yml`
  - Define `http_2xx_insecure_tls` with `insecure_skip_verify: true` for local self-signed MinIO TLS.
- Create `scripts/monitoring/dashboards/platform-services-ct110-ct120-ct134.json`
  - Dense dashboard covering Nginx, MinIO, Infisical, PostgreSQL, Redis, node metrics, probes, and logs.
- Modify `scripts/monitoring/Publish-GrafanaDashboards.ps1`
  - No code change expected; it publishes every dashboard JSON in the folder.
- Modify `tests/Validate-MonitoringStack.ps1`
  - Assert new artifacts, scrape targets, Blackbox config, Infisical exporters, dashboard coverage, and secret-safety.
- Modify `docs/monitoring/2026-06-14-centralized-monitoring.md`
  - Document CT `110`, CT `120`, CT `134`, install commands, rollback, and validation evidence.

## Task 1: Add Static Contract

**Files:**
- Modify: `tests/Validate-MonitoringStack.ps1`
- Test: `tests/Validate-MonitoringStack.ps1`

- [ ] **Step 1: Require new artifacts**

Add required artifacts:

```powershell
"scripts/monitoring/Install-InfisicalMonitoringExporters.ps1",
"scripts/monitoring/templates/blackbox.yml",
"scripts/monitoring/dashboards/platform-services-ct110-ct120-ct134.json",
```

- [ ] **Step 2: Assert Prometheus target coverage**

Require these active template terms:

```powershell
"NGINX_CT_TARGET_METRICS_HOST:9100",
"NGINX_CT_TARGET_METRICS_HOST:9113",
"INFISICAL_CT_TARGET_METRICS_HOST:9100",
"INFISICAL_CT_TARGET_METRICS_HOST:9187",
"INFISICAL_CT_TARGET_METRICS_HOST:9121",
"MINIO_CT_TARGET_METRICS_HOST:9100",
"MINIO_CT_TARGET_METRICS_HOST:9000",
"/minio/v2/metrics/cluster",
"prometheus-blackbox-exporter",
"http_2xx_insecure_tls",
```

- [ ] **Step 3: Assert dashboard coverage**

Require dashboard expressions containing:

```powershell
"probe_success",
"nginx_up",
"minio_cluster_capacity_usable_free_bytes",
"minio_cluster_bucket_total",
"pg_up",
"redis_up",
"node_filesystem_avail_bytes",
"host=\"nginx\"",
"host=\"infisical\"",
"host=\"esus-pec-minio\"",
```

- [ ] **Step 4: Run static test and verify red**

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-MonitoringStack.ps1
```

Expected: fail on missing `Install-InfisicalMonitoringExporters.ps1`.

## Task 2: Implement Core Scrapes and Blackbox Exporter

**Files:**
- Modify: `scripts/monitoring/Provision-MonitoringCore.ps1`
- Modify: `scripts/monitoring/templates/prometheus.yml`
- Create: `scripts/monitoring/templates/blackbox.yml`
- Test: `tests/Validate-MonitoringStack.ps1`

- [ ] **Step 1: Add Blackbox config**

Create:

```yaml
modules:
  http_2xx_insecure_tls:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: []
      method: GET
      preferred_ip_protocol: ip4
      tls_config:
        insecure_skip_verify: true
```

- [ ] **Step 2: Add Prometheus jobs**

Add jobs:

```yaml
  - job_name: nginx
    static_configs:
      - targets:
          - NGINX_CT_TARGET_METRICS_HOST:9100
          - NGINX_CT_TARGET_METRICS_HOST:9113
        labels:
          host: nginx
          ctid: "110"
          app: nginx

  - job_name: infisical
    static_configs:
      - targets:
          - INFISICAL_CT_TARGET_METRICS_HOST:9100
          - INFISICAL_CT_TARGET_METRICS_HOST:9187
          - INFISICAL_CT_TARGET_METRICS_HOST:9121
        labels:
          host: infisical
          ctid: "120"
          app: infisical

  - job_name: esus-pec-minio
    static_configs:
      - targets:
          - MINIO_CT_TARGET_METRICS_HOST:9100
        labels:
          host: esus-pec-minio
          ctid: "134"
          app: minio

  - job_name: esus-pec-minio-native
    scheme: https
    metrics_path: /minio/v2/metrics/cluster
    tls_config:
      insecure_skip_verify: true
    static_configs:
      - targets:
          - MINIO_CT_TARGET_METRICS_HOST:9000
        labels:
          host: esus-pec-minio
          ctid: "134"
          app: minio

  - job_name: platform-http-probes
    metrics_path: /probe
    params:
      module: [http_2xx_insecure_tls]
    static_configs:
      - targets: [http://NGINX_CT_TARGET_METRICS_HOST/]
        labels: { host: nginx, ctid: "110", app: nginx }
      - targets: [http://INFISICAL_CT_TARGET_METRICS_HOST:8080/health]
        labels: { host: infisical, ctid: "120", app: infisical }
      - targets: [https://MINIO_CT_TARGET_METRICS_HOST:9000/minio/health/live]
        labels: { host: esus-pec-minio, ctid: "134", app: minio }
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: 127.0.0.1:9115
```

- [ ] **Step 3: Update core provisioner**

Install `prometheus-blackbox-exporter`, write `/etc/prometheus/blackbox.yml`, manage the service, and include it in service health checks.

- [ ] **Step 4: Run static test**

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-MonitoringStack.ps1
```

Expected: fail only for missing Infisical exporter script or dashboard.

## Task 3: Install Target Agents and Infisical Exporters

**Files:**
- Modify: `scripts/monitoring/Install-MonitoringTargetAgent.ps1`
- Create: `scripts/monitoring/Install-InfisicalMonitoringExporters.ps1`
- Test: `tests/Validate-MonitoringStack.ps1`

- [ ] **Step 1: Generalize target metrics host**

Add:

```powershell
[string]$TargetMetricsHost = "192.168.1.209"
```

Use it when delegating to application exporters and in JSON output.

- [ ] **Step 2: Add Infisical exporter installer**

Implement a CT identity guard for `TargetCtid=120`, `TargetName=infisical`, install `prometheus-postgres-exporter` and `prometheus-redis-exporter`, and write services:

```ini
[Service]
User=postgres
Environment='DATA_SOURCE_NAME=user=postgres host=/var/run/postgresql dbname=postgres sslmode=disable'
ExecStart=/usr/bin/prometheus-postgres-exporter --web.listen-address=0.0.0.0:9187
```

```ini
[Service]
ExecStart=/usr/bin/prometheus-redis-exporter --redis.addr=redis://127.0.0.1:6379 --web.listen-address=0.0.0.0:9121
```

Firewall must allow loopback and `192.168.1.190` only.

- [ ] **Step 3: Validate exporters locally**

Inside CT `120`, require:

```bash
curl -fsS http://127.0.0.1:9187/metrics | grep -q '^pg_up 1'
curl -fsS http://127.0.0.1:9121/metrics | grep -q '^redis_up 1'
```

## Task 4: Add Platform Services Dashboard

**Files:**
- Create: `scripts/monitoring/dashboards/platform-services-ct110-ct120-ct134.json`
- Test: JSON parse and `tests/Validate-MonitoringStack.ps1`

- [ ] **Step 1: Add dense panels**

Panels must include:

- Nginx availability, Nginx exporter status, active connections, request rate, OS CPU/memory/disk.
- MinIO probe, native scrape, capacity, bucket count, online/offline drives, node disk.
- Infisical probe, PostgreSQL up, Redis up, PostgreSQL connections, Redis memory, node CPU/memory.
- Logs for `host=~"nginx|infisical|esus-pec-minio"`.

- [ ] **Step 2: Parse dashboards**

```powershell
rtk node -e "const fs=require('fs'); for (const f of fs.readdirSync('scripts/monitoring/dashboards').filter(x=>x.endsWith('.json'))) JSON.parse(fs.readFileSync('scripts/monitoring/dashboards/'+f,'utf8')); console.log('dashboard json ok')"
```

## Task 5: Deploy, Validate, Document, Commit

**Files:**
- Modify: `docs/monitoring/2026-06-14-centralized-monitoring.md`
- External: CT `110`, CT `120`, CT `134`, CT `190`, Grafana

- [ ] **Step 1: Install agents**

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Install-MonitoringTargetAgent.ps1 -TargetCtid 110 -TargetName nginx -TargetMetricsHost 192.168.1.139
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Install-MonitoringTargetAgent.ps1 -TargetCtid 120 -TargetName infisical -TargetMetricsHost 192.168.1.226
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Install-MonitoringTargetAgent.ps1 -TargetCtid 134 -TargetName esus-pec-minio -TargetMetricsHost 192.168.1.210
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Install-InfisicalMonitoringExporters.ps1
```

- [ ] **Step 2: Apply core config and dashboards**

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Provision-MonitoringCore.ps1 -SkipCreate
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Publish-GrafanaDashboards.ps1
```

- [ ] **Step 3: Validate Prometheus**

Expected non-empty vectors:

```text
up{host="nginx",instance="192.168.1.139:9113"} == 1
up{host="infisical",instance="192.168.1.226:9187"} == 1
up{host="infisical",instance="192.168.1.226:9121"} == 1
up{job="esus-pec-minio-native"} == 1
probe_success{host="nginx"} == 1
probe_success{host="infisical"} == 1
probe_success{host="esus-pec-minio"} == 1
```

- [ ] **Step 4: Document and log**

Update the runbook with installation, rollback, and validation evidence. Register a secret-safe Obsidian finding after live validation.

- [ ] **Step 5: Final verification and commit**

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-MonitoringStack.ps1
rtk node -e "const fs=require('fs'); for (const f of fs.readdirSync('scripts/monitoring/dashboards').filter(x=>x.endsWith('.json'))) JSON.parse(fs.readFileSync('scripts/monitoring/dashboards/'+f,'utf8')); console.log('dashboard json ok')"
rtk git diff --check
rtk git status --short
```

Commit:

```powershell
rtk git add scripts/monitoring tests/Validate-MonitoringStack.ps1 docs/monitoring/2026-06-14-centralized-monitoring.md docs/superpowers/plans/2026-06-21-monitoring-extra-targets.md
rtk git commit -m "Add monitoring for platform service containers"
```
