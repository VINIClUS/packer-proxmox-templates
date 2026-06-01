param(
  [Parameter(Mandatory = $true)]
  [string]$JsonPath,

  [string]$BaseUrl,
  [switch]$Apply,
  [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Exit-WithLastExitCode {
  if (Test-Path variable:global:LASTEXITCODE) {
    exit $global:LASTEXITCODE
  }
  exit 0
}

$requiredKeys = @(
  "ESUS_PEC_BASE_URL",
  "ESUS_PEC_INSTALLATION_NAME",
  "ESUS_PEC_INSTALLATION_URL",
  "ESUS_PEC_INSTALLATION_TYPE",
  "ESUS_PEC_INSTALLER_NAME_CIVIL",
  "ESUS_PEC_INSTALLER_CPF",
  "ESUS_PEC_INITIAL_PASSWORD"
)

if (-not (Test-Path -LiteralPath $JsonPath)) {
  throw "Secret JSON file not found: $JsonPath"
}

$secretValues = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json
$names = @($secretValues.PSObject.Properties.Name)
$missing = @($requiredKeys | Where-Object { $_ -notin $names })
if ($missing.Count -gt 0) {
  throw "Secret JSON is missing required keys: $($missing -join ', ')"
}

foreach ($key in $requiredKeys) {
  [Environment]::SetEnvironmentVariable($key, [string]$secretValues.$key, "Process")
}

$scriptPath = Join-Path $PSScriptRoot "Invoke-EsusPecFirstRunConfig.ps1"
if ($Apply) {
  if ($BaseUrl) {
    & $scriptPath -BaseUrl $BaseUrl -Apply
  } else {
    & $scriptPath -Apply
  }
  Exit-WithLastExitCode
}

if ($Quiet) {
  if ($BaseUrl) {
    & $scriptPath -BaseUrl $BaseUrl *> $null
  } else {
    & $scriptPath *> $null
  }
  Write-Output "dry_run_ok"
  Exit-WithLastExitCode
}

if ($BaseUrl) {
  & $scriptPath -BaseUrl $BaseUrl
} else {
  & $scriptPath
}
