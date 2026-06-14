# e-SUS PEC Centralized Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and validate a native systemd monitoring core in LXC `190` with Prometheus, Grafana, Loki, and Alloy, then onboard LXC `133 esus-pec-lxc-5437` as the first e-SUS PEC target.

**Architecture:** The repository owns PowerShell orchestration scripts and non-secret service templates. Proxmox creates or updates CT `190`; CT-local bash installs systemd services and writes configs. Target onboarding uses `pct exec` against CT `133` to install Alloy/exporters and configure safe local-only scrape/log collection.

**Tech Stack:** Proxmox LXC, Debian, PowerShell, bash, systemd, Prometheus, Grafana, Loki, Grafana Alloy, node_exporter-compatible metrics, nginx `stub_status`, postgres_exporter, JMX exporter planning.

---

## File Map

- Create `tests/Validate-MonitoringStack.ps1`: static validation for scripts, templates, docs, no secrets, no Promtail agent config, CTID `190`, and CT `133` target.
- Create `scripts/monitoring/Provision-MonitoringCore.ps1`: create/update CT `190`, install Prometheus/Grafana/Loki/Alloy, push configs, run live health checks.
- Create `scripts/monitoring/Install-MonitoringTargetAgent.ps1`: configure CT `133` with Alloy, node/system metrics, Nginx status, PostgreSQL exporter scaffolding, and JVM inspection without production Java mutation by default.
- Create `scripts/monitoring/templates/prometheus.yml`: scrape config for monitoring core and CT `133`.
- Create `scripts/monitoring/templates/loki.yml`: single-node filesystem Loki config.
- Create `scripts/monitoring/templates/alloy-core.alloy`: Alloy config for CT `190` logs and local metrics.
- Create `scripts/monitoring/templates/alloy-linux-target.alloy`: Alloy config template for CT `133` logs and target metrics.
- Create `scripts/monitoring/templates/grafana-datasources.yml`: Grafana provisioning for Prometheus and Loki datasources.
- Create `docs/monitoring/2026-06-14-centralized-monitoring.md`: runbook, validation evidence, rollback, target roadmap.
- Modify `docs/superpowers/specs/2026-06-14-esus-pec-centralized-monitoring-design.md`: only if execution discovers a required correction.

## Task 1: Static Validation Test

**Files:**
- Create: `tests/Validate-MonitoringStack.ps1`

- [ ] **Step 1: Write the failing test**

Create `tests/Validate-MonitoringStack.ps1` with checks for required artifacts and security invariants:

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$required = @(
  "scripts/monitoring/Provision-MonitoringCore.ps1",
  "scripts/monitoring/Install-MonitoringTargetAgent.ps1",
  "scripts/monitoring/templates/prometheus.yml",
  "scripts/monitoring/templates/loki.yml",
  "scripts/monitoring/templates/alloy-core.alloy",
  "scripts/monitoring/templates/alloy-linux-target.alloy",
  "scripts/monitoring/templates/grafana-datasources.yml",
  "docs/monitoring/2026-06-14-centralized-monitoring.md",
  "docs/superpowers/specs/2026-06-14-esus-pec-centralized-monitoring-design.md"
)

foreach ($relative in $required) {
  $path = Join-Path $root $relative
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing monitoring artifact: $relative"
  }
}

$allText = foreach ($relative in $required) {
  Get-Content -LiteralPath (Join-Path $root $relative) -Raw
}
$joined = $allText -join "`n"

foreach ($needle in @("CTID 190", "monitoring-core", "Prometheus", "Grafana", "Loki", "Alloy", "133", "esus-pec-lxc-5437")) {
  if ($joined -notmatch [regex]::Escape($needle)) {
    throw "Monitoring artifacts must mention required term: $needle"
  }
}

if ($joined -match "(?i)promtail(?!.*documentation)") {
  throw "Do not introduce Promtail agent configuration; use Grafana Alloy."
}

$secretPatterns = @(
  "B[E]GIN [A-Z ]*PRIVATE KEY",
  "(?i)grafana_admin_password\s*=\s*['""][^'""]+",
  "(?i)password\s*=\s*['""][^'""]+",
  "(?i)token\s*=\s*['""][^'""]+",
  "(?i)secretValue\s*=\s*['""][^'""]+"
)
foreach ($pattern in $secretPatterns) {
  if ($joined -match $pattern) {
    throw "Potential secret value found by pattern: $pattern"
  }
}

$prometheus = Get-Content -LiteralPath (Join-Path $root "scripts/monitoring/templates/prometheus.yml") -Raw
foreach ($needle in @("monitoring-core", "esus-pec-lxc-5437", "localhost:9090", "133")) {
  if ($prometheus -notmatch [regex]::Escape($needle)) {
    throw "Prometheus template must include $needle"
  }
}

Write-Host "Monitoring stack static validation passed."
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-MonitoringStack.ps1
```

Expected: fails with `Missing monitoring artifact: scripts/monitoring/Provision-MonitoringCore.ps1`.

- [ ] **Step 3: Commit the failing test**

Run:

```powershell
rtk git add tests/Validate-MonitoringStack.ps1
rtk git commit -m "Add monitoring stack validation test"
```

## Task 2: Non-Secret Templates

**Files:**
- Create: `scripts/monitoring/templates/prometheus.yml`
- Create: `scripts/monitoring/templates/loki.yml`
- Create: `scripts/monitoring/templates/alloy-core.alloy`
- Create: `scripts/monitoring/templates/alloy-linux-target.alloy`
- Create: `scripts/monitoring/templates/grafana-datasources.yml`

- [ ] **Step 1: Add Prometheus template**

Create `scripts/monitoring/templates/prometheus.yml`:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: monitoring-core
    static_configs:
      - targets:
          - localhost:9090
        labels:
          host: monitoring-core
          ctid: "190"

  - job_name: monitoring-core-alloy
    static_configs:
      - targets:
          - localhost:12345
        labels:
          host: monitoring-core
          ctid: "190"

  - job_name: esus-pec-lxc-5437
    static_configs:
      - targets:
          - ESUS_PEC_LXC_TARGET_METRICS_HOST:9100
          - ESUS_PEC_LXC_TARGET_METRICS_HOST:9113
          - ESUS_PEC_LXC_TARGET_METRICS_HOST:9187
          - ESUS_PEC_LXC_TARGET_METRICS_HOST:9404
        labels:
          host: esus-pec-lxc-5437
          ctid: "133"
          app: esus-pec
```

- [ ] **Step 2: Add Loki template**

Create `scripts/monitoring/templates/loki.yml` with single-node filesystem storage:

```yaml
auth_enabled: false

server:
  http_listen_address: 0.0.0.0
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  allow_structured_metadata: false
  retention_period: 168h
```

- [ ] **Step 3: Add Alloy core template**

Create `scripts/monitoring/templates/alloy-core.alloy`:

```hcl
prometheus.exporter.unix "core" {
  include_exporter_metrics = true
}

prometheus.scrape "core" {
  targets    = prometheus.exporter.unix.core.targets
  forward_to = [prometheus.remote_write.local.receiver]
}

prometheus.remote_write "local" {
  endpoint {
    url = "http://127.0.0.1:9090/api/v1/write"
  }
}

loki.source.journal "core" {
  labels = {
    job = "monitoring-core-journal",
    host = "monitoring-core",
    ctid = "190",
  }
  forward_to = [loki.write.local.receiver]
}

loki.write "local" {
  endpoint {
    url = "http://127.0.0.1:3100/loki/api/v1/push"
  }
}
```

- [ ] **Step 4: Add Alloy Linux target template**

Create `scripts/monitoring/templates/alloy-linux-target.alloy`:

```hcl
loki.source.journal "system" {
  labels = {
    job = "linux-journal",
    host = "ESUS_PEC_TARGET_NAME",
    ctid = "133",
    app = "esus-pec",
  }
  forward_to = [loki.write.monitoring.receiver]
}

loki.source.file "nginx" {
  targets = [
    {__path__ = "/var/log/nginx/*.log", job = "nginx", host = "ESUS_PEC_TARGET_NAME", ctid = "133"},
  ]
  forward_to = [loki.write.monitoring.receiver]
}

loki.source.file "esus" {
  targets = [
    {__path__ = "/opt/e-SUS/**/*.log", job = "esus-pec", host = "ESUS_PEC_TARGET_NAME", ctid = "133"},
  ]
  forward_to = [loki.write.monitoring.receiver]
}

loki.write "monitoring" {
  endpoint {
    url = "http://MONITORING_CORE_HOST:3100/loki/api/v1/push"
  }
}
```

- [ ] **Step 5: Add Grafana datasource template**

Create `scripts/monitoring/templates/grafana-datasources.yml`:

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://127.0.0.1:9090
    isDefault: true
  - name: Loki
    type: loki
    access: proxy
    url: http://127.0.0.1:3100
```

- [ ] **Step 6: Run validation and verify remaining expected failure**

Run:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-MonitoringStack.ps1
```

Expected: fails on missing scripts or docs, not templates.

- [ ] **Step 7: Commit templates**

Run:

```powershell
rtk git add scripts/monitoring/templates
rtk git commit -m "Add monitoring stack templates"
```

## Task 3: Monitoring Core Provisioning Script

**Files:**
- Create: `scripts/monitoring/Provision-MonitoringCore.ps1`

- [ ] **Step 1: Add script with safe parameters and helper functions**

Create a PowerShell script modeled on existing `scripts/esus-pec/Provision-EsusPecMinioObjectStorage.ps1`:

```powershell
param(
  [string]$ConfigFile = "config/Proxmox.pkrvars.hcl",
  [int]$Ctid = 190,
  [string]$Hostname = "monitoring-core",
  [string]$IpCidr = "192.168.1.190/24",
  [string]$Gateway = "192.168.1.1",
  [string]$Bridge = "vmbr0",
  [string]$Storage = "rpool",
  [string]$Template = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst",
  [string]$RootfsSize = "40",
  [int]$MemoryMb = 4096,
  [int]$Cores = 2,
  [int]$SwapMb = 512,
  [int]$InitialTargetCtid = 133,
  [string]$InitialTargetName = "esus-pec-lxc-5437",
  [string]$InitialTargetMetricsHost = "192.168.1.209",
  [switch]$SkipCreate,
  [switch]$SkipHealthChecks
)
```

The implementation must include `Get-HclValue`, `Invoke-ProxmoxSsh`, `Invoke-ProxmoxBash`, `Invoke-ContainerBash`, and `Push-ContainerFile` helpers. Do not print `proxmox_api_token_secret`, SSH key contents, Grafana admin password, or exporter DSNs.

- [ ] **Step 2: Implement CT create/update**

The script must:

- Read `proxmox_ssh_host`, `proxmox_ssh_port`, `proxmox_ssh_user`, and `proxmox_ssh_private_key_file`.
- Check whether `pct status 190` succeeds.
- Create CT `190` only when missing and `-SkipCreate` is not set.
- Start CT `190`.
- Install `curl`, `wget`, `gpg`, `ca-certificates`, `apt-transport-https`, `tar`, and `systemd`.

Use this remote create shape:

```bash
pct create 190 local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
  --hostname monitoring-core \
  --rootfs rpool:40 \
  --cores 2 --memory 4096 --swap 512 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.1.190/24,gw=192.168.1.1,firewall=1 \
  --unprivileged 1 --features nesting=1,keyctl=1 --ostype debian --onboot 1
```

- [ ] **Step 3: Implement native install**

Inside CT `190`, install Grafana and Alloy using the Grafana APT repository. Install Prometheus and Loki as native systemd services using official release artifacts when no Debian package is available in the base repositories.

The CT-local script must:

- Create service users and directories.
- Write `/etc/prometheus/prometheus.yml`.
- Write `/etc/loki/loki.yml`.
- Write `/etc/alloy/config.alloy`.
- Write `/etc/grafana/provisioning/datasources/datasources.yml`.
- Enable and start `prometheus`, `grafana-server`, `loki`, and `alloy`.

- [ ] **Step 4: Implement health checks**

Unless `-SkipHealthChecks` is set, check from CT `190`:

```bash
systemctl is-active prometheus grafana-server loki alloy
curl -fsS http://127.0.0.1:9090/-/ready
curl -fsS http://127.0.0.1:3000/api/health
curl -fsS http://127.0.0.1:3100/ready
```

The script output should summarize `service=active` and HTTP status only.

- [ ] **Step 5: Run validation**

Run:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-MonitoringStack.ps1
```

Expected: fails only on missing target agent script or docs.

- [ ] **Step 6: Commit core script**

Run:

```powershell
rtk git add scripts/monitoring/Provision-MonitoringCore.ps1
rtk git commit -m "Add monitoring core provisioner"
```

## Task 4: CT 133 Target Agent Script

**Files:**
- Create: `scripts/monitoring/Install-MonitoringTargetAgent.ps1`

- [ ] **Step 1: Add target parameters**

Create a script with:

```powershell
param(
  [string]$ConfigFile = "config/Proxmox.pkrvars.hcl",
  [int]$TargetCtid = 133,
  [string]$TargetName = "esus-pec-lxc-5437",
  [string]$MonitoringCoreHost = "192.168.1.190",
  [switch]$ConfigurePostgresExporter,
  [switch]$ConfigureJmxExporter,
  [switch]$ApplyJavaServiceChange
)
```

- [ ] **Step 2: Implement CT `133` Linux agent install**

The script must:

- Install Grafana Alloy through the Grafana APT repository.
- Install `prometheus-node-exporter`.
- Configure Alloy from `scripts/monitoring/templates/alloy-linux-target.alloy`.
- Enable Alloy and node exporter.
- Detect Nginx and configure local-only `stub_status` if Nginx is present.
- Install or configure an Nginx metrics endpoint on `:9113` when available.

- [ ] **Step 3: Implement database and JVM guarded paths**

For `-ConfigurePostgresExporter`, require an ignored local env file or explicit environment variables for the DSN and write only an on-host `0600` env file. If no DSN is available, exit with a clear non-secret message.

For `-ConfigureJmxExporter`, inspect `e-SUS-PEC.service` and write a proposed change file under `/root/monitoring-jmx-proposal.txt`. Only change the Java service when `-ApplyJavaServiceChange` is also present.

- [ ] **Step 4: Implement target health checks**

From the Proxmox host, verify:

```bash
pct exec 133 -- systemctl is-active alloy prometheus-node-exporter
pct exec 133 -- curl -fsS http://127.0.0.1:9100/metrics
pct exec 133 -- curl -fsS http://127.0.0.1:9113/metrics
```

Treat `:9113` as skipped when Nginx is absent. Do not print database DSNs or service environment files.

- [ ] **Step 5: Run validation**

Run:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-MonitoringStack.ps1
```

Expected: fails only on missing docs.

- [ ] **Step 6: Commit target script**

Run:

```powershell
rtk git add scripts/monitoring/Install-MonitoringTargetAgent.ps1
rtk git commit -m "Add PEC monitoring target agent installer"
```

## Task 5: Documentation and Static Green

**Files:**
- Create: `docs/monitoring/2026-06-14-centralized-monitoring.md`

- [ ] **Step 1: Add runbook**

Create a runbook with:

- CT `190` topology and ports.
- CT `133` as initial e-SUS PEC target.
- Explicit note that production PEC is future work and uses Tomcat instead of CT `133` Nginx.
- Install commands:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Provision-MonitoringCore.ps1
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Install-MonitoringTargetAgent.ps1
```

- Validation commands:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-MonitoringStack.ps1
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Provision-MonitoringCore.ps1 -SkipCreate
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Install-MonitoringTargetAgent.ps1
```

- Secret-handling rules: no Grafana passwords, PostgreSQL DSNs, tokens, or patient/request body data in Git or chat logs.
- Rollback commands for CT `190` services and CT `133` agents.

- [ ] **Step 2: Run static validation and verify pass**

Run:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-MonitoringStack.ps1
```

Expected: `Monitoring stack static validation passed.`

- [ ] **Step 3: Commit docs**

Run:

```powershell
rtk git add docs/monitoring/2026-06-14-centralized-monitoring.md tests/Validate-MonitoringStack.ps1
rtk git commit -m "Document centralized monitoring runbook"
```

## Task 6: Live Build and Validation

**Files:**
- May modify: `docs/monitoring/2026-06-14-centralized-monitoring.md`

- [ ] **Step 1: Provision CT `190`**

Run:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Provision-MonitoringCore.ps1
```

Expected: CT `190` running; Prometheus, Grafana, Loki, and Alloy active.

- [ ] **Step 2: Install CT `133` agents**

Run:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Install-MonitoringTargetAgent.ps1
```

Expected: Alloy and node exporter active on CT `133`; Nginx exporter active or documented skipped state.

- [ ] **Step 3: Validate endpoints**

Run Proxmox checks without printing secrets:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Provision-MonitoringCore.ps1 -SkipCreate
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-MonitoringStack.ps1
```

Expected: static validation passes and live checks summarize service and HTTP health.

- [ ] **Step 4: Update runbook with evidence**

Record only:

- CT IDs, hostnames, non-secret IPs.
- Service active states.
- HTTP status codes.
- Exporter endpoint names.
- Skipped items and why.

Do not record Grafana admin credentials, PostgreSQL DSNs, tokens, or raw log content.

- [ ] **Step 5: Commit live validation evidence**

Run:

```powershell
rtk git add docs/monitoring/2026-06-14-centralized-monitoring.md
rtk git commit -m "Record monitoring stack validation evidence"
```

## Task 7: Obsidian Capture

**Files:**
- No repository file changes expected.

- [ ] **Step 1: Capture durable finding**

Write an Obsidian note under `Knowledge/packer-proxmox-templates/Engineering findings/2026-06-14 - centralized-monitoring-systemd-lxc.md` with:

- Context: monitoring stack for e-SUS PEC.
- Decision: CT `190`, native systemd, Alloy over Promtail.
- Evidence: commit hashes, validation commands, service checks.
- Open questions: production PEC Tomcat instrumentation and SIHA VM `7001` target OS.

- [ ] **Step 2: Verify no secrets were captured**

Inspect the note content before sending it. It must not include Grafana admin passwords, PostgreSQL DSNs, tokens, or raw log content.

## Self-Review

- Spec coverage: CT `190`, native systemd, Prometheus/Grafana/Loki/Alloy, CT `133` target, future production PEC Tomcat distinction, SIHA future scope, validation, rollback, and secret handling are each mapped to tasks.
- Placeholder scan: no deferred-work marker remains; production PEC and SIHA are explicitly future scope, not placeholders for this implementation.
- Type consistency: CTID parameter names are `Ctid` for core and `TargetCtid` for target; host names are `Hostname`, `InitialTargetName`, and `TargetName`; commands use `rtk` as required by the repo.
