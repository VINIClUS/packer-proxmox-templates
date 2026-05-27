Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$paths = @(
  "docs/esus-pec/2026-05-27-lxc-conversion-plan.md",
  "docs/esus-pec/2026-05-27-lxc-ct133-installation.md",
  "docs/credentials/esus-pec-infisical-secrets.html",
  "config/esus-pec.infisical.env.example",
  "scripts/esus-pec/bootstrap-lxc.sh",
  "scripts/esus-pec/install-lxc.sh",
  "docs/setup-readonly/2026-05-25-implementation-plan.md"
)

foreach ($relativePath in $paths) {
  $path = Join-Path $root $relativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing e-SUS PEC LXC artifact: $relativePath"
  }
}

$combined = ($paths | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $root $_) -Raw
  }) -join "`n"

$requiredFragments = @(
  'CTID: `133`',
  'esus-pec-lxc-5437',
  '192.168.1.209',
  'unprivileged',
  'RemoveIPC=no',
  'default-jre-headless',
  'locales',
  'No external PostgreSQL client/server package was installed',
  'e-SUS-AB-PostgreSQL.service`: `active`',
  'e-SUS-PEC.service`: `active`',
  '127.0.0.1:5433',
  '0.0.0.0:8080',
  'http://192.168.1.209:8080/ -> HTTP 200',
  '/opt/e-SUS/webserver/config/credenciais.txt',
  'Mode: 600',
  '/esus-pec/test-lxc',
  'VM `101 ESUS-TESTE`',
  'CT `100 Netbird`'
)

foreach ($fragment in $requiredFragments) {
  if ($combined -notmatch [regex]::Escape($fragment)) {
    throw "Missing required e-SUS PEC LXC documentation fragment: $fragment"
  }
}

$forbidden = @(
  'ESUS_PEC_DB_PASSWORD=.',
  'ESUS_PEC_ADMIN_PASSWORD=.',
  '-----BEGIN .*PRIVATE KEY-----',
  'JSESSIONID=',
  'XSRF-TOKEN='
)

foreach ($pattern in $forbidden) {
  if ($combined -match $pattern) {
    throw "Documentation appears to contain a secret or session-token pattern: $pattern"
  }
}

Write-Host "e-SUS PEC LXC documentation is valid."
