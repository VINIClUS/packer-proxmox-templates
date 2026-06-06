Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$paths = @(
  "scripts/esus-pec/Provision-EsusPecMinioObjectStorage.ps1",
  "scripts/esus-pec/Upload-EsusPecBackupToMinio.ps1",
  "docs/esus-pec/2026-06-06-minio-object-storage.md",
  "docs/credentials/esus-pec-object-storage-credentials.html",
  "config/esus-pec.infisical.env.example"
)

foreach ($relativePath in $paths) {
  $path = Join-Path $root $relativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing e-SUS PEC object-storage artifact: $relativePath"
  }
}

foreach ($script in @(
    "scripts/esus-pec/Provision-EsusPecMinioObjectStorage.ps1",
    "scripts/esus-pec/Upload-EsusPecBackupToMinio.ps1"
  )) {
  $scriptErrors = $null
  $null = [System.Management.Automation.PSParser]::Tokenize(
    (Get-Content -LiteralPath (Join-Path $root $script) -Raw),
    [ref]$scriptErrors
  )
  if ($scriptErrors.Count -gt 0) {
    throw "Object-storage script has parse errors: $script"
  }
}

$combined = ($paths | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $root $_) -Raw
  }) -join "`n"

$requiredFragments = @(
  "ESUS_PEC_OBJECT_STORAGE_PROVIDER",
  "ESUS_PEC_OBJECT_STORAGE_ROOT_PASSWORD",
  "ESUS_PEC_OBJECT_STORAGE_BACKUP_SECRET_KEY",
  "ESUS_PEC_OBJECT_STORAGE_TLS_PRIVATE_KEY_PEM",
  "ESUS_PEC_OBJECT_STORAGE_BACKUP_SHA256",
  "esus-pec-minio",
  "192.168.1.210",
  "rpool/subvol-134-disk-0",
  "esus-pec-backups",
  "postgres/2026/05/20260519192557-esus-postgres.backup",
  "A388D0769B5B0907652E3DC325E5FEFD7782A4D8206B070AA8CFF31E5DF3918C",
  "object_lock=enabled",
  "versioning=enabled",
  "local_backup_present=false"
)

foreach ($fragment in $requiredFragments) {
  if ($combined -notmatch [regex]::Escape($fragment)) {
    throw "Missing object-storage documentation fragment: $fragment"
  }
}

$forbiddenPatterns = @(
  ('-----BEGIN CERT' + 'IFICATE-----'),
  ('-----BEGIN .*PRIVATE ' + 'KEY-----'),
  ('ESUS_PEC_.*PASS' + 'WORD=[^\r\n]+'),
  ('ESUS_PEC_.*SECRET' + '_KEY=[^\r\n]+'),
  'Authorization:\s*Bearer',
  ('JSESSION' + 'ID='),
  ('XSRF' + '-TOKEN=')
)

foreach ($pattern in $forbiddenPatterns) {
  if ($combined -match $pattern) {
    throw "Object-storage artifacts appear to contain secret material: $pattern"
  }
}

Write-Host "e-SUS PEC object-storage artifacts are valid."
