param(
  [string]$EnvFile = ".env",
  [string]$ExampleFile = "config/esus-pec.infisical.env.example",
  [string]$InfisicalUrl = "http://192.168.1.226:8080",
  [string]$InfisicalWorkspaceId = "2c83cfe9-e794-4961-977d-23000ae14461",
  [string]$InfisicalEnvironment = "dev",
  [string]$RuntimeSecretPath = "/test",
  [string]$InstallationSecretPath = "/test/InstallationConfig",
  [string]$MonitoringSecretPath = "/test/Monitoring",
  [string]$ObjectStorageSecretPath = "/test/ObjectStorage",
  [string]$OutputPath = "output/esus-pec-infisical-variable-analysis.json"
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

  if ($Name -eq "ESUS_PEC_POSTGRES_EXPORTER_PASSWORD" -or $Name -in @("grafana_url", "grafana_token")) {
    return $MonitoringSecretPath
  }

  if ($Name -match "^ESUS_PEC_DB_" -or
      $Name -in $runtimeExactNames) {
    return $RuntimeSecretPath
  }

  if ($Name -match "^ESUS_PEC_") {
    return $InstallationSecretPath
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
$runtimeNames = @(Get-InfisicalSecretNames -SecretPath $RuntimeSecretPath -Headers $headers)
$installationNames = @(Get-InfisicalSecretNames -SecretPath $InstallationSecretPath -Headers $headers)
$monitoringNames = @(Get-InfisicalSecretNames -SecretPath $MonitoringSecretPath -Headers $headers)
$objectStorageNames = @(Get-InfisicalSecretNames -SecretPath $ObjectStorageSecretPath -Headers $headers)
$exampleNames = @(Get-ExampleSecretNames -Path $ExampleFile)

$expectedRuntime = @($exampleNames | Where-Object { (Get-DesiredInfisicalPath -Name $_) -eq $RuntimeSecretPath } | Sort-Object -Unique)
$expectedInstallation = @($exampleNames | Where-Object { (Get-DesiredInfisicalPath -Name $_) -eq $InstallationSecretPath } | Sort-Object -Unique)
$expectedMonitoring = @($exampleNames | Where-Object { (Get-DesiredInfisicalPath -Name $_) -eq $MonitoringSecretPath } | Sort-Object -Unique)
$expectedObjectStorage = @($exampleNames | Where-Object { (Get-DesiredInfisicalPath -Name $_) -eq $ObjectStorageSecretPath } | Sort-Object -Unique)

$pathMaps = @(
  @{ Path = $RuntimeSecretPath; Names = $runtimeNames },
  @{ Path = $InstallationSecretPath; Names = $installationNames },
  @{ Path = $MonitoringSecretPath; Names = $monitoringNames },
  @{ Path = $ObjectStorageSecretPath; Names = $objectStorageNames }
)

$seen = @{}
foreach ($pathMap in $pathMaps) {
  foreach ($name in @($pathMap["Names"])) {
    if (-not $seen.ContainsKey($name)) {
      $seen[$name] = New-Object System.Collections.Generic.List[string]
    }
    $seen[$name].Add([string]$pathMap["Path"])
  }
}

$duplicateNames = @($seen.Keys | Where-Object { $seen[$_].Count -gt 1 } | Sort-Object)
$missingRuntime = @($expectedRuntime | Where-Object { $_ -notin $runtimeNames } | ForEach-Object { New-PathEntry -Path $RuntimeSecretPath -Name $_ })
$missingInstallation = @($expectedInstallation | Where-Object { $_ -notin $installationNames } | ForEach-Object { New-PathEntry -Path $InstallationSecretPath -Name $_ })
$missingMonitoring = @($expectedMonitoring | Where-Object { $_ -notin $monitoringNames } | ForEach-Object { New-PathEntry -Path $MonitoringSecretPath -Name $_ })
$missingObjectStorage = @($expectedObjectStorage | Where-Object { $_ -notin $objectStorageNames } | ForEach-Object { New-PathEntry -Path $ObjectStorageSecretPath -Name $_ })
$misplacedRuntime = @($runtimeNames | Where-Object { (Get-DesiredInfisicalPath -Name $_) -ne $RuntimeSecretPath -and $null -ne (Get-DesiredInfisicalPath -Name $_) } | ForEach-Object { New-PathEntry -Path $RuntimeSecretPath -Name $_ })
$misplacedInstallation = @($installationNames | Where-Object { (Get-DesiredInfisicalPath -Name $_) -ne $InstallationSecretPath -and $null -ne (Get-DesiredInfisicalPath -Name $_) } | ForEach-Object { New-PathEntry -Path $InstallationSecretPath -Name $_ })
$misplacedMonitoring = @($monitoringNames | Where-Object { (Get-DesiredInfisicalPath -Name $_) -ne $MonitoringSecretPath -and $null -ne (Get-DesiredInfisicalPath -Name $_) } | ForEach-Object { New-PathEntry -Path $MonitoringSecretPath -Name $_ })
$misplacedObjectStorage = @($objectStorageNames | Where-Object { (Get-DesiredInfisicalPath -Name $_) -ne $ObjectStorageSecretPath -and $null -ne (Get-DesiredInfisicalPath -Name $_) } | ForEach-Object { New-PathEntry -Path $ObjectStorageSecretPath -Name $_ })
$unmanagedRuntime = @($runtimeNames | Where-Object { $null -eq (Get-DesiredInfisicalPath -Name $_) } | ForEach-Object { New-PathEntry -Path $RuntimeSecretPath -Name $_ })
$unmanagedInstallation = @($installationNames | Where-Object { $null -eq (Get-DesiredInfisicalPath -Name $_) } | ForEach-Object { New-PathEntry -Path $InstallationSecretPath -Name $_ })
$unmanagedMonitoring = @($monitoringNames | Where-Object { $null -eq (Get-DesiredInfisicalPath -Name $_) } | ForEach-Object { New-PathEntry -Path $MonitoringSecretPath -Name $_ })
$unmanagedObjectStorage = @($objectStorageNames | Where-Object { $null -eq (Get-DesiredInfisicalPath -Name $_) } | ForEach-Object { New-PathEntry -Path $ObjectStorageSecretPath -Name $_ })

$report = [ordered]@{
  generatedAtUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  infisicalUrl = $InfisicalUrl
  environment = $InfisicalEnvironment
  runtimePath = $RuntimeSecretPath
  installationPath = $InstallationSecretPath
  monitoringPath = $MonitoringSecretPath
  objectStoragePath = $ObjectStorageSecretPath
  counts = [ordered]@{
    runtimeCurrent = $runtimeNames.Count
    installationCurrent = $installationNames.Count
    monitoringCurrent = $monitoringNames.Count
    objectStorageCurrent = $objectStorageNames.Count
    expectedRuntime = $expectedRuntime.Count
    expectedInstallation = $expectedInstallation.Count
    expectedMonitoring = $expectedMonitoring.Count
    expectedObjectStorage = $expectedObjectStorage.Count
    duplicateNames = $duplicateNames.Count
    missingRuntime = $missingRuntime.Count
    missingInstallation = $missingInstallation.Count
    missingMonitoring = $missingMonitoring.Count
    missingObjectStorage = $missingObjectStorage.Count
    misplacedRuntime = $misplacedRuntime.Count
    misplacedInstallation = $misplacedInstallation.Count
    misplacedMonitoring = $misplacedMonitoring.Count
    misplacedObjectStorage = $misplacedObjectStorage.Count
    unmanagedRuntime = $unmanagedRuntime.Count
    unmanagedInstallation = $unmanagedInstallation.Count
    unmanagedMonitoring = $unmanagedMonitoring.Count
    unmanagedObjectStorage = $unmanagedObjectStorage.Count
  }
  duplicateNames = @($duplicateNames)
  missingRuntime = @($missingRuntime)
  missingInstallation = @($missingInstallation)
  missingMonitoring = @($missingMonitoring)
  missingObjectStorage = @($missingObjectStorage)
  misplacedRuntime = @($misplacedRuntime)
  misplacedInstallation = @($misplacedInstallation)
  misplacedMonitoring = @($misplacedMonitoring)
  misplacedObjectStorage = @($misplacedObjectStorage)
  unmanagedRuntime = @($unmanagedRuntime)
  unmanagedInstallation = @($unmanagedInstallation)
  unmanagedMonitoring = @($unmanagedMonitoring)
  unmanagedObjectStorage = @($unmanagedObjectStorage)
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
  New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

$json = $report | ConvertTo-Json -Depth 8
Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8
$json
