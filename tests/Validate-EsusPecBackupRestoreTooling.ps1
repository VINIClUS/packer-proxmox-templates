Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$paths = @(
  "scripts/esus-pec/Restore-EsusPecBackupFromMinio.ps1",
  "docs/esus-pec/2026-06-06-pec-backup-restore-tooling.md",
  "docs/esus-pec/2026-06-06-minio-object-storage.md"
)

foreach ($relativePath in $paths) {
  $path = Join-Path $root $relativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing e-SUS PEC backup-restore artifact: $relativePath"
  }
}

$scriptPath = Join-Path $root "scripts/esus-pec/Restore-EsusPecBackupFromMinio.ps1"
$scriptErrors = $null
$null = [System.Management.Automation.PSParser]::Tokenize(
  (Get-Content -LiteralPath $scriptPath -Raw),
  [ref]$scriptErrors
)
if ($scriptErrors.Count -gt 0) {
  throw "Restore script has parse errors."
}

$combined = ($paths | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $root $_) -Raw
  }) -join "`n"

$requiredFragments = @(
  "backup-postgres.sh",
  "backup-postgres.jar",
  "HeadlessException",
  "RestoreTask",
  "pg_restore --list",
  "esus_new",
  "Restore-EsusPecBackupFromMinio.ps1",
  "-Apply -ConfirmDestructiveRestore",
  "pre-pec-restore",
  "pg_restore_list_ok",
  "A388D0769B5B0907652E3DC325E5FEFD7782A4D8206B070AA8CFF31E5DF3918C",
  "temporary_files_removed=true"
)

foreach ($fragment in $requiredFragments) {
  if ($combined -notmatch [regex]::Escape($fragment)) {
    throw "Missing backup-restore documentation fragment: $fragment"
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
    throw "Backup-restore artifacts appear to contain secret material: $pattern"
  }
}

Write-Host "e-SUS PEC backup-restore artifacts are valid."
