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

## Topology

### Monitoring Core

- CTID: `190` (`CTID 190`)
- Hostname: `monitoring-core`
- Runtime model: native Grafana/Alloy and upstream Prometheus/Loki systemd
  services, not Docker.
- Prometheus: `http://192.168.1.190:9090`
- Grafana: `http://192.168.1.190:3000`
- Loki: `http://192.168.1.190:3100`
- Grafana Alloy: local service on CT `190`; the default Alloy diagnostic
  endpoint is local-only on port `12345` when enabled by the packaged service.

### Initial Target

- CTID: `133`
- Hostname: `esus-pec-lxc-5437`
- Role: initial e-SUS PEC 5.4.37 target for Linux metrics, Nginx metrics where
  available, PostgreSQL exporter when a local secret DSN is provided, and Alloy
  log shipping.

### Future Targets

- Production PEC: future work. Do not assume the CT `133` Nginx pattern applies;
  production uses Tomcat, so JVM/Tomcat collection must be validated separately
  before applying agents.
- SIHA: VM `7001`, future target after the OS and billing systems are ready for
  monitored access.

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

Expected static validation output:

```text
Monitoring stack static validation passed.
```

## Secret Handling

Do not commit, paste, or print Grafana passwords, PostgreSQL DSNs, tokens,
patient data, request body data, or raw sensitive logs in Git, chat, terminal
logs, screenshots, or documentation.

The PostgreSQL exporter is optional. If PostgreSQL exporter access is needed,
run `scripts/monitoring/Install-MonitoringTargetAgent.ps1` with
`-ConfigurePostgresExporter` and provide `ESUS_PEC_POSTGRES_EXPORTER_DSN`
through the ignored local file `config/monitoring-targets.local.env` or another
approved secret channel. The local env file or environment variable only
supplies the DSN; it is not applied unless the install script is run with
`-ConfigurePostgresExporter`. Keep only the variable name and storage location
in tracked files; never include the value.

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

If the agent install created the managed Nginx stub status endpoint, roll it
back by stopping the exporter if present and removing only the managed
`/etc/nginx/conf.d/monitoring-stub-status.conf` file. Leave unrelated Nginx
configuration untouched. The install script keeps a temporary failure-time
rollback while updating the config, but it does not leave a durable post-success
backup for later rollback.

```powershell
rtk ssh <proxmox-ssh-target> "pct exec 133 -- bash -lc 'systemctl stop prometheus-nginx-exporter 2>/dev/null || true; systemctl disable prometheus-nginx-exporter 2>/dev/null || true; rm -f /etc/nginx/conf.d/monitoring-stub-status.conf'"
rtk ssh <proxmox-ssh-target> "pct exec 133 -- bash -lc 'nginx -t && systemctl reload nginx'"
```

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

Live CT `133` target evidence collected on 2026-06-14:

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
- PostgreSQL exporter: `skipped`, because no approved DSN was provided with
  `-ConfigurePostgresExporter`
- JMX exporter: `skipped`, because Java service mutation is proposal-only until
  staged JMX artifacts and a reviewed apply plan exist

Prometheus target evidence collected on 2026-06-14:

- `monitoring-core` at `http://localhost:9090/metrics`: `up`
- `monitoring-core-alloy` at `http://localhost:12345/metrics`: `up`
- `esus-pec-lxc-5437` node exporter at `http://192.168.1.209:9100/metrics`:
  `up`
- `esus-pec-lxc-5437` Nginx exporter at `http://192.168.1.209:9113/metrics`:
  `up`
- Optional PostgreSQL and JMX exporters are intentionally not in the default
  scrape set until their guarded installers are applied.

Loki evidence collected on 2026-06-14:

- `GET /loki/api/v1/labels` returned `5` label names, confirming non-empty
  Loki ingestion metadata without recording raw log content.
