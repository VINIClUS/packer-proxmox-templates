param(
  [string]$ConfigFile = "config/Proxmox.pkrvars.hcl",
  [string]$ProxyCtid = "",
  [string]$ProxyIp = "",
  [string]$ProxyExpectedHostname = "",
  [string]$PublicIp = "",
  [string]$InfisicalUrl = "",
  [string]$InfisicalWorkspaceId = "",
  [string]$InfisicalProjectSlug = "",
  [string]$InfisicalEnvironment = "",
  [string]$EdgeProxySecretPath = "/test/EdgeProxy",
  [string]$InstallationSecretPath = "/test/InstallationConfig",
  [string]$MonitoringSecretPath = "/test/Monitoring",
  [string]$ObjectStorageSecretPath = "/test/ObjectStorage",
  [string]$CloudflareZoneId = "",
  [string]$CloudflareZoneName = "",
  [string]$CloudflareAccountId = "",
  [string]$CloudflareApiToken = "",
  [string]$PrometheusBasicAuthHtpasswd = "",
  [string]$PrometheusBasicAuthUsername = "",
  [string]$PrometheusBasicAuthPassword = "",
  [switch]$SkipCloudflare,
  [switch]$SkipInfisical,
  [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\InfisicalEndpoint.ps1")

$envFile = ".env"

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
  throw "Infisical token not found. Set infisical_secret_key in .env or INFISICAL_TOKEN."
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
    [Parameter(Mandatory = $true)][string]$SecretPath,
    [Parameter(Mandatory = $true)][string]$Name,
    [AllowEmptyString()][Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][hashtable]$Headers
  )

  $uri = "$InfisicalUrl/api/v3/secrets/raw/$([uri]::EscapeDataString($Name))"
  $body = @{
    environment = $InfisicalEnvironment
    workspaceId = $InfisicalWorkspaceId
    projectSlug = $InfisicalProjectSlug
    secretPath = $SecretPath
    secretValue = $Value
    skipMultilineEncoding = $true
    type = "shared"
    secretComment = "Managed by scripts/esus-pec/Configure-EdgeProxyRoutes.ps1"
  } | ConvertTo-Json -Depth 5

  try {
    $null = Invoke-RestMethod -Method Patch -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
    return "updated"
  } catch {
    $status = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { "unknown" }
    if ($status -ne 404) { throw "Failed to update Infisical secret $Name in $SecretPath. HTTP status: $status" }
    Ensure-InfisicalFolderPath -SecretPath $SecretPath -Headers $Headers
    $null = Invoke-RestMethod -Method Post -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
    return "created"
  }
}

function Remove-InfisicalSecret {
  param(
    [Parameter(Mandatory = $true)][string]$SecretPath,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][hashtable]$Headers
  )

  $uri = "$InfisicalUrl/api/v3/secrets/raw/$([uri]::EscapeDataString($Name))"
  $body = @{
    environment = $InfisicalEnvironment
    workspaceId = $InfisicalWorkspaceId
    secretPath = $SecretPath
    type = "shared"
  } | ConvertTo-Json -Depth 5

  $null = Invoke-RestMethod -Method Delete -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
}

function Test-InfisicalSecretPathWritable {
  param(
    [Parameter(Mandatory = $true)][string]$SecretPath,
    [Parameter(Mandatory = $true)][hashtable]$Headers
  )

  $probeName = "__EDGE_PROXY_WRITE_TEST_$([guid]::NewGuid().ToString("N"))"
  try {
    $null = Set-InfisicalSecret -SecretPath $SecretPath -Name $probeName -Value "probe" -Headers $Headers
    Remove-InfisicalSecret -SecretPath $SecretPath -Name $probeName -Headers $Headers
  } catch {
    $status = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { "unknown" }
    throw "Infisical path '$SecretPath' is not writable by the current token. Grant create/update/delete on this exact path before applying edge proxy routes with Infisical sync. HTTP status: $status"
  }
}

function Convert-ToBase64 {
  param([AllowEmptyString()][string]$Value)
  return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

function Resolve-RequiredUrl {
  param([Parameter(Mandatory = $true)][string]$Name)
  $value = Resolve-InfisicalSetting -Name $Name -CurrentValue "" -EnvFilePath $envFile
  if (-not [uri]::IsWellFormedUriString($value, [System.UriKind]::Absolute)) {
    throw "Invalid $Name '$value'. Provide an absolute upstream URL."
  }
  return $value.TrimEnd("/")
}

function Resolve-OptionalSetting {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [AllowEmptyString()][string]$CurrentValue = ""
  )

  if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
    return $CurrentValue.Trim()
  }

  $environmentValue = [Environment]::GetEnvironmentVariable($Name)
  if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
    return $environmentValue.Trim()
  }

  if (Test-Path -LiteralPath $envFile -PathType Leaf) {
    $line = Get-Content -LiteralPath $envFile | Where-Object { $_ -match ("^" + [regex]::Escape($Name) + "\s*=") } | Select-Object -First 1
    if ($line) {
      $value = (($line -split "=", 2)[1]).Trim().Trim('"').Trim("'")
      if (-not [string]::IsNullOrWhiteSpace($value)) {
        return $value
      }
    }
  }

  return ""
}

function New-Route {
  param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][string]$DomainVariable,
    [Parameter(Mandatory = $true)][string]$UpstreamVariable,
    [string]$HealthPath = "/",
    [string[]]$ExpectedStatuses = @("200", "301", "302", "401", "403"),
    [bool]$RequirePrometheusAuth = $false,
    [string]$ClientMaxBodySize = "100m"
  )

  $domain = Resolve-InfisicalSetting -Name $DomainVariable -CurrentValue "" -EnvFilePath $envFile
  $upstream = Resolve-RequiredUrl -Name $UpstreamVariable
  return [pscustomobject][ordered]@{
    id = $Id
    domainVariable = $DomainVariable
    upstreamVariable = $UpstreamVariable
    domain = $domain
    upstream = $upstream
    healthPath = $HealthPath
    expectedStatuses = $ExpectedStatuses
    requirePrometheusAuth = $RequirePrometheusAuth
    clientMaxBodySize = $ClientMaxBodySize
  }
}

function Get-NginxRouteBlock {
  param([Parameter(Mandatory = $true)][object]$Route)

  $uri = [uri]$Route.upstream
  $sslDirectives = ""
  if ($uri.Scheme -eq "https") {
    $sslDirectives = @"
        proxy_ssl_server_name on;
        proxy_ssl_verify off;
"@
  }

  $authDirectives = ""
  if ($Route.requirePrometheusAuth) {
    $authDirectives = @"
    auth_basic "Prometheus";
    auth_basic_user_file /etc/nginx/edge-proxy-prometheus.htpasswd;

"@
  }

  $routeBody = @"
    client_max_body_size $($Route.clientMaxBodySize);
$authDirectives
    location / {
        proxy_pass $($Route.upstream);
        proxy_http_version 1.1;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade `$http_upgrade;
        proxy_set_header Connection "upgrade";
$sslDirectives
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
"@

  return @"
server {
    listen 80;
    server_name $($Route.domain);
$routeBody
server {
    listen 443 ssl;
    server_name $($Route.domain);

    ssl_certificate /etc/nginx/edge-proxy-origin.crt;
    ssl_certificate_key /etc/nginx/edge-proxy-origin.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
$routeBody
"@
}

function Get-NginxDefaultServerBlock {
  return @"
server {
    listen 80 default_server;
    server_name _;

    return 404;
}

server {
    listen 443 ssl default_server;
    server_name _;

    ssl_certificate /etc/nginx/edge-proxy-origin.crt;
    ssl_certificate_key /etc/nginx/edge-proxy-origin.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    return 404;
}
"@
}

function Set-CloudflareDnsRecord {
  param(
    [Parameter(Mandatory = $true)][string]$ZoneId,
    [Parameter(Mandatory = $true)][string]$Token,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Content,
    [bool]$Proxied = $true
  )

  $headers = @{ Authorization = "Bearer $Token"; "Content-Type" = "application/json" }
  $escapedName = [uri]::EscapeDataString($Name)
  $list = Invoke-RestMethod -Method Get -Uri "https://api.cloudflare.com/client/v4/zones/$ZoneId/dns_records?type=A&name=$escapedName" -Headers $headers -TimeoutSec 30
  $body = @{
    type = "A"
    name = $Name
    content = $Content
    ttl = 1
    proxied = $Proxied
  } | ConvertTo-Json -Compress

  if (@($list.result).Count -gt 0) {
    $recordId = [string]$list.result[0].id
    $null = Invoke-RestMethod -Method Patch -Uri "https://api.cloudflare.com/client/v4/zones/$ZoneId/dns_records/$recordId" -Headers $headers -Body $body -TimeoutSec 30
    return "updated"
  }

  $null = Invoke-RestMethod -Method Post -Uri "https://api.cloudflare.com/client/v4/zones/$ZoneId/dns_records" -Headers $headers -Body $body -TimeoutSec 30
  return "created"
}

function Resolve-CloudflareToken {
  param([AllowEmptyString()][string]$CurrentValue = "")

  if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
    return $CurrentValue.Trim()
  }

  $named = Resolve-OptionalSetting -Name "CLOUDFLARE_API_TOKEN"
  if (-not [string]::IsNullOrWhiteSpace($named)) {
    return $named
  }

  $alias = Resolve-OptionalSetting -Name "CLOUDFLARE_TOKEN"
  if (-not [string]::IsNullOrWhiteSpace($alias)) {
    return $alias
  }

  throw "Missing required Cloudflare token. Set CLOUDFLARE_API_TOKEN or CLOUDFLARE_TOKEN."
}

function Resolve-CloudflareZoneId {
  param(
    [AllowEmptyString()][string]$CurrentZoneId = "",
    [Parameter(Mandatory = $true)][string]$Token,
    [AllowEmptyString()][string]$ZoneName = "",
    [AllowEmptyString()][string]$AccountId = ""
  )

  if (-not [string]::IsNullOrWhiteSpace($CurrentZoneId)) {
    return $CurrentZoneId.Trim()
  }

  $resolvedZoneName = Resolve-OptionalSetting -Name "CLOUDFLARE_ZONE_NAME_VINISANTANA" -CurrentValue $ZoneName
  if ([string]::IsNullOrWhiteSpace($resolvedZoneName)) {
    throw "Missing required Cloudflare zone name. Set CLOUDFLARE_ZONE_NAME_VINISANTANA when CLOUDFLARE_ZONE_ID_VINISANTANA is absent."
  }

  $resolvedAccountId = Resolve-OptionalSetting -Name "CLOUDFLARE_ACCOUNT_ID" -CurrentValue $AccountId
  $headers = @{ Authorization = "Bearer $Token" }
  $query = "name=$([uri]::EscapeDataString($resolvedZoneName))"
  if (-not [string]::IsNullOrWhiteSpace($resolvedAccountId)) {
    $query = "$query&account.id=$([uri]::EscapeDataString($resolvedAccountId))"
  }

  $response = Invoke-RestMethod -Method Get -Uri "https://api.cloudflare.com/client/v4/zones?$query" -Headers $headers -TimeoutSec 30
  $zones = @($response.result)
  if ($zones.Count -ne 1) {
    throw "Cloudflare zone lookup for '$resolvedZoneName' returned $($zones.Count) zones. Set CLOUDFLARE_ZONE_ID_VINISANTANA explicitly."
  }

  return [string]$zones[0].id
}

$resolvedProxyCtid = [int](Resolve-InfisicalSetting -Name "EDGE_PROXY_LXC_CTID" -CurrentValue $ProxyCtid -EnvFilePath $envFile)
$resolvedProxyIp = Resolve-InfisicalSetting -Name "EDGE_PROXY_LXC_IP" -CurrentValue $ProxyIp -EnvFilePath $envFile
$resolvedProxyExpectedHostname = Resolve-InfisicalSetting -Name "EDGE_PROXY_LXC_NAME" -CurrentValue $ProxyExpectedHostname -EnvFilePath $envFile
$resolvedPublicIp = Resolve-InfisicalSetting -Name "PUBLIC_IP" -CurrentValue $PublicIp -EnvFilePath $envFile
$PrometheusBasicAuthHtpasswd = Resolve-InfisicalSetting -Name "EDGE_PROXY_PROMETHEUS_BASIC_AUTH_HTPASSWD" -CurrentValue $PrometheusBasicAuthHtpasswd -EnvFilePath $envFile
$PrometheusBasicAuthUsername = Resolve-OptionalSetting -Name "EDGE_PROXY_PROMETHEUS_BASIC_AUTH_USERNAME" -CurrentValue $PrometheusBasicAuthUsername
$PrometheusBasicAuthPassword = Resolve-OptionalSetting -Name "EDGE_PROXY_PROMETHEUS_BASIC_AUTH_PASSWORD" -CurrentValue $PrometheusBasicAuthPassword

if (-not $SkipCloudflare) {
  $CloudflareApiToken = Resolve-CloudflareToken -CurrentValue $CloudflareApiToken
  $CloudflareAccountId = Resolve-OptionalSetting -Name "CLOUDFLARE_ACCOUNT_ID" -CurrentValue $CloudflareAccountId
  $CloudflareZoneName = Resolve-OptionalSetting -Name "CLOUDFLARE_ZONE_NAME_VINISANTANA" -CurrentValue $CloudflareZoneName
  $CloudflareZoneId = Resolve-CloudflareZoneId -CurrentZoneId (Resolve-OptionalSetting -Name "CLOUDFLARE_ZONE_ID_VINISANTANA" -CurrentValue $CloudflareZoneId) -Token $CloudflareApiToken -ZoneName $CloudflareZoneName -AccountId $CloudflareAccountId
}

if (-not $SkipInfisical) {
  $InfisicalUrl = Resolve-InfisicalUrl -CurrentValue $InfisicalUrl -EnvFilePath $envFile
  $InfisicalWorkspaceId = Resolve-InfisicalSetting -Name "INFISICAL_WORKSPACE_ID" -CurrentValue $InfisicalWorkspaceId -EnvFilePath $envFile
  $InfisicalProjectSlug = Resolve-InfisicalSetting -Name "INFISICAL_PROJECT_SLUG" -CurrentValue $InfisicalProjectSlug -EnvFilePath $envFile
  $InfisicalEnvironment = Resolve-InfisicalSetting -Name "INFISICAL_ENVIRONMENT" -CurrentValue $InfisicalEnvironment -EnvFilePath $envFile
  $infisicalPreflightHeaders = @{ Authorization = "Bearer $(Get-InfisicalToken)" }
  foreach ($path in @($EdgeProxySecretPath, $InstallationSecretPath, $MonitoringSecretPath, $ObjectStorageSecretPath)) {
    Test-InfisicalSecretPathWritable -SecretPath $path -Headers $infisicalPreflightHeaders
  }
}

$publicDomain = Resolve-InfisicalSetting -Name "ESUS_PEC_PUBLIC_DOMAIN" -CurrentValue "" -EnvFilePath $envFile
$publicBaseUrl = Resolve-InfisicalSetting -Name "ESUS_PEC_PUBLIC_BASE_URL" -CurrentValue "" -EnvFilePath $envFile
$externalBaseUrl = Resolve-InfisicalSetting -Name "ESUS_PEC_EXTERNAL_BASE_URL" -CurrentValue "" -EnvFilePath $envFile
$testHttpsUrl = Resolve-InfisicalSetting -Name "ESUS_PEC_LXC_TEST_HTTPS_URL" -CurrentValue "" -EnvFilePath $envFile
$productionDomain = Resolve-InfisicalSetting -Name "ESUS_PEC_PRODUCTION_DOMAIN" -CurrentValue "" -EnvFilePath $envFile
$productionUpstreamUrl = Resolve-RequiredUrl -Name "ESUS_PEC_PRODUCTION_UPSTREAM_URL"
$objectStoragePublicApiUrl = Resolve-InfisicalSetting -Name "ESUS_PEC_OBJECT_STORAGE_PUBLIC_API_URL" -CurrentValue "" -EnvFilePath $envFile
$objectStoragePublicConsoleUrl = Resolve-InfisicalSetting -Name "ESUS_PEC_OBJECT_STORAGE_PUBLIC_CONSOLE_URL" -CurrentValue "" -EnvFilePath $envFile
$walgInternalEndpoint = Resolve-RequiredUrl -Name "ESUS_PEC_WALG_AWS_ENDPOINT"
$grafanaUrl = Resolve-InfisicalSetting -Name "grafana_url" -CurrentValue "" -EnvFilePath $envFile
$prometheusUrl = Resolve-InfisicalSetting -Name "prometheus_url" -CurrentValue "" -EnvFilePath $envFile
$infisicalPublicUrl = Resolve-InfisicalSetting -Name "INFISICAL_PUBLIC_URL" -CurrentValue "" -EnvFilePath $envFile
$proxmoxPublicUrl = Resolve-InfisicalSetting -Name "PROXMOX_PUBLIC_URL" -CurrentValue "" -EnvFilePath $envFile

$routes = @(
  (New-Route -Id "esus-dev" -DomainVariable "EDGE_PROXY_ESUS_DEV_DOMAIN" -UpstreamVariable "EDGE_PROXY_ESUS_DEV_UPSTREAM_URL" -ExpectedStatuses @("200", "301", "302")),
  (New-Route -Id "s3" -DomainVariable "EDGE_PROXY_S3_DOMAIN" -UpstreamVariable "EDGE_PROXY_S3_UPSTREAM_URL" -HealthPath "/minio/health/ready" -ExpectedStatuses @("200", "301", "302")),
  (New-Route -Id "minio-console" -DomainVariable "EDGE_PROXY_MINIO_DOMAIN" -UpstreamVariable "EDGE_PROXY_MINIO_UPSTREAM_URL" -ExpectedStatuses @("200", "302", "403")),
  (New-Route -Id "infisical" -DomainVariable "EDGE_PROXY_INFISICAL_DOMAIN" -UpstreamVariable "EDGE_PROXY_INFISICAL_UPSTREAM_URL" -ExpectedStatuses @("200", "302", "404")),
  (New-Route -Id "proxmox" -DomainVariable "EDGE_PROXY_PROXMOX_DOMAIN" -UpstreamVariable "EDGE_PROXY_PROXMOX_UPSTREAM_URL" -ExpectedStatuses @("200", "302")),
  (New-Route -Id "grafana" -DomainVariable "EDGE_PROXY_GRAFANA_DOMAIN" -UpstreamVariable "EDGE_PROXY_GRAFANA_UPSTREAM_URL" -HealthPath "/api/health" -ExpectedStatuses @("200")),
  (New-Route -Id "prometheus" -DomainVariable "EDGE_PROXY_PROMETHEUS_DOMAIN" -UpstreamVariable "EDGE_PROXY_PROMETHEUS_UPSTREAM_URL" -HealthPath "/-/ready" -ExpectedStatuses @("401") -RequirePrometheusAuth $true)
)

$nginxConfig = @(
  "# Managed by scripts/esus-pec/Configure-EdgeProxyRoutes.ps1"
  "# Cloudflare handles public TLS for vinisantana.com; this origin listens on HTTP and HTTPS."
  "# Explicit default servers prevent unknown Host headers from falling through to esus.vinisantana.com."
  (Get-NginxDefaultServerBlock)
  ($routes | ForEach-Object { Get-NginxRouteBlock -Route $_ })
) -join "`n"

$configText = Get-Content -LiteralPath $ConfigFile -Raw
$sshHost = Get-HclValue -Name "proxmox_ssh_host" -Text $configText
$sshPort = Get-HclValue -Name "proxmox_ssh_port" -Text $configText -Default "22"
$sshUser = Get-HclValue -Name "proxmox_ssh_user" -Text $configText -Default "root"
$sshKey = Get-HclValue -Name "proxmox_ssh_private_key_file" -Text $configText
if (-not $sshHost -or -not $sshKey) {
  throw "Missing proxmox_ssh_host or proxmox_ssh_private_key_file in $ConfigFile."
}

$cloudflareChanges = @()
if (-not $SkipCloudflare) {
  foreach ($route in $routes) {
    $action = Set-CloudflareDnsRecord -ZoneId $CloudflareZoneId -Token $CloudflareApiToken -Name $route.domain -Content $resolvedPublicIp -Proxied $true
    $cloudflareChanges += [pscustomobject]@{ domain = $route.domain; action = $action; proxied = $true }
  }
}

$target = "$sshUser@$sshHost"
$nginxConfigB64 = Convert-ToBase64 -Value $nginxConfig
$htpasswdB64 = Convert-ToBase64 -Value $PrometheusBasicAuthHtpasswd
$routesJsonB64 = Convert-ToBase64 -Value ($routes | ConvertTo-Json -Depth 6 -Compress)
$proxyExpectedHostnameB64 = Convert-ToBase64 -Value $resolvedProxyExpectedHostname
$validateOnlyFlag = if ($ValidateOnly) { "1" } else { "0" }

$remoteScript = @"
set -euo pipefail
exec 2>&1

PROXY_EXPECTED_HOSTNAME="`$(printf '%s' '$proxyExpectedHostnameB64' | base64 -d)"
NGINX_CONFIG_B64='$nginxConfigB64'
HTPASSWD_B64='$htpasswdB64'
ROUTES_JSON_B64='$routesJsonB64'
VALIDATE_ONLY='$validateOnlyFlag'
ORIGIN_CERT="/etc/nginx/edge-proxy-origin.crt"
ORIGIN_KEY="/etc/nginx/edge-proxy-origin.key"

actual_hostname="`$(hostname -s)"
if [ "`$actual_hostname" != "`$PROXY_EXPECTED_HOSTNAME" ]; then
  echo "PROXY_HOSTNAME_MISMATCH=expected:`$PROXY_EXPECTED_HOSTNAME actual:`$actual_hostname"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends nginx ca-certificates curl jq openssl

routes_json="`$(printf '%s' "`$ROUTES_JSON_B64" | base64 -d)"
origin_san="`$(printf '%s' "`$routes_json" | jq -r '.[].domain | "DNS:" + .' | paste -sd, -)"
if [ ! -s "`$ORIGIN_CERT" ] || [ ! -s "`$ORIGIN_KEY" ]; then
  openssl req -x509 -newkey rsa:2048 -sha256 -days 397 -nodes \
    -keyout "`$ORIGIN_KEY" \
    -out "`$ORIGIN_CERT" \
    -subj "/CN=edge-proxy.vinisantana.com" \
    -addext "subjectAltName=`$origin_san" >/dev/null 2>&1
  chmod 0600 "`$ORIGIN_KEY"
  chmod 0644 "`$ORIGIN_CERT"
fi

site_available="/etc/nginx/sites-available/edge-proxy-routes.conf"
site_enabled="/etc/nginx/sites-enabled/edge-proxy-routes.conf"
tmp_site="`$(mktemp /tmp/edge-proxy-routes.XXXXXX)"
printf '%s' "`$NGINX_CONFIG_B64" | base64 -d > "`$tmp_site"
install -m 0644 "`$tmp_site" "`$site_available"
rm -f "`$tmp_site"

printf '%s' "`$HTPASSWD_B64" | base64 -d > /etc/nginx/edge-proxy-prometheus.htpasswd
chmod 0640 /etc/nginx/edge-proxy-prometheus.htpasswd
chown root:www-data /etc/nginx/edge-proxy-prometheus.htpasswd

ln -sfn "`$site_available" "`$site_enabled"
nginx -t

if [ "`$VALIDATE_ONLY" != "1" ]; then
  systemctl enable --now nginx >/dev/null
  systemctl reload nginx
else
  echo "ROUTE_PROBES_SKIPPED=validate-only"
  echo "EDGE_PROXY_READY=0"
  echo "NGINX_ACTIVE=`$(systemctl is-active nginx || true)"
  exit 0
fi

route_count="`$(printf '%s' "`$routes_json" | jq length)"
echo "ROUTE_COUNT=`$route_count"
for idx in `$(seq 0 `$((route_count - 1))); do
  id="`$(printf '%s' "`$routes_json" | jq -r ".[`$idx].id")"
  domain="`$(printf '%s' "`$routes_json" | jq -r ".[`$idx].domain")"
  health_path="`$(printf '%s' "`$routes_json" | jq -r ".[`$idx].healthPath")"
  expected="`$(printf '%s' "`$routes_json" | jq -r ".[`$idx].expectedStatuses | join(\",\")")"
  status="`$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 -H "Host: `$domain" "http://127.0.0.1`$health_path" || true)"
  echo "ROUTE_`${id}_STATUS=`$status"
  if ! printf ',%s,' "`$expected" | grep -q ",`$status,"; then
    echo "ROUTE_`${id}_EXPECTED=`$expected"
    exit 1
  fi
done

default_status="`$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 -H "Host: unknown.vinisantana.com" "http://127.0.0.1/" || true)"
echo "DEFAULT_SERVER_STATUS=`$default_status"
if [ "`$default_status" != "404" ]; then
  exit 1
fi

echo "EDGE_PROXY_READY=1"
echo "NGINX_ACTIVE=`$(systemctl is-active nginx || true)"
"@

$applyOutput = Invoke-ContainerScript -Target $target -Port $sshPort -KeyFile $sshKey -ContainerId $resolvedProxyCtid -Script $remoteScript

$metadata = @{}
foreach ($line in ($applyOutput -split "`n")) {
  if ($line -match "^([A-Z0-9_-]+)=(.*)$") {
    $metadata[$Matches[1]] = $Matches[2]
  }
}

$created = 0
$updated = 0
if (-not $SkipInfisical) {
  $headers = @{ Authorization = "Bearer $(Get-InfisicalToken)" }
  $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $secretSets = [ordered]@{
    $EdgeProxySecretPath = [ordered]@{
      EDGE_PROXY_LXC_CTID = [string]$resolvedProxyCtid
      EDGE_PROXY_LXC_IP = $resolvedProxyIp
      EDGE_PROXY_LXC_NAME = $resolvedProxyExpectedHostname
      EDGE_PROXY_PUBLIC_IP = $resolvedPublicIp
      EDGE_PROXY_ESUS_DEV_DOMAIN = $routes[0].domain
      EDGE_PROXY_ESUS_DEV_UPSTREAM_URL = $routes[0].upstream
      EDGE_PROXY_S3_DOMAIN = $routes[1].domain
      EDGE_PROXY_S3_UPSTREAM_URL = $routes[1].upstream
      EDGE_PROXY_MINIO_DOMAIN = $routes[2].domain
      EDGE_PROXY_MINIO_UPSTREAM_URL = $routes[2].upstream
      EDGE_PROXY_INFISICAL_DOMAIN = $routes[3].domain
      EDGE_PROXY_INFISICAL_UPSTREAM_URL = $routes[3].upstream
      EDGE_PROXY_PROXMOX_DOMAIN = $routes[4].domain
      EDGE_PROXY_PROXMOX_UPSTREAM_URL = $routes[4].upstream
      EDGE_PROXY_GRAFANA_DOMAIN = $routes[5].domain
      EDGE_PROXY_GRAFANA_UPSTREAM_URL = $routes[5].upstream
      EDGE_PROXY_PROMETHEUS_DOMAIN = $routes[6].domain
      EDGE_PROXY_PROMETHEUS_UPSTREAM_URL = $routes[6].upstream
      EDGE_PROXY_PROMETHEUS_BASIC_AUTH_HTPASSWD = $PrometheusBasicAuthHtpasswd
      EDGE_PROXY_PROMETHEUS_BASIC_AUTH_USERNAME = $PrometheusBasicAuthUsername
      EDGE_PROXY_PROMETHEUS_BASIC_AUTH_PASSWORD = $PrometheusBasicAuthPassword
      INFISICAL_PUBLIC_URL = $infisicalPublicUrl
      PROXMOX_PUBLIC_URL = $proxmoxPublicUrl
      EDGE_PROXY_LAST_VALIDATED_AT = $now
      EDGE_PROXY_NGINX_ACTIVE = [string]$metadata["NGINX_ACTIVE"]
      EDGE_PROXY_CLOUDFLARE_MANAGED = [string](-not $SkipCloudflare.IsPresent)
    }
    $InstallationSecretPath = [ordered]@{
      ESUS_PEC_PUBLIC_DOMAIN = $publicDomain
      ESUS_PEC_PUBLIC_BASE_URL = $publicBaseUrl
      ESUS_PEC_EXTERNAL_BASE_URL = $externalBaseUrl
      ESUS_PEC_LXC_TEST_HTTPS_URL = $testHttpsUrl
      ESUS_PEC_PRODUCTION_DOMAIN = $productionDomain
      ESUS_PEC_PRODUCTION_UPSTREAM_URL = $productionUpstreamUrl
    }
    $MonitoringSecretPath = [ordered]@{
      grafana_url = $grafanaUrl
      prometheus_url = $prometheusUrl
    }
    $ObjectStorageSecretPath = [ordered]@{
      ESUS_PEC_OBJECT_STORAGE_PUBLIC_API_URL = $objectStoragePublicApiUrl
      ESUS_PEC_OBJECT_STORAGE_PUBLIC_CONSOLE_URL = $objectStoragePublicConsoleUrl
      ESUS_PEC_WALG_AWS_ENDPOINT = $walgInternalEndpoint
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($CloudflareZoneId)) {
    $secretSets[$EdgeProxySecretPath]["CLOUDFLARE_ZONE_ID_VINISANTANA"] = $CloudflareZoneId
  }
  if (-not [string]::IsNullOrWhiteSpace($CloudflareZoneName)) {
    $secretSets[$EdgeProxySecretPath]["CLOUDFLARE_ZONE_NAME_VINISANTANA"] = $CloudflareZoneName
  }
  if (-not [string]::IsNullOrWhiteSpace($CloudflareAccountId)) {
    $secretSets[$EdgeProxySecretPath]["CLOUDFLARE_ACCOUNT_ID"] = $CloudflareAccountId
  }
  if (-not [string]::IsNullOrWhiteSpace($CloudflareApiToken)) {
    $secretSets[$EdgeProxySecretPath]["CLOUDFLARE_API_TOKEN"] = $CloudflareApiToken
    $secretSets[$EdgeProxySecretPath]["CLOUDFLARE_TOKEN"] = $CloudflareApiToken
  }

  foreach ($path in $secretSets.Keys) {
    foreach ($entry in $secretSets[$path].GetEnumerator()) {
      $result = Set-InfisicalSecret -SecretPath $path -Name $entry.Key -Value ([string]$entry.Value) -Headers $headers
      if ($result -eq "created") { $created++ } else { $updated++ }
    }
  }
}

[ordered]@{
  proxyCtid = $resolvedProxyCtid
  proxyIp = $resolvedProxyIp
  proxyName = $resolvedProxyExpectedHostname
  publicIp = $resolvedPublicIp
  routeCount = $routes.Count
  routes = @($routes | ForEach-Object { [ordered]@{ id = $_.id; domain = $_.domain; upstream = $_.upstream } })
  cloudflareChanges = @($cloudflareChanges)
  cloudflareSkipped = $SkipCloudflare.IsPresent
  nginxActive = [string]$metadata["NGINX_ACTIVE"]
  infisicalUpdated = (-not $SkipInfisical.IsPresent)
  infisicalCreated = $created
  infisicalUpdatedCount = $updated
  secretValuesPrinted = $false
} | ConvertTo-Json -Depth 6
