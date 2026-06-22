# Centralized Monitoring Runbook

Date: 2026-06-14
Workspace: `C:\Users\Vinicius\Projetos\packer-proxmox-templates`

## Scope

This runbook covers the first centralized monitoring rollout for e-SUS PEC lab
monitoring. The implementation creates a native systemd monitoring core in LXC
`190 monitoring-core` and installs the first Linux target agents on LXC
`133 esus-pec-lxc-5437`.

Production PEC and SIHA are documented as future targets. Production PEC is not
the same collection shape as CT `133`: production uses Tomcat instead of the
CT `133` Nginx termination pattern. SIHA VM `7001` remains future work until the
target OS and systems are ready for monitored agent installation.

The second platform rollout adds observability for CT `110 nginx`, CT
`120 infisical`, and CT `134 esus-pec-minio`.

## Topology

### Monitoring Core

- CTID: `190` (`CTID 190`)
- Hostname: `monitoring-core`
- Runtime model: native Grafana/Alloy and upstream Prometheus/Loki systemd
  services, not Docker.
- Prometheus origin: `http://192.168.1.190:9090`
- Grafana origin: `http://192.168.1.190:3000`
- Prometheus public URL: `https://prometheus.vinisantana.com`
- Grafana public URL: `https://grafana.vinisantana.com`
- Loki: `http://192.168.1.190:3100`
- Grafana Alloy: local service on CT `190`; the default Alloy diagnostic
  endpoint is local-only on port `12345` when enabled by the packaged service.

### Initial Target

- CTID: `133`
- Hostname: `esus-pec-lxc-5437`
- Role: e-SUS PEC 5.4.37 application and bundled database target for Linux
  metrics, PostgreSQL exporter through a dedicated `prometheus_exporter`
  account managed in Infisical when configured, and Alloy log shipping.

### Future Targets

- Production PEC: future work. Do not assume the CT `133` Nginx pattern applies;
  production uses Tomcat, so JVM/Tomcat collection must be validated separately
  before applying agents.
- SIHA: VM `7001`, future target after the OS and billing systems are ready for
  monitored access.

### Platform Service Targets

- CTID: `110`
  - Hostname: `nginx`
  - Metrics host: `192.168.1.139`
  - Coverage: node exporter, Alloy logs, Nginx exporter, Blackbox HTTP probe.
- CTID: `120`
  - Hostname: `infisical`
  - Metrics host: `192.168.1.226`
  - Coverage: node exporter, Alloy logs, Blackbox `/health` probe, PostgreSQL
    exporter through local peer authentication, Redis exporter through local
    `redis://127.0.0.1:6379`.
- CTID: `134`
  - Hostname: `esus-pec-minio`
  - Metrics host: `192.168.1.210`
  - Coverage: node exporter, Alloy logs, Blackbox HTTPS health probe, native
    MinIO Prometheus metrics at `/minio/v2/metrics/cluster` with local TLS
    verification disabled in Prometheus for the self-signed endpoint.

## Agent Choice

Use Grafana Alloy instead of Promtail for new log collection. Promtail is in
long-term support and has an announced end-of-life date, while Grafana's current
collection path is Alloy. New monitoring configuration should therefore use
Alloy for logs and compatible metrics pipelines.

## Install

Run commands from the repository worktree. These commands read Proxmox access
settings from local ignored configuration and must not print secrets.

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Provision-MonitoringCore.ps1
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Install-MonitoringTargetAgent.ps1
```

`Provision-MonitoringCore.ps1` creates or updates CT `190` and installs
Prometheus, Grafana, Loki, and Alloy as systemd services. `Install-MonitoringTargetAgent.ps1`
targets CT `133 esus-pec-lxc-5437` by default and installs Alloy plus exporter
services.

Application exporters are opt-in because they create a database role and, for
JMX, update the e-SUS PEC Java service start command through a managed
systemd drop-in. After the monitoring core already exists, apply the core
config, install the PostgreSQL and JMX exporters, then publish dashboards:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Provision-MonitoringCore.ps1 -SkipCreate
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Install-MonitoringTargetAgent.ps1 -ConfigurePostgresExporter -ConfigureJmxExporter -ApplyJavaServiceChange
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Publish-GrafanaDashboards.ps1
```

`-ConfigurePostgresExporter` installs `prometheus-postgres-exporter` on CT
`133` and exposes metrics on TCP `9187`. `-ConfigureJmxExporter` stages the JMX
agent and exposes JVM metrics on TCP `9404`. `-ApplyJavaServiceChange` writes
the managed `monitoring-jmx.conf` drop-in, points `ExecStart` to
`/opt/monitoring/run-esus-pec-with-jmx.sh`, and restarts
`e-SUS-PEC.service`; omit that flag when only staging/reviewing JMX artifacts.

The target-side firewall must remain restricted to the Prometheus host:
loopback is accepted, the monitoring core host is accepted, and other traffic to
TCP `9187`/`9404` is rejected or dropped. Do not expose these ports broadly.

Pinned application exporter artifacts:

| Component | Version | SHA256 |
|---|---:|---|
| `postgres_exporter` | `postgres_exporter 0.19.1` | `229096c7988df6ca41fe5b4bf66865089971535e7f0d819c12c920ec64dd2bd0` |
| `jmx_exporter` | `jmx_exporter 1.6.0` | `a95983fd96e865d2bcdf911cc500e7c82808c27ab9fd226bf96732b6c3d8c46e` |

## Grafana Dashboards

Managed dashboards live in `scripts/monitoring/dashboards` and are published
through the Grafana API using these local `.env` keys:

```text
grafana_url=https://grafana.vinisantana.com
prometheus_url=https://prometheus.vinisantana.com
grafana_token=<Grafana service account token>
```

Create the token as a Grafana service account token with dashboard and folder
write permissions. Do not store the token in tracked files. The publisher reads
lowercase names from `.env` and also accepts uppercase environment variables.

Publish or update the managed dashboards:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Publish-GrafanaDashboards.ps1
```

The managed folder is `e-SUS PEC Monitoring` with folder UID
`esus-pec-monitoring`. The current dashboard set is:

- `e-SUS Monitoring Overview`
- `Monitoring Core CT 190`
- `e-SUS PEC CT 133`
- `Platform Services CT 110 120 134`
- `Logs and Diagnostics`

Datasource UIDs are fixed as `prometheus` and `loki`. The publisher manages
them through the Grafana API before writing dashboards. File-based datasource
provisioning is intentionally not pushed by `Provision-MonitoringCore.ps1`
because Grafana `13.0.2` returned `Datasource provisioning error: data source
not found` during service startup in this CT.

## Infisical Grafana Env Sync

The appropriate Infisical location for Grafana dashboard publishing variables is
`/test/Monitoring` in project `esus-pec-z-px-c`, environment `dev`.
This dedicated path keeps monitoring credentials separate from PEC installation
configuration after the 2026-06-21 token expansion. Tracked
placeholders are in `config/esus-pec.infisical.env.example`.

Sync the non-secret URL and, when present locally, the token value:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Sync-GrafanaInfisicalEnv.ps1
```

If `grafana_token` is absent locally, the script writes only `grafana_url` and
reports `grafana_token` as skipped without overwriting any existing remote
token.

## Validation

Static validation:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-MonitoringStack.ps1
```

Live or idempotence validation after the core exists:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Provision-MonitoringCore.ps1 -SkipCreate
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Install-MonitoringTargetAgent.ps1
```

Application exporter validation after the guarded install:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Provision-MonitoringCore.ps1 -SkipCreate
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Install-MonitoringTargetAgent.ps1 -ConfigurePostgresExporter -ConfigureJmxExporter -ApplyJavaServiceChange
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Publish-GrafanaDashboards.ps1
```

Platform service validation:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Install-MonitoringTargetAgent.ps1 -TargetCtid 110 -TargetName nginx -TargetMetricsHost 192.168.1.139
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Install-MonitoringTargetAgent.ps1 -TargetCtid 120 -TargetName infisical -TargetMetricsHost 192.168.1.226
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Install-MonitoringTargetAgent.ps1 -TargetCtid 134 -TargetName esus-pec-minio -TargetMetricsHost 192.168.1.210
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Install-InfisicalMonitoringExporters.ps1
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Provision-MonitoringCore.ps1 -SkipCreate
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Publish-GrafanaDashboards.ps1
```

Expected platform checks:

- CT `110`: `alloy`, `prometheus-node-exporter`, and
  `prometheus-nginx-exporter` active; Prometheus reports
  `up{host="nginx",instance="192.168.1.139:9113"} == 1` and
  `nginx_up{host="nginx"} == 1`.
- CT `120`: `alloy`, `prometheus-node-exporter`,
  `prometheus-postgres-exporter`, and `prometheus-redis-exporter` active;
  Prometheus reports `pg_up{host="infisical"} == 1` and
  `redis_up{host="infisical"} == 1`.
- CT `134`: `alloy` and `prometheus-node-exporter` active; Prometheus reports
  `up{job="esus-pec-minio-native"} == 1` and MinIO native metrics such as
  `minio_cluster_bucket_total{host="esus-pec-minio"}`.
- Blackbox probes report `probe_success == 1` for `nginx`, `infisical`, and
  `esus-pec-minio`.

Expected live checks:

- PostgreSQL exporter: expected `up` on `192.168.1.209:9187`, `pg_up` present,
  and database panels populated from `pg_stat_database` metrics.
- For CT 133 PostgreSQL 9.6.13, `postgres_exporter 0.19.1` must run with
  the PG10+ default collectors `wal`, `replication`, `replication_slot`, and
  `stat_progress_vacuum` disabled. Its compatibility view also adds a
  synthetic `backend_type` column for the default `pg_stat_activity` map. A
  healthy scrape has `pg_exporter_last_scrape_error 0` and no recent
  `source=collector.go` or `postgres_exporter.go:713` errors in
  `journalctl -u prometheus-postgres-exporter`.
- JMX exporter: expected `up` on `192.168.1.209:9404`, JVM memory, garbage
  collection, and thread metrics present.
- Prometheus target access remains restricted to the Prometheus host, with no
  broad firewall rule for TCP `9187` or TCP `9404`.
- Grafana dashboards publish without printing `grafana_token` or
  `ESUS_PEC_POSTGRES_EXPORTER_PASSWORD`.
- Nginx exporter for PEC HTTP/TLS must be checked on CT `110`, not CT `133`.
  CT `133` should expose application metrics on `9100`, `9187`, and `9404`.

Expected static validation output:

```text
Monitoring stack static validation passed.
```

## Secret Handling

Do not commit, paste, or print Grafana passwords, PostgreSQL exporter
passwords, tokens, patient data, request body data, or raw sensitive logs in
Git, chat, terminal logs, screenshots, or documentation.

The Grafana dashboard publisher requires `grafana_token`, but the token value is
only read from `.env`, environment variables, or Infisical. The sync and publish
scripts report presence/absence and target paths only; they do not print token
values.

The PostgreSQL exporter is optional. If PostgreSQL exporter access is needed,
run `scripts/monitoring/Install-MonitoringTargetAgent.ps1` with
`-ConfigurePostgresExporter`. The exporter uses the dedicated database user
`prometheus_exporter`; the provisioner generates the password when needed,
stores it in Infisical `/test/Monitoring` as
`ESUS_PEC_POSTGRES_EXPORTER_PASSWORD`, and writes the secret only to the
root-only `/etc/monitoring/postgres-exporter-password` file on CT `133`,
consumed by `DATA_SOURCE_PASS_FILE`. Keep only the variable name and storage
location in tracked files; never include the value.

## Rollback

The default rollback preserves configuration and data directories. Destructive
removal of CT `190`, Grafana data, Loki data, Prometheus TSDB data, or target
agent configuration requires separate operator confirmation.

### CT 190 Services

Stop and disable monitoring services on the core:

```powershell
rtk ssh <proxmox-ssh-target> "pct exec 190 -- bash -lc 'systemctl stop prometheus grafana-server loki alloy && systemctl disable prometheus grafana-server loki alloy'"
```

Check service state:

```powershell
rtk ssh <proxmox-ssh-target> "pct exec 190 -- bash -lc 'systemctl is-active prometheus grafana-server loki alloy || true'"
```

Restart services after a rollback test if the deployment should remain active:

```powershell
rtk ssh <proxmox-ssh-target> "pct exec 190 -- bash -lc 'systemctl enable prometheus grafana-server loki alloy && systemctl restart prometheus grafana-server loki alloy'"
```

### CT 133 Agents

Stop and disable target agents and exporters:

```powershell
rtk ssh <proxmox-ssh-target> "pct exec 133 -- bash -lc 'systemctl stop alloy prometheus-node-exporter prometheus-nginx-exporter prometheus-postgres-exporter 2>/dev/null || true; systemctl disable alloy prometheus-node-exporter prometheus-nginx-exporter prometheus-postgres-exporter 2>/dev/null || true'"
```

If an older agent install created the managed Nginx stub status endpoint on CT
`133`, roll it back after CT `110` successfully owns PEC TLS by stopping the
exporter if present and removing only the managed
`/etc/nginx/conf.d/monitoring-stub-status.conf` file. Leave unrelated PEC files
untouched. The install script keeps a temporary failure-time rollback while
updating the config, but it does not leave a durable post-success backup for
later rollback.

```powershell
rtk ssh <proxmox-ssh-target> "pct exec 133 -- bash -lc 'systemctl stop prometheus-nginx-exporter 2>/dev/null || true; systemctl disable prometheus-nginx-exporter 2>/dev/null || true; rm -f /etc/nginx/conf.d/monitoring-stub-status.conf'"
rtk ssh <proxmox-ssh-target> "pct exec 133 -- bash -lc 'nginx -t && systemctl reload nginx'"
```

Rollback the application exporters separately. Stop and disable the PostgreSQL
exporter and its firewall unit, remove the JMX service drop-in and wrapper,
reload systemd, and restart e-SUS PEC:

```powershell
rtk ssh <proxmox-ssh-target> "pct exec 133 -- bash -lc 'systemctl disable --now prometheus-postgres-exporter prometheus-postgres-exporter-firewall 2>/dev/null || true'"
rtk ssh <proxmox-ssh-target> "pct exec 133 -- bash -lc 'rm -f /etc/systemd/system/e-SUS-PEC.service.d/monitoring-jmx.conf /opt/monitoring/run-esus-pec-with-jmx.sh; systemctl daemon-reload; systemctl restart e-SUS-PEC.service'"
rtk ssh <proxmox-ssh-target> "pct exec 133 -- bash -lc 'systemctl is-active prometheus-postgres-exporter 2>/dev/null || true; systemctl is-active e-SUS-PEC.service'"
```

The database role is not removed automatically. If the `prometheus_exporter`
role should be removed later, first confirm that no dashboard, Prometheus job,
or external operator still depends on it, then perform a separate reviewed DB
cleanup.

Rollback platform service exporters:

```powershell
rtk ssh <proxmox-ssh-target> "pct exec 110 -- bash -lc 'systemctl disable --now prometheus-nginx-exporter 2>/dev/null || true; rm -f /etc/nginx/conf.d/monitoring-stub-status.conf; nginx -t && systemctl reload nginx'"
rtk ssh <proxmox-ssh-target> "pct exec 120 -- bash -lc 'systemctl disable --now prometheus-postgres-exporter prometheus-redis-exporter infisical-monitoring-exporters-firewall 2>/dev/null || true; rm -f /etc/systemd/system/prometheus-postgres-exporter.service /etc/systemd/system/prometheus-redis-exporter.service /etc/systemd/system/infisical-monitoring-exporters-firewall.service /usr/local/sbin/apply-infisical-monitoring-exporter-firewall; systemctl daemon-reload'"
rtk ssh <proxmox-ssh-target> "pct exec 190 -- bash -lc 'systemctl disable --now prometheus-blackbox-exporter 2>/dev/null || true; rm -f /etc/prometheus/blackbox.yml; systemctl restart prometheus'"
```

This rollback does not remove node exporter or Alloy from CT `110`, `120`, or
`134`; remove those only after confirming no other dashboard or log pipeline
depends on them.

Review the JMX proposal before making or rolling back Java changes. The current
agent install writes review material and does not apply a Java service change by
default:

```powershell
rtk ssh <proxmox-ssh-target> "pct exec 133 -- bash -lc 'test -f /root/monitoring-jmx-proposal.txt && sed -n \"1,160p\" /root/monitoring-jmx-proposal.txt || true'"
```

## Validation Evidence

Static validation status:

- `tests/Validate-MonitoringStack.ps1`: passed on 2026-06-14 with
  `Monitoring stack static validation passed.`
- Git whitespace validation: passed on 2026-06-14 for monitoring scripts,
  templates, tests, and this runbook.

Live CT `190` evidence collected on 2026-06-14:

- CTID: `190`
- Hostname: `monitoring-core`
- IP: `192.168.1.190`
- `prometheus`: `active`, readiness `ready`
- `grafana-server`: `active`, `/api/health` database `ok`, version `13.0.2`
- `loki`: `active`, readiness `ready`
- `alloy`: `active`
- Endpoints:
  - Prometheus: `http://192.168.1.190:9090`
  - Grafana: `http://192.168.1.190:3000`
  - Loki: `http://192.168.1.190:3100`

Live CT `133` target evidence collected on 2026-06-14, before the later
decision to consolidate all Nginx responsibility into CT `110`:

- CTID: `133`
- Hostname: `esus-pec-lxc-5437`
- `alloy`: `active`
- `prometheus-node-exporter`: `active`
- `prometheus-nginx-exporter`: `active`
- Node exporter metrics: `http://127.0.0.1:9100/metrics` returned success
  inside CT `133`
- Nginx exporter metrics: `http://127.0.0.1:9113/metrics` returned success
  inside CT `133`
- Nginx status endpoint: managed local-only `stub_status`
- PostgreSQL exporter: previous rollout skipped; the current exporter rollout
  provisions a dedicated monitoring account through Infisical when
  `-ConfigurePostgresExporter` is applied.
- JMX exporter: `skipped`, because Java service mutation is proposal-only until
  staged JMX artifacts and a reviewed apply plan exist

Prometheus target evidence collected on 2026-06-14, before Nginx consolidation:

- `monitoring-core` at `http://localhost:9090/metrics`: `up`
- `monitoring-core-alloy` at `http://localhost:12345/metrics`: `up`
- `esus-pec-lxc-5437` node exporter at `http://192.168.1.209:9100/metrics`:
  `up`
- `esus-pec-lxc-5437` Nginx exporter at `http://192.168.1.209:9113/metrics`:
  `up` at that time; this target is no longer part of the desired topology
  after CT `110` became the single edge Nginx.
- Optional PostgreSQL and JMX exporters are intentionally not in the default
  scrape set until their guarded installers are applied.

Loki evidence collected on 2026-06-14:

- `GET /loki/api/v1/labels` returned `5` label names, confirming non-empty
  Loki ingestion metadata without recording raw log content.

Grafana dashboard and Infisical env evidence collected on 2026-06-14:

- `scripts/monitoring/Sync-GrafanaInfisicalEnv.ps1`: synced
  `/test/Monitoring/grafana_url` and
  `/test/Monitoring/grafana_token`; output reported both values present
  without printing either value.
- A dedicated `/test/Monitoring/Grafana` Infisical path was evaluated first,
  but the then-current token could not create that secret-folder tree. On
  2026-06-21, the expanded token allowed `/test/Monitoring` to become the
  current operational location.
- `scripts/monitoring/Publish-GrafanaDashboards.ps1`: Grafana database health
  `ok`; folder UID `esus-pec-monitoring`; `4` dashboards updated.
- Dashboard JSON validation: all files under `scripts/monitoring/dashboards`
  parsed successfully with Node JSON parsing.

Grafana dashboard connection repair evidence collected on 2026-06-14:

- Symptom: CT `133` dashboard panels showed `No data`.
- Root cause: dashboard PromQL referenced nonexistent jobs
  `esus-pec-lxc-5437-node` and `esus-pec-lxc-5437-nginx`.
- Observed Prometheus labels: CT `133` target series use
  `host="esus-pec-lxc-5437"`, `job="esus-pec-lxc-5437"`, and distinguish
  node/Nginx exporters by `instance="192.168.1.209:9100"` and
  `instance="192.168.1.209:9113"`.
- Corrected dashboard selectors returned live data for node exporter, Nginx
  exporter, CPU, memory, and Nginx activity before republishing dashboards.
- Loki labels for CT `133` exist with `host="esus-pec-lxc-5437"`, but log
  panels can still be empty when there are no matching logs in the selected
  time range.

Application exporter evidence collected on 2026-06-20:

- `Install-MonitoringTargetAgent.ps1 -ConfigurePostgresExporter
  -ConfigureJmxExporter -ApplyJavaServiceChange`: completed with
  `postgres_exporter=ready` and `jmx=ready`.
- `e-SUS-PEC.service` and `prometheus-postgres-exporter`: `active` after the
  JMX wrapper change.
- PEC HTTP endpoint: `http://127.0.0.1:8080/` returned HTTP `200` inside CT
  `133`.
- PostgreSQL exporter: `http://127.0.0.1:9187/metrics` exposed `pg_up 1`.
- JMX exporter: `http://127.0.0.1:9404/metrics` exposed representative JVM
  metrics including `jvm_memory_bytes_used`, `jvm_gc_collection_seconds_count`,
  `jvm_threads_current`, `jvm_classes_loaded_total`, and
  `process_cpu_seconds_total`.
- `Provision-MonitoringCore.ps1 -SkipCreate`: completed health checks with
  `prometheus`, `grafana-server`, `loki`, and `alloy` active; Prometheus,
  Grafana, and Loki readiness returned `ready`.
- Grafana dashboards published through the API with datasource UIDs
  `prometheus` and `loki`; dashboard count remained `4`, Grafana database
  health was `ok`, and folder UID was `esus-pec-monitoring`.
- Prometheus query
  `up{instance="192.168.1.209:9187"}` returned value `1`.
- Prometheus query
  `up{instance="192.168.1.209:9404"}` returned value `1`.
- Prometheus query `pg_up{host="esus-pec-lxc-5437"}` returned value `1`.
- Prometheus query
  `jvm_memory_bytes_used{host="esus-pec-lxc-5437",area="heap"}` returned a
  non-empty vector.

Platform service evidence collected on 2026-06-21:

- CT `110 nginx`: target installer completed with `alloy=active`,
  `node_exporter=active`, `nginx=stub_status_local`, and
  `nginx_exporter=active`.
- CT `120 infisical`: target installer completed with `alloy=active` and
  `node_exporter=active`; `Install-InfisicalMonitoringExporters.ps1` completed
  with `postgres_exporter=ready`, `redis_exporter=ready`, and
  `firewall=active`.
- CT `134 esus-pec-minio`: target installer completed with `alloy=active` and
  `node_exporter=active`.
- CT `190 monitoring-core`: `Provision-MonitoringCore.ps1 -SkipCreate`
  completed with `prometheus-blackbox-exporter=active` and Blackbox readiness
  `ready`.
- Grafana dashboard publisher updated existing dashboards and created
  `platform-services-ct110-ct120-ct134`; dashboard count is `5`, database
  health is `ok`, and datasource UIDs `prometheus` and `loki` were updated.
- Prometheus query `up{host="nginx",instance="192.168.1.139:9113"}` returned
  value `1`.
- Prometheus query `up{host="infisical",instance="192.168.1.226:9187"}`
  returned value `1`.
- Prometheus query `up{host="infisical",instance="192.168.1.226:9121"}`
  returned value `1`.
- Prometheus query `up{job="esus-pec-minio-native"}` returned value `1`.
- Prometheus query
  `probe_success{host=~"nginx|infisical|esus-pec-minio"}` returned value `1`
  for all three targets.
- Representative native metrics returned non-empty vectors:
  `nginx_up{host="nginx"}`, `pg_up{host="infisical"}`,
  `redis_up{host="infisical"}`, and
  `minio_cluster_bucket_total{host="esus-pec-minio"}`.

Nginx consolidation evidence collected on 2026-06-21:

- CT `110 nginx` already had Alloy, node exporter, and
  `prometheus-nginx-exporter` active on `192.168.1.139:9113`.
- CT `110` received Certbot and the managed PEC vhost
  `/etc/nginx/sites-available/esus-pec-tls.conf`, proxying to
  `http://192.168.1.209:8080`.
- CT `133` still had `nginx` and `prometheus-nginx-exporter` active from the
  previous local TLS path. They were not disabled because trusted CT `110`
  issuance is blocked by public HTTP-01 reachability.
- Desired Prometheus config now scrapes Nginx exporter only from CT `110`; CT
  `133` remains responsible for node, PostgreSQL, and JVM metrics.
