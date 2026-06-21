param(
  [string]$ConfigFile = "config/Proxmox.pkrvars.hcl",
  [int]$TargetCtid = 120,
  [string]$TargetName = "infisical",
  [string]$TargetMetricsHost = "192.168.1.226",
  [string]$MonitoringCoreHost = "192.168.1.190"
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

function Invoke-ProxmoxSsh {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [string]$Label = "proxmox-ssh"
  )

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
    throw "Remote Proxmox command '$Label' failed with exit code $exitCode."
  }
  return ($output -join "`n")
}

function Copy-TextToProxmoxTempFile {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [string]$Prefix = "codex-monitoring-script"
  )

  $localTemp = [System.IO.Path]::GetTempFileName()
  $remoteTemp = $null
  try {
    $normalizedText = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    [System.IO.File]::WriteAllText($localTemp, $normalizedText, [System.Text.UTF8Encoding]::new($false))
    $remoteTemp = (Invoke-ProxmoxSsh -Command "umask 077; mktemp /root/$Prefix.XXXXXXXXXX" -Label "remote-tempfile").Trim()
    $scpTarget = "{0}:{1}" -f $script:SshTarget, $remoteTemp

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
      $scpOutput = & scp -i $script:SshKey -P $script:SshPort -o BatchMode=yes -o StrictHostKeyChecking=accept-new $localTemp $scpTarget 2>&1 |
        ForEach-Object { $_.ToString() }
      $scpExitCode = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($scpExitCode -ne 0) {
      $scpOutput
      throw "SCP transfer for remote script failed with exit code $scpExitCode."
    }

    return $remoteTemp
  } catch {
    if (-not [string]::IsNullOrWhiteSpace($remoteTemp)) {
      $remoteTempQuoted = ConvertTo-ShellSingleQuoted -Value $remoteTemp
      try {
        Invoke-ProxmoxSsh -Command "rm -f $remoteTempQuoted" -Label "remote-tempfile-cleanup" | Out-Null
      } catch {
      }
    }
    throw
  } finally {
    if (Test-Path -LiteralPath $localTemp -PathType Leaf) {
      Remove-Item -LiteralPath $localTemp -Force
    }
  }
}

function Invoke-ContainerBash {
  param(
    [Parameter(Mandatory = $true)][string]$Script,
    [string]$Label = "container-bash"
  )

  $remoteTemp = Copy-TextToProxmoxTempFile -Text $Script
  $remoteTempQuoted = ConvertTo-ShellSingleQuoted -Value $remoteTemp
  try {
    Invoke-ProxmoxSsh -Command "pct exec $TargetCtid -- bash -se < $remoteTempQuoted" -Label $Label
  } finally {
    Invoke-ProxmoxSsh -Command "rm -f $remoteTempQuoted" -Label "$Label-cleanup" | Out-Null
  }
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

$ctExists = (Invoke-ProxmoxSsh -Command "pct status $TargetCtid >/dev/null 2>&1; echo `$?" -Label "target-exists").Trim() -eq "0"
if (-not $ctExists) {
  throw "CTID $TargetCtid ($TargetName) does not exist on the Proxmox host."
}

$ctConfig = Invoke-ProxmoxSsh -Command "pct config $TargetCtid" -Label "target-config"
Assert-TargetContainerIdentity -ConfigText $ctConfig

$ctStatus = (Invoke-ProxmoxSsh -Command "pct status $TargetCtid" -Label "target-status").Trim()
if ($ctStatus -notmatch "status:\s+running") {
  throw "CTID $TargetCtid ($TargetName) is not running. Start and verify the container manually before installing monitoring exporters; this script will not mutate CT power state."
}

$runtimeHostname = (Invoke-ContainerBash -Script "hostname -s" -Label "target-runtime-hostname").Trim()
if ($runtimeHostname -ne $TargetName) {
  throw "CTID $TargetCtid runtime hostname is '$runtimeHostname', expected '$TargetName'. Refusing to continue."
}

$monitoringCoreHostQuoted = ConvertTo-ShellSingleQuoted -Value $MonitoringCoreHost
$targetMetricsHostQuoted = ConvertTo-ShellSingleQuoted -Value $TargetMetricsHost

$installOutput = Invoke-ContainerBash -Label "infisical-exporters-install" -Script @"
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
monitoring_core_host=$monitoringCoreHostQuoted
target_metrics_host=$targetMetricsHostQuoted

if ! hostname -I | tr ' ' '\n' | grep -Fxq "`$target_metrics_host"; then
  echo "CTID $TargetCtid ($TargetName) does not have expected TargetMetricsHost IP `$target_metrics_host." >&2
  exit 1
fi

if ! systemctl is-active postgresql@17-main.service >/dev/null; then
  echo "postgresql@17-main.service is not active on Infisical target." >&2
  exit 1
fi
if ! systemctl is-active redis-server.service >/dev/null; then
  echo "redis-server.service is not active on Infisical target." >&2
  exit 1
fi
if ! curl -fsS http://127.0.0.1:6379 >/dev/null 2>&1; then
  true
fi
runuser -u postgres -- psql -Atqc 'select 1' postgres | grep -qx 1

apt-get update -qq
apt-get install -y -qq ca-certificates curl nftables prometheus-postgres-exporter prometheus-redis-exporter >/dev/null

postgres_exporter_bin="`$(command -v prometheus-postgres-exporter || command -v postgres_exporter || true)"
redis_exporter_bin="`$(command -v prometheus-redis-exporter || command -v redis_exporter || true)"
if [ -z "`$postgres_exporter_bin" ]; then
  echo "prometheus-postgres-exporter binary not found after package install." >&2
  exit 1
fi
if [ -z "`$redis_exporter_bin" ]; then
  echo "prometheus-redis-exporter binary not found after package install." >&2
  exit 1
fi

cat >/usr/local/sbin/apply-infisical-monitoring-exporter-firewall <<'FIREWALL'
#!/usr/bin/env bash
set -euo pipefail
monitoring_core_host="`$1"
table_name="monitoring_infisical_exporters"

if nft list table inet "`$table_name" >/dev/null 2>&1; then
  nft delete table inet "`$table_name"
fi

nft add table inet "`$table_name"
nft 'add chain inet monitoring_infisical_exporters input { type filter hook input priority -50; policy accept; }'
nft add rule inet "`$table_name" input iifname "lo" tcp dport 9187 accept
nft add rule inet "`$table_name" input iifname "lo" tcp dport 9121 accept
nft add rule inet "`$table_name" input ip saddr "`$monitoring_core_host" tcp dport 9187 accept
nft add rule inet "`$table_name" input ip saddr "`$monitoring_core_host" tcp dport 9121 accept
nft add rule inet "`$table_name" input tcp dport 9187 reject
nft add rule inet "`$table_name" input tcp dport 9121 reject
FIREWALL
chmod 0755 /usr/local/sbin/apply-infisical-monitoring-exporter-firewall

cat >/etc/systemd/system/infisical-monitoring-exporters-firewall.service <<UNIT
[Unit]
Description=Restrict Infisical monitoring exporter ports to Prometheus
DefaultDependencies=no
Before=prometheus-postgres-exporter.service prometheus-redis-exporter.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/apply-infisical-monitoring-exporter-firewall $MonitoringCoreHost
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

cat >/etc/systemd/system/prometheus-postgres-exporter.service <<UNIT
[Unit]
Description=Prometheus PostgreSQL Exporter for Infisical
Wants=network-online.target infisical-monitoring-exporters-firewall.service
After=network-online.target infisical-monitoring-exporters-firewall.service postgresql@17-main.service

[Service]
Type=simple
User=postgres
Environment='DATA_SOURCE_NAME=user=postgres host=/var/run/postgresql dbname=postgres sslmode=disable'
ExecStart=`$postgres_exporter_bin --web.listen-address=0.0.0.0:9187
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true

[Install]
WantedBy=multi-user.target
UNIT

cat >/etc/systemd/system/prometheus-redis-exporter.service <<UNIT
[Unit]
Description=Prometheus Redis Exporter for Infisical
Wants=network-online.target infisical-monitoring-exporters-firewall.service
After=network-online.target infisical-monitoring-exporters-firewall.service redis-server.service

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=`$redis_exporter_bin --redis.addr=redis://127.0.0.1:6379 --web.listen-address=0.0.0.0:9121
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now infisical-monitoring-exporters-firewall.service >/dev/null
systemctl enable --now prometheus-postgres-exporter.service prometheus-redis-exporter.service >/dev/null
systemctl restart prometheus-postgres-exporter.service prometheus-redis-exporter.service

for attempt in `$(seq 1 30); do
  if curl -fsS http://127.0.0.1:9187/metrics | grep -q '^pg_up 1' &&
     curl -fsS http://127.0.0.1:9121/metrics | grep -q '^redis_up 1'; then
    printf 'postgres_exporter=ready\n'
    printf 'redis_exporter=ready\n'
    printf 'firewall=active\n'
    exit 0
  fi
  sleep 2
done

journalctl -u prometheus-postgres-exporter -u prometheus-redis-exporter -n 60 --no-pager >&2
exit 1
"@

$state = Read-KeyValueOutput -Output $installOutput

[ordered]@{
  target = [ordered]@{
    ctid = $TargetCtid
    name = $TargetName
    metricsHost = $TargetMetricsHost
  }
  postgres_exporter = if ($state.Contains("postgres_exporter")) { $state["postgres_exporter"] } else { "unknown" }
  redis_exporter = if ($state.Contains("redis_exporter")) { $state["redis_exporter"] } else { "unknown" }
  firewall = if ($state.Contains("firewall")) { $state["firewall"] } else { "unknown" }
} | ConvertTo-Json -Depth 4
