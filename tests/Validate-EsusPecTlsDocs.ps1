Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$paths = @(
  "scripts/esus-pec/Enable-EsusPecLxcTls.ps1",
  "scripts/esus-pec/Set-EsusPecTlsProxyInfisicalMetadata.ps1",
  "docs/esus-pec/2026-06-05-lxc-tls.md",
  "docs/esus-pec/2026-06-23-production-tls-preflight.md",
  "docs/credentials/esus-pec-infisical-secrets.html",
  "config/esus-pec.infisical.env.example"
)

foreach ($relativePath in $paths) {
  $path = Join-Path $root $relativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing e-SUS PEC TLS artifact: $relativePath"
  }
}

$scriptPaths = @(
  "scripts/esus-pec/Enable-EsusPecLxcTls.ps1",
  "scripts/esus-pec/Set-EsusPecTlsProxyInfisicalMetadata.ps1"
)
foreach ($scriptPath in $scriptPaths) {
  $scriptErrors = $null
  $null = [System.Management.Automation.PSParser]::Tokenize(
    (Get-Content -LiteralPath (Join-Path $root $scriptPath) -Raw),
    [ref]$scriptErrors
  )
  if ($scriptErrors.Count -gt 0) {
    throw "TLS PowerShell script has parse errors in ${scriptPath}: $($scriptErrors -join '; ')"
  }
}

$combined = ($paths | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $root $_) -Raw
  }) -join "`n"

$requiredFragments = @(
  "Enable-EsusPecLxcTls.ps1",
  "Set-EsusPecTlsProxyInfisicalMetadata.ps1",
  "ESUS_PEC_TLS_CERTIFICATE_PEM",
  "ESUS_PEC_TLS_PRIVATE_KEY_PEM",
  "ESUS_PEC_TLS_HTTPS_URL",
  "ESUS_PEC_TLS_CERTIFICATE_SHA256",
  "ESUS_PEC_TLS_CERTIFICATE_NOT_AFTER",
  "ESUS_PEC_TLS_CERTIFICATE_SAN",
  "ESUS_PEC_TLS_CERTIFICATE_KIND",
  "ESUS_PEC_TLS_TERMINATION",
  "ESUS_PEC_TLS_PROXY_LXC_CTID",
  "ESUS_PEC_TLS_PROXY_LXC_IP",
  "ESUS_PEC_TLS_PROXY_LXC_NAME",
  "ESUS_PEC_TLS_UPSTREAM_LXC_IP",
  "ESUS_PEC_TLS_UPSTREAM_URL",
  "ESUS_PEC_PRODUCTION_UPSTREAM_URL=https://192.168.1.253",
  "PEC_UPSTREAM_URL",
  "SkipPublicAcmePreflight",
  "Production TLS Preflight",
  "Invalid API Token",
  "prod_upstream_status",
  "certbotRenewDryRunStatus=success",
  "ssl_verify_result=0",
  "C=US, O=Let's Encrypt, CN=YE1",
  "nginx-edge-lxc-certbot",
  'CT `110`',
  'production PEC vhost for `esus.presidenteepitacio.sp.gov.br` must proxy to `https://192.168.1.253`',
  "ACME_PUBLIC_HTTP_STATUS=000",
  "/test/InstallationConfig",
  "No PEM values are stored in Git or documentation",
  "pct exec 110 -- rm -f /etc/nginx/sites-enabled/esus-pec-tls.conf"
)

foreach ($fragment in $requiredFragments) {
  if ($combined -notmatch [regex]::Escape($fragment)) {
    throw "Missing TLS documentation fragment: $fragment"
  }
}

$forbiddenPatterns = @(
  '-----BEGIN CERTIFICATE-----',
  '-----BEGIN .*PRIVATE KEY-----',
  'ESUS_PEC_TLS_PRIVATE_KEY_PEM=[^\r\n]+',
  'ESUS_PEC_TLS_CERTIFICATE_PEM=[^\r\n]+',
  'esus\.presidenteepitacio\.sp\.gov\.br:443:192\.168\.1\.209',
  '192\.168\.1\.209\s+esus\.presidenteepitacio\.sp\.gov\.br'
)

foreach ($pattern in $forbiddenPatterns) {
  if ($combined -match $pattern) {
    throw "TLS artifacts appear to contain PEM material or private key content: $pattern"
  }
}

Write-Host "e-SUS PEC TLS artifacts are valid."
