Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$docPath = Join-Path $root "docs/esus-pec/2026-06-13-production-replacement-variable-comparison.md"
$htmlPath = Join-Path $root "docs/credentials/esus-pec-infisical-secrets.html"
$examplePath = Join-Path $root "config/esus-pec.infisical.env.example"
$collectorPath = Join-Path $root "scripts/esus-pec/Collect-EsusPecConfigurationComparison.mjs"

foreach ($path in @($docPath, $htmlPath, $examplePath, $collectorPath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing production replacement comparison artifact: $path"
  }
}

$combined = @(
  Get-Content -LiteralPath $docPath -Raw
  Get-Content -LiteralPath $htmlPath -Raw
  Get-Content -LiteralPath $examplePath -Raw
  Get-Content -LiteralPath $collectorPath -Raw
) -join "`n"

$requiredFragments = @(
  "ESUS_PEC_GOVBR_ENABLED=true",
  "ESUS_PEC_SERVER_TIMEZONE=America/Sao_Paulo",
  "ESUS_PEC_SERVER_TIMEZONE_OFFSET_MINUTES=-180",
  "ESUS_PEC_CNES_IMPORT_ROUTE=/importarCnes",
  "ESUS_PEC_BOLSA_FAMILIA_IMPORT_ROUTE=/importar-bolsa-familia",
  "ESUS_PEC_BOLSA_FAMILIA_EXPECTED_LATEST_VIGENCIA=202402",
  "ESUS_PEC_BOLSA_FAMILIA_EXPECTED_IMPORT_COUNT=1",
  "ESUS_PEC_BOLSA_FAMILIA_EXPECTED_IMPORT_STATUS=FINALIZADO",
  "ESUS_PEC_TRANSMISSAO_CONFIG_ROUTE=/transmissao/configuracoes",
  "ESUS_PEC_TRANSMISSAO_LINK_HOSTNAME=esusab.saude.gov.br",
  "ESUS_PEC_TRANSMISSAO_LINK_NAME=Centralizador Nacional",
  "ESUS_PEC_TRANSMISSAO_LINK_ACTIVE=true",
  "ESUS_PEC_TRANSMISSAO_LINK_STATUS_EXPECTED=true",
  "ESUS_PEC_TRANSMISSAO_LOTE_PROCESSAMENTO_HORARIO=00:00:00",
  "ESUS_PEC_TRANSMISSAO_CREDENCIAIS_INTEGRACAO_EXPECTED_COUNT=0",
  "ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_PERSON_TYPE=FISICA",
  "ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_RESPONSIBLE_NAME=",
  "ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_CPF_CNPJ=",
  "ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_EMAIL=",
  "ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_NAME=",
  "ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_ACTIVE_ONLY=false",
  "govBREnabled",
  "serverTimezoneOffset",
  "Pagina nao encontrada"
)

foreach ($fragment in $requiredFragments) {
  if ($combined -notmatch [regex]::Escape($fragment)) {
    throw "Missing production replacement comparison fragment: $fragment"
  }
}

$forbiddenPatterns = @(
  'password_esus_presidenteepitacio\s*=\s*[^`\r\n]+',
  'user_esus_presidenteepitacio\s*=\s*[^`\r\n]+',
  'JSESSIONID=',
  'XSRF-TOKEN=',
  '-----BEGIN .*PRIVATE KEY-----',
  'ESUS_PEC_[A-Z0-9_]*PASSWORD=[^\r\n]+',
  'ESUS_PEC_[A-Z0-9_]*SECRET=[^\r\n]+'
)

foreach ($pattern in $forbiddenPatterns) {
  if ($combined -match $pattern) {
    throw "Comparison artifacts appear to contain a secret or session-token pattern: $pattern"
  }
}

Write-Host "e-SUS PEC production replacement comparison artifacts are valid."
