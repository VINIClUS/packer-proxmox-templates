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
  [string]$PrometheusVersion = "3.12.0",
  [string]$LokiVersion = "3.7.2",
  [switch]$SkipCreate,
  [switch]$SkipHealthChecks
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
    [Parameter(Mandatory = $true)][string]$Command
  )

  $output = & ssh -i $script:SshKey -p $script:SshPort -o BatchMode=yes -o StrictHostKeyChecking=accept-new $script:SshTarget $Command 2>&1
  if ($LASTEXITCODE -ne 0) {
    $output
    throw "Remote Proxmox command failed with exit code $LASTEXITCODE."
  }
  return ($output -join "`n")
}

function Invoke-ProxmoxBash {
  param([Parameter(Mandatory = $true)][string]$Script)

  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
  $output = & ssh -i $script:SshKey -p $script:SshPort -o BatchMode=yes -o StrictHostKeyChecking=accept-new $script:SshTarget "echo $encoded | base64 -d | bash -se" 2>&1
  if ($LASTEXITCODE -ne 0) {
    $output
    throw "Remote Proxmox bash script failed with exit code $LASTEXITCODE."
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
  $remoteTemp = "/tmp/codex-monitoring-$Ctid-$([guid]::NewGuid().ToString("N"))"

  $pushScript = @"
set -euo pipefail
cat > '$remoteTemp.b64' <<'PUSH_PAYLOAD'
$encoded
PUSH_PAYLOAD
base64 -d '$remoteTemp.b64' > '$remoteTemp'
pct exec $Ctid -- mkdir -p $remoteDir
pct push $Ctid '$remoteTemp' $remotePath --perms $remoteMode >/dev/null
pct exec $Ctid -- chown $remoteOwner $remotePath
rm -f '$remoteTemp' '$remoteTemp.b64'
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
systemctl is-active prometheus grafana-server loki alloy >/dev/null
curl -fsS http://127.0.0.1:9090/-/ready >/dev/null
printf 'prometheus=ready\n'
curl -fsS http://127.0.0.1:3000/api/health >/dev/null
printf 'grafana=ready\n'
curl -fsS http://127.0.0.1:3100/ready >/dev/null
printf 'loki=ready\n'
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
if (-not $ctExists) {
  if ($SkipCreate) {
    throw "CTID $Ctid ($Hostname) does not exist and -SkipCreate was set."
  }

  $rootfs = "$Storage`:$RootfsSize"
  $net0 = "name=eth0,bridge=$Bridge,ip=$IpCidr,gw=$Gateway,firewall=1"
  $createScript = @"
set -euo pipefail
pct create $Ctid $(ConvertTo-ShellSingleQuoted -Value $Template) \
  --hostname $(ConvertTo-ShellSingleQuoted -Value $Hostname) \
  --rootfs $(ConvertTo-ShellSingleQuoted -Value $rootfs) \
  --cores $Cores --memory $MemoryMb --swap $SwapMb \
  --net0 $(ConvertTo-ShellSingleQuoted -Value $net0) \
  --unprivileged 1 --features nesting=1,keyctl=1 --ostype debian --onboot 1 \
  --description $(ConvertTo-ShellSingleQuoted -Value "CTID 190 monitoring-core provisioned by scripts/monitoring/Provision-MonitoringCore.ps1. No secrets.")
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

install -d -m 0755 /etc/apt/keyrings
if [ ! -s /etc/apt/keyrings/grafana.gpg ]; then
  wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
fi
chmod 0644 /etc/apt/keyrings/grafana.gpg
cat >/etc/apt/sources.list.d/grafana.list <<'APT'
deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main
APT
apt-get update -qq
apt-get install -y -qq grafana alloy >/dev/null

id prometheus >/dev/null 2>&1 || useradd --system --user-group --home-dir /var/lib/prometheus --shell /usr/sbin/nologin prometheus
install -d -o prometheus -g prometheus -m 0755 /etc/prometheus /var/lib/prometheus
install -d -o root -g root -m 0755 /usr/local/share/prometheus

prom_tmp="`$(mktemp -d)"
curl -fsSL "https://github.com/prometheus/prometheus/releases/download/v$PrometheusVersion/prometheus-$PrometheusVersion.linux-amd64.tar.gz" -o "`$prom_tmp/prometheus.tar.gz"
tar -xzf "`$prom_tmp/prometheus.tar.gz" -C "`$prom_tmp"
prom_dir="`$prom_tmp/prometheus-$PrometheusVersion.linux-amd64"
install -m 0755 "`$prom_dir/prometheus" /usr/local/bin/prometheus
install -m 0755 "`$prom_dir/promtool" /usr/local/bin/promtool
rm -rf /usr/local/share/prometheus/consoles /usr/local/share/prometheus/console_libraries
cp -R "`$prom_dir/consoles" /usr/local/share/prometheus/consoles
cp -R "`$prom_dir/console_libraries" /usr/local/share/prometheus/console_libraries
rm -rf "`$prom_tmp"
chown -R root:root /usr/local/share/prometheus

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
  --web.console.templates=/usr/local/share/prometheus/consoles \
  --web.console.libraries=/usr/local/share/prometheus/console_libraries \
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
curl -fsSL "https://github.com/grafana/loki/releases/download/v$LokiVersion/loki-linux-amd64.zip" -o "`$loki_tmp/loki.zip"
unzip -q -o "`$loki_tmp/loki.zip" -d "`$loki_tmp"
loki_bin="`$(find "`$loki_tmp" -maxdepth 1 -type f -name 'loki*' | head -1)"
install -m 0755 "`$loki_bin" /usr/local/bin/loki
rm -rf "`$loki_tmp"

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

Push-ContainerFile -Path "/etc/prometheus/prometheus.yml" -Content $prometheusConfig -Owner "prometheus" -Group "prometheus" -Mode "0644"
Push-ContainerFile -Path "/etc/loki/loki.yml" -Content $lokiConfig -Owner "loki" -Group "loki" -Mode "0644"
Push-ContainerFile -Path "/etc/alloy/config.alloy" -Content $alloyConfig -Owner "root" -Group "alloy" -Mode "0640"
Push-ContainerFile -Path "/etc/grafana/provisioning/datasources/datasources.yml" -Content $grafanaDatasourceConfig -Owner "root" -Group "grafana" -Mode "0640"

Invoke-ContainerBash -Script @'
set -euo pipefail
systemctl daemon-reload
systemctl enable prometheus grafana-server loki alloy >/dev/null
systemctl restart prometheus grafana-server loki alloy
'@ | Out-Null

$serviceStates = Get-ContainerServiceStates
$readiness = Test-ContainerReadiness

[ordered]@{
  ctid = $Ctid
  hostname = $Hostname
  ip = $ipAddress
  services = $serviceStates
  readiness = $readiness
  endpoints = [ordered]@{
    prometheus = "http://$ipAddress`:9090"
    grafana = "http://$ipAddress`:3000"
    loki = "http://$ipAddress`:3100"
  }
} | ConvertTo-Json -Depth 5
