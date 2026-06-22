param(
  [string]$EnvFile = ".env",
  [string]$ExampleFile = "config/esus-pec.infisical.env.example",
  [string]$InfisicalUrl = "",
  [string]$InfisicalWorkspaceId = "",
  [string]$InfisicalEnvironment = "",
  [string]$RuntimeSecretPath = "/test",
  [string]$InstallationSecretPath = "/test/InstallationConfig",
  [string]$MonitoringSecretPath = "/test/Monitoring",
  [string]$ObjectStorageSecretPath = "/test/ObjectStorage",
  [string]$EdgeProxySecretPath = "/test/EdgeProxy",
  [string]$OutputPath = "output/esus-pec-infisical-variable-analysis.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\InfisicalEndpoint.ps1")
$infisicalEnvFile = if (Get-Variable -Name EnvFile -ErrorAction SilentlyContinue) { $EnvFile } else { ".env" }
$InfisicalUrl = Resolve-InfisicalUrl -CurrentValue $InfisicalUrl -EnvFilePath $infisicalEnvFile
$InfisicalWorkspaceId = Resolve-InfisicalSetting -Name "INFISICAL_WORKSPACE_ID" -CurrentValue $InfisicalWorkspaceId -EnvFilePath $infisicalEnvFile
$InfisicalEnvironment = Resolve-InfisicalSetting -Name "INFISICAL_ENVIRONMENT" -CurrentValue $InfisicalEnvironment -EnvFilePath $infisicalEnvFile

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

function Get-InfisicalSecretNames {
  param(
    [Parameter(Mandatory = $true)][string]$SecretPath,
    [Parameter(Mandatory = $true)][hashtable]$Headers
  )

  $uri = "$InfisicalUrl/api/v3/secrets/raw?workspaceId=$InfisicalWorkspaceId&environment=$InfisicalEnvironment&secretPath=$([uri]::EscapeDataString($SecretPath))"
  try {
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -TimeoutSec 30
  } catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
      return @()
    }
    throw
  }
  return @($response.secrets | ForEach-Object { [string]$_.secretKey } | Sort-Object -Unique)
}

function Get-ExampleSecretNames {
  param([Parameter(Mandatory = $true)][string]$Path)

  $names = New-Object System.Collections.Generic.List[string]
  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed.StartsWith("#") -or $trimmed -notmatch "=") {
      continue
    }

    $name = ($trimmed -split "=", 2)[0].Trim()
    if ($name -match "^[A-Za-z_][A-Za-z0-9_]*$") {
      $names.Add($name)
    }
  }

  return @($names.ToArray() | Sort-Object -Unique)
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
    "$InstallationSecretPath/ImportacaoCNES",
    "$InstallationSecretPath/ImportacaoBolsaFamilia",
    "$InstallationSecretPath/Transmissao",
    "$InstallationSecretPath/TransmissaoAPI"
  )
}

function Get-DesiredInfisicalPath {
  param([Parameter(Mandatory = $true)][string]$Name)

  $runtimeExactNames = @(
    "ESUS_PEC_ADMIN_USERNAME",
    "ESUS_PEC_ADMIN_PASSWORD",
    "ESUS_PEC_SMTP_HOST",
    "ESUS_PEC_SMTP_PORT",
    "ESUS_PEC_SMTP_USERNAME",
    "ESUS_PEC_SMTP_PASSWORD",
    "ESUS_PEC_BACKUP_ENCRYPTION_PASSWORD",
    "ESUS_PEC_RESTORE_ARCHIVE_PASSWORD"
  )

  if ($Name -match "^ESUS_PEC_OBJECT_STORAGE_" -or $Name -match "^ESUS_PEC_WALG_") {
    return $ObjectStorageSecretPath
  }

  if ($Name -match "^EDGE_PROXY_" -or $Name -match "^CLOUDFLARE_" -or $Name -match "^ESUS_PEC_PRODUCTION_" -or $Name -in @("INFISICAL_PUBLIC_URL", "PROXMOX_PUBLIC_URL")) {
    return $EdgeProxySecretPath
  }

  if ($Name -eq "ESUS_PEC_POSTGRES_EXPORTER_PASSWORD" -or $Name -in @("grafana_url", "grafana_token", "prometheus_url")) {
    return $MonitoringSecretPath
  }

  if ($Name -match "^ESUS_PEC_DB_" -or $Name -in $runtimeExactNames) {
    return $RuntimeSecretPath
  }

  if ($Name -match "^ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_" -or $Name -eq "ESUS_PEC_TRANSMISSAO_CREDENCIAIS_INTEGRACAO_EXPECTED_COUNT") {
    return "$InstallationSecretPath/TransmissaoAPI"
  }
  if ($Name -match "^ESUS_PEC_TRANSMISSAO_") {
    return "$InstallationSecretPath/Transmissao"
  }
  if ($Name -match "^ESUS_PEC_CNES_") {
    return "$InstallationSecretPath/ImportacaoCNES"
  }
  if ($Name -match "^ESUS_PEC_BOLSA_FAMILIA_") {
    return "$InstallationSecretPath/ImportacaoBolsaFamilia"
  }
  if ($Name -match "^ESUS_PEC_GOVBR_") {
    return "$InstallationSecretPath/GovBrOAuth"
  }
  if ($Name -match "^ESUS_PEC_TLS_") {
    return "$InstallationSecretPath/TLS"
  }
  if ($Name -in @("ESUS_PEC_INTERNET_ENABLED", "ESUS_PEC_CADSUS_ENABLED", "ESUS_PEC_CADSUS_DISABLE_INTERVAL", "ESUS_PEC_HORUS_ENABLED", "ESUS_PEC_HORUS_DISABLE_INTERVAL", "ESUS_PEC_VIDEOCHAMADAS_ENABLED", "ESUS_PEC_AGENDA_ONLINE_ENABLED", "ESUS_PEC_SMTP_ENABLED", "ESUS_PEC_SMTP_FROM_EMAIL", "ESUS_PEC_SMTP_USE_LOGIN_AS_SENDER")) {
    return "$InstallationSecretPath/Connectivity"
  }
  if ($Name -in @("ESUS_PEC_ASSINATURA_DIGITAL_ENABLED", "ESUS_PEC_ASSINATURA_DIGITAL_LOGIN", "ESUS_PEC_ASSINATURA_DIGITAL_PASSWORD", "ESUS_PEC_PASSWORD_RESET_PERIOD_MONTHS", "ESUS_PEC_MAX_INACTIVITY_MINUTES", "ESUS_PEC_MAX_LOGIN_ATTEMPTS", "ESUS_PEC_FORCE_PASSWORD_RESET_ON_NEXT_LOGIN")) {
    return "$InstallationSecretPath/Security"
  }
  if ($Name -in @("ESUS_PEC_MUNICIPALITY_ID", "ESUS_PEC_RESPONSIBLE_PROFESSIONAL_ID", "ESUS_PEC_MUNICIPAL_RESPONSIBLE_ENABLED")) {
    return "$InstallationSecretPath/Municipality"
  }
  if ($Name -match "^ESUS_PEC_FILE_ATTACHMENTS_") {
    return "$InstallationSecretPath/Files"
  }
  if ($Name -in @("ESUS_PEC_CONCURRENT_REQUESTS_USE_DEFAULT", "ESUS_PEC_CONCURRENT_REQUESTS", "ESUS_PEC_CITIZEN_SEARCH_BY_PROPERTIES_ENABLED", "ESUS_PEC_CDS_PROPERTY_FAMILY_REGISTRATION_ENABLED", "ESUS_PEC_BASE_UNIFICATION_ENABLED", "ESUS_PEC_BASE_UNIFICATION_MODE", "ESUS_PEC_SERVER_TIMEZONE", "ESUS_PEC_SERVER_TIMEZONE_OFFSET_MINUTES")) {
    return "$InstallationSecretPath/Advanced"
  }
  if ($Name -match "^ESUS_PEC_") {
    return "$InstallationSecretPath/FirstRun"
  }

  return $null
}

function New-PathEntry {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Name
  )

  return "$Path/$Name"
}

$headers = @{ Authorization = "Bearer $(Get-InfisicalToken)" }
$exampleNames = @(Get-ExampleSecretNames -Path $ExampleFile)
$managedPaths = @($RuntimeSecretPath) + @(Get-InstallationSecretPaths) + @($MonitoringSecretPath, $ObjectStorageSecretPath, $EdgeProxySecretPath)

$currentByPath = [ordered]@{}
foreach ($path in $managedPaths) {
  $currentByPath[$path] = @(Get-InfisicalSecretNames -SecretPath $path -Headers $headers)
}

$expectedByPath = [ordered]@{}
foreach ($path in $managedPaths) {
  $expectedByPath[$path] = @()
}
foreach ($name in $exampleNames) {
  $desiredPath = Get-DesiredInfisicalPath -Name $name
  if ($null -ne $desiredPath) {
    if (-not $expectedByPath.Contains($desiredPath)) {
      $expectedByPath[$desiredPath] = @()
    }
    $expectedByPath[$desiredPath] = @($expectedByPath[$desiredPath] + $name | Sort-Object -Unique)
  }
}

$seen = @{}
foreach ($path in $managedPaths) {
  foreach ($name in @($currentByPath[$path])) {
    if (-not $seen.ContainsKey($name)) {
      $seen[$name] = New-Object System.Collections.Generic.List[string]
    }
    $seen[$name].Add([string]$path)
  }
}

$missing = New-Object System.Collections.Generic.List[string]
$misplaced = New-Object System.Collections.Generic.List[string]
$unmanaged = New-Object System.Collections.Generic.List[string]

foreach ($path in $managedPaths) {
  foreach ($name in @($expectedByPath[$path])) {
    if ($name -notin @($currentByPath[$path])) {
      $missing.Add((New-PathEntry -Path $path -Name $name))
    }
  }

  foreach ($name in @($currentByPath[$path])) {
    $desiredPath = Get-DesiredInfisicalPath -Name $name
    if ($null -eq $desiredPath) {
      $unmanaged.Add((New-PathEntry -Path $path -Name $name))
    } elseif ($desiredPath -ne $path) {
      $misplaced.Add((New-PathEntry -Path $path -Name $name))
    }
  }
}

$installationPaths = @(Get-InstallationSecretPaths)
$installationCurrent = 0
$expectedInstallation = 0
foreach ($path in $installationPaths) {
  $installationCurrent += @($currentByPath[$path]).Count
  $expectedInstallation += @($expectedByPath[$path]).Count
}

$duplicateNames = @($seen.Keys | Where-Object { $seen[$_].Count -gt 1 } | Sort-Object)
$report = [ordered]@{
  generatedAtUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  infisicalUrl = $InfisicalUrl
  environment = $InfisicalEnvironment
  runtimePath = $RuntimeSecretPath
  installationPath = $InstallationSecretPath
  installationPaths = @($installationPaths)
  monitoringPath = $MonitoringSecretPath
  objectStoragePath = $ObjectStorageSecretPath
  edgeProxyPath = $EdgeProxySecretPath
  counts = [ordered]@{
    runtimeCurrent = @($currentByPath[$RuntimeSecretPath]).Count
    installationCurrent = $installationCurrent
    monitoringCurrent = @($currentByPath[$MonitoringSecretPath]).Count
    objectStorageCurrent = @($currentByPath[$ObjectStorageSecretPath]).Count
    edgeProxyCurrent = @($currentByPath[$EdgeProxySecretPath]).Count
    expectedRuntime = @($expectedByPath[$RuntimeSecretPath]).Count
    expectedInstallation = $expectedInstallation
    expectedMonitoring = @($expectedByPath[$MonitoringSecretPath]).Count
    expectedObjectStorage = @($expectedByPath[$ObjectStorageSecretPath]).Count
    expectedEdgeProxy = @($expectedByPath[$EdgeProxySecretPath]).Count
    duplicateNames = $duplicateNames.Count
    missing = $missing.Count
    misplaced = $misplaced.Count
    unmanaged = $unmanaged.Count
  }
  currentByPath = $currentByPath
  expectedByPath = $expectedByPath
  duplicateNames = @($duplicateNames)
  missing = @($missing)
  misplaced = @($misplaced)
  unmanaged = @($unmanaged)
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
  New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

$json = $report | ConvertTo-Json -Depth 10
Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8
$json

