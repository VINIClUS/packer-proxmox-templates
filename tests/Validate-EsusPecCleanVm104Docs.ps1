Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$paths = @(
  "docs/esus-pec/2026-05-26-clean-vm-104-installation.md",
  "docs/credentials/esus-pec-infisical-secrets.html",
  "config/esus-pec.infisical.env.example",
  "docs/setup-readonly/2026-05-25-implementation-plan.md"
)

foreach ($relativePath in $paths) {
  $path = Join-Path $root $relativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing e-SUS PEC VM 104 artifact: $relativePath"
  }
}

$combined = ($paths | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $root $_) -Raw
  }) -join "`n"

$requiredFragments = @(
  'VMID: 104',
  'test-esus-pec-clean104-5437',
  'VM `101 ESUS-TESTE` was not modified',
  'CT `100 Netbird` was not modified',
  'sudo java -jar eSUS-AB-PEC-5.4.37-Linux64.jar -console -continue',
  'pt_BR.UTF-8',
  'No external PostgreSQL client/server package was installed',
  'e-SUS-AB-PostgreSQL.service: active running',
  'e-SUS-PEC.service: active running',
  '0.0.0.0:8080',
  'http://192.168.1.204:8080/ -> HTTP 200',
  '/opt/e-SUS/webserver/config/credenciais.txt',
  'Mode: 600',
  '/esus-pec/test'
)

foreach ($fragment in $requiredFragments) {
  if ($combined -notmatch [regex]::Escape($fragment)) {
    throw "Missing required e-SUS PEC VM 104 documentation fragment: $fragment"
  }
}

$forbidden = @(
  'ESUS_PEC_DB_PASSWORD=.',
  'ESUS_PEC_ADMIN_PASSWORD=.',
  '-----BEGIN .*PRIVATE KEY-----'
)

foreach ($pattern in $forbidden) {
  if ($combined -match $pattern) {
    throw "Documentation appears to contain a secret pattern: $pattern"
  }
}

Write-Host "e-SUS PEC clean VM 104 documentation is valid."
