Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$paths = @(
  "scripts/esus-pec/Configure-EsusPecGovBrOAuth.ps1",
  "scripts/esus-pec/Validate-EsusPecGovBrOAuth.mjs",
  "docs/esus-pec/2026-06-21-govbr-oauth-implementation-plan.md",
  "docs/credentials/esus-pec-infisical-secrets.html",
  "config/esus-pec.infisical.env.example"
)

foreach ($relativePath in $paths) {
  $path = Join-Path $root $relativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing Gov.br OAuth planning artifact: $relativePath"
  }
}

$combined = ($paths | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $root $_) -Raw
  }) -join "`n"

$requiredFragments = @(
  "GovBrOAuth.txt",
  "Configure-EsusPecGovBrOAuth.ps1",
  "Validate-EsusPecGovBrOAuth.mjs",
  "7F308D919AF4F4493CA86601D02BF291C905D76F1F686C9A8259A90AEBC96501",
  "bridge.security.oauth2.client.registration.govbr",
  "bridge.security.oauth2.client.registration.govbr.client-id",
  "bridge.security.oauth2.client.registration.govbr.client-secret",
  "ESUS_PEC_GOVBR_OAUTH_CLIENT_ID",
  "ESUS_PEC_GOVBR_OAUTH_CLIENT_SECRET",
  "ESUS_PEC_GOVBR_OAUTH_ALLOWED_DOMAIN=esus.presidenteepitacio.sp.gov.br",
  "ESUS_PEC_GOVBR_OAUTH_REDIRECT_BASE_URL=https://esus.presidenteepitacio.sp.gov.br",
  "ESUS_PEC_GOVBR_OAUTH_TEST_HOST_OVERRIDE=192.168.1.253 esus.presidenteepitacio.sp.gov.br",
  "ESUS_PEC_GOVBR_OAUTH_TEST_STRATEGY=production-domain-production-upstream",
  "ESUS_PEC_GOVBR_OAUTH_TLS_MODE=nginx-termination",
  "ESUS_PEC_GOVBR_OAUTH_NATIVE_TLS_FALLBACK=false",
  "ESUS_PEC_GOVBR_SSL_KEYSTORE_TYPE=PKCS12",
  "ESUS_PEC_GOVBR_DEBUG_MITM_REQUIRED=false",
  "mitmproxy",
  "govBREnabled=true",
  "serverTimezoneOffset=0"
)

foreach ($fragment in $requiredFragments) {
  if ($combined -notmatch [regex]::Escape($fragment)) {
    throw "Missing Gov.br OAuth plan fragment: $fragment"
  }
}

$forbiddenPatterns = @(
  'bridge\.security\.oauth2\.client\.registration\.govbr\.client-secret\s*=\s*[^`\r\n]+',
  'ESUS_PEC_GOVBR_OAUTH_CLIENT_SECRET=[^\r\n]+',
  'ESUS_PEC_GOVBR_SSL_KEYSTORE_PASSWORD=[^\r\n]+',
  '-----BEGIN .*PRIVATE KEY-----',
  'JSESSIONID=',
  'XSRF-TOKEN=',
  'esus\.presidenteepitacio\.sp\.gov\.br:443:192\.168\.1\.209',
  '192\.168\.1\.209\s+esus\.presidenteepitacio\.sp\.gov\.br'
)

foreach ($pattern in $forbiddenPatterns) {
  if ($combined -match $pattern) {
    throw "Gov.br OAuth plan artifacts appear to contain a secret pattern: $pattern"
  }
}

Write-Host "e-SUS PEC Gov.br OAuth planning artifacts are valid."
