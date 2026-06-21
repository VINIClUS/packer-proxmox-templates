param(
  [string]$EnvFile = ".env",
  [string]$InfisicalUrl = "http://192.168.1.226:8080",
  [string]$InfisicalWorkspaceId = "2c83cfe9-e794-4961-977d-23000ae14461",
  [string]$InfisicalProjectSlug = "esus-pec-z-px-c",
  [string]$InfisicalEnvironment = "dev",
  [string]$InfisicalSecretPath = "/test/Monitoring",
  [string]$DefaultGrafanaUrl = "http://192.168.1.190:3000",
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\InfisicalEndpoint.ps1")
$infisicalEnvFile = if (Get-Variable -Name EnvFile -ErrorAction SilentlyContinue) { $EnvFile } else { ".env" }
$InfisicalUrl = Resolve-InfisicalUrl -CurrentValue $InfisicalUrl -EnvFilePath $infisicalEnvFile

function Get-EnvFileValues {
  param([string]$Path)

  $values = @{}
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $values
  }

  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed.StartsWith("#") -or $trimmed -notmatch "=") {
      continue
    }

    $parts = $trimmed -split "=", 2
    $values[$parts[0].Trim()] = $parts[1].Trim().Trim('"').Trim("'")
  }

  return $values
}

function Get-ConfigValue {
  param(
    [hashtable]$Values,
    [string]$Name,
    [string]$Default = $null
  )

  $upperName = $Name.ToUpperInvariant()
  foreach ($candidate in @($Name, $upperName)) {
    $environmentValue = [Environment]::GetEnvironmentVariable($candidate)
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
      return $environmentValue.Trim()
    }
  }

  foreach ($candidate in @($Name, $upperName)) {
    if ($Values.ContainsKey($candidate) -and -not [string]::IsNullOrWhiteSpace([string]$Values[$candidate])) {
      return [string]$Values[$candidate]
    }
  }

  return $Default
}

function Get-InfisicalCredential {
  param([hashtable]$Values)

  foreach ($candidate in @("infisical_secret_key", "INFISICAL_TOKEN")) {
    $environmentValue = [Environment]::GetEnvironmentVariable($candidate)
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
      return $environmentValue.Trim()
    }
    if ($Values.ContainsKey($candidate) -and -not [string]::IsNullOrWhiteSpace([string]$Values[$candidate])) {
      return [string]$Values[$candidate]
    }
  }

  throw "Infisical token not found. Set infisical_secret_key in .env or INFISICAL_TOKEN."
}

function Get-InfisicalSecrets {
  param(
    [string]$SecretPath,
    [hashtable]$Headers
  )

  $uri = "$InfisicalUrl/api/v3/secrets/raw?workspaceId=$InfisicalWorkspaceId&environment=$InfisicalEnvironment&secretPath=$([uri]::EscapeDataString($SecretPath))"
  $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -TimeoutSec 30
  $result = @{}
  foreach ($item in @($response.secrets)) {
    $result[[string]$item.secretKey] = [string]$item.secretValue
  }
  return $result
}

function Ensure-InfisicalFolderPath {
  param(
    [string]$SecretPath,
    [hashtable]$Headers
  )

  $segments = @($SecretPath.Trim("/") -split "/" | Where-Object { $_ -ne "" })
  if ($segments.Count -eq 0) {
    return
  }

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
        if (-not $_.Exception.Response -or $_.Exception.Response.StatusCode.value__ -ne 409) {
          throw
        }
      }
    }

    if ($parent -eq "/") {
      $parent = "/$segment"
    } else {
      $parent = "$parent/$segment"
    }
  }
}

function Set-InfisicalSecret {
  param(
    [string]$Name,
    [AllowEmptyString()][string]$Value,
    [hashtable]$Headers,
    [bool]$Exists
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
    secretComment = "Managed by scripts/monitoring/Sync-GrafanaInfisicalEnv.ps1"
  } | ConvertTo-Json -Depth 5

  if (-not $Exists) {
    $null = Invoke-RestMethod -Method Post -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
    return "created"
  }

  try {
    $null = Invoke-RestMethod -Method Patch -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
    return "updated"
  } catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
      $null = Invoke-RestMethod -Method Post -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
      return "created"
    }
    throw
  }
}

$envValues = Get-EnvFileValues -Path $EnvFile
$infisicalCredential = Get-InfisicalCredential -Values $envValues
$headers = @{ Authorization = "Bearer $infisicalCredential" }
$grafanaUrl = Get-ConfigValue -Values $envValues -Name "grafana_url" -Default $DefaultGrafanaUrl
$grafanaCredential = Get-ConfigValue -Values $envValues -Name "grafana_token"

$desired = [ordered]@{
  grafana_url = $grafanaUrl
}

if (-not [string]::IsNullOrWhiteSpace($grafanaCredential)) {
  $desired["grafana_token"] = $grafanaCredential
}

try {
  $existing = Get-InfisicalSecrets -SecretPath $InfisicalSecretPath -Headers $headers
} catch {
  if (-not $DryRun -and $_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
    Ensure-InfisicalFolderPath -SecretPath $InfisicalSecretPath -Headers $headers
    $existing = Get-InfisicalSecrets -SecretPath $InfisicalSecretPath -Headers $headers
  } else {
    throw
  }
}
$changes = New-Object System.Collections.Generic.List[object]

foreach ($entry in $desired.GetEnumerator()) {
  $exists = $existing.ContainsKey($entry.Key)
  $action = if ($DryRun) {
    if ($exists) { "would-update" } else { "would-create" }
  } else {
    Set-InfisicalSecret -Name $entry.Key -Value ([string]$entry.Value) -Headers $headers -Exists $exists
  }

  $changes.Add([pscustomobject]@{
      path = "$InfisicalSecretPath/$($entry.Key)"
      action = $action
      valuePresent = -not [string]::IsNullOrWhiteSpace([string]$entry.Value)
    })
}

$skipped = @()
if ([string]::IsNullOrWhiteSpace($grafanaCredential)) {
  $skipped = @("$InfisicalSecretPath/grafana_token")
}

$report = @{
  dryRun = [bool]$DryRun.IsPresent
  infisicalUrl = $InfisicalUrl
  environment = $InfisicalEnvironment
  secretPath = $InfisicalSecretPath
  grafanaUrlPresent = [bool](-not [string]::IsNullOrWhiteSpace($grafanaUrl))
  grafanaTokenPresent = [bool](-not [string]::IsNullOrWhiteSpace($grafanaCredential))
  syncedCount = [int]$changes.Count
  changes = @($changes.ToArray())
  skipped = @($skipped)
}

$report | ConvertTo-Json -Depth 5
