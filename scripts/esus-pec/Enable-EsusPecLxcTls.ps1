param(
  [string]$ConfigFile = "config/Proxmox.pkrvars.hcl",
  [string]$ProxyCtid = "",
  [string]$ProxyIp = "",
  [string]$ProxyExpectedHostname = "",
  [string]$AppCtid = "",
  [string]$PecIp = "",
  [string]$Domain = "",
  [string]$PublicIp = "",
  [string]$LetsEncryptEmail = "",
  [string]$InfisicalUrl = "",
  [string]$InfisicalWorkspaceId = "",
  [string]$InfisicalProjectSlug = "",
  [string]$InfisicalEnvironment = "",
  [string]$InfisicalSecretPath = "/test/InstallationConfig/TLS",
  [switch]$ForceRenewCertificate,
  [switch]$UseStaging,
  [switch]$RegisterWithoutEmail,
  [switch]$SkipPublicAcmePreflight,
  [switch]$SkipRenewDryRun,
  [switch]$DisableApplicationNginx,
  [switch]$SkipInfisical
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\InfisicalEndpoint.ps1")

$envFile = ".env"
$resolvedProxyCtid = [int](Resolve-InfisicalSetting -Name "EDGE_PROXY_LXC_CTID" -CurrentValue $ProxyCtid -EnvFilePath $envFile)
$resolvedProxyIp = Resolve-InfisicalSetting -Name "EDGE_PROXY_LXC_IP" -CurrentValue $ProxyIp -EnvFilePath $envFile
$resolvedProxyExpectedHostname = Resolve-InfisicalSetting -Name "EDGE_PROXY_LXC_NAME" -CurrentValue $ProxyExpectedHostname -EnvFilePath $envFile
$resolvedProductionUpstreamUrl = Resolve-InfisicalSetting -Name "ESUS_PEC_PRODUCTION_UPSTREAM_URL" -CurrentValue "" -EnvFilePath $envFile
if (-not [uri]::IsWellFormedUriString($resolvedProductionUpstreamUrl, [System.UriKind]::Absolute)) {
  throw "Invalid ESUS_PEC_PRODUCTION_UPSTREAM_URL '$resolvedProductionUpstreamUrl'. Provide an absolute URL."
}
$resolvedProductionUpstreamUrl = $resolvedProductionUpstreamUrl.TrimEnd("/")
$resolvedPecIp = if (-not [string]::IsNullOrWhiteSpace($PecIp)) { $PecIp } else { ([uri]$resolvedProductionUpstreamUrl).Host }
$resolvedDomain = Resolve-InfisicalSetting -Name "ESUS_PEC_PRODUCTION_DOMAIN" -CurrentValue $Domain -EnvFilePath $envFile
$resolvedPublicIp = Resolve-InfisicalSetting -Name "PUBLIC_IP" -CurrentValue $PublicIp -EnvFilePath $envFile
$resolvedAppCtid = $null
if ($DisableApplicationNginx) {
  $resolvedAppCtid = [int](Resolve-InfisicalSetting -Name "ESUS_PEC_LXC_CTID" -CurrentValue $AppCtid -EnvFilePath $envFile)
}

if (-not $RegisterWithoutEmail) {
  $LetsEncryptEmail = Resolve-InfisicalSetting -Name "LETSENCRYPT_EMAIL" -CurrentValue $LetsEncryptEmail -EnvFilePath $envFile
  if ($LetsEncryptEmail -notmatch "^[^@\s]+@[^@\s]+\.[^@\s]+$") {
    throw "Invalid LETSENCRYPT_EMAIL. Provide a valid ACME contact e-mail or explicitly pass -RegisterWithoutEmail."
  }
}

$parsedPecIp = $null
if (-not [System.Net.IPAddress]::TryParse($resolvedPecIp, [ref]$parsedPecIp)) {
  throw "Invalid production upstream IP '$resolvedPecIp'."
}
$parsedProxyIp = $null
if (-not [System.Net.IPAddress]::TryParse($resolvedProxyIp, [ref]$parsedProxyIp)) {
  throw "Invalid EDGE_PROXY_LXC_IP '$resolvedProxyIp'."
}
$parsedPublicIp = $null
if (-not [System.Net.IPAddress]::TryParse($resolvedPublicIp, [ref]$parsedPublicIp)) {
  throw "Invalid PUBLIC_IP '$resolvedPublicIp'."
}

if (-not $SkipInfisical) {
  $InfisicalUrl = Resolve-InfisicalUrl -CurrentValue $InfisicalUrl -EnvFilePath $envFile
  $InfisicalWorkspaceId = Resolve-InfisicalSetting -Name "INFISICAL_WORKSPACE_ID" -CurrentValue $InfisicalWorkspaceId -EnvFilePath $envFile
  $InfisicalProjectSlug = Resolve-InfisicalSetting -Name "INFISICAL_PROJECT_SLUG" -CurrentValue $InfisicalProjectSlug -EnvFilePath $envFile
  $InfisicalEnvironment = Resolve-InfisicalSetting -Name "INFISICAL_ENVIRONMENT" -CurrentValue $InfisicalEnvironment -EnvFilePath $envFile
}

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
  if ($env:infisical_secret_key) { return $env:infisical_secret_key }
  if ($env:INFISICAL_TOKEN) { return $env:INFISICAL_TOKEN }
  if (Test-Path -LiteralPath ".env") {
    foreach ($candidate in @("infisical_secret_key", "INFISICAL_TOKEN")) {
      $line = Get-Content -LiteralPath ".env" | Where-Object { $_ -match ("^" + [regex]::Escape($candidate) + "=") } | Select-Object -First 1
      if ($line) {
        $value = (($line -split "=", 2)[1]).Trim().Trim('"').Trim("'")
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
      }
    }
  }
  throw "Infisical token not found. Set infisical_secret_key in .env or INFISICAL_TOKEN in the environment."
}

function Ensure-InfisicalFolderPath {
  param(
    [Parameter(Mandatory = $true)][string]$SecretPath,
    [Parameter(Mandatory = $true)][hashtable]$Headers
  )

  $segments = @($SecretPath.Trim("/") -split "/" | Where-Object { $_ -ne "" })
  if ($segments.Count -eq 0) { return }

  $parent = "/"
  foreach ($segment in $segments) {
    $listUri = "$InfisicalUrl/api/v1/folders?workspaceId=$InfisicalWorkspaceId&environment=$InfisicalEnvironment&path=$([uri]::EscapeDataString($parent))"
    $folders = Invoke-RestMethod -Method Get -Uri $listUri -Headers $Headers -TimeoutSec 30

    if (@($folders.folders | Where-Object { $_.name -eq $segment }).Count -eq 0) {
      $body = @{
        workspaceId = $InfisicalWorkspaceId
        environment = $InfisicalEnvironment
        name = $segment
        path = $parent
      } | ConvertTo-Json -Compress

      try {
        $null = Invoke-RestMethod -Method Post -Uri "$InfisicalUrl/api/v1/folders" -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
      } catch {
        if (-not $_.Exception.Response -or $_.Exception.Response.StatusCode.value__ -ne 409) { throw }
      }
    }

    if ($parent -eq "/") { $parent = "/$segment" } else { $parent = "$parent/$segment" }
  }
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
    Ensure-InfisicalFolderPath -SecretPath $InfisicalSecretPath -Headers $Headers
    $null = Invoke-RestMethod -Method Post -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
  }
}

function Convert-ToBase64 {
  param([AllowEmptyString()][string]$Value)
  return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
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
$domainB64 = Convert-ToBase64 -Value $resolvedDomain
$pecIpB64 = Convert-ToBase64 -Value $resolvedPecIp
$productionUpstreamUrlB64 = Convert-ToBase64 -Value $resolvedProductionUpstreamUrl
$proxyIpB64 = Convert-ToBase64 -Value $resolvedProxyIp
$proxyExpectedHostnameB64 = Convert-ToBase64 -Value $resolvedProxyExpectedHostname
$publicIpB64 = Convert-ToBase64 -Value $resolvedPublicIp
$emailB64 = Convert-ToBase64 -Value $LetsEncryptEmail
$emailMode = if ($RegisterWithoutEmail) { "none" } else { "email" }
$forceRenew = if ($ForceRenewCertificate) { "1" } else { "0" }
$staging = if ($UseStaging) { "1" } else { "0" }
$renewDryRun = if ($SkipRenewDryRun) { "0" } else { "1" }
$publicAcmePreflight = if ($SkipPublicAcmePreflight) { "0" } else { "1" }

$applyScript = @"
set -euo pipefail
exec 2>&1

DOMAIN="`$(printf '%s' '$domainB64' | base64 -d)"
PEC_IP="`$(printf '%s' '$pecIpB64' | base64 -d)"
PEC_UPSTREAM_URL="`$(printf '%s' '$productionUpstreamUrlB64' | base64 -d)"
PROXY_IP="`$(printf '%s' '$proxyIpB64' | base64 -d)"
PROXY_EXPECTED_HOSTNAME="`$(printf '%s' '$proxyExpectedHostnameB64' | base64 -d)"
PUBLIC_IP="`$(printf '%s' '$publicIpB64' | base64 -d)"
LE_EMAIL="`$(printf '%s' '$emailB64' | base64 -d)"
EMAIL_MODE="$emailMode"
FORCE_RENEW="$forceRenew"
USE_STAGING="$staging"
RUN_RENEW_DRY_RUN="$renewDryRun"
PUBLIC_ACME_PREFLIGHT="$publicAcmePreflight"

WEBROOT="/var/www/letsencrypt"
NGINX_SITE="/etc/nginx/sites-available/esus-pec-tls.conf"
CERT_LIVE="/etc/letsencrypt/live/`$DOMAIN"
LE_CERT="`$CERT_LIVE/fullchain.pem"
LE_KEY="`$CERT_LIVE/privkey.pem"
BOOTSTRAP_DIR="/etc/esus-pec/tls"
BOOTSTRAP_CERT="`$BOOTSTRAP_DIR/bootstrap.crt"
BOOTSTRAP_KEY="`$BOOTSTRAP_DIR/bootstrap.key"
DEPLOY_HOOK="/etc/letsencrypt/renewal-hooks/deploy/esus-pec-nginx-reload.sh"

resolved_public="`$(getent ahostsv4 "`$DOMAIN" | awk 'NR == 1 { print `$1 }')"
if [ "`$resolved_public" != "`$PUBLIC_IP" ]; then
  echo "DNS_PUBLIC_IP_MISMATCH=expected:`$PUBLIC_IP actual:`$resolved_public"
  exit 1
fi

actual_hostname="`$(hostname -s)"
if [ "`$actual_hostname" != "`$PROXY_EXPECTED_HOSTNAME" ]; then
  echo "PROXY_HOSTNAME_MISMATCH=expected:`$PROXY_EXPECTED_HOSTNAME actual:`$actual_hostname"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends nginx ca-certificates curl openssl certbot python3-certbot-nginx

install -d -m 0755 "`$WEBROOT/.well-known/acme-challenge"
install -d -m 0700 "`$BOOTSTRAP_DIR"

if [ ! -s "`$BOOTSTRAP_CERT" ] || [ ! -s "`$BOOTSTRAP_KEY" ]; then
  openssl req -x509 -newkey rsa:2048 -sha256 -days 7 -nodes \
    -keyout "`$BOOTSTRAP_KEY" \
    -out "`$BOOTSTRAP_CERT" \
    -subj "/CN=`$DOMAIN" \
    -addext "subjectAltName=DNS:`$DOMAIN,IP:`$PROXY_IP" >/dev/null 2>&1
  chmod 0600 "`$BOOTSTRAP_KEY"
  chmod 0644 "`$BOOTSTRAP_CERT"
fi

write_nginx_site() {
  cert_path="`$1"
  key_path="`$2"
  cat > "`$NGINX_SITE" <<'NGINX'
server {
    listen 80;
    server_name __DOMAIN__;

    location ^~ /.well-known/acme-challenge/ {
        root __WEBROOT__;
        default_type "text/plain";
    }

    location / {
        return 301 https://`$host`$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name __DOMAIN__;

    ssl_certificate __CERT_PATH__;
    ssl_certificate_key __KEY_PATH__;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    client_max_body_size 100m;

    location / {
        proxy_pass __PEC_UPSTREAM_URL__;
        proxy_http_version 1.1;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade `$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_ssl_server_name on;
        proxy_ssl_verify off;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
NGINX
  sed -i \
    -e "s#__DOMAIN__#`$DOMAIN#g" \
    -e "s#__WEBROOT__#`$WEBROOT#g" \
    -e "s#__CERT_PATH__#`$cert_path#g" \
    -e "s#__KEY_PATH__#`$key_path#g" \
    -e "s#__PEC_UPSTREAM_URL__#`$PEC_UPSTREAM_URL#g" \
    "`$NGINX_SITE"
}

if [ -s "`$LE_CERT" ] && [ -s "`$LE_KEY" ]; then
  write_nginx_site "`$LE_CERT" "`$LE_KEY"
else
  write_nginx_site "`$BOOTSTRAP_CERT" "`$BOOTSTRAP_KEY"
fi

rm -f /etc/nginx/sites-enabled/default
ln -sfn "`$NGINX_SITE" /etc/nginx/sites-enabled/esus-pec-tls.conf
nginx -t
systemctl enable --now nginx >/dev/null
systemctl reload nginx

challenge_name="codex-preflight-`$(date +%s)"
printf 'ok\n' > "`$WEBROOT/.well-known/acme-challenge/`$challenge_name"
curl -fsS --max-time 10 --resolve "`$DOMAIN:80:127.0.0.1" "http://`$DOMAIN/.well-known/acme-challenge/`$challenge_name" >/dev/null
pec_upstream_status="`$(curl --insecure -sS -o /dev/null -w '%{http_code}' --max-time 20 "`$PEC_UPSTREAM_URL/" || true)"
if [ "`$pec_upstream_status" != "200" ]; then
  echo "PEC_UPSTREAM_HTTP_STATUS=`$pec_upstream_status"
  exit 1
fi
if [ "`$PUBLIC_ACME_PREFLIGHT" = "1" ]; then
  public_http_status="`$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "http://`$DOMAIN/.well-known/acme-challenge/`$challenge_name" || true)"
else
  public_http_status="skipped"
fi
rm -f "`$WEBROOT/.well-known/acme-challenge/`$challenge_name"
if [ "`$PUBLIC_ACME_PREFLIGHT" = "1" ] && [ "`$public_http_status" != "200" ]; then
  echo "ACME_PUBLIC_HTTP_STATUS=`$public_http_status"
  exit 1
fi

certbot_args=(certonly --webroot -w "`$WEBROOT" -d "`$DOMAIN" --agree-tos --non-interactive --keep-until-expiring)
if [ "`$EMAIL_MODE" = "email" ]; then
  certbot_args+=(--email "`$LE_EMAIL")
else
  certbot_args+=(--register-unsafely-without-email)
fi
if [ "`$FORCE_RENEW" = "1" ]; then
  certbot_args+=(--force-renewal)
fi
if [ "`$USE_STAGING" = "1" ]; then
  certbot_args+=(--staging)
fi

certbot "`${certbot_args[@]}"

write_nginx_site "`$LE_CERT" "`$LE_KEY"
nginx -t
systemctl reload nginx

install -d -m 0755 "`$(dirname "`$DEPLOY_HOOK")"
cat > "`$DEPLOY_HOOK" <<'HOOK'
#!/bin/sh
set -eu
nginx -t >/dev/null
systemctl reload nginx
HOOK
chmod 0755 "`$DEPLOY_HOOK"

timer_present=false
timer_active=inactive
if systemctl list-unit-files certbot.timer --no-pager 2>/dev/null | grep -q '^certbot.timer'; then
  timer_present=true
  systemctl enable --now certbot.timer >/dev/null
  timer_active="`$(systemctl is-active certbot.timer || true)"
fi

cron_present=false
if [ -f /etc/cron.d/certbot ]; then
  cron_present=true
fi

if [ "`$timer_present" != "true" ] && [ "`$cron_present" != "true" ]; then
  echo "CERTBOT_RENEWAL_SCHEDULER_MISSING=true"
  exit 1
fi

renew_status=skipped
if [ "`$RUN_RENEW_DRY_RUN" = "1" ]; then
  certbot renew --cert-name "`$DOMAIN" --dry-run --non-interactive --no-random-sleep-on-renew
  renew_status=success
fi

https_status="`$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 --resolve "`$DOMAIN:443:`$PROXY_IP" "https://`$DOMAIN/" || true)"
if [ "`$https_status" != "200" ]; then
  echo "HTTPS_VALIDATE_STATUS=`$https_status"
  exit 1
fi

fingerprint="`$(openssl x509 -in "`$LE_CERT" -noout -fingerprint -sha256 | sed 's/^sha256 Fingerprint=//;s/^SHA256 Fingerprint=//')"
not_after="`$(openssl x509 -in "`$LE_CERT" -noout -enddate | cut -d= -f2-)"
issuer="`$(openssl x509 -in "`$LE_CERT" -noout -issuer | sed 's/^issuer=//')"
san="`$(openssl x509 -in "`$LE_CERT" -noout -ext subjectAltName | tail -n +2 | tr -d ' ')"

printf 'TLS_READY=1\n'
printf 'DOMAIN=%s\n' "`$DOMAIN"
printf 'PUBLIC_IP=%s\n' "`$PUBLIC_IP"
printf 'PROXY_IP=%s\n' "`$PROXY_IP"
printf 'PROXY_HOSTNAME=%s\n' "`$actual_hostname"
printf 'PEC_IP=%s\n' "`$PEC_IP"
printf 'PEC_UPSTREAM_URL=%s\n' "`$PEC_UPSTREAM_URL"
printf 'HTTPS_URL=https://%s/\n' "`$DOMAIN"
printf 'CERT_SHA256=%s\n' "`$fingerprint"
printf 'CERT_NOT_AFTER=%s\n' "`$not_after"
printf 'CERT_ISSUER=%s\n' "`$issuer"
printf 'CERT_SAN=%s\n' "`$san"
printf 'CERTBOT_VERSION=%s\n' "`$(certbot --version | awk '{print `$2}')"
printf 'CERTBOT_TIMER_PRESENT=%s\n' "`$timer_present"
printf 'CERTBOT_TIMER_ACTIVE=%s\n' "`$timer_active"
printf 'CERTBOT_CRON_PRESENT=%s\n' "`$cron_present"
printf 'CERTBOT_RENEW_DRY_RUN_STATUS=%s\n' "`$renew_status"
printf 'ACME_PUBLIC_HTTP_STATUS=%s\n' "`$public_http_status"
printf 'HTTPS_VALIDATE_STATUS=%s\n' "`$https_status"
printf 'PEC_UPSTREAM_HTTP_STATUS=%s\n' "`$pec_upstream_status"
printf 'NGINX_ACTIVE=%s\n' "`$(systemctl is-active nginx)"
"@

$applyOutput = Invoke-ContainerScript -Target $target -Port $sshPort -KeyFile $sshKey -ContainerId $resolvedProxyCtid -Script $applyScript

$metadata = @{}
foreach ($line in ($applyOutput -split "`n")) {
  if ($line -match "^([A-Z0-9_]+)=(.*)$") {
    $metadata[$Matches[1]] = $Matches[2]
  }
}

$certPem = Invoke-ContainerScript -Target $target -Port $sshPort -KeyFile $sshKey -ContainerId $resolvedProxyCtid -Script "cat /etc/letsencrypt/live/$resolvedDomain/fullchain.pem"
$keyPem = Invoke-ContainerScript -Target $target -Port $sshPort -KeyFile $sshKey -ContainerId $resolvedProxyCtid -Script "cat /etc/letsencrypt/live/$resolvedDomain/privkey.pem"

$applicationCleanup = [ordered]@{
  attempted = $false
  ctid = $resolvedAppCtid
  nginxActive = "not-requested"
  nginxExporterActive = "not-requested"
}

if ($DisableApplicationNginx) {
  $cleanupScript = @'
set -euo pipefail
if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now nginx >/dev/null 2>&1 || true
  systemctl disable --now prometheus-nginx-exporter >/dev/null 2>&1 || true
fi
rm -f /etc/nginx/sites-enabled/esus-pec-tls.conf 2>/dev/null || true
printf 'APP_NGINX_ACTIVE=%s\n' "$(systemctl is-active nginx 2>/dev/null || true)"
printf 'APP_NGINX_EXPORTER_ACTIVE=%s\n' "$(systemctl is-active prometheus-nginx-exporter 2>/dev/null || true)"
'@
  $cleanupOutput = Invoke-ContainerScript -Target $target -Port $sshPort -KeyFile $sshKey -ContainerId $resolvedAppCtid -Script $cleanupScript
  $applicationCleanup["attempted"] = $true
  foreach ($line in ($cleanupOutput -split "`n")) {
    if ($line -match "^APP_NGINX_ACTIVE=(.*)$") { $applicationCleanup["nginxActive"] = $Matches[1] }
    if ($line -match "^APP_NGINX_EXPORTER_ACTIVE=(.*)$") { $applicationCleanup["nginxExporterActive"] = $Matches[1] }
  }
}

if (-not $SkipInfisical) {
  $token = Get-InfisicalToken
  $headers = @{ Authorization = "Bearer $token" }
  $secrets = [ordered]@{
    ESUS_PEC_TLS_CERTIFICATE_PEM = $certPem.Trim()
    ESUS_PEC_TLS_PRIVATE_KEY_PEM = $keyPem.Trim()
    ESUS_PEC_TLS_HTTPS_URL = "https://$resolvedDomain/"
    ESUS_PEC_TLS_CERTIFICATE_SHA256 = [string]$metadata["CERT_SHA256"]
    ESUS_PEC_TLS_CERTIFICATE_NOT_AFTER = [string]$metadata["CERT_NOT_AFTER"]
    ESUS_PEC_TLS_CERTIFICATE_SAN = [string]$metadata["CERT_SAN"]
    ESUS_PEC_TLS_CERTIFICATE_KIND = "letsencrypt"
    ESUS_PEC_TLS_TERMINATION = "nginx-edge-lxc-certbot"
    ESUS_PEC_TLS_DOMAIN = $resolvedDomain
    ESUS_PEC_TLS_PUBLIC_IP = $resolvedPublicIp
    ESUS_PEC_TLS_PROXY_LXC_CTID = [string]$resolvedProxyCtid
    ESUS_PEC_TLS_PROXY_LXC_IP = $resolvedProxyIp
    ESUS_PEC_TLS_PROXY_LXC_NAME = $resolvedProxyExpectedHostname
    ESUS_PEC_TLS_UPSTREAM_LXC_IP = $resolvedPecIp
    ESUS_PEC_TLS_UPSTREAM_URL = $resolvedProductionUpstreamUrl
    ESUS_PEC_TLS_LETSENCRYPT_EMAIL = $LetsEncryptEmail
    ESUS_PEC_TLS_CERTBOT_VERSION = [string]$metadata["CERTBOT_VERSION"]
    ESUS_PEC_TLS_CERTBOT_TIMER_PRESENT = [string]$metadata["CERTBOT_TIMER_PRESENT"]
    ESUS_PEC_TLS_CERTBOT_TIMER_ACTIVE = [string]$metadata["CERTBOT_TIMER_ACTIVE"]
    ESUS_PEC_TLS_CERTBOT_CRON_PRESENT = [string]$metadata["CERTBOT_CRON_PRESENT"]
    ESUS_PEC_TLS_CERTBOT_RENEW_DRY_RUN_STATUS = [string]$metadata["CERTBOT_RENEW_DRY_RUN_STATUS"]
    ESUS_PEC_TLS_ACME_PUBLIC_HTTP_STATUS = [string]$metadata["ACME_PUBLIC_HTTP_STATUS"]
    ESUS_PEC_TLS_UPSTREAM_HTTP_STATUS = [string]$metadata["PEC_UPSTREAM_HTTP_STATUS"]
    ESUS_PEC_TLS_LAST_VALIDATED_AT = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  }

  foreach ($entry in $secrets.GetEnumerator()) {
    Set-InfisicalSecret -Name $entry.Key -Value $entry.Value -Headers $headers
  }
}

[ordered]@{
  proxyCtid = $resolvedProxyCtid
  proxyIp = $resolvedProxyIp
  proxyName = $resolvedProxyExpectedHostname
  applicationCtid = $resolvedAppCtid
  domain = $resolvedDomain
  publicIp = $resolvedPublicIp
  pecIp = $resolvedPecIp
  pecUpstreamUrl = $resolvedProductionUpstreamUrl
  httpsUrl = "https://$resolvedDomain/"
  nginxActive = [string]$metadata["NGINX_ACTIVE"]
  pecUpstreamHttpStatus = [string]$metadata["PEC_UPSTREAM_HTTP_STATUS"]
  certificateIssuer = [string]$metadata["CERT_ISSUER"]
  certificateSha256 = [string]$metadata["CERT_SHA256"]
  certificateNotAfter = [string]$metadata["CERT_NOT_AFTER"]
  certbotTimerPresent = [string]$metadata["CERTBOT_TIMER_PRESENT"]
  certbotTimerActive = [string]$metadata["CERTBOT_TIMER_ACTIVE"]
  certbotCronPresent = [string]$metadata["CERTBOT_CRON_PRESENT"]
  certbotRenewDryRunStatus = [string]$metadata["CERTBOT_RENEW_DRY_RUN_STATUS"]
  acmePublicHttpStatus = [string]$metadata["ACME_PUBLIC_HTTP_STATUS"]
  httpsValidateStatus = [string]$metadata["HTTPS_VALIDATE_STATUS"]
  applicationNginxCleanup = $applicationCleanup
  infisicalUpdated = (-not $SkipInfisical.IsPresent)
} | ConvertTo-Json -Depth 3
