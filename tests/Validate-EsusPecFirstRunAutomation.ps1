Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$paths = @(
  "scripts/esus-pec/Invoke-EsusPecFirstRunConfig.ps1",
  "docs/esus-pec/2026-05-30-first-run-automation-plan.md",
  "docs/esus-pec/2026-05-30-first-run-wizard-automation.md",
  "docs/credentials/esus-pec-infisical-secrets.html",
  "config/esus-pec.infisical.env.example"
)

foreach ($relativePath in $paths) {
  $path = Join-Path $root $relativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing e-SUS PEC first-run artifact: $relativePath"
  }
}

$combined = ($paths | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $root $_) -Raw
  }) -join "`n"

$requiredFragments = @(
  "ESUS_PEC_INSTALLATION_NAME",
  "ESUS_PEC_INSTALLATION_URL",
  "ESUS_PEC_INSTALLATION_TYPE",
  "ESUS_PEC_INSTALLER_NAME_CIVIL",
  "ESUS_PEC_INSTALLER_CPF",
  "ESUS_PEC_INITIAL_PASSWORD",
  "mutation Instalar",
  "InstalacaoInput",
  "PRONTUARIO",
  "CENTRALIZADORA",
  "Dry-run only",
  "-Apply",
  "Nome da instalação",
  "Cadastrar instalador",
  "Finalizar instalação",
  "Não foi possível validar este endereço",
  "/esus-pec/test-lxc"
)

foreach ($fragment in $requiredFragments) {
  if ($combined -notmatch [regex]::Escape($fragment)) {
    throw "Missing required first-run automation fragment: $fragment"
  }
}

$script = Join-Path $root "scripts/esus-pec/Invoke-EsusPecFirstRunConfig.ps1"
$env:ESUS_PEC_BASE_URL = "http://192.0.2.10:8080"
$env:ESUS_PEC_INSTALLATION_NAME = "Automacao PEC Teste"
$env:ESUS_PEC_INSTALLATION_URL = "https://test.esus.example.org"
$env:ESUS_PEC_INSTALLATION_TYPE = "PRONTUARIO"
$env:ESUS_PEC_INSTALLER_NAME_CIVIL = "Operador Automacao"
$env:ESUS_PEC_INSTALLER_CPF = "529.982.247-25"
$env:ESUS_PEC_INITIAL_PASSWORD = "Auto#2026X"

$output = & $script 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
  throw "First-run script dry-run failed: $output"
}
if ($output -notmatch "\[REDACTED\]") {
  throw "First-run script dry-run did not redact the password."
}
if ($output -match [regex]::Escape($env:ESUS_PEC_INITIAL_PASSWORD)) {
  throw "First-run script dry-run leaked the password."
}

$forbidden = @(
  'ESUS_PEC_INITIAL_PASSWORD=.',
  'ESUS_PEC_DB_PASSWORD=.',
  '-----BEGIN .*PRIVATE KEY-----',
  'JSESSIONID=',
  'XSRF-TOKEN='
)

foreach ($pattern in $forbidden) {
  if ($combined -match $pattern) {
    throw "First-run artifacts appear to contain a secret or session-token pattern: $pattern"
  }
}

Write-Host "e-SUS PEC first-run automation artifacts are valid."
