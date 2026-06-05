Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$docPath = Join-Path $root "docs/esus-pec/2026-06-05-installation-config-variable-inventory.md"
$htmlPath = Join-Path $root "docs/credentials/esus-pec-infisical-secrets.html"
$examplePath = Join-Path $root "config/esus-pec.infisical.env.example"

foreach ($path in @($docPath, $htmlPath, $examplePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing e-SUS PEC installation configuration artifact: $path"
  }
}

$combined = @(
  Get-Content -LiteralPath $docPath -Raw
  Get-Content -LiteralPath $htmlPath -Raw
  Get-Content -LiteralPath $examplePath -Raw
) -join "`n"

$requiredFragments = @(
  "ESUS_PEC_INTERNET_ENABLED",
  "ESUS_PEC_CADSUS_ENABLED",
  "ESUS_PEC_HORUS_ENABLED",
  "ESUS_PEC_SMTP_ENABLED",
  "ESUS_PEC_SMTP_FROM_EMAIL",
  "ESUS_PEC_SMTP_USE_LOGIN_AS_SENDER",
  "ESUS_PEC_MUNICIPALITY_ID",
  "ESUS_PEC_RESPONSIBLE_PROFESSIONAL_ID",
  "ESUS_PEC_FILE_ATTACHMENTS_DIRECTORY",
  "ESUS_PEC_CONCURRENT_REQUESTS",
  "ESUS_PEC_BASE_UNIFICATION_MODE",
  "AlterarServidorSMTP",
  "AlterarConfiguracaoAnexoArquivos",
  "AlterarQtdRequisicoes",
  "unificacaoBaseAtiva",
  "Reuse existing SMTP credentials",
  "No PEC settings were changed"
)

foreach ($fragment in $requiredFragments) {
  if ($combined -notmatch [regex]::Escape($fragment)) {
    throw "Missing installation configuration inventory fragment: $fragment"
  }
}

$forbiddenPatterns = @(
  'ESUS_PEC_[A-Z0-9_]*PASSWORD=[^\r\n]+',
  'ESUS_PEC_[A-Z0-9_]*SECRET=[^\r\n]+',
  'JSESSIONID=',
  'XSRF-TOKEN=',
  '-----BEGIN .*PRIVATE KEY-----'
)

foreach ($pattern in $forbiddenPatterns) {
  if ($combined -match $pattern) {
    throw "Inventory appears to contain a secret or session-token pattern: $pattern"
  }
}

Write-Host "e-SUS PEC installation configuration inventory artifacts are valid."
