Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$paths = @(
  "docs/esus-pec/2026-06-06-https-variable-validation.md",
  "docs/credentials/esus-pec-infisical-secrets.html"
)

foreach ($relativePath in $paths) {
  $path = Join-Path $root $relativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing e-SUS PEC HTTPS validation artifact: $relativePath"
  }
}

$combined = ($paths | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $root $_) -Raw
  }) -join "`n"

$requiredFragments = @(
  "ESUS_PEC_TLS_HTTPS_URL",
  "ESUS_PEC_LXC_TEST_HTTPS_URL",
  "ESUS_PEC_BASE_UNIFICATION_ENABLED",
  "ESUS_PEC_BASE_UNIFICATION_MODE",
  "https://192.168.1.209/",
  "configuracoes/instalacao/unificacaobase",
  "nginx=active",
  "e-SUS-PEC.service=active",
  "fingerprint_matches_live_certificate=true",
  "No secret values, PEM bodies, cookies, or tokens"
)

foreach ($fragment in $requiredFragments) {
  if ($combined -notmatch [regex]::Escape($fragment)) {
    throw "Missing HTTPS validation documentation fragment: $fragment"
  }
}

$forbiddenPatterns = @(
  '-----BEGIN CERTIFICATE-----',
  '-----BEGIN .*PRIVATE KEY-----',
  ('JSESSION' + 'ID='),
  ('XSRF' + '-TOKEN='),
  'Authorization:\s*Bearer',
  'ESUS_PEC_.*PASSWORD=[^\r\n]+'
)

foreach ($pattern in $forbiddenPatterns) {
  if ($combined -match $pattern) {
    throw "HTTPS validation artifacts appear to contain secret material: $pattern"
  }
}

Write-Host "e-SUS PEC HTTPS validation artifacts are valid."
