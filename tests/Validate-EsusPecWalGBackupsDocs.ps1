Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$requiredFiles = @(
  "scripts/esus-pec/Configure-EsusPecWalGBackups.ps1",
  "docs/esus-pec/2026-06-06-walg-backup-policy.md",
  "docs/esus-pec/2026-06-06-pec-backup-restore-tooling.md",
  "docs/credentials/esus-pec-object-storage-credentials.html",
  "config/esus-pec.infisical.env.example"
)

foreach ($file in $requiredFiles) {
  if (-not (Test-Path -LiteralPath $file)) {
    throw "Missing required file: $file"
  }
}

$example = Get-Content -LiteralPath "config/esus-pec.infisical.env.example" -Raw
foreach ($name in @(
    "ESUS_PEC_WALG_ENABLED",
    "ESUS_PEC_WALG_VERSION",
    "ESUS_PEC_WALG_S3_PREFIX",
    "ESUS_PEC_WALG_RETENTION_FULL",
    "ESUS_PEC_WALG_FULL_BACKUP_SCHEDULE",
    "ESUS_PEC_WALG_LAST_FULL_BACKUP"
  )) {
  if ($example -notmatch "(?m)^$([regex]::Escape($name))=") {
    throw "Missing example variable: $name"
  }
}

$policy = Get-Content -LiteralPath "docs/esus-pec/2026-06-06-walg-backup-policy.md" -Raw
foreach ($needle in @(
    "esus-pec-walg-full-backup.timer",
    "wal-g delete retain FULL 4 --confirm",
    "base_0000000100000000000000E5",
    "wal_verify_integrity=OK"
  )) {
  if ($policy -notlike "*$needle*") {
    throw "Missing WAL-G policy evidence: $needle"
  }
}

$script = Get-Content -LiteralPath "scripts/esus-pec/Configure-EsusPecWalGBackups.ps1" -Raw
foreach ($needle in @(
    "archive_command = '/usr/local/bin/esus-pec-walg-wal-push %p'",
    'OnCalendar=$Schedule',
    "timeout 60 /usr/local/bin/wal-g backup-list",
    "run_pg_ctl -l"
  )) {
  if ($script -notlike "*$needle*") {
    throw "Missing script behavior: $needle"
  }
}

"WAL-G backup documentation validation passed."
