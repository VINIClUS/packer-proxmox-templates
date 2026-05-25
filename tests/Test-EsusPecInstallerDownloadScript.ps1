Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$scriptPath = Join-Path $root "shared/scripts/Get-EsusPecInstaller.ps1"

if (-not (Test-Path -LiteralPath $scriptPath)) {
  throw "Missing e-SUS PEC installer script: $scriptPath"
}

$linuxDryRun = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Platform Linux -DryRun
if ($LASTEXITCODE -ne 0) {
  throw "Linux dry-run failed."
}

$windowsDryRun = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Platform Windows -DryRun
if ($LASTEXITCODE -ne 0) {
  throw "Windows dry-run failed."
}

$expectedFragments = @(
  "Version: 5.4.37",
  "https://sisaps.saude.gov.br/sistemas/esusaps/blog/versao-5-4-37/",
  "eSUS-AB-PEC-5.4.37-Linux64.jar",
  "eSUS-AB-PEC-5.4.37-Win64.jar",
  "DryRun: no download performed."
)

$combined = "$($linuxDryRun -join "`n")`n$($windowsDryRun -join "`n")"
foreach ($fragment in $expectedFragments) {
  if ($combined -notmatch [regex]::Escape($fragment)) {
    throw "Dry-run output missing expected fragment: $fragment"
  }
}

Write-Host "e-SUS PEC installer download script dry-runs are valid."
