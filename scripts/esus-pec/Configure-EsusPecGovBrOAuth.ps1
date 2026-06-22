param(
  [string]$ConfigFile = "config/Proxmox.pkrvars.hcl",
  [string]$Ctid = "",
  [string]$ProxyCtid = "",
  [string]$ProxyExpectedHostname = "",
  [string]$SourceFile = "GovBrOAuth.txt",
  [string]$InfisicalUrl = "",
  [string]$InfisicalWorkspaceId = "",
  [string]$InfisicalProjectSlug = "",
  [string]$InfisicalEnvironment = "",
  [string]$InfisicalSecretPath = "/test/InstallationConfig/GovBrOAuth",
  [string]$LegacyInfisicalSecretPath = "/test/InstallationConfig",
  [string]$Domain = "",
  [string]$LocalIp = "",
  [string]$ServerTimezone = "",
  [string]$AppPropertiesPath = "/opt/e-SUS/webserver/config/application.properties",
  [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\InfisicalEndpoint.ps1")
$infisicalEnvFile = if (Get-Variable -Name EnvFile -ErrorAction SilentlyContinue) { $EnvFile } else { ".env" }
$InfisicalUrl = Resolve-InfisicalUrl -CurrentValue $InfisicalUrl -EnvFilePath $infisicalEnvFile
$InfisicalWorkspaceId = Resolve-InfisicalSetting -Name "INFISICAL_WORKSPACE_ID" -CurrentValue $InfisicalWorkspaceId -EnvFilePath $infisicalEnvFile
$InfisicalProjectSlug = Resolve-InfisicalSetting -Name "INFISICAL_PROJECT_SLUG" -CurrentValue $InfisicalProjectSlug -EnvFilePath $infisicalEnvFile
$InfisicalEnvironment = Resolve-InfisicalSetting -Name "INFISICAL_ENVIRONMENT" -CurrentValue $InfisicalEnvironment -EnvFilePath $infisicalEnvFile
$resolvedAppCtid = [int](Resolve-InfisicalSetting -Name "ESUS_PEC_LXC_CTID" -CurrentValue $Ctid -EnvFilePath $infisicalEnvFile)
$resolvedProxyCtid = [int](Resolve-InfisicalSetting -Name "EDGE_PROXY_LXC_CTID" -CurrentValue $ProxyCtid -EnvFilePath $infisicalEnvFile)
$resolvedProxyExpectedHostname = Resolve-InfisicalSetting -Name "EDGE_PROXY_LXC_NAME" -CurrentValue $ProxyExpectedHostname -EnvFilePath $infisicalEnvFile
$Domain = Resolve-InfisicalSetting -Name "ESUS_PEC_PRODUCTION_DOMAIN" -CurrentValue $Domain -EnvFilePath $infisicalEnvFile
$LocalIp = Resolve-InfisicalSetting -Name "ESUS_PEC_LXC_IP" -CurrentValue $LocalIp -EnvFilePath $infisicalEnvFile
$ServerTimezone = Resolve-InfisicalSetting -Name "ESUS_PEC_SERVER_TIMEZONE" -CurrentValue $ServerTimezone -EnvFilePath $infisicalEnvFile

function Get-HclValue {
  param([string]$Name, [string]$Text, [string]$Default = $null)
  $line = $Text -split "`n" | Where-Object { $_ -match ("^\s*" + [regex]::Escape($Name) + "\s*=") } | Select-Object -First 1
  if (-not $line) { return $Default }
  return (($line -split "=", 2)[1]).Trim().Trim('"')
}

function Invoke-ProxmoxSsh {
  param([Parameter(Mandatory = $true)][string]$Command)
  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & ssh -i $script:SshKey -p $script:SshPort -o BatchMode=yes -o StrictHostKeyChecking=accept-new $script:SshTarget $Command 2>&1 |
      ForEach-Object { $_.ToString() }
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previous
  }
  if ($exitCode -ne 0) {
    $tail = ($output | Select-Object -Last 120) -join "`n"
    throw "Remote Proxmox command failed with exit code $exitCode.`n$tail"
  }
  return ($output -join "`n")
}

function Invoke-ContainerBash {
  param([int]$ContainerId, [string]$Script)
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
  Invoke-ProxmoxSsh -Command "pct exec $ContainerId -- bash -lc 'echo $encoded | base64 -d | bash'"
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

function Get-InfisicalSecrets {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Headers,
    [Parameter(Mandatory = $true)][string]$SecretPath
  )
  $uri = "$InfisicalUrl/api/v3/secrets/raw?workspaceId=$InfisicalWorkspaceId&environment=$InfisicalEnvironment&secretPath=$([uri]::EscapeDataString($SecretPath))"
  try {
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -TimeoutSec 30
  } catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
      return @{}
    }
    throw
  }
  $result = @{}
  foreach ($secret in @($response.secrets)) {
    $result[[string]$secret.secretKey] = [string]$secret.secretValue
  }
  return $result
}

function Get-MergedInfisicalSecrets {
  param([Parameter(Mandatory = $true)][hashtable]$Headers)

  $legacy = Get-InfisicalSecrets -Headers $Headers -SecretPath $LegacyInfisicalSecretPath
  $current = Get-InfisicalSecrets -Headers $Headers -SecretPath $InfisicalSecretPath
  foreach ($key in $legacy.Keys) {
    if (-not $current.ContainsKey($key)) {
      $current[$key] = [string]$legacy[$key]
    }
  }
  return $current
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
    [AllowEmptyString()][Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][hashtable]$Headers,
    [Parameter(Mandatory = $true)][bool]$Exists
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
    secretComment = "Managed by scripts/esus-pec/Configure-EsusPecGovBrOAuth.ps1"
  } | ConvertTo-Json -Depth 5

  if ($Exists) {
    $null = Invoke-RestMethod -Method Patch -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
  } else {
    Ensure-InfisicalFolderPath -SecretPath $InfisicalSecretPath -Headers $Headers
    $null = Invoke-RestMethod -Method Post -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
  }
}

function Get-PropertiesFileValues {
  param([Parameter(Mandatory = $true)][string]$Path)
  $values = @{}
  foreach ($line in (Get-Content -LiteralPath $Path)) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith("#") -or $trimmed -notmatch "=") { continue }
    $key, $value = $trimmed -split "=", 2
    $values[$key.Trim()] = $value.Trim()
  }
  return $values
}

function Convert-ToBase64 {
  param([AllowEmptyString()][string]$Value)
  return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

$configText = Get-Content -LiteralPath $ConfigFile -Raw
$sshHost = Get-HclValue -Name "proxmox_ssh_host" -Text $configText
$script:SshPort = Get-HclValue -Name "proxmox_ssh_port" -Text $configText -Default "22"
$sshUser = Get-HclValue -Name "proxmox_ssh_user" -Text $configText -Default "root"
$script:SshKey = Get-HclValue -Name "proxmox_ssh_private_key_file" -Text $configText
$script:SshTarget = "$sshUser@$sshHost"

if (-not $sshHost -or -not $script:SshKey) {
  throw "Missing proxmox_ssh_host or proxmox_ssh_private_key_file in $ConfigFile."
}

$headers = @{ Authorization = "Bearer $(Get-InfisicalToken)" }
$existing = Get-MergedInfisicalSecrets -Headers $headers

if (Test-Path -LiteralPath $SourceFile) {
  $sourcePath = Resolve-Path -LiteralPath $SourceFile
  $sourceValues = Get-PropertiesFileValues -Path $sourcePath
  foreach ($required in @(
      "bridge.security.oauth2.client.registration.govbr.client-id",
      "bridge.security.oauth2.client.registration.govbr.client-secret"
    )) {
    if (-not $sourceValues.ContainsKey($required) -or -not $sourceValues[$required]) {
      throw "Missing required Gov.br property in ${SourceFile}: $required"
    }
  }

  $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToUpperInvariant()
  $sourceMetadata = [ordered]@{
    ESUS_PEC_GOVBR_ENABLED = "true"
    ESUS_PEC_GOVBR_OAUTH_PROPERTY_PREFIX = "bridge.security.oauth2.client.registration.govbr"
    ESUS_PEC_GOVBR_OAUTH_CLIENT_ID = [string]$sourceValues["bridge.security.oauth2.client.registration.govbr.client-id"]
    ESUS_PEC_GOVBR_OAUTH_CLIENT_SECRET = [string]$sourceValues["bridge.security.oauth2.client.registration.govbr.client-secret"]
    ESUS_PEC_GOVBR_OAUTH_ALLOWED_DOMAIN = $Domain
    ESUS_PEC_GOVBR_OAUTH_REDIRECT_BASE_URL = "https://$Domain"
    ESUS_PEC_GOVBR_OAUTH_TEST_HOST_OVERRIDE = "$LocalIp $Domain"
    ESUS_PEC_GOVBR_OAUTH_TEST_STRATEGY = "hosts-file-split-dns"
    ESUS_PEC_GOVBR_OAUTH_PROXY_LXC_CTID = [string]$resolvedProxyCtid
    ESUS_PEC_GOVBR_OAUTH_PROXY_LXC_NAME = $resolvedProxyExpectedHostname
    ESUS_PEC_GOVBR_OAUTH_SOURCE_FILE_SHA256 = $sourceHash
    ESUS_PEC_GOVBR_OAUTH_APP_PROPERTIES_PATH = $AppPropertiesPath
    ESUS_PEC_GOVBR_OAUTH_TLS_MODE = "nginx-termination"
    ESUS_PEC_GOVBR_OAUTH_NATIVE_TLS_FALLBACK = "false"
    ESUS_PEC_GOVBR_DEBUG_MITM_REQUIRED = "false"
    ESUS_PEC_GOVBR_DEBUG_PROXY_TOOL = "mitmproxy"
    ESUS_PEC_SERVER_TIMEZONE = $ServerTimezone
    ESUS_PEC_SERVER_TIMEZONE_OFFSET_MINUTES = "-180"
  }

  foreach ($entry in $sourceMetadata.GetEnumerator()) {
    Set-InfisicalSecret -Name $entry.Key -Value ([string]$entry.Value) -Headers $headers -Exists $existing.ContainsKey($entry.Key)
  }
  $existing = Get-MergedInfisicalSecrets -Headers $headers
}

foreach ($required in @(
    "ESUS_PEC_GOVBR_OAUTH_CLIENT_ID",
    "ESUS_PEC_GOVBR_OAUTH_CLIENT_SECRET"
  )) {
  if (-not $existing.ContainsKey($required) -or -not $existing[$required]) {
    throw "Missing required Infisical secret: $required"
  }
}

$clientIdB64 = Convert-ToBase64 -Value $existing["ESUS_PEC_GOVBR_OAUTH_CLIENT_ID"]
$clientSecretB64 = Convert-ToBase64 -Value $existing["ESUS_PEC_GOVBR_OAUTH_CLIENT_SECRET"]
$domainB64 = Convert-ToBase64 -Value $Domain
$timezoneB64 = Convert-ToBase64 -Value $ServerTimezone
$appPropertiesB64 = Convert-ToBase64 -Value $AppPropertiesPath
$applyValue = if ($Apply) { "true" } else { "false" }

$remoteScript = @"
set -euo pipefail
exec 2>&1

APPLY="$applyValue"
APP_PROPERTIES="`$(printf '%s' '$appPropertiesB64' | base64 -d)"
CLIENT_ID="`$(printf '%s' '$clientIdB64' | base64 -d)"
CLIENT_SECRET="`$(printf '%s' '$clientSecretB64' | base64 -d)"
DOMAIN="`$(printf '%s' '$domainB64' | base64 -d)"
SERVER_TIMEZONE="`$(printf '%s' '$timezoneB64' | base64 -d)"
PREFIX="bridge.security.oauth2.client.registration.govbr"
BACKUP_DIR="/var/backups/esus-pec-govbr"

if [ ! -f "`$APP_PROPERTIES" ]; then
  echo "APP_PROPERTIES_MISSING=`$APP_PROPERTIES"
  exit 1
fi

if [ "`$APPLY" != "true" ]; then
  echo "DRY_RUN=true"
  echo "APP_PROPERTIES=`$APP_PROPERTIES"
  echo "DOMAIN=`$DOMAIN"
  echo "SERVER_TIMEZONE=`$SERVER_TIMEZONE"
  exit 0
fi

install -d -m 0700 "`$BACKUP_DIR"
backup="`$BACKUP_DIR/application.properties.`$(date -u +%Y%m%dT%H%M%SZ).bak"
cp -a "`$APP_PROPERTIES" "`$backup"

export APP_PROPERTIES CLIENT_ID CLIENT_SECRET PREFIX
python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["APP_PROPERTIES"])
prefix = os.environ["PREFIX"]
client_id = os.environ["CLIENT_ID"]
client_secret = os.environ["CLIENT_SECRET"]
managed = {
    f"{prefix}.client-id": client_id,
    f"{prefix}.client-secret": client_secret,
}
lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
filtered = []
for line in lines:
    stripped = line.strip()
    if any(stripped.startswith(key + "=") for key in managed):
        continue
    if stripped == "# Managed Gov.br OAuth properties":
        continue
    filtered.append(line.rstrip())
while filtered and filtered[-1] == "":
    filtered.pop()
filtered.append("")
filtered.append("# Managed Gov.br OAuth properties")
for key, value in managed.items():
    filtered.append(f"{key}={value}")
path.write_text("\n".join(filtered) + "\n", encoding="utf-8")
PY

if [ -f "/usr/share/zoneinfo/`$SERVER_TIMEZONE" ]; then
  ln -snf "/usr/share/zoneinfo/`$SERVER_TIMEZONE" /etc/localtime
  printf '%s\n' "`$SERVER_TIMEZONE" > /etc/timezone
fi

systemctl restart e-SUS-PEC.service
for i in `$(seq 1 90); do
  if curl -fsS --max-time 5 http://127.0.0.1:8080/ >/dev/null 2>&1; then
    break
  fi
  sleep 5
  if [ "`$i" = "90" ]; then
    echo "PEC_READY_TIMEOUT=true"
    exit 1
  fi
done

echo "APPLIED=true"
echo "BACKUP=`$backup"
echo "PEC_SERVICE=`$(systemctl is-active e-SUS-PEC.service)"
echo "TIMEZONE=`$(cat /etc/timezone 2>/dev/null || true)"
echo "APP_PROPERTIES_SHA256=`$(sha256sum "`$APP_PROPERTIES" | awk '{print `$1}')"
grep -E '^bridge\.security\.oauth2\.client\.registration\.govbr\.(client-id|client-secret)=' "`$APP_PROPERTIES" | sed -E 's/(client-id=).+/\1[REDACTED]/; s/(client-secret=).+/\1[REDACTED]/'
"@

$result = Invoke-ContainerBash -ContainerId $resolvedAppCtid -Script $remoteScript
$proxyValidationResult = @()

if ($Apply) {
  $proxyHostnameB64 = Convert-ToBase64 -Value $resolvedProxyExpectedHostname
  $proxyValidationScript = @"
set -euo pipefail
EXPECTED_HOSTNAME="`$(printf '%s' '$proxyHostnameB64' | base64 -d)"
DOMAIN="`$(printf '%s' '$domainB64' | base64 -d)"
NGINX_SITE="/etc/nginx/sites-available/esus-pec-tls.conf"
actual_hostname="`$(hostname -s)"
if [ "`$actual_hostname" != "`$EXPECTED_HOSTNAME" ]; then
  echo "PROXY_HOSTNAME_MISMATCH=expected:`$EXPECTED_HOSTNAME actual:`$actual_hostname"
  exit 1
fi
if [ ! -f "`$NGINX_SITE" ]; then
  echo "PROXY_NGINX_SITE_MISSING=`$NGINX_SITE"
  exit 1
fi
if ! grep -Eq "server_name[[:space:]]+`$DOMAIN([[:space:];]|$)" "`$NGINX_SITE"; then
  echo "PROXY_NGINX_DOMAIN_MISSING=`$DOMAIN"
  exit 1
fi
nginx -t >/dev/null
systemctl reload nginx
echo "PROXY_NGINX_RELOADED=true"
echo "PROXY_NGINX_SERVICE=`$(systemctl is-active nginx)"
"@
  $proxyValidationResult = @(Invoke-ContainerBash -ContainerId $resolvedProxyCtid -Script $proxyValidationScript)
}

[ordered]@{
  applied = $Apply.IsPresent
  applicationCtid = $resolvedAppCtid
  proxyCtid = $resolvedProxyCtid
  proxyName = $resolvedProxyExpectedHostname
  infisicalPath = $InfisicalSecretPath
  sourceFilePresent = (Test-Path -LiteralPath $SourceFile)
  domain = $Domain
  appPropertiesPath = $AppPropertiesPath
  output = ($result -split "`n" | ForEach-Object {
      $_ -replace '(client-id=).*', '$1[REDACTED]' -replace '(client-secret=).*', '$1[REDACTED]'
    })
  proxyOutput = (($proxyValidationResult -join "`n") -split "`n")
} | ConvertTo-Json -Depth 5
