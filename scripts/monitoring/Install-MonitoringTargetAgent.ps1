param(
  [string]$ConfigFile = "config/Proxmox.pkrvars.hcl",
  [int]$TargetCtid = 133,
  [string]$TargetName = "esus-pec-lxc-5437",
  [string]$MonitoringCoreHost = "192.168.1.190",
  [switch]$ConfigurePostgresExporter,
  [switch]$ConfigureJmxExporter,
  [switch]$ApplyJavaServiceChange
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-HclValue {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Text,
    [string]$Default = $null
  )

  $line = $Text -split "`n" | Where-Object {
    $_ -match ("^\s*" + [regex]::Escape($Name) + "\s*=")
  } | Select-Object -First 1

  if (-not $line) { return $Default }
  return (($line -split "=", 2)[1]).Trim().Trim('"')
}

function ConvertTo-ShellSingleQuoted {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
  return "'" + ($Value -replace "'", "'\''") + "'"
}

function ConvertTo-SystemdEnvironmentValue {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
  $escaped = $Value.Replace("\", "\\").Replace('"', '\"')
  return '"' + $escaped + '"'
}

function Invoke-ProxmoxSsh {
  param([Parameter(Mandatory = $true)][string]$Command)

  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & ssh -i $script:SshKey -p $script:SshPort -o BatchMode=yes -o StrictHostKeyChecking=accept-new $script:SshTarget $Command 2>&1 |
      ForEach-Object { $_.ToString() }
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }

  if ($exitCode -ne 0) {
    $output
    throw "Remote Proxmox command failed with exit code $exitCode."
  }
  return ($output -join "`n")
}

function Invoke-ProxmoxBash {
  param([Parameter(Mandatory = $true)][string]$Script)

  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
  Invoke-ProxmoxSsh -Command "echo $encoded | base64 -d | bash -se"
}

function Invoke-ContainerBash {
  param([Parameter(Mandatory = $true)][string]$Script)

  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
  Invoke-ProxmoxSsh -Command "pct exec $TargetCtid -- bash -lc 'echo $encoded | base64 -d | bash -se'"
}

function Push-ContainerFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content,
    [string]$Owner = "root",
    [string]$Group = "root",
    [string]$Mode = "0644"
  )

  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Content))
  $remotePath = ConvertTo-ShellSingleQuoted -Value $Path
  $remoteDir = ConvertTo-ShellSingleQuoted -Value (Split-Path -Parent $Path).Replace("\", "/")
  $remoteOwner = ConvertTo-ShellSingleQuoted -Value "${Owner}:${Group}"
  $remoteMode = ConvertTo-ShellSingleQuoted -Value $Mode

  $pushScript = @"
set -euo pipefail
umask 077
work_dir="`$(mktemp -d /root/codex-monitoring-target-push.XXXXXX)"
trap 'rm -rf "`$work_dir"' EXIT HUP INT TERM
payload_b64="`$work_dir/payload.b64"
payload_file="`$work_dir/payload"
cat > "`$payload_b64" <<'PUSH_PAYLOAD'
$encoded
PUSH_PAYLOAD
base64 -d "`$payload_b64" > "`$payload_file"
pct exec $TargetCtid -- mkdir -p $remoteDir
pct push $TargetCtid "`$payload_file" $remotePath --perms $remoteMode >/dev/null
pct exec $TargetCtid -- chown $remoteOwner $remotePath
"@
  Invoke-ProxmoxBash -Script $pushScript | Out-Null
}

function Get-TemplateContent {
  param([Parameter(Mandatory = $true)][string]$Name)

  $path = Join-Path $PSScriptRoot "templates/$Name"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Missing monitoring template: $path"
  }
  Get-Content -LiteralPath $path -Raw
}

function Assert-TargetContainerIdentity {
  param([Parameter(Mandatory = $true)][string]$ConfigText)

  $hostnameLine = $ConfigText -split "`n" | Where-Object {
    $_ -match "^\s*hostname:\s*(?<hostname>\S+)\s*$"
  } | Select-Object -First 1

  if (-not $hostnameLine) {
    throw "CTID $TargetCtid exists but its Proxmox hostname could not be read. Refusing to mutate an unverified container."
  }

  $configuredName = ([regex]::Match($hostnameLine, "^\s*hostname:\s*(?<hostname>\S+)\s*$")).Groups["hostname"].Value
  if ($configuredName -ne $TargetName) {
    throw "CTID $TargetCtid exists but hostname is '$configuredName', expected '$TargetName'. Refusing to mutate an unrelated container."
  }
}

function Get-LocalPostgresExporterDsn {
  if (-not [string]::IsNullOrWhiteSpace($env:ESUS_PEC_POSTGRES_EXPORTER_DSN)) {
    return $env:ESUS_PEC_POSTGRES_EXPORTER_DSN
  }

  $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
  $relativeEnvFile = "config/monitoring-targets.local.env"
  $envFile = Join-Path $repoRoot $relativeEnvFile
  if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
    throw "Postgres exporter DSN was not provided. Set ESUS_PEC_POSTGRES_EXPORTER_DSN or create ignored local file config/monitoring-targets.local.env."
  }

  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & git -C $repoRoot check-ignore -q -- $relativeEnvFile
    $ignoreExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($ignoreExitCode -ne 0) {
    throw "Refusing to read config/monitoring-targets.local.env because git does not report it as ignored."
  }

  foreach ($line in Get-Content -LiteralPath $envFile) {
    if ($line -match "^\s*ESUS_PEC_POSTGRES_EXPORTER_DSN\s*=\s*(?<value>.+?)\s*$") {
      return $matches.value.Trim().Trim('"').Trim("'")
    }
  }

  throw "config/monitoring-targets.local.env does not define ESUS_PEC_POSTGRES_EXPORTER_DSN."
}

function Read-KeyValueOutput {
  param([Parameter(Mandatory = $true)][string]$Output)

  $result = [ordered]@{}
  foreach ($line in ($Output -split "`n")) {
    if ($line -match "^(?<name>[^=]+)=(?<value>.*)$") {
      $result[$matches.name.Trim()] = $matches.value.Trim()
    }
  }
  return $result
}

$configText = Get-Content -LiteralPath $ConfigFile -Raw
$sshHost = Get-HclValue -Name "proxmox_ssh_host" -Text $configText
$script:SshPort = Get-HclValue -Name "proxmox_ssh_port" -Text $configText -Default "22"
$sshUser = Get-HclValue -Name "proxmox_ssh_user" -Text $configText -Default "root"
$script:SshKey = Get-HclValue -Name "proxmox_ssh_private_key_file" -Text $configText

if ([string]::IsNullOrWhiteSpace($sshHost) -or [string]::IsNullOrWhiteSpace($script:SshKey)) {
  throw "Missing proxmox_ssh_host or proxmox_ssh_private_key_file in $ConfigFile."
}
if (-not (Test-Path -LiteralPath $script:SshKey -PathType Leaf)) {
  throw "SSH private key file not found: $script:SshKey"
}

$script:SshTarget = "$sshUser@$sshHost"

$ctExists = (Invoke-ProxmoxSsh -Command "pct status $TargetCtid >/dev/null 2>&1; echo `$?").Trim() -eq "0"
if (-not $ctExists) {
  throw "CTID $TargetCtid ($TargetName) does not exist on the Proxmox host."
}

$ctConfig = Invoke-ProxmoxSsh -Command "pct config $TargetCtid"
Assert-TargetContainerIdentity -ConfigText $ctConfig

$ctStatus = (Invoke-ProxmoxSsh -Command "pct status $TargetCtid").Trim()
if ($ctStatus -notmatch "status:\s+running") {
  Invoke-ProxmoxSsh -Command "pct start $TargetCtid >/dev/null" | Out-Null
  Start-Sleep -Seconds 5
}

$runtimeHostname = (Invoke-ContainerBash -Script "hostname -s").Trim()
if ($runtimeHostname -ne $TargetName) {
  throw "CTID $TargetCtid runtime hostname is '$runtimeHostname', expected '$TargetName'. Refusing to continue."
}

$installOutput = Invoke-ContainerBash -Script @'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

apt-get update -qq
apt-get install -y -qq ca-certificates curl gpg wget apt-transport-https systemd prometheus-node-exporter >/dev/null

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://apt.grafana.com/gpg-full.key -o /etc/apt/keyrings/grafana.asc
chmod 0644 /etc/apt/keyrings/grafana.asc
cat >/etc/apt/sources.list.d/grafana.list <<'APT'
deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main
APT
apt-get update -qq
apt-get install -y -qq alloy prometheus-node-exporter >/dev/null

install -d -o root -g alloy -m 0750 /etc/alloy
systemctl daemon-reload
systemctl enable alloy prometheus-node-exporter >/dev/null
systemctl restart alloy prometheus-node-exporter
printf 'base=installed\n'
'@

$alloyConfig = (Get-TemplateContent -Name "alloy-linux-target.alloy").
  Replace("ESUS_PEC_TARGET_NAME", $TargetName).
  Replace("MONITORING_CORE_HOST", $MonitoringCoreHost).
  Replace('ctid = "133"', ('ctid = "{0}"' -f $TargetCtid)).
  Replace('ctid     = "133"', ('ctid     = "{0}"' -f $TargetCtid))

Push-ContainerFile -Path "/etc/alloy/config.alloy" -Content $alloyConfig -Owner "root" -Group "alloy" -Mode "0640"
Invoke-ContainerBash -Script @'
set -euo pipefail
systemctl restart alloy
'@ | Out-Null

$nginxOutput = Invoke-ContainerBash -Script @'
set -euo pipefail
if ! command -v nginx >/dev/null 2>&1; then
  printf 'nginx=absent\n'
  printf 'nginx_exporter=skipped\n'
  exit 0
fi

can_check_status_ports="true"
if ! command -v ss >/dev/null 2>&1 && [ ! -r /proc/net/tcp ]; then
  can_check_status_ports="false"
fi

is_local_status_port_free() {
  port="$1"

  if command -v ss >/dev/null 2>&1; then
    if ss -H -ltn 2>/dev/null | awk -v port="$port" '{ local_address = $4; sub(/^.*:/, "", local_address); if (local_address == port) { found = 1 } } END { exit found ? 0 : 1 }'; then
      return 1
    fi
    return 0
  fi

  port_hex="$(printf '%04X' "$port")"
  if awk -v port_hex=":$port_hex" 'NR > 1 && $4 == "0A" && index($2, port_hex) { found = 1 } END { exit found ? 0 : 1 }' /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
    return 1
  fi
  return 0
}

if [ "$can_check_status_ports" != "true" ]; then
  printf 'nginx=skipped-status-port-check-unavailable\n'
  printf 'nginx_exporter=skipped-status-port-check-unavailable\n'
  exit 0
fi

nginx_status_port=""
for candidate_port in 18080 18081 18082; do
  if is_local_status_port_free "$candidate_port"; then
    nginx_status_port="$candidate_port"
    break
  fi
done

if [ -z "$nginx_status_port" ]; then
  printf 'nginx=skipped-status-port-unavailable\n'
  printf 'nginx_exporter=skipped-status-port-unavailable\n'
  exit 0
fi

cat >/etc/nginx/conf.d/monitoring-stub-status.conf <<NGINX
server {
  listen 127.0.0.1:$nginx_status_port;
  server_name 127.0.0.1 localhost;

  access_log off;

  location = /nginx_status {
    stub_status;
    allow 127.0.0.1;
    deny all;
  }
}
NGINX

nginx -t >/dev/null
systemctl reload nginx
printf 'nginx=stub_status_local\n'
printf 'nginx_status_port=%s\n' "$nginx_status_port"

export DEBIAN_FRONTEND=noninteractive
if apt-cache show prometheus-nginx-exporter >/dev/null 2>&1; then
  apt-get install -y -qq prometheus-nginx-exporter >/dev/null
elif apt-cache show nginx-prometheus-exporter >/dev/null 2>&1; then
  apt-get install -y -qq nginx-prometheus-exporter >/dev/null
else
  printf 'nginx_exporter=skipped-package-unavailable\n'
  exit 0
fi

exporter_bin="$(command -v prometheus-nginx-exporter || command -v nginx-prometheus-exporter || true)"
if [ -z "$exporter_bin" ]; then
  printf 'nginx_exporter=skipped-binary-unavailable\n'
  exit 0
fi

cat >/etc/systemd/system/prometheus-nginx-exporter.service <<UNIT
[Unit]
Description=Prometheus Nginx Exporter
Wants=network-online.target
After=network-online.target nginx.service

[Service]
Type=simple
ExecStart=$exporter_bin --nginx.scrape-uri=http://127.0.0.1:$nginx_status_port/nginx_status --web.listen-address=0.0.0.0:9113
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable prometheus-nginx-exporter >/dev/null
systemctl restart prometheus-nginx-exporter
printf 'nginx_exporter=active\n'
'@
$nginxState = Read-KeyValueOutput -Output $nginxOutput

$postgresStatus = "skipped"
if ($ConfigurePostgresExporter) {
  $postgresDsn = Get-LocalPostgresExporterDsn
  $postgresEnvContent = "DATA_SOURCE_NAME={0}`n" -f (ConvertTo-SystemdEnvironmentValue -Value $postgresDsn)

  Push-ContainerFile -Path "/etc/monitoring/postgres-exporter.env" -Content $postgresEnvContent -Owner "root" -Group "root" -Mode "0600"
  Invoke-ContainerBash -Script @'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
if ! apt-cache show prometheus-postgres-exporter >/dev/null 2>&1; then
  echo "prometheus-postgres-exporter apt package is not available on this target." >&2
  exit 1
fi
apt-get install -y -qq prometheus-postgres-exporter >/dev/null

postgres_exporter_bin="$(command -v prometheus-postgres-exporter || command -v postgres_exporter || true)"
if [ -z "$postgres_exporter_bin" ]; then
  echo "Postgres exporter binary was not found after package install." >&2
  exit 1
fi

cat >/etc/systemd/system/prometheus-postgres-exporter.service <<UNIT
[Unit]
Description=Prometheus PostgreSQL Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/monitoring/postgres-exporter.env
ExecStart=$postgres_exporter_bin --web.listen-address=0.0.0.0:9187
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable prometheus-postgres-exporter >/dev/null
systemctl restart prometheus-postgres-exporter
'@ | Out-Null
  $postgresStatus = "configured"
}

$jmxStatus = "skipped"
if ($ConfigureJmxExporter) {
  $jmxScript = @'
set -euo pipefail
apply_requested="__APPLY_JMX_SERVICE_CHANGE__"
javaagent_option="-javaagent:/opt/monitoring/jmx_prometheus_javaagent.jar=9404:/etc/monitoring/jmx-exporter.yml"
proposal_file="/root/monitoring-jmx-proposal.txt"
unit_snapshot="$(mktemp)"

if systemctl cat e-SUS-PEC.service >"$unit_snapshot" 2>&1; then
  service_found="true"
else
  service_found="false"
  printf 'e-SUS-PEC.service was not found by systemctl.\n' >"$unit_snapshot"
fi

{
  printf 'e-SUS PEC JMX exporter proposal\n'
  printf 'Generated by scripts/monitoring/Install-MonitoringTargetAgent.ps1.\n\n'
  printf 'Current e-SUS-PEC.service unit content follows for manual review.\n\n'
  cat "$unit_snapshot"
  printf '\nSuggested guarded change:\n'
  printf 'Set JAVA_TOOL_OPTIONS=%s through a systemd drop-in only if the service already has an EnvironmentFile= or Environment= pattern.\n' "$javaagent_option"
  printf 'Do not download the JMX agent jar from this script; stage /opt/monitoring/jmx_prometheus_javaagent.jar after verifying its integrity.\n'
  printf 'Expose the JMX exporter on 127.0.0.1 or a firewall-restricted target port only.\n'
} >"$proposal_file"
chmod 0600 "$proposal_file"

if [ "$apply_requested" != "true" ]; then
  printf 'jmx=proposal\n'
  exit 0
fi

if [ "$service_found" != "true" ]; then
  printf 'jmx=refused-service-missing\n'
  exit 0
fi

if [ ! -s /opt/monitoring/jmx_prometheus_javaagent.jar ] || [ ! -s /etc/monitoring/jmx-exporter.yml ]; then
  printf 'jmx=refused-missing-local-jmx-files\n'
  exit 0
fi

if grep -Eq '^[[:space:]]*Environment(File)?=' "$unit_snapshot"; then
  :
else
  printf 'jmx=refused-unrecognized-service-environment-pattern\n'
  exit 0
fi

if grep -Eq 'JAVA_TOOL_OPTIONS|-javaagent:.*/jmx_prometheus_javaagent\.jar' "$unit_snapshot"; then
  printf 'jmx=refused-existing-javaagent-configuration\n'
  exit 0
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="/root/monitoring-jmx-backups"
dropin_dir="/etc/systemd/system/e-SUS-PEC.service.d"
dropin_file="$dropin_dir/90-monitoring-jmx.conf"
install -d -m 0700 "$backup_dir"
cp "$unit_snapshot" "$backup_dir/e-SUS-PEC.service.$timestamp.cat"
if [ -f "$dropin_file" ]; then
  cp "$dropin_file" "$backup_dir/90-monitoring-jmx.conf.$timestamp.bak"
fi

install -d -m 0755 "$dropin_dir"
cat >"$dropin_file" <<UNIT
[Service]
Environment=JAVA_TOOL_OPTIONS=$javaagent_option
UNIT
chmod 0644 "$dropin_file"

systemctl daemon-reload
systemctl restart e-SUS-PEC.service
printf 'jmx=applied-systemd-dropin\n'
'@.Replace("__APPLY_JMX_SERVICE_CHANGE__", $(if ($ApplyJavaServiceChange) { "true" } else { "false" }))

  $jmxOutput = Invoke-ContainerBash -Script $jmxScript
  $jmxState = Read-KeyValueOutput -Output $jmxOutput
  if ($jmxState.Contains("jmx")) {
    $jmxStatus = $jmxState["jmx"]
  } else {
    $jmxStatus = "proposal"
  }

  if ($ApplyJavaServiceChange -and $jmxStatus.StartsWith("refused")) {
    throw "JMX apply refused with status '$jmxStatus'. Review /root/monitoring-jmx-proposal.txt on CTID $TargetCtid; no Java service change was made."
  }
}

$healthOutput = Invoke-ContainerBash -Script @'
set -euo pipefail
systemctl is-active alloy prometheus-node-exporter >/dev/null
curl -fsS http://127.0.0.1:9100/metrics >/dev/null
printf 'alloy=%s\n' "$(systemctl is-active alloy)"
printf 'node_exporter=%s\n' "$(systemctl is-active prometheus-node-exporter)"
if systemctl is-active prometheus-nginx-exporter >/dev/null 2>&1; then
  curl -fsS http://127.0.0.1:9113/metrics >/dev/null
  printf 'nginx_exporter_health=ready\n'
else
  printf 'nginx_exporter_health=skipped\n'
fi
'@
$health = Read-KeyValueOutput -Output $healthOutput

$serviceSummary = [ordered]@{
  target = [ordered]@{
    ctid = $TargetCtid
    name = $TargetName
  }
  alloy = $health["alloy"]
  node_exporter = $health["node_exporter"]
  nginx = if ($nginxState.Contains("nginx")) { $nginxState["nginx"] } else { "unknown" }
  nginx_exporter = if ($nginxState.Contains("nginx_exporter")) { $nginxState["nginx_exporter"] } else { $health["nginx_exporter_health"] }
  postgres_exporter = $postgresStatus
  jmx = $jmxStatus
}

if (-not [string]::IsNullOrWhiteSpace($installOutput)) {
  $installState = Read-KeyValueOutput -Output $installOutput
  if ($installState.Contains("base")) {
    $serviceSummary["base"] = $installState["base"]
  }
}

$serviceSummary | ConvertTo-Json -Depth 4
