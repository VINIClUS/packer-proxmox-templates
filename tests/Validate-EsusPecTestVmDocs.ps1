Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$paths = @(
  "docs/esus-pec/2026-05-25-test-vm-102-implementation.md",
  "docs/credentials/esus-pec-infisical-secrets.html",
  "config/esus-pec.infisical.env.example"
)

foreach ($relativePath in $paths) {
  $path = Join-Path $root $relativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing e-SUS PEC test VM artifact: $relativePath"
  }
}

$combined = ($paths | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $root $_) -Raw
  }) -join "`n"

$requiredFragments = @(
  'VMID: 102',
  'test-esus-pec-5437',
  'VM `101 ESUS-TESTE` was not modified',
  'CT `100 Netbird` was not',
  '192.168.1.202',
  '9975a55184a6dd1f66d8a837bbc533376e0400069485e8acb45100c23a535bfb',
  'OpenJDK 21.0.11',
  'PostgreSQL 17.10',
  'Esta ferramenta necessita executar com privilégios de administrador',
  'ESUS_PEC_DB_PASSWORD',
  'ESUS_PEC_ADMIN_PASSWORD',
  'ESUS_PEC_TLS_PRIVATE_KEY_PEM',
  '/esus-pec/test'
)

foreach ($fragment in $requiredFragments) {
  if ($combined -notmatch [regex]::Escape($fragment)) {
    throw "Missing required e-SUS PEC test VM documentation fragment: $fragment"
  }
}

$exampleLines = Get-Content -LiteralPath (Join-Path $root "config/esus-pec.infisical.env.example")
foreach ($line in $exampleLines) {
  if ($line -match '^\s*#' -or $line -match '^\s*$') {
    continue
  }
  if ($line -match '^\s*([A-Z0-9_]*(PASSWORD|PRIVATE_KEY|CERTIFICATE)[A-Z0-9_]*)=(.+)$' -and $matches[3].Trim()) {
    throw "Sensitive placeholder must not contain a value: $($matches[1])"
  }
  if ($line -match '-----BEGIN') {
    throw "Example file appears to contain PEM material."
  }
}

Write-Host "e-SUS PEC test VM documentation and Infisical placeholders are valid."
