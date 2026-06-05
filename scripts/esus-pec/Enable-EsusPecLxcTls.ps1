param(
  [string]$ConfigFile = "config/Proxmox.pkrvars.hcl",
  [int]$Ctid = 133,
  [string]$PecIp = "192.168.1.209",
  [string]$PrimaryDnsName = "esus-pec-lxc-5437",
  [int]$CertificateDays = 825,
  [string]$InfisicalUrl = "http://192.168.1.226:8080",
  [string]$InfisicalWorkspaceId = "2c83cfe9-e794-4961-977d-23000ae14461",
  [string]$InfisicalProjectSlug = "esus-pec-z-px-c",
  [string]$InfisicalEnvironment = "dev",
  [string]$InfisicalSecretPath = "/test/InstallationConfig",
  [switch]$ForceRotateCertificate,
  [switch]$SkipInfisical
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

  if (-not $line) {
    return $Default
  }

  return (($line -split "=", 2)[1]).Trim().Trim('"')
}

function Invoke-ProxmoxSsh {
  param(
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$Port,
    [Parameter(Mandatory = $true)][string]$KeyFile,
    [Parameter(Mandatory = $true)][string]$RemoteCommand
  )

  $output = & ssh -i $KeyFile -p $Port -o BatchMode=yes -o StrictHostKeyChecking=accept-new $Target $RemoteCommand 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "Remote SSH command failed with exit code $LASTEXITCODE. Output: $($output -join "`n")"
  }
  return ($output -join "`n")
}

function Invoke-ContainerScript {
  param(
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$Port,
    [Parameter(Mandatory = $true)][string]$KeyFile,
    [Parameter(Mandatory = $true)][int]$ContainerId,
    [Parameter(Mandatory = $true)][string]$Script
  )

  $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Script))
  $remoteCommand = "printf %s $encoded | base64 -d | pct exec $ContainerId -- bash -s"
  return Invoke-ProxmoxSsh -Target $Target -Port $Port -KeyFile $KeyFile -RemoteCommand $remoteCommand
}

function Get-InfisicalToken {
  if ($env:infisical_secret_key) {
    return $env:infisical_secret_key
  }
  if ($env:INFISICAL_TOKEN) {
    return $env:INFISICAL_TOKEN
  }
  if (Test-Path -LiteralPath ".env") {
    $line = Get-Content -LiteralPath ".env" | Where-Object { $_ -match "^infisical_secret_key=" } | Select-Object -First 1
    if ($line) {
      return (($line -split "=", 2)[1]).Trim()
    }
  }
  throw "Infisical token not found. Set infisical_secret_key in .env or INFISICAL_TOKEN in the environment."
}

function Set-InfisicalSecret {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][hashtable]$Headers
  )

  $uri = "$InfisicalUrl/api/v3/secrets/raw/$([uri]::EscapeDataString($Name))"
  $body = @{
    environment = $InfisicalEnvironment
    workspaceId = $InfisicalWorkspaceId
    projectSlug = $InfisicalProjectSlug
    secretPath = $InfisicalSecretPath
    secretValue = $Value
    skipMultilineEncoding = $true
    type = "shared"
    secretComment = "Managed by scripts/esus-pec/Enable-EsusPecLxcTls.ps1"
  } | ConvertTo-Json -Depth 5

  try {
    $null = Invoke-RestMethod -Method Patch -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
  } catch {
    $status = $_.Exception.Response.StatusCode.value__
    if ($status -ne 404) {
      throw "Failed to update Infisical secret $Name. HTTP status: $status"
    }
    $null = Invoke-RestMethod -Method Post -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
  }
}

$configText = Get-Content -LiteralPath $ConfigFile -Raw
$sshHost = Get-HclValue -Name "proxmox_ssh_host" -Text $configText
$sshPort = Get-HclValue -Name "proxmox_ssh_port" -Text $configText -Default "22"
$sshUser = Get-HclValue -Name "proxmox_ssh_user" -Text $configText -Default "root"
$sshKey = Get-HclValue -Name "proxmox_ssh_private_key_file" -Text $configText

if (-not $sshHost -or -not $sshKey) {
  throw "Missing proxmox_ssh_host or proxmox_ssh_private_key_file in $ConfigFile."
}

$target = "$sshUser@$sshHost"
$httpsUrl = "https://$PecIp/"
$rotateFlag = if ($ForceRotateCertificate) { "1" } else { "0" }

$applyScript = @"
set -euo pipefail
exec 2>&1

PEC_IP="$PecIp"
PRIMARY_DNS="$PrimaryDnsName"
CERT_DAYS="$CertificateDays"
FORCE_ROTATE="$rotateFlag"
TLS_DIR="/etc/esus-pec/tls"
CERT_FILE="`$TLS_DIR/tls.crt"
KEY_FILE="`$TLS_DIR/tls.key"
NGINX_SITE="/etc/nginx/sites-available/esus-pec-tls.conf"

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required inside the container" >&2
  exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends nginx ca-certificates
fi

install -d -m 0700 "`$TLS_DIR"

if [ "`$FORCE_ROTATE" = "1" ] || [ ! -s "`$CERT_FILE" ] || [ ! -s "`$KEY_FILE" ]; then
  tmpdir="`$(mktemp -d)"
  trap 'rm -rf "`$tmpdir"' EXIT
  openssl req -x509 -newkey rsa:4096 -sha256 -days "`$CERT_DAYS" -nodes \
    -keyout "`$tmpdir/tls.key" \
    -out "`$tmpdir/tls.crt" \
    -subj "/CN=`$PRIMARY_DNS" \
    -addext "subjectAltName=DNS:`$PRIMARY_DNS,DNS:localhost,IP:`$PEC_IP,IP:127.0.0.1" 2>/dev/null
  install -m 0600 "`$tmpdir/tls.key" "`$KEY_FILE"
  install -m 0644 "`$tmpdir/tls.crt" "`$CERT_FILE"
fi

cat > "`$NGINX_SITE" <<'NGINX'
server {
    listen 443 ssl;
    server_name _;

    ssl_certificate /etc/esus-pec/tls/tls.crt;
    ssl_certificate_key /etc/esus-pec/tls/tls.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    client_max_body_size 100m;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade `$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
NGINX

rm -f /etc/nginx/sites-enabled/default
ln -sfn "`$NGINX_SITE" /etc/nginx/sites-enabled/esus-pec-tls.conf
nginx -t
systemctl enable --now nginx >/dev/null
systemctl reload nginx

fingerprint="`$(openssl x509 -in "`$CERT_FILE" -noout -fingerprint -sha256 | sed 's/^sha256 Fingerprint=//;s/^SHA256 Fingerprint=//')"
not_after="`$(openssl x509 -in "`$CERT_FILE" -noout -enddate | cut -d= -f2-)"
subject="`$(openssl x509 -in "`$CERT_FILE" -noout -subject | sed 's/^subject=//')"
san="`$(openssl x509 -in "`$CERT_FILE" -noout -ext subjectAltName | tail -n +2 | tr -d ' ')"

printf 'TLS_READY=1\n'
printf 'HTTPS_URL=https://%s/\n' "`$PEC_IP"
printf 'CERT_SHA256=%s\n' "`$fingerprint"
printf 'CERT_NOT_AFTER=%s\n' "`$not_after"
printf 'CERT_SUBJECT=%s\n' "`$subject"
printf 'CERT_SAN=%s\n' "`$san"
printf 'NGINX_ACTIVE=%s\n' "`$(systemctl is-active nginx)"
printf 'PEC_ACTIVE=%s\n' "`$(systemctl is-active e-SUS-PEC.service)"
"@

$applyOutput = Invoke-ContainerScript -Target $target -Port $sshPort -KeyFile $sshKey -ContainerId $Ctid -Script $applyScript

$certPem = Invoke-ContainerScript -Target $target -Port $sshPort -KeyFile $sshKey -ContainerId $Ctid -Script "cat /etc/esus-pec/tls/tls.crt"
$keyPem = Invoke-ContainerScript -Target $target -Port $sshPort -KeyFile $sshKey -ContainerId $Ctid -Script "cat /etc/esus-pec/tls/tls.key"

$metadata = @{}
foreach ($line in ($applyOutput -split "`n")) {
  if ($line -match "^([A-Z0-9_]+)=(.*)$") {
    $metadata[$Matches[1]] = $Matches[2]
  }
}

if (-not $SkipInfisical) {
  $token = Get-InfisicalToken
  $headers = @{ Authorization = "Bearer $token" }
  $secrets = [ordered]@{
    ESUS_PEC_TLS_CERTIFICATE_PEM = $certPem.Trim()
    ESUS_PEC_TLS_PRIVATE_KEY_PEM = $keyPem.Trim()
    ESUS_PEC_TLS_HTTPS_URL = $httpsUrl
    ESUS_PEC_TLS_CERTIFICATE_SHA256 = [string]$metadata["CERT_SHA256"]
    ESUS_PEC_TLS_CERTIFICATE_NOT_AFTER = [string]$metadata["CERT_NOT_AFTER"]
    ESUS_PEC_TLS_CERTIFICATE_SAN = [string]$metadata["CERT_SAN"]
    ESUS_PEC_TLS_CERTIFICATE_KIND = "self-signed"
    ESUS_PEC_TLS_TERMINATION = "nginx-lxc"
  }

  foreach ($entry in $secrets.GetEnumerator()) {
    Set-InfisicalSecret -Name $entry.Key -Value $entry.Value -Headers $headers
  }
}

[ordered]@{
  ctid = $Ctid
  httpsUrl = $httpsUrl
  nginxActive = [string]$metadata["NGINX_ACTIVE"]
  pecActive = [string]$metadata["PEC_ACTIVE"]
  certificateSha256 = [string]$metadata["CERT_SHA256"]
  certificateNotAfter = [string]$metadata["CERT_NOT_AFTER"]
  infisicalUpdated = (-not $SkipInfisical.IsPresent)
} | ConvertTo-Json -Depth 3
