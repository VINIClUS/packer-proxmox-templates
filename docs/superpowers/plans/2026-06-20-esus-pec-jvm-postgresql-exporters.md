# e-SUS PEC JVM and PostgreSQL Exporters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install, secure, scrape, visualize, and validate PostgreSQL 9.6 and JVM exporters for e-SUS PEC on CT `133`.

**Architecture:** Add a focused `Configure-EsusPecApplicationExporters.ps1` orchestrator and keep `Install-MonitoringTargetAgent.ps1` as the public entry point. The PostgreSQL exporter uses a dedicated non-superuser whose password is persisted in Infisical; the JMX exporter is injected through a reversible systemd drop-in that points `ExecStart` to a managed wrapper. Prometheus and Grafana continue using the existing `host`, `ctid`, `app`, and `instance` labels.

**Tech Stack:** PowerShell, Proxmox `pct`, systemd, PostgreSQL 9.6, postgres_exporter 0.19.1, JMX Exporter 1.6.0, Prometheus, Grafana, Infisical API.

---

## File Structure

- Create `scripts/monitoring/Configure-EsusPecApplicationExporters.ps1`
  - Owns Infisical password lifecycle, artifact downloads, PostgreSQL bootstrap,
    JMX wrapper/drop-in deployment, health checks, and rollback.
- Create `scripts/monitoring/templates/postgres-exporter-9.6.sql`
  - Idempotent PostgreSQL 9.6 non-superuser compatibility objects.
- Create `scripts/monitoring/templates/jmx-exporter.yml`
  - JMX Exporter configuration for JVM and application MBeans.
- Modify `scripts/monitoring/Install-MonitoringTargetAgent.ps1`
  - Delegates existing PostgreSQL/JMX switches to the focused orchestrator.
- Modify `scripts/monitoring/templates/prometheus.yml`
  - Adds ports `9187` and `9404` to the CT `133` scrape set.
- Modify `scripts/monitoring/Provision-MonitoringCore.ps1`
  - Validates Prometheus configuration with `promtool` before restart.
- Modify `scripts/monitoring/dashboards/esus-pec-ct133.json`
  - Adds PostgreSQL and JVM operational panels.
- Modify `tests/Validate-MonitoringStack.ps1`
  - Enforces versions, checksums, security properties, scrape targets, and
    dashboard coverage.
- Modify `config/esus-pec.infisical.env.example`
  - Registers the PostgreSQL exporter secret name without a value.
- Modify `docs/monitoring/2026-06-14-centralized-monitoring.md`
  - Records installation, rollback, and validation evidence.

### Pinned Artifacts

```text
postgres_exporter version: 0.19.1
postgres_exporter URL: https://github.com/prometheus-community/postgres_exporter/releases/download/v0.19.1/postgres_exporter-0.19.1.linux-amd64.tar.gz
postgres_exporter SHA-256: 229096c7988df6ca41fe5b4bf66865089971535e7f0d819c12c920ec64dd2bd0

JMX Exporter version: 1.6.0
JMX Exporter URL: https://github.com/prometheus/jmx_exporter/releases/download/v1.6.0/jmx_prometheus_javaagent-1.6.0.jar
JMX Exporter SHA-256: a95983fd96e865d2bcdf911cc500e7c82808c27ab9fd226bf96732b6c3d8c46e
```

### Worktree Safety

The worktree already contains approved, uncommitted monitoring changes. Before
each task:

```powershell
rtk git status --short
rtk git diff -- scripts/monitoring tests/Validate-MonitoringStack.ps1 config/esus-pec.infisical.env.example docs/monitoring/2026-06-14-centralized-monitoring.md
```

Never reset, restore, or overwrite those changes. Apply new edits on top of the
current file content. Before each commit, inspect `rtk git diff --cached --stat`
and verify that `.Codex/napkin.md`, `.gitignore`, `AGENTS.md`, and `.env.example`
are not staged.

### Task 1: Add the Failing Static Contract

**Files:**
- Modify: `tests/Validate-MonitoringStack.ps1`
- Test: `tests/Validate-MonitoringStack.ps1`

- [ ] **Step 1: Add required artifacts**

Add these paths to `$requiredArtifacts`:

```powershell
"scripts/monitoring/Configure-EsusPecApplicationExporters.ps1",
"scripts/monitoring/templates/postgres-exporter-9.6.sql",
"scripts/monitoring/templates/jmx-exporter.yml",
```

- [ ] **Step 2: Add exporter security and version assertions**

Add:

```powershell
$applicationExporterProvisioner =
  $artifactByPath["scripts/monitoring/Configure-EsusPecApplicationExporters.ps1"].Content

foreach ($term in @(
  "0.19.1",
  "229096c7988df6ca41fe5b4bf66865089971535e7f0d819c12c920ec64dd2bd0",
  "1.6.0",
  "a95983fd96e865d2bcdf911cc500e7c82808c27ab9fd226bf96732b6c3d8c46e",
  "ESUS_PEC_POSTGRES_EXPORTER_PASSWORD",
  "/test/InstallationConfig",
  "prometheus_exporter",
  "127.0.0.1:5433",
  "DATA_SOURCE_PASS_FILE",
  "monitoring-jmx.conf",
  "/opt/monitoring/run-esus-pec-with-jmx.sh",
  "ExecStart=",
  "wait_http_ready",
  "rollback_jmx"
)) {
  if ($applicationExporterProvisioner -notmatch [regex]::Escape($term)) {
    throw "Missing application exporter provisioner term: $term"
  }
}

foreach ($forbiddenTerm in @(
  "SUPERUSER",
  "ALTER SYSTEM",
  "listen_addresses = '*'"
)) {
  if ($applicationExporterProvisioner -match [regex]::Escape($forbiddenTerm)) {
    throw "Application exporter provisioner contains forbidden term: $forbiddenTerm"
  }
}
```

- [ ] **Step 3: Add PostgreSQL 9.6 SQL assertions**

```powershell
$postgresSql =
  $artifactByPath["scripts/monitoring/templates/postgres-exporter-9.6.sql"].Content

foreach ($term in @(
  "CREATE SCHEMA IF NOT EXISTS postgres_exporter",
  "SECURITY DEFINER",
  "get_pg_stat_activity",
  "get_pg_stat_replication",
  "GRANT SELECT ON postgres_exporter.pg_stat_activity",
  "GRANT SELECT ON postgres_exporter.pg_stat_replication"
)) {
  if ($postgresSql -notmatch [regex]::Escape($term)) {
    throw "Missing PostgreSQL 9.6 exporter SQL term: $term"
  }
}

if ($postgresSql -match "CREATE EXTENSION.*pg_stat_statements") {
  throw "PostgreSQL exporter bootstrap must not enable pg_stat_statements implicitly."
}
```

- [ ] **Step 4: Add Prometheus and dashboard assertions**

Place the Prometheus assertions after the existing assignment:

```powershell
$prometheusTemplate = Get-Content -LiteralPath (
  Get-ArtifactPath "scripts/monitoring/templates/prometheus.yml"
) -Raw
```

Place the dashboard assertions after the existing `$ct133Dashboard` assignment.
Then add:

```powershell
foreach ($term in @(
  "ESUS_PEC_LXC_TARGET_METRICS_HOST:9187",
  "ESUS_PEC_LXC_TARGET_METRICS_HOST:9404"
)) {
  if ($prometheusTemplate -notmatch [regex]::Escape($term)) {
    throw "Missing application exporter Prometheus target: $term"
  }
}

foreach ($term in @(
  'instance=\"192.168.1.209:9187\"',
  'instance=\"192.168.1.209:9404\"',
  "pg_up",
  "pg_stat_database",
  "jvm_memory",
  "jvm_gc",
  "jvm_threads"
)) {
  if ($ct133Dashboard -notmatch [regex]::Escape($term)) {
    throw "Missing CT 133 application exporter dashboard term: $term"
  }
}
```

- [ ] **Step 5: Run the test and verify RED**

Run:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-MonitoringStack.ps1
```

Expected: failure beginning with:

```text
Missing monitoring artifact: scripts/monitoring/Configure-EsusPecApplicationExporters.ps1
```

- [ ] **Step 6: Commit the failing test**

```powershell
rtk git add tests/Validate-MonitoringStack.ps1
rtk git commit -m "Test PEC application exporter contract"
```

### Task 2: Add PostgreSQL and JMX Templates

**Files:**
- Create: `scripts/monitoring/templates/postgres-exporter-9.6.sql`
- Create: `scripts/monitoring/templates/jmx-exporter.yml`
- Test: `tests/Validate-MonitoringStack.ps1`

- [ ] **Step 1: Create PostgreSQL 9.6 compatibility SQL**

Use placeholders replaced by the orchestrator before execution:

```sql
\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION __tmp_create_monitoring_user() RETURNS void AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_user WHERE usename = 'prometheus_exporter'
  ) THEN
    CREATE USER prometheus_exporter;
  END IF;
END;
$$ LANGUAGE plpgsql;

SELECT __tmp_create_monitoring_user();
DROP FUNCTION __tmp_create_monitoring_user();

ALTER USER prometheus_exporter WITH
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION
  PASSWORD '__POSTGRES_EXPORTER_PASSWORD__';
ALTER USER prometheus_exporter
  SET SEARCH_PATH TO postgres_exporter,pg_catalog;
GRANT CONNECT ON DATABASE postgres TO prometheus_exporter;

CREATE SCHEMA IF NOT EXISTS postgres_exporter;
REVOKE ALL ON SCHEMA postgres_exporter FROM PUBLIC;
GRANT USAGE ON SCHEMA postgres_exporter TO prometheus_exporter;

CREATE OR REPLACE FUNCTION get_pg_stat_activity()
RETURNS SETOF pg_catalog.pg_stat_activity AS $$
  SELECT * FROM pg_catalog.pg_stat_activity;
$$ LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp;

CREATE OR REPLACE VIEW postgres_exporter.pg_stat_activity AS
  SELECT * FROM get_pg_stat_activity();
REVOKE ALL ON postgres_exporter.pg_stat_activity FROM PUBLIC;
GRANT SELECT ON postgres_exporter.pg_stat_activity TO prometheus_exporter;

CREATE OR REPLACE FUNCTION get_pg_stat_replication()
RETURNS SETOF pg_catalog.pg_stat_replication AS $$
  SELECT * FROM pg_catalog.pg_stat_replication;
$$ LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp;

CREATE OR REPLACE VIEW postgres_exporter.pg_stat_replication AS
  SELECT * FROM get_pg_stat_replication();
REVOKE ALL ON postgres_exporter.pg_stat_replication FROM PUBLIC;
GRANT SELECT ON postgres_exporter.pg_stat_replication TO prometheus_exporter;
```

- [ ] **Step 2: Create JMX configuration**

```yaml
lowercaseOutputName: true
lowercaseOutputLabelNames: true
excludeObjectNames:
  - "java.lang:type=ClassLoading"
rules:
  - pattern: ".*"
```

Do not disable the JMX Exporter built-in JVM metrics. The exclusion avoids a
duplicate generic ClassLoading MBean while retaining the exporter-native
`jvm_classes_*` metrics.

- [ ] **Step 3: Run the test**

Run:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-MonitoringStack.ps1
```

Expected: still FAIL, now for the missing orchestrator.

- [ ] **Step 4: Commit templates**

```powershell
rtk git add scripts/monitoring/templates/postgres-exporter-9.6.sql scripts/monitoring/templates/jmx-exporter.yml
rtk git commit -m "Add PEC PostgreSQL and JMX exporter templates"
```

### Task 3: Implement Secret-Safe PostgreSQL Exporter Provisioning

**Files:**
- Create: `scripts/monitoring/Configure-EsusPecApplicationExporters.ps1`
- Test: `tests/Validate-MonitoringStack.ps1`

- [ ] **Step 1: Add parameters and pinned constants**

```powershell
param(
  [string]$ConfigFile = "config/Proxmox.pkrvars.hcl",
  [int]$TargetCtid = 133,
  [string]$TargetName = "esus-pec-lxc-5437",
  [string]$TargetMetricsHost = "192.168.1.209",
  [string]$MonitoringCoreHost = "192.168.1.190",
  [string]$InfisicalUrl = "http://192.168.1.226:8080",
  [string]$InfisicalWorkspaceId = "2c83cfe9-e794-4961-977d-23000ae14461",
  [string]$InfisicalProjectSlug = "esus-pec-z-px-c",
  [string]$InfisicalEnvironment = "dev",
  [string]$RuntimeSecretPath = "/test",
  [string]$InstallationSecretPath = "/test/InstallationConfig",
  [switch]$ConfigurePostgresExporter,
  [switch]$ConfigureJmxExporter,
  [switch]$ApplyJavaServiceChange
)

$postgresExporterVersion = "0.19.1"
$postgresExporterSha256 =
  "229096c7988df6ca41fe5b4bf66865089971535e7f0d819c12c920ec64dd2bd0"
$postgresExporterUrl =
  "https://github.com/prometheus-community/postgres_exporter/releases/download/v0.19.1/postgres_exporter-0.19.1.linux-amd64.tar.gz"

$jmxExporterVersion = "1.6.0"
$jmxExporterSha256 =
  "a95983fd96e865d2bcdf911cc500e7c82808c27ab9fd226bf96732b6c3d8c46e"
$jmxExporterUrl =
  "https://github.com/prometheus/jmx_exporter/releases/download/v1.6.0/jmx_prometheus_javaagent-1.6.0.jar"
```

- [ ] **Step 2: Add reusable remote and Infisical helpers**

Copy these functions byte-for-byte from
`scripts/monitoring/Install-MonitoringTargetAgent.ps1`:

```powershell
Get-HclValue
ConvertTo-ShellSingleQuoted
Invoke-ProxmoxSsh
Invoke-ProxmoxBash
Invoke-ContainerBash
Push-ContainerFile
Protect-LocalTemporarySecretFile
Push-ContainerSecretFile
Get-TemplateContent
```

Copy these functions byte-for-byte from
`scripts/monitoring/Sync-GrafanaInfisicalEnv.ps1`, changing only parameter
defaults to the values declared by the new orchestrator:

```powershell
Get-InfisicalToken
Get-InfisicalSecrets
Set-InfisicalSecret
```

`Set-InfisicalSecret` must set:

```powershell
secretComment = "Managed by scripts/monitoring/Configure-EsusPecApplicationExporters.ps1"
```

- [ ] **Step 3: Generate or retrieve the exporter password**

Implement:

```powershell
function New-ExporterPassword {
  $bytes = New-Object byte[] 32
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  return [Convert]::ToBase64String($bytes).
    TrimEnd("=").
    Replace("+", "-").
    Replace("/", "_")
}

function Get-OrCreatePostgresExporterPassword {
  param([hashtable]$Headers)

  $name = "ESUS_PEC_POSTGRES_EXPORTER_PASSWORD"
  $existing = Get-InfisicalSecrets `
    -SecretPath $InstallationSecretPath `
    -Headers $Headers

  if ($existing.ContainsKey($name) -and
      -not [string]::IsNullOrWhiteSpace([string]$existing[$name])) {
    return [string]$existing[$name]
  }

  $password = New-ExporterPassword
  $null = Set-InfisicalSecret `
    -SecretPath $InstallationSecretPath `
    -Name $name `
    -Value $password `
    -Headers $Headers `
    -Exists $false
  return $password
}
```

Never include `$password` in output objects or exception messages.

- [ ] **Step 4: Retrieve database bootstrap credentials**

Read existing values from `$RuntimeSecretPath`:

```powershell
$runtimeSecrets = Get-InfisicalSecrets `
  -SecretPath $RuntimeSecretPath `
  -Headers $headers

foreach ($requiredName in @(
  "ESUS_PEC_DB_USER",
  "ESUS_PEC_DB_PASSWORD"
)) {
  if (-not $runtimeSecrets.ContainsKey($requiredName) -or
      [string]::IsNullOrWhiteSpace([string]$runtimeSecrets[$requiredName])) {
    throw "Infisical runtime secret is missing: $requiredName"
  }
}
```

Use the existing full-access database account only for bootstrap SQL. The
exporter runtime account remains `prometheus_exporter`.

- [ ] **Step 5: Push SQL and secret files**

Replace `__POSTGRES_EXPORTER_PASSWORD__` with a PostgreSQL-safe literal:

```powershell
$sqlPassword = $exporterPassword.Replace("'", "''")
$postgresSql = (Get-TemplateContent -Name "postgres-exporter-9.6.sql").
  Replace("__POSTGRES_EXPORTER_PASSWORD__", $sqlPassword)

Push-ContainerSecretFile `
  -Path "/etc/monitoring/postgres-exporter-bootstrap.sql" `
  -Content $postgresSql `
  -Mode "0600"

Push-ContainerSecretFile `
  -Path "/etc/monitoring/postgres-exporter-password" `
  -Content ($exporterPassword + "`n") `
  -Mode "0600"

$dataSourceUri = "127.0.0.1:5433/postgres?sslmode=disable"
$environmentContent = @"
DATA_SOURCE_URI=$dataSourceUri
DATA_SOURCE_USER=prometheus_exporter
DATA_SOURCE_PASS_FILE=/etc/monitoring/postgres-exporter-password
PG_EXPORTER_COLLECTION_TIMEOUT=15s
"@

Push-ContainerFile `
  -Path "/etc/monitoring/postgres-exporter.env" `
  -Content $environmentContent `
  -Mode "0640"
```

- [ ] **Step 6: Bootstrap PostgreSQL and install the binary**

Execute an encoded container script that:

```bash
set -euo pipefail
pg_root=/opt/e-SUS/database/postgresql-9.6.13-1-linux-x64
admin_user='__ADMIN_USER__'
admin_password_file=/etc/monitoring/postgres-bootstrap-password

export PGPASSWORD="$(cat "$admin_password_file")"
"$pg_root/bin/psql" \
  -h 127.0.0.1 \
  -p 5433 \
  -U "$admin_user" \
  -d postgres \
  -v ON_ERROR_STOP=1 \
  -Atc "SELECT rolsuper FROM pg_catalog.pg_roles WHERE rolname = current_user" |
  grep -qx t

"$pg_root/bin/psql" \
  -h 127.0.0.1 \
  -p 5433 \
  -U "$admin_user" \
  -d postgres \
  -f /etc/monitoring/postgres-exporter-bootstrap.sql
unset PGPASSWORD
rm -f "$admin_password_file" /etc/monitoring/postgres-exporter-bootstrap.sql

download=/tmp/postgres_exporter.tar.gz
curl -4 -fL --retry 5 --retry-all-errors --connect-timeout 15 \
  '__POSTGRES_EXPORTER_URL__' -o "$download"
echo '__POSTGRES_EXPORTER_SHA256__  '"$download" | sha256sum -c -
tar -xzf "$download" -C /tmp
install -m 0755 \
  /tmp/postgres_exporter-0.19.1.linux-amd64/postgres_exporter \
  /usr/local/bin/postgres_exporter
rm -rf "$download" /tmp/postgres_exporter-0.19.1.linux-amd64
```

Push the bootstrap password separately with `Push-ContainerSecretFile` to
`/etc/monitoring/postgres-bootstrap-password` and remove it in a `finally`
cleanup even when SQL execution fails.

- [ ] **Step 7: Install the systemd service**

```ini
[Unit]
Description=Prometheus PostgreSQL Exporter for e-SUS PEC
Wants=network-online.target
After=network-online.target e-SUS-AB-PostgreSQL.service

[Service]
Type=simple
User=nobody
Group=nogroup
EnvironmentFile=/etc/monitoring/postgres-exporter.env
ExecStart=/usr/local/bin/postgres_exporter --web.listen-address=0.0.0.0:9187
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadOnlyPaths=/etc/monitoring/postgres-exporter-password

[Install]
WantedBy=multi-user.target
```

Set `/etc/monitoring/postgres-exporter.env` to `0640 root:nogroup` and the
password file to `0640 root:nogroup`, because the service runs as `nobody`.

- [ ] **Step 8: Add PostgreSQL health validation**

Require:

```bash
systemctl enable --now prometheus-postgres-exporter
for attempt in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:9187/metrics |
      grep -q '^pg_up 1$'; then
    printf 'postgres_exporter=ready\n'
    exit 0
  fi
  sleep 2
done
journalctl -u prometheus-postgres-exporter -n 30 --no-pager >&2
exit 1
```

- [ ] **Step 9: Run the static test**

Expected: PostgreSQL assertions pass; test remains red for missing JMX
implementation or Prometheus/dashboard references.

- [ ] **Step 10: Commit PostgreSQL provisioning**

```powershell
rtk git add scripts/monitoring/Configure-EsusPecApplicationExporters.ps1
rtk git commit -m "Provision PEC PostgreSQL exporter"
```

### Task 4: Implement JMX Agent Deployment and Rollback

**Files:**
- Modify: `scripts/monitoring/Configure-EsusPecApplicationExporters.ps1`
- Test: `tests/Validate-MonitoringStack.ps1`

- [ ] **Step 1: Download and verify the JMX agent**

The container script must use:

```bash
install -d -m 0755 /opt/monitoring /etc/monitoring
jmx_tmp=/tmp/jmx_prometheus_javaagent.jar
curl -4 -fL --retry 5 --retry-all-errors --connect-timeout 15 \
  'https://github.com/prometheus/jmx_exporter/releases/download/v1.6.0/jmx_prometheus_javaagent-1.6.0.jar' \
  -o "$jmx_tmp"
echo 'a95983fd96e865d2bcdf911cc500e7c82808c27ab9fd226bf96732b6c3d8c46e  '"$jmx_tmp" |
  sha256sum -c -
install -m 0644 "$jmx_tmp" /opt/monitoring/jmx_prometheus_javaagent.jar
rm -f "$jmx_tmp"
```

Push `jmx-exporter.yml` to `/etc/monitoring/jmx-exporter.yml` with mode `0644`.

- [ ] **Step 2: Implement readiness and rollback functions**

Embed:

```bash
wait_http_ready() {
  url="$1"
  attempts="$2"
  for attempt in $(seq 1 "$attempts"); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

rollback_jmx() {
  if [ -f "$dropin_backup" ]; then
    install -m 0644 "$dropin_backup" "$dropin_file"
  else
    rm -f "$dropin_file"
  fi
  systemctl daemon-reload
  systemctl restart e-SUS-PEC.service
  wait_http_ready http://127.0.0.1:8080 90
}
```

- [ ] **Step 3: Write the managed wrapper and drop-in**

```ini
[Service]
ExecStart=
ExecStart=/opt/monitoring/run-esus-pec-with-jmx.sh
```

Use:

```bash
dropin_dir=/etc/systemd/system/e-SUS-PEC.service.d
dropin_file="$dropin_dir/monitoring-jmx.conf"
dropin_backup="$(mktemp)"
install -d -m 0755 "$dropin_dir"

if [ -f "$dropin_file" ]; then
  cp -p "$dropin_file" "$dropin_backup"
else
  rm -f "$dropin_backup"
fi
```

- [ ] **Step 4: Guard application**

Before modification:

```bash
systemctl is-active e-SUS-PEC.service >/dev/null
wait_http_ready http://127.0.0.1:8080 5
/opt/e-SUS/jre/current/bin/java -version 2>&1 | grep -q '17\.'
```

Apply only when `-ApplyJavaServiceChange` is present. Otherwise return:

```text
jmx=staged-awaiting-apply
```

After writing the drop-in:

```bash
systemctl daemon-reload
if ! systemctl restart e-SUS-PEC.service; then
  rollback_jmx
  exit 1
fi

if ! wait_http_ready http://127.0.0.1:8080 90 ||
   ! wait_http_ready http://127.0.0.1:9404/metrics 60; then
  rollback_jmx
  exit 1
fi

curl -fsS http://127.0.0.1:9404/metrics |
  grep -Eq '^jvm_(memory|gc|threads)_'
printf 'jmx=ready\n'
```

- [ ] **Step 5: Run the static test**

Expected: JMX assertions pass; test remains red for Prometheus/dashboard
references.

- [ ] **Step 6: Commit JMX deployment**

```powershell
rtk git add scripts/monitoring/Configure-EsusPecApplicationExporters.ps1
rtk git commit -m "Provision PEC JMX exporter with rollback"
```

### Task 5: Wire the Entry Point and Prometheus Targets

**Files:**
- Modify: `scripts/monitoring/Install-MonitoringTargetAgent.ps1`
- Modify: `scripts/monitoring/templates/prometheus.yml`
- Modify: `scripts/monitoring/Provision-MonitoringCore.ps1`
- Test: `tests/Validate-MonitoringStack.ps1`

- [ ] **Step 1: Replace the old optional exporter blocks**

Remove the current inline PostgreSQL exporter block and the proposal-only JMX
block. After base/Nginx health validation, delegate:

```powershell
$applicationExporterSummary = $null
if ($ConfigurePostgresExporter -or $ConfigureJmxExporter) {
  $applicationExporterScript =
    Join-Path $PSScriptRoot "Configure-EsusPecApplicationExporters.ps1"

  $applicationExporterParameters = @{
    ConfigFile = $ConfigFile
    TargetCtid = $TargetCtid
    TargetName = $TargetName
    TargetMetricsHost = "192.168.1.209"
    MonitoringCoreHost = $MonitoringCoreHost
    ConfigurePostgresExporter = $ConfigurePostgresExporter
    ConfigureJmxExporter = $ConfigureJmxExporter
    ApplyJavaServiceChange = $ApplyJavaServiceChange
  }

  $applicationExporterJson =
    & $applicationExporterScript @applicationExporterParameters
  $applicationExporterSummary =
    $applicationExporterJson | ConvertFrom-Json
}
```

Set summary fields:

```powershell
postgres_exporter = if ($applicationExporterSummary) {
  $applicationExporterSummary.postgres_exporter
} else {
  "skipped"
}
jmx = if ($applicationExporterSummary) {
  $applicationExporterSummary.jmx
} else {
  "skipped"
}
```

- [ ] **Step 2: Add targets to Prometheus**

Change CT `133` targets to:

```yaml
      - targets:
          - ESUS_PEC_LXC_TARGET_METRICS_HOST:9100
          - ESUS_PEC_LXC_TARGET_METRICS_HOST:9113
          - ESUS_PEC_LXC_TARGET_METRICS_HOST:9187
          - ESUS_PEC_LXC_TARGET_METRICS_HOST:9404
```

Remove the obsolete commented optional-target section.

- [ ] **Step 3: Validate Prometheus before restart**

In `Provision-MonitoringCore.ps1`, replace unconditional restart with:

```bash
/usr/local/bin/promtool check config /etc/prometheus/prometheus.yml
systemctl restart prometheus grafana-server loki alloy
```

The pushed config should first go to
`/etc/prometheus/prometheus.yml.candidate`. Validate it, then atomically move it:

```bash
/usr/local/bin/promtool check config /etc/prometheus/prometheus.yml.candidate
install -o prometheus -g prometheus -m 0644 \
  /etc/prometheus/prometheus.yml.candidate \
  /etc/prometheus/prometheus.yml
rm -f /etc/prometheus/prometheus.yml.candidate
```

- [ ] **Step 4: Run the static test**

Expected: Prometheus target assertions pass; test remains red only for dashboard
coverage if the dashboard has not been changed.

- [ ] **Step 5: Commit integration**

```powershell
rtk git add scripts/monitoring/Install-MonitoringTargetAgent.ps1 scripts/monitoring/templates/prometheus.yml scripts/monitoring/Provision-MonitoringCore.ps1
rtk git commit -m "Scrape PEC PostgreSQL and JMX exporters"
```

### Task 6: Add PostgreSQL and JVM Dashboard Panels

**Files:**
- Modify: `scripts/monitoring/dashboards/esus-pec-ct133.json`
- Test: `tests/Validate-MonitoringStack.ps1`

- [ ] **Step 1: Add availability stats**

Add stat panels:

```promql
up{host="esus-pec-lxc-5437",instance="192.168.1.209:9187"}
up{host="esus-pec-lxc-5437",instance="192.168.1.209:9404"}
pg_up{host="esus-pec-lxc-5437"}
```

- [ ] **Step 2: Add PostgreSQL panels**

Use:

```promql
sum by (datname) (pg_stat_database_numbackends{host="esus-pec-lxc-5437"})
pg_database_size_bytes{host="esus-pec-lxc-5437"}
rate(pg_stat_database_xact_commit{host="esus-pec-lxc-5437"}[5m])
rate(pg_stat_database_xact_rollback{host="esus-pec-lxc-5437"}[5m])
rate(pg_stat_database_deadlocks{host="esus-pec-lxc-5437"}[5m])
rate(pg_stat_database_tup_inserted{host="esus-pec-lxc-5437"}[5m])
rate(pg_stat_database_tup_updated{host="esus-pec-lxc-5437"}[5m])
rate(pg_stat_database_tup_deleted{host="esus-pec-lxc-5437"}[5m])
rate(pg_stat_database_blks_hit{host="esus-pec-lxc-5437"}[5m])
/
clamp_min(
  rate(pg_stat_database_blks_hit{host="esus-pec-lxc-5437"}[5m])
  +
  rate(pg_stat_database_blks_read{host="esus-pec-lxc-5437"}[5m]),
  1
)
```

- [ ] **Step 3: Add JVM panels**

Use:

```promql
jvm_memory_bytes_used{host="esus-pec-lxc-5437",area="heap"}
jvm_memory_bytes_max{host="esus-pec-lxc-5437",area="heap"}
jvm_memory_bytes_used{host="esus-pec-lxc-5437",area="nonheap"}
rate(jvm_gc_collection_seconds_sum{host="esus-pec-lxc-5437"}[5m])
rate(jvm_gc_collection_seconds_count{host="esus-pec-lxc-5437"}[5m])
jvm_threads_current{host="esus-pec-lxc-5437"}
jvm_threads_daemon{host="esus-pec-lxc-5437"}
jvm_classes_loaded_total{host="esus-pec-lxc-5437"}
process_cpu_seconds_total{host="esus-pec-lxc-5437",instance="192.168.1.209:9404"}
process_start_time_seconds{host="esus-pec-lxc-5437",instance="192.168.1.209:9404"}
```

Keep the dashboard at 24 columns, no nested cards, and preserve the existing
logs panel below the new operational sections.

- [ ] **Step 4: Run JSON and static validation**

```powershell
rtk node -e "JSON.parse(require('fs').readFileSync('scripts/monitoring/dashboards/esus-pec-ct133.json','utf8')); console.log('dashboard json ok')"
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-MonitoringStack.ps1
```

Expected:

```text
dashboard json ok
Monitoring stack static validation passed.
```

- [ ] **Step 5: Commit dashboard**

```powershell
rtk git add scripts/monitoring/dashboards/esus-pec-ct133.json tests/Validate-MonitoringStack.ps1
rtk git commit -m "Add PEC PostgreSQL and JVM dashboards"
```

### Task 7: Register the Infisical Variable and Update Documentation

**Files:**
- Modify: `config/esus-pec.infisical.env.example`
- Modify: `docs/monitoring/2026-06-14-centralized-monitoring.md`
- Test: `tests/Validate-MonitoringStack.ps1`

- [ ] **Step 1: Add the secret placeholder**

```text
# Dedicated PostgreSQL 9.6 monitoring account. Store the generated value in
# Infisical /test/InstallationConfig; never commit the real value.
ESUS_PEC_POSTGRES_EXPORTER_PASSWORD=
```

- [ ] **Step 2: Update installation commands**

Document:

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Install-MonitoringTargetAgent.ps1 -ConfigurePostgresExporter -ConfigureJmxExporter -ApplyJavaServiceChange
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Provision-MonitoringCore.ps1 -SkipCreate
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Publish-GrafanaDashboards.ps1
```

- [ ] **Step 3: Document rollback**

Document these commands:

```powershell
rtk ssh <proxmox-target> "pct exec 133 -- systemctl disable --now prometheus-postgres-exporter"
rtk ssh <proxmox-target> "pct exec 133 -- rm -f /etc/systemd/system/e-SUS-PEC.service.d/monitoring-jmx.conf"
rtk ssh <proxmox-target> "pct exec 133 -- systemctl daemon-reload"
rtk ssh <proxmox-target> "pct exec 133 -- systemctl restart e-SUS-PEC.service"
```

State that database role removal is a separate destructive action and is not
part of automatic rollback.

- [ ] **Step 4: Run static validation**

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-MonitoringStack.ps1
rtk git diff --check
```

- [ ] **Step 5: Commit documentation**

```powershell
rtk git add config/esus-pec.infisical.env.example docs/monitoring/2026-06-14-centralized-monitoring.md
rtk git commit -m "Document PEC application exporters"
```

### Task 8: Deploy and Validate Live

**Files:**
- Modify after evidence collection:
  `docs/monitoring/2026-06-14-centralized-monitoring.md`
- External state: CT `133`, CT `190`, Infisical, Grafana

- [ ] **Step 1: Run the target installer**

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Install-MonitoringTargetAgent.ps1 -ConfigurePostgresExporter -ConfigureJmxExporter -ApplyJavaServiceChange
```

Expected JSON fields:

```json
{
  "postgres_exporter": "ready",
  "jmx": "ready"
}
```

- [ ] **Step 2: Apply Prometheus configuration**

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Provision-MonitoringCore.ps1 -SkipCreate
```

Expected: `promtool check config` succeeds and services remain active.

- [ ] **Step 3: Validate CT 133 locally**

```powershell
rtk ssh -i C:/Users/Vinicius/.ssh/id_ed25519 root@192.168.1.149 "pct exec 133 -- systemctl is-active prometheus-postgres-exporter e-SUS-PEC.service"
rtk ssh -i C:/Users/Vinicius/.ssh/id_ed25519 root@192.168.1.149 "pct exec 133 -- curl -fsS http://127.0.0.1:9187/metrics"
rtk ssh -i C:/Users/Vinicius/.ssh/id_ed25519 root@192.168.1.149 "pct exec 133 -- curl -fsS http://127.0.0.1:9404/metrics"
rtk ssh -i C:/Users/Vinicius/.ssh/id_ed25519 root@192.168.1.149 "pct exec 133 -- curl -fsS http://127.0.0.1:8080/"
```

Do not paste complete metric output into docs. Record only metric names and
success states.

- [ ] **Step 4: Validate Prometheus targets and queries**

```powershell
rtk curl "http://192.168.1.190:9090/api/v1/query?query=up%7Binstance%3D%22192.168.1.209%3A9187%22%7D"
rtk curl "http://192.168.1.190:9090/api/v1/query?query=up%7Binstance%3D%22192.168.1.209%3A9404%22%7D"
rtk curl "http://192.168.1.190:9090/api/v1/query?query=pg_up%7Bhost%3D%22esus-pec-lxc-5437%22%7D"
rtk curl "http://192.168.1.190:9090/api/v1/query?query=jvm_memory_bytes_used%7Bhost%3D%22esus-pec-lxc-5437%22%7D"
```

Expected: each query returns a non-empty result; both `up` values equal `1`.

- [ ] **Step 5: Publish and validate Grafana**

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File scripts/monitoring/Publish-GrafanaDashboards.ps1
```

Expected: dashboard UID `esus-pec-ct133` is updated and Grafana database health
is `ok`.

- [ ] **Step 6: Verify Infisical without exposing the value**

Run a presence-only query through the orchestrator or Infisical API and record:

```text
/test/InstallationConfig/ESUS_PEC_POSTGRES_EXPORTER_PASSWORD: present
```

Never print the secret value.

- [ ] **Step 7: Record evidence and update Obsidian**

Append service states, versions, target status, representative metric names,
and rollback behavior to the runbook and:

```text
Knowledge/packer-proxmox-templates/Engineering findings/2026-06-14 - centralized-monitoring-systemd-lxc.md
```

- [ ] **Step 8: Run final verification**

```powershell
rtk powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-MonitoringStack.ps1
rtk node -e "const fs=require('fs'); for(const f of fs.readdirSync('scripts/monitoring/dashboards').filter(x=>x.endsWith('.json'))) JSON.parse(fs.readFileSync('scripts/monitoring/dashboards/'+f,'utf8')); console.log('dashboard json ok')"
rtk git diff --check
rtk git status --short
```

Expected:

```text
Monitoring stack static validation passed.
dashboard json ok
```

- [ ] **Step 9: Commit validation evidence**

Stage only files belonging to this implementation:

```powershell
rtk git add scripts/monitoring tests/Validate-MonitoringStack.ps1 config/esus-pec.infisical.env.example docs/monitoring/2026-06-14-centralized-monitoring.md
rtk git commit -m "Deploy PEC JVM and PostgreSQL monitoring"
```

Do not stage unrelated existing changes in `.Codex/napkin.md`, `.gitignore`,
`AGENTS.md`, or `.env.example`.
