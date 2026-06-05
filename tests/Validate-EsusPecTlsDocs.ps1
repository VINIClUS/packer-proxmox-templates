Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$paths = @(
  "scripts/esus-pec/Enable-EsusPecLxcTls.ps1",
  "docs/esus-pec/2026-06-05-lxc-tls.md",
  "docs/credentials/esus-pec-infisical-secrets.html",
  "config/esus-pec.infisical.env.example"
)

foreach ($relativePath in $paths) {
  $path = Join-Path $root $relativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing e-SUS PEC TLS artifact: $relativePath"
  }
}

$scriptErrors = $null
$null = [System.Management.Automation.PSParser]::Tokenize(
  (Get-Content -LiteralPath (Join-Path $root "scripts/esus-pec/Enable-EsusPecLxcTls.ps1") -Raw),
  [ref]$scriptErrors
)
if ($scriptErrors.Count -gt 0) {
  throw "TLS PowerShell script has parse errors: $($scriptErrors -join '; ')"
}

$combined = ($paths | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $root $_) -Raw
  }) -join "`n"

$requiredFragments = @(
  "Enable-EsusPecLxcTls.ps1",
  "ESUS_PEC_TLS_CERTIFICATE_PEM",
  "ESUS_PEC_TLS_PRIVATE_KEY_PEM",
  "ESUS_PEC_TLS_HTTPS_URL",
  "ESUS_PEC_TLS_CERTIFICATE_SHA256",
  "ESUS_PEC_TLS_CERTIFICATE_NOT_AFTER",
  "ESUS_PEC_TLS_CERTIFICATE_SAN",
  "ESUS_PEC_TLS_CERTIFICATE_KIND",
  "ESUS_PEC_TLS_TERMINATION",
  "nginx-lxc",
  "https://192.168.1.209/",
  "/test/InstallationConfig",
  "No PEM values are stored in Git or documentation",
  "pct exec 133 -- systemctl disable --now nginx"
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
  'ESUS_PEC_TLS_CERTIFICATE_PEM=[^\r\n]+'
)

foreach ($pattern in $forbiddenPatterns) {
  if ($combined -match $pattern) {
    throw "TLS artifacts appear to contain PEM material or private key content: $pattern"
  }
}

Write-Host "e-SUS PEC TLS artifacts are valid."
