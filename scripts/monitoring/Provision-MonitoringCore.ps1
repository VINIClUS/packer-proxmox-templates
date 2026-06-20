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

$script:PrometheusVersion = "3.12.0"
$script:LokiVersion = "3.7.2"
$script:ManagedMarker = "codex-monitoring-core"

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
    [Parameter(Mandatory = $true)][string]$Command
  )

  $nativeErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & ssh -i $script:SshKey -p $script:SshPort -o BatchMode=yes -o StrictHostKeyChecking=accept-new $script:SshTarget $Command 2>&1 |
      ForEach-Object { "$_" }
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $nativeErrorActionPreference
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
  $nativeErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & ssh -i $script:SshKey -p $script:SshPort -o BatchMode=yes -o StrictHostKeyChecking=accept-new $script:SshTarget "echo $encoded | base64 -d | bash -se" 2>&1 |
      ForEach-Object { "$_" }
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $nativeErrorActionPreference
  }

  if ($exitCode -ne 0) {
    $output
    throw "Remote Proxmox bash script failed with exit code $exitCode."
  }
  return ($output -join "`n")
}

function Invoke-ContainerBash {
  param(
    [Parameter(Mandatory = $true)][string]$Script
  )

  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
  Invoke-ProxmoxSsh -Command "pct exec $Ctid -- bash -lc 'echo $encoded | base64 -d | bash -se'"
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
work_dir="`$(mktemp -d /root/codex-monitoring-push.XXXXXX)"
trap 'rm -rf "`$work_dir"' EXIT HUP INT TERM
payload_b64="`$work_dir/payload.b64"
payload_file="`$work_dir/payload"
cat > "`$payload_b64" <<'PUSH_PAYLOAD'
$encoded
PUSH_PAYLOAD
base64 -d "`$payload_b64" > "`$payload_file"
pct exec $Ctid -- mkdir -p $remoteDir
pct push $Ctid "`$payload_file" $remotePath --perms $remoteMode >/dev/null
pct exec $Ctid -- chown $remoteOwner $remotePath
"@
  Invoke-ProxmoxBash -Script $pushScript | Out-Null
}

function Assert-MonitoringContainerConfig {
  param([Parameter(Mandatory = $true)][string]$ConfigText)

  $configLines = $ConfigText -split "`n"
  $expectedHostnamePattern = ("^\s*hostname:\s*" + [regex]::Escape($Hostname) + "\s*$")
  $expectedOstypePattern = "^\s*ostype:\s*debian\s*$"
  $expectedIp = "ip=$IpCidr"

  $hasExpectedHostname = $configLines | Where-Object { $_ -match $expectedHostnamePattern } | Select-Object -First 1
  $hasExpectedOstype = $configLines | Where-Object { $_ -match $expectedOstypePattern } | Select-Object -First 1
  $hasRequestedIp = $configLines | Where-Object {
    $_ -match "^\s*net0:" -and $_ -match [regex]::Escape($expectedIp)
  } | Select-Object -First 1
  $hasManagedMarker = $ConfigText -match [regex]::Escape($script:ManagedMarker)

  if (-not $hasExpectedHostname -or -not $hasExpectedOstype -or (-not $hasRequestedIp -and -not $hasManagedMarker)) {
    throw "CTID $Ctid exists but does not match the requested monitoring CT. Expected hostname '$Hostname', ostype 'debian', and either net0 containing '$expectedIp' or description marker '$($script:ManagedMarker)'. Inspect manually on the Proxmox host with 'pct config $Ctid' before rerunning."
  }
}

function Get-TemplateContent {
  param([Parameter(Mandatory = $true)][string]$Name)

  $path = Join-Path $PSScriptRoot "templates/$Name"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Missing monitoring template: $path"
  }
  Get-Content -LiteralPath $path -Raw
}

function Get-ContainerServiceStates {
  $statusOutput = Invoke-ContainerBash -Script @'
set -euo pipefail
for service in prometheus grafana-server loki alloy; do
  printf '%s=%s\n' "$service" "$(systemctl is-active "$service" 2>/dev/null || true)"
done
'@

  $states = [ordered]@{}
  foreach ($line in ($statusOutput -split "`n")) {
    if ($line -match "^(?<name>[^=]+)=(?<state>.+)$") {
      $states[$matches.name] = $matches.state.Trim()
    }
  }
  return $states
}

function Test-ContainerReadiness {
  if ($SkipHealthChecks) {
    return [ordered]@{
      prometheus = "skipped"
      grafana = "skipped"
      loki = "skipped"
    }
  }

  $healthOutput = Invoke-ContainerBash -Script @'
set -euo pipefail

wait_service_active() {
  local service="$1"
  for attempt in $(seq 1 30); do
    if systemctl is-active "$service" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  systemctl is-active "$service"
}

wait_http_ready() {
  local name="$1"
  local url="$2"
  for attempt in $(seq 1 30); do
    if curl -fsS --max-time 5 "$url" >/dev/null 2>&1; then
      printf '%s=ready\n' "$name"
      return 0
    fi
    sleep 2
  done
  echo "$name readiness endpoint did not become ready: $url" >&2
  return 1
}

for service in prometheus grafana-server loki alloy; do
  wait_service_active "$service" >/dev/null
done

wait_http_ready prometheus http://127.0.0.1:9090/-/ready
wait_http_ready grafana http://127.0.0.1:3000/api/health
wait_http_ready loki http://127.0.0.1:3100/ready
'@

  $readiness = [ordered]@{}
  foreach ($line in ($healthOutput -split "`n")) {
    if ($line -match "^(?<name>[^=]+)=(?<state>.+)$") {
      $readiness[$matches.name] = $matches.state.Trim()
    }
  }
  return $readiness
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
$ipAddress = ($IpCidr -split "/", 2)[0]

$ctExists = (Invoke-ProxmoxSsh -Command "pct status $Ctid >/dev/null 2>&1; echo `$?").Trim() -eq "0"
if ($ctExists) {
  $ctConfig = Invoke-ProxmoxSsh -Command "pct config $Ctid"
  Assert-MonitoringContainerConfig -ConfigText $ctConfig
} else {
  if ($SkipCreate) {
    throw "CTID $Ctid ($Hostname) does not exist and -SkipCreate was set."
  }

  $rootfs = "$Storage`:$RootfsSize"
  $net0 = "name=eth0,bridge=$Bridge,ip=$IpCidr,gw=$Gateway,firewall=1"
  $description = "$($script:ManagedMarker); CTID $Ctid ($Hostname) provisioned by scripts/monitoring/Provision-MonitoringCore.ps1 (default CTID 190 monitoring-core). No secrets."
  $createScript = @"
set -euo pipefail
pct create $Ctid $(ConvertTo-ShellSingleQuoted -Value $Template) \
  --hostname $(ConvertTo-ShellSingleQuoted -Value $Hostname) \
  --rootfs $(ConvertTo-ShellSingleQuoted -Value $rootfs) \
  --cores $Cores --memory $MemoryMb --swap $SwapMb \
  --net0 $(ConvertTo-ShellSingleQuoted -Value $net0) \
  --unprivileged 1 --features nesting=1,keyctl=1 --ostype debian --onboot 1 \
  --description $(ConvertTo-ShellSingleQuoted -Value $description)
"@
  Invoke-ProxmoxBash -Script $createScript | Out-Null
}

$ctStatus = (Invoke-ProxmoxSsh -Command "pct status $Ctid").Trim()
if ($ctStatus -notmatch "status:\s+running") {
  Invoke-ProxmoxSsh -Command "pct start $Ctid >/dev/null" | Out-Null
  Start-Sleep -Seconds 5
}

$installScript = @"
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

apt-get update -qq
apt-get install -y -qq curl wget gpg ca-certificates apt-transport-https tar systemd unzip >/dev/null

download_url() {
  local url="`$1"
  local output_path="`$2"
  curl -4 -fsSL --retry 5 --retry-all-errors --retry-delay 3 --connect-timeout 20 --max-time 300 "`$url" -o "`$output_path"
}

install -d -m 0755 /etc/apt/keyrings
download_url https://apt.grafana.com/gpg-full.key /etc/apt/keyrings/grafana.asc
chmod 0644 /etc/apt/keyrings/grafana.asc
cat >/etc/apt/sources.list.d/grafana.list <<'APT'
deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main
APT
apt-get update -qq
apt-get install -y -qq grafana alloy >/dev/null

arch="`$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "`$arch" in
  amd64|x86_64)
    release_arch="amd64"
    ;;
  *)
    echo "Unsupported container architecture: `$arch. Monitoring core binary install supports amd64/x86_64 only." >&2
    exit 1
    ;;
esac

verify_release_asset() {
  local checksums_file="`$1"
  local asset_name="`$2"
  local asset_path="`$3"
  local expected

  expected="`$(awk -v asset="`$asset_name" '
    {
      name = `$2
      sub(/^\*/, "", name)
      sub(/^\.\//, "", name)
      if (name == asset) {
        print `$1
        found = 1
        exit
      }
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "`$checksums_file")" || {
    echo "Checksum file does not contain expected asset: `$asset_name" >&2
    exit 1
  }

  printf '%s  %s\n' "`$expected" "`$asset_path" | sha256sum -c - >/dev/null
}

cleanup_downloads() {
  if [ -n "`${prom_tmp:-}" ]; then rm -rf "`$prom_tmp"; fi
  if [ -n "`${loki_tmp:-}" ]; then rm -rf "`$loki_tmp"; fi
}
trap cleanup_downloads EXIT

id prometheus >/dev/null 2>&1 || useradd --system --user-group --home-dir /var/lib/prometheus --shell /usr/sbin/nologin prometheus
install -d -o prometheus -g prometheus -m 0755 /etc/prometheus /var/lib/prometheus

prom_tmp="`$(mktemp -d)"
prom_asset="prometheus-$($script:PrometheusVersion).linux-`$release_arch.tar.gz"
download_url "https://github.com/prometheus/prometheus/releases/download/v$($script:PrometheusVersion)/`$prom_asset" "`$prom_tmp/`$prom_asset"
download_url "https://github.com/prometheus/prometheus/releases/download/v$($script:PrometheusVersion)/sha256sums.txt" "`$prom_tmp/sha256sums.txt"
verify_release_asset "`$prom_tmp/sha256sums.txt" "`$prom_asset" "`$prom_tmp/`$prom_asset"
tar -xzf "`$prom_tmp/`$prom_asset" -C "`$prom_tmp"
prom_dir="`$prom_tmp/prometheus-$($script:PrometheusVersion).linux-`$release_arch"
install -m 0755 "`$prom_dir/prometheus" /usr/local/bin/prometheus
install -m 0755 "`$prom_dir/promtool" /usr/local/bin/promtool

cat >/etc/systemd/system/prometheus.service <<'UNIT'
[Unit]
Description=Prometheus Monitoring Server
Documentation=https://prometheus.io/docs/prometheus/latest/installation/
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.listen-address=0.0.0.0:9090 \
  --web.enable-lifecycle \
  --web.enable-remote-write-receiver
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

id loki >/dev/null 2>&1 || useradd --system --user-group --home-dir /var/lib/loki --shell /usr/sbin/nologin loki
install -d -o loki -g loki -m 0755 /etc/loki /var/lib/loki /var/lib/loki/chunks /var/lib/loki/rules /var/lib/loki/compactor

loki_tmp="`$(mktemp -d)"
loki_asset="loki-linux-`$release_arch.zip"
download_url "https://github.com/grafana/loki/releases/download/v$($script:LokiVersion)/`$loki_asset" "`$loki_tmp/`$loki_asset"
download_url "https://github.com/grafana/loki/releases/download/v$($script:LokiVersion)/SHA256SUMS" "`$loki_tmp/SHA256SUMS"
verify_release_asset "`$loki_tmp/SHA256SUMS" "`$loki_asset" "`$loki_tmp/`$loki_asset"
unzip -q -o "`$loki_tmp/`$loki_asset" -d "`$loki_tmp"
loki_bin="`$loki_tmp/loki-linux-`$release_arch"
if [ ! -f "`$loki_bin" ]; then
  echo "Loki archive did not contain expected binary path: loki-linux-`$release_arch" >&2
  exit 1
fi
install -m 0755 "`$loki_bin" /usr/local/bin/loki

cat >/etc/systemd/system/loki.service <<'UNIT'
[Unit]
Description=Loki Log Aggregation Server
Documentation=https://grafana.com/docs/loki/latest/
Wants=network-online.target
After=network-online.target

[Service]
User=loki
Group=loki
Type=simple
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

install -d -o root -g alloy -m 0750 /etc/alloy
install -d -o root -g grafana -m 0750 /etc/grafana/provisioning/datasources

systemctl daemon-reload
"@
Invoke-ContainerBash -Script $installScript | Out-Null

$prometheusConfig = (Get-TemplateContent -Name "prometheus.yml").
  Replace("ESUS_PEC_LXC_TARGET_METRICS_HOST", $InitialTargetMetricsHost).
  Replace("esus-pec-lxc-5437", $InitialTargetName).
  Replace('ctid: "133"', ('ctid: "{0}"' -f $InitialTargetCtid))
$lokiConfig = Get-TemplateContent -Name "loki.yml"
$alloyConfig = (Get-TemplateContent -Name "alloy-core.alloy").
  Replace("monitoring-core", $Hostname).
  Replace('ctid = "190"', ('ctid = "{0}"' -f $Ctid))
$grafanaDatasourceConfig = Get-TemplateContent -Name "grafana-datasources.yml"

Push-ContainerFile -Path "/etc/prometheus/prometheus.yml.candidate" -Content $prometheusConfig -Owner "root" -Group "root" -Mode "0644"
Invoke-ContainerBash -Script @'
set -euo pipefail
candidate="/etc/prometheus/prometheus.yml.candidate"
active="/etc/prometheus/prometheus.yml"
trap 'rm -f "$candidate"' EXIT HUP INT TERM
promtool check config "$candidate"
install -o prometheus -g prometheus -m 0644 "$candidate" "$active"
rm -f "$candidate"
trap - EXIT HUP INT TERM
'@ | Out-Null

Push-ContainerFile -Path "/etc/loki/loki.yml" -Content $lokiConfig -Owner "loki" -Group "loki" -Mode "0644"
Push-ContainerFile -Path "/etc/alloy/config.alloy" -Content $alloyConfig -Owner "root" -Group "alloy" -Mode "0640"
Push-ContainerFile -Path "/etc/grafana/provisioning/datasources/datasources.yml" -Content $grafanaDatasourceConfig -Owner "root" -Group "grafana" -Mode "0640"

Invoke-ContainerBash -Script @'
set -euo pipefail
systemctl daemon-reload
systemctl enable prometheus grafana-server loki alloy >/dev/null
systemctl restart prometheus grafana-server loki alloy
'@ | Out-Null

if ($SkipHealthChecks) {
  $healthChecks = "skipped"
  $serviceStates = "skipped"
  $readiness = "skipped"
} else {
  $healthChecks = "completed"
  $serviceStates = Get-ContainerServiceStates
  $readiness = Test-ContainerReadiness
}

[ordered]@{
  ctid = $Ctid
  hostname = $Hostname
  ip = $ipAddress
  healthChecks = $healthChecks
  services = $serviceStates
  readiness = $readiness
  endpoints = [ordered]@{
    prometheus = "http://$ipAddress`:9090"
    grafana = "http://$ipAddress`:3000"
    loki = "http://$ipAddress`:3100"
  }
} | ConvertTo-Json -Depth 5
