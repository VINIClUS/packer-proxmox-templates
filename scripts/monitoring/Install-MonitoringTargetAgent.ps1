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

function Invoke-ProxmoxBash {
  param(
    [Parameter(Mandatory = $true)][string]$Script,
    [string]$Label = "proxmox-bash"
  )

  $remoteTemp = Copy-TextToProxmoxTempFile -Text $Script
  $remoteTempQuoted = ConvertTo-ShellSingleQuoted -Value $remoteTemp
  try {
    Invoke-ProxmoxSsh -Command "bash $remoteTempQuoted" -Label $Label
  } finally {
    Invoke-ProxmoxSsh -Command "rm -f $remoteTempQuoted" -Label "$Label-cleanup" | Out-Null
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
  Invoke-ProxmoxBash -Script $pushScript -Label "push-container-file:$Path" | Out-Null
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
  throw "CTID $TargetCtid ($TargetName) is not running. Start and verify the container manually before installing monitoring agents; this script will not mutate CT power state."
}

$runtimeHostname = (Invoke-ContainerBash -Script "hostname -s" -Label "target-runtime-hostname").Trim()
if ($runtimeHostname -ne $TargetName) {
  throw "CTID $TargetCtid runtime hostname is '$runtimeHostname', expected '$TargetName'. Refusing to continue."
}

$installOutput = Invoke-ContainerBash -Label "base-packages" -Script @'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

echo "[monitoring-target] base apt update" >&2
apt-get update -qq
echo "[monitoring-target] base package install" >&2
apt-get install -y -qq ca-certificates curl gpg wget apt-transport-https systemd prometheus-node-exporter >/dev/null

echo "[monitoring-target] grafana apt key" >&2
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://apt.grafana.com/gpg-full.key -o /etc/apt/keyrings/grafana.asc
chmod 0644 /etc/apt/keyrings/grafana.asc
cat >/etc/apt/sources.list.d/grafana.list <<'APT'
deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main
APT
echo "[monitoring-target] grafana apt update" >&2
apt-get update -qq
echo "[monitoring-target] alloy package install" >&2
apt-get install -y -qq alloy prometheus-node-exporter >/dev/null

echo "[monitoring-target] base services restart" >&2
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
Invoke-ContainerBash -Label "restart-alloy" -Script @'
set -euo pipefail
systemctl restart alloy
'@ | Out-Null

$nginxOutput = Invoke-ContainerBash -Label "nginx-exporter" -Script @'
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

nginx_stub_config="/etc/nginx/conf.d/monitoring-stub-status.conf"
nginx_stub_marker="# Managed by scripts/monitoring/Install-MonitoringTargetAgent.ps1"

get_managed_stub_status_port() {
  if [ ! -f "$nginx_stub_config" ]; then
    return 1
  fi
  if ! grep -Fqx "$nginx_stub_marker" "$nginx_stub_config"; then
    return 1
  fi
  sed -n -E 's/^[[:space:]]*listen[[:space:]]+127\.0\.0\.1:([0-9]+);.*/\1/p' "$nginx_stub_config" | head -n 1
}

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

restore_nginx_stub_config() {
  backup_file="$1"
  if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
    cp -p "$backup_file" "$nginx_stub_config"
  else
    rm -f "$nginx_stub_config"
  fi
}

write_nginx_stub_config() {
  port="$1"
  candidate_file="$(mktemp /etc/nginx/conf.d/monitoring-stub-status.conf.tmp.XXXXXX)"
  backup_file=""

  if [ -f "$nginx_stub_config" ]; then
    if ! grep -Fqx "$nginx_stub_marker" "$nginx_stub_config"; then
      rm -f "$candidate_file"
      printf 'nginx=skipped-existing-unmanaged-stub-status-config\n'
      return 2
    fi
    backup_file="$(mktemp /etc/nginx/conf.d/monitoring-stub-status.conf.bak.XXXXXX)"
    cp -p "$nginx_stub_config" "$backup_file"
  fi

  cat >"$candidate_file" <<NGINX
$nginx_stub_marker
server {
  listen 127.0.0.1:$port;
  server_name 127.0.0.1 localhost;

  access_log off;

  location = /nginx_status {
    stub_status;
    allow 127.0.0.1;
    deny all;
  }
}
NGINX
  chmod 0644 "$candidate_file"
  mv "$candidate_file" "$nginx_stub_config"

  if ! nginx -t >/dev/null 2>&1; then
    restore_nginx_stub_config "$backup_file"
    rm -f "$backup_file"
    echo "Generated nginx stub_status config failed validation; restored previous config." >&2
    return 1
  fi

  if ! systemctl reload nginx >/dev/null 2>&1; then
    restore_nginx_stub_config "$backup_file"
    if nginx -t >/dev/null 2>&1; then
      systemctl reload nginx >/dev/null 2>&1 || true
    fi
    rm -f "$backup_file"
    echo "nginx reload failed after stub_status update; restored previous config." >&2
    return 1
  fi

  rm -f "$backup_file"
  printf 'nginx=stub_status_local\n'
  return 0
}

existing_managed_port="$(get_managed_stub_status_port || true)"
nginx_status_port=""
nginx_status_config="new-managed"

if [ -n "$existing_managed_port" ]; then
  nginx_status_port="$existing_managed_port"
  nginx_status_config="reused-managed"
elif [ "$can_check_status_ports" != "true" ]; then
  printf 'nginx=skipped-status-port-check-unavailable\n'
  printf 'nginx_exporter=skipped-status-port-check-unavailable\n'
  exit 0
else
  for candidate_port in 18080 18081 18082; do
    if is_local_status_port_free "$candidate_port"; then
      nginx_status_port="$candidate_port"
      break
    fi
  done
fi

if [ -z "$nginx_status_port" ]; then
  printf 'nginx=skipped-status-port-unavailable\n'
  printf 'nginx_exporter=skipped-status-port-unavailable\n'
  exit 0
fi

set +e
write_nginx_stub_config "$nginx_status_port"
nginx_stub_write_status="$?"
set -e
if [ "$nginx_stub_write_status" -eq 2 ]; then
  printf 'nginx_exporter=skipped-existing-unmanaged-stub-status-config\n'
  exit 0
elif [ "$nginx_stub_write_status" -ne 0 ]; then
  exit "$nginx_stub_write_status"
fi
printf 'nginx_status_port=%s\n' "$nginx_status_port"
printf 'nginx_status_config=%s\n' "$nginx_status_config"

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

$healthOutput = Invoke-ContainerBash -Label "target-health-check" -Script @'
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

$applicationExporterSummary = $null
if ($ConfigurePostgresExporter -or $ConfigureJmxExporter) {
  $applicationExporterScript = Join-Path $PSScriptRoot "Configure-EsusPecApplicationExporters.ps1"
  if (-not (Test-Path -LiteralPath $applicationExporterScript -PathType Leaf)) {
    throw "Missing application exporter provisioner: $applicationExporterScript"
  }

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

  $applicationExporterJson = & $applicationExporterScript @applicationExporterParameters
  $applicationExporterSummary = $applicationExporterJson | ConvertFrom-Json
}

$serviceSummary = [ordered]@{
  target = [ordered]@{
    ctid = $TargetCtid
    name = $TargetName
  }
  alloy = $health["alloy"]
  node_exporter = $health["node_exporter"]
  nginx = if ($nginxState.Contains("nginx")) { $nginxState["nginx"] } else { "unknown" }
  nginx_exporter = if ($nginxState.Contains("nginx_exporter")) { $nginxState["nginx_exporter"] } else { $health["nginx_exporter_health"] }
  postgres_exporter = if ($applicationExporterSummary) { $applicationExporterSummary.postgres_exporter } else { "skipped" }
  jmx = if ($applicationExporterSummary) { $applicationExporterSummary.jmx } else { "skipped" }
}

if (-not [string]::IsNullOrWhiteSpace($installOutput)) {
  $installState = Read-KeyValueOutput -Output $installOutput
  if ($installState.Contains("base")) {
    $serviceSummary["base"] = $installState["base"]
  }
}

$serviceSummary | ConvertTo-Json -Depth 4
