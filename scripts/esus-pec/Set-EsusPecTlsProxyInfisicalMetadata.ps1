param(
  [string]$InfisicalUrl = "",
  [string]$InfisicalWorkspaceId = "",
  [string]$InfisicalProjectSlug = "",
  [string]$InfisicalEnvironment = "",
  [string]$TlsSecretPath = "/test/InstallationConfig/TLS",
  [string]$GovBrSecretPath = "/test/InstallationConfig/GovBrOAuth",
  [string]$Domain = "",
  [string]$PublicIp = "",
  [string]$ProxyCtid = "",
  [string]$ProxyIp = "",
  [string]$ProxyName = "",
  [string]$UpstreamIp = "",
  [string]$LetsEncryptEmail = "",
  [string]$AcmePublicHttpStatus = "",
  [string]$UpstreamHttpStatus = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\InfisicalEndpoint.ps1")

$envFile = ".env"
$InfisicalUrl = Resolve-InfisicalUrl -CurrentValue $InfisicalUrl -EnvFilePath $envFile
$InfisicalWorkspaceId = Resolve-InfisicalSetting -Name "INFISICAL_WORKSPACE_ID" -CurrentValue $InfisicalWorkspaceId -EnvFilePath $envFile
$InfisicalProjectSlug = Resolve-InfisicalSetting -Name "INFISICAL_PROJECT_SLUG" -CurrentValue $InfisicalProjectSlug -EnvFilePath $envFile
$InfisicalEnvironment = Resolve-InfisicalSetting -Name "INFISICAL_ENVIRONMENT" -CurrentValue $InfisicalEnvironment -EnvFilePath $envFile
$Domain = Resolve-InfisicalSetting -Name "ESUS_PEC_PUBLIC_DOMAIN" -CurrentValue $Domain -EnvFilePath $envFile
$PublicIp = Resolve-InfisicalSetting -Name "PUBLIC_IP" -CurrentValue $PublicIp -EnvFilePath $envFile
$ProxyCtid = Resolve-InfisicalSetting -Name "ESUS_PEC_PROXY_LXC_CTID" -CurrentValue $ProxyCtid -EnvFilePath $envFile
$ProxyIp = Resolve-InfisicalSetting -Name "ESUS_PEC_PROXY_LXC_IP" -CurrentValue $ProxyIp -EnvFilePath $envFile
$ProxyName = Resolve-InfisicalSetting -Name "ESUS_PEC_PROXY_LXC_NAME" -CurrentValue $ProxyName -EnvFilePath $envFile
$UpstreamIp = Resolve-InfisicalSetting -Name "ESUS_PEC_LXC_IP" -CurrentValue $UpstreamIp -EnvFilePath $envFile
$LetsEncryptEmail = Resolve-InfisicalSetting -Name "LETSENCRYPT_EMAIL" -CurrentValue $LetsEncryptEmail -EnvFilePath $envFile

if ([string]::IsNullOrWhiteSpace($AcmePublicHttpStatus)) {
  throw "AcmePublicHttpStatus is required. Pass the observed HTTP-01 preflight status explicitly."
}
if ([string]::IsNullOrWhiteSpace($UpstreamHttpStatus)) {
  throw "UpstreamHttpStatus is required. Pass the observed proxy-to-PEC upstream status explicitly."
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

function Set-InfisicalSecret {
  param(
    [Parameter(Mandatory = $true)][string]$SecretPath,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
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
    secretComment = "Managed by scripts/esus-pec/Set-EsusPecTlsProxyInfisicalMetadata.ps1"
  } | ConvertTo-Json -Depth 5

  try {
    $null = Invoke-RestMethod -Method Patch -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
    return "updated"
  } catch {
    $status = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { "unknown" }
    if ($status -ne 404) { throw "Failed to update Infisical secret $Name in $SecretPath. HTTP status: $status" }
    $null = Invoke-RestMethod -Method Post -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
    return "created"
  }
}

$headers = @{ Authorization = "Bearer $(Get-InfisicalToken)" }
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$secrets = [ordered]@{
  $TlsSecretPath = [ordered]@{
    ESUS_PEC_TLS_DOMAIN = $Domain
    ESUS_PEC_TLS_PUBLIC_IP = $PublicIp
    ESUS_PEC_TLS_PROXY_LXC_CTID = $ProxyCtid
    ESUS_PEC_TLS_PROXY_LXC_IP = $ProxyIp
    ESUS_PEC_TLS_PROXY_LXC_NAME = $ProxyName
    ESUS_PEC_TLS_UPSTREAM_LXC_IP = $UpstreamIp
    ESUS_PEC_TLS_UPSTREAM_URL = "http://$UpstreamIp:8080/"
    ESUS_PEC_TLS_LETSENCRYPT_EMAIL = $LetsEncryptEmail
    ESUS_PEC_TLS_TERMINATION = "nginx-edge-lxc-certbot"
    ESUS_PEC_TLS_ACME_PUBLIC_HTTP_STATUS = $AcmePublicHttpStatus
    ESUS_PEC_TLS_UPSTREAM_HTTP_STATUS = $UpstreamHttpStatus
    ESUS_PEC_TLS_LAST_VALIDATED_AT = $now
  }
  $GovBrSecretPath = [ordered]@{
    ESUS_PEC_GOVBR_OAUTH_PROXY_LXC_CTID = $ProxyCtid
    ESUS_PEC_GOVBR_OAUTH_PROXY_LXC_NAME = $ProxyName
  }
}

$created = 0
$updated = 0
foreach ($path in $secrets.Keys) {
  foreach ($entry in $secrets[$path].GetEnumerator()) {
    $result = Set-InfisicalSecret -SecretPath $path -Name $entry.Key -Value ([string]$entry.Value) -Headers $headers
    if ($result -eq "created") { $created++ } else { $updated++ }
  }
}

[ordered]@{
  tlsSecretPath = $TlsSecretPath
  govBrSecretPath = $GovBrSecretPath
  created = $created
  updated = $updated
  secretValuesPrinted = $false
} | ConvertTo-Json -Depth 3
