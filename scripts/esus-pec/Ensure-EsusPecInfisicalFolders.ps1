param(
  [string]$EnvFile = ".env",
  [string]$InfisicalUrl = "http://192.168.1.226:8080",
  [string]$InfisicalWorkspaceId = "2c83cfe9-e794-4961-977d-23000ae14461",
  [string]$InfisicalEnvironment = "dev",
  [string]$RuntimeSecretPath = "/test",
  [string]$InstallationSecretPath = "/test/InstallationConfig",
  [string]$MonitoringSecretPath = "/test/Monitoring",
  [string]$ObjectStorageSecretPath = "/test/ObjectStorage"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-EnvFileValues {
  param([Parameter(Mandatory = $true)][string]$Path)

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

function Get-InfisicalToken {
  $envValues = Get-EnvFileValues -Path $EnvFile
  foreach ($candidate in @("infisical_secret_key", "INFISICAL_TOKEN")) {
    $environmentValue = [Environment]::GetEnvironmentVariable($candidate)
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
      return $environmentValue.Trim()
    }
    if ($envValues.ContainsKey($candidate) -and -not [string]::IsNullOrWhiteSpace([string]$envValues[$candidate])) {
      return [string]$envValues[$candidate]
    }
  }

  throw "Infisical token not found. Set infisical_secret_key in .env or INFISICAL_TOKEN."
}

function Get-InstallationSecretPaths {
  return @(
    $InstallationSecretPath,
    "$InstallationSecretPath/FirstRun",
    "$InstallationSecretPath/TLS",
    "$InstallationSecretPath/Connectivity",
    "$InstallationSecretPath/Security",
    "$InstallationSecretPath/Municipality",
    "$InstallationSecretPath/Files",
    "$InstallationSecretPath/Advanced",
    "$InstallationSecretPath/GovBrOAuth",
    "$InstallationSecretPath/Importacao",
    "$InstallationSecretPath/ImportacaoCNES",
    "$InstallationSecretPath/ImportacaoBolsaFamilia",
    "$InstallationSecretPath/Transmissao",
    "$InstallationSecretPath/TransmissaoAPI"
  )
}

function Get-Folders {
  param(
    [Parameter(Mandatory = $true)][string]$ParentPath,
    [Parameter(Mandatory = $true)][hashtable]$Headers
  )

  $uri = "$InfisicalUrl/api/v1/folders?workspaceId=$InfisicalWorkspaceId&environment=$InfisicalEnvironment&path=$([uri]::EscapeDataString($ParentPath))"
  $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -TimeoutSec 30
  return @($response.folders)
}

function Ensure-InfisicalFolderPath {
  param(
    [Parameter(Mandatory = $true)][string]$SecretPath,
    [Parameter(Mandatory = $true)][hashtable]$Headers
  )

  $segments = @($SecretPath.Trim("/") -split "/" | Where-Object { $_ -ne "" })
  if ($segments.Count -eq 0) {
    return @()
  }

  $events = @()
  $parent = "/"
  foreach ($segment in $segments) {
    $folders = Get-Folders -ParentPath $parent -Headers $Headers
    $exists = @($folders | Where-Object { $_.name -eq $segment }).Count -gt 0

    if (-not $exists) {
      $body = @{
        workspaceId = $InfisicalWorkspaceId
        environment = $InfisicalEnvironment
        name = $segment
        path = $parent
      } | ConvertTo-Json -Compress

      try {
        $null = Invoke-RestMethod -Method Post -Uri "$InfisicalUrl/api/v1/folders" -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
        $events += [pscustomobject][ordered]@{ path = (Join-InfisicalPath -ParentPath $parent -Name $segment); action = "created" }
      } catch {
        if (-not $_.Exception.Response -or $_.Exception.Response.StatusCode.value__ -ne 409) {
          throw
        }
        $events += [pscustomobject][ordered]@{ path = (Join-InfisicalPath -ParentPath $parent -Name $segment); action = "already-exists" }
      }
    } else {
      $events += [pscustomobject][ordered]@{ path = (Join-InfisicalPath -ParentPath $parent -Name $segment); action = "already-exists" }
    }

    $parent = Join-InfisicalPath -ParentPath $parent -Name $segment
  }

  return @($events)
}

function Join-InfisicalPath {
  param(
    [Parameter(Mandatory = $true)][string]$ParentPath,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if ($ParentPath -eq "/") {
    return "/$Name"
  }
  return "$ParentPath/$Name"
}

function Test-InfisicalFolderPath {
  param(
    [Parameter(Mandatory = $true)][string]$SecretPath,
    [Parameter(Mandatory = $true)][hashtable]$Headers
  )

  $segments = @($SecretPath.Trim("/") -split "/" | Where-Object { $_ -ne "" })
  if ($segments.Count -eq 0) {
    return $true
  }

  $parent = "/"
  foreach ($segment in $segments) {
    $folders = Get-Folders -ParentPath $parent -Headers $Headers
    if (@($folders | Where-Object { $_.name -eq $segment }).Count -eq 0) {
      return $false
    }
    $parent = Join-InfisicalPath -ParentPath $parent -Name $segment
  }

  return $true
}

$headers = @{ Authorization = "Bearer $(Get-InfisicalToken)" }
$targetPaths = @($RuntimeSecretPath) + @(Get-InstallationSecretPaths) + @($MonitoringSecretPath, $ObjectStorageSecretPath)
$events = @()

foreach ($path in $targetPaths) {
  foreach ($event in (Ensure-InfisicalFolderPath -SecretPath $path -Headers $headers)) {
    $events += $event
  }
}

$missing = @($targetPaths | Where-Object { -not (Test-InfisicalFolderPath -SecretPath $_ -Headers $headers) })

[ordered]@{
  generatedAtUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  infisicalUrl = $InfisicalUrl
  environment = $InfisicalEnvironment
  targetPaths = @($targetPaths)
  created = @($events | Where-Object { $_.action -eq "created" } | Select-Object -ExpandProperty path -Unique)
  existing = @($events | Where-Object { $_.action -eq "already-exists" } | Select-Object -ExpandProperty path -Unique)
  missing = @($missing)
  missingCount = $missing.Count
} | ConvertTo-Json -Depth 6

