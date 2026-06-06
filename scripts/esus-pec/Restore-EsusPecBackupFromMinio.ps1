param(
  [string]$ConfigFile = "config/Proxmox.pkrvars.hcl",
  [int]$TargetCtid = 133,
  [int]$ObjectStorageCtid = 134,
  [string]$ObjectKey = "",
  [string]$ExpectedSha256 = "",
  [string]$ExpectedSizeBytes = "",
  [string]$InfisicalUrl = "http://192.168.1.226:8080",
  [string]$InfisicalWorkspaceId = "2c83cfe9-e794-4961-977d-23000ae14461",
  [string]$InfisicalProjectSlug = "esus-pec-z-px-c",
  [string]$InfisicalEnvironment = "dev",
  [string]$InfisicalSecretPath = "/test",
  [switch]$Apply,
  [switch]$ConfirmDestructiveRestore,
  [switch]$SkipSnapshot,
  [switch]$KeepDownloadedBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-HclValue {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Text,
    [string]$Default = $null
  )
  $line = $Text -split "`n" | Where-Object {
    $_ -match ("^\s*" + [regex]::Escape($Name) + "\s*=")
  } | Select-Object -First 1
  if (-not $line) { return $Default }
  return (($line -split "=", 2)[1]).Trim().Trim('"')
}

function Invoke-ProxmoxSsh {
  param([Parameter(Mandatory = $true)][string]$Command)
  $output = & ssh -i $script:SshKey -p $script:SshPort -o BatchMode=yes -o StrictHostKeyChecking=accept-new $script:SshTarget $Command 2>&1
  if ($LASTEXITCODE -ne 0) {
    $output
    throw "Remote Proxmox command failed with exit code $LASTEXITCODE."
  }
  return ($output -join "`n")
}

function Invoke-ContainerBash {
  param(
    [Parameter(Mandatory = $true)][int]$Ctid,
    [Parameter(Mandatory = $true)][string]$Script
  )
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
  Invoke-ProxmoxSsh -Command "pct exec $Ctid -- bash -lc 'echo $encoded | base64 -d | bash'"
}

function Get-InfisicalToken {
  if ($env:infisical_secret_key) { return $env:infisical_secret_key }
  if ($env:INFISICAL_TOKEN) { return $env:INFISICAL_TOKEN }
  if (Test-Path -LiteralPath ".env") {
    $line = Get-Content -LiteralPath ".env" | Where-Object { $_ -match "^infisical_secret_key=" } | Select-Object -First 1
    if ($line) { return (($line -split "=", 2)[1]).Trim() }
  }
  throw "Infisical token not found. Set infisical_secret_key in .env or INFISICAL_TOKEN."
}

function Get-InfisicalSecrets {
  param([Parameter(Mandatory = $true)][hashtable]$Headers)
  $uri = "$InfisicalUrl/api/v3/secrets/raw?workspaceId=$InfisicalWorkspaceId&environment=$InfisicalEnvironment&secretPath=$([uri]::EscapeDataString($InfisicalSecretPath))"
  $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -TimeoutSec 30
  $result = @{}
  foreach ($secret in @($response.secrets)) {
    $result[[string]$secret.secretKey] = [string]$secret.secretValue
  }
  return $result
}

$configText = Get-Content -LiteralPath $ConfigFile -Raw
$sshHost = Get-HclValue -Name "proxmox_ssh_host" -Text $configText
$script:SshPort = Get-HclValue -Name "proxmox_ssh_port" -Text $configText -Default "22"
$sshUser = Get-HclValue -Name "proxmox_ssh_user" -Text $configText -Default "root"
$script:SshKey = Get-HclValue -Name "proxmox_ssh_private_key_file" -Text $configText
$script:SshTarget = "$sshUser@$sshHost"

if ($Apply -and -not $ConfirmDestructiveRestore) {
  throw "Refusing destructive restore. Re-run with -Apply -ConfirmDestructiveRestore after validating the target CT."
}

$headers = @{ Authorization = "Bearer $(Get-InfisicalToken)" }
$secrets = Get-InfisicalSecrets -Headers $headers

foreach ($name in @(
    "ESUS_PEC_OBJECT_STORAGE_API_URL",
    "ESUS_PEC_OBJECT_STORAGE_BUCKET",
    "ESUS_PEC_OBJECT_STORAGE_BACKUP_ACCESS_KEY",
    "ESUS_PEC_OBJECT_STORAGE_BACKUP_SECRET_KEY"
  )) {
  if (-not $secrets.ContainsKey($name)) {
    throw "Missing required Infisical secret: $name"
  }
}

if (-not $ObjectKey) {
  if (-not $secrets.ContainsKey("ESUS_PEC_OBJECT_STORAGE_BACKUP_OBJECT_KEY")) {
    throw "ObjectKey was not provided and ESUS_PEC_OBJECT_STORAGE_BACKUP_OBJECT_KEY is missing."
  }
  $ObjectKey = $secrets["ESUS_PEC_OBJECT_STORAGE_BACKUP_OBJECT_KEY"]
}

if (-not $ExpectedSha256 -and $secrets.ContainsKey("ESUS_PEC_OBJECT_STORAGE_BACKUP_SHA256")) {
  $ExpectedSha256 = $secrets["ESUS_PEC_OBJECT_STORAGE_BACKUP_SHA256"]
}
if (-not $ExpectedSizeBytes -and $secrets.ContainsKey("ESUS_PEC_OBJECT_STORAGE_BACKUP_SIZE_BYTES")) {
  $ExpectedSizeBytes = $secrets["ESUS_PEC_OBJECT_STORAGE_BACKUP_SIZE_BYTES"]
}

$apiUrl = $secrets["ESUS_PEC_OBJECT_STORAGE_API_URL"]
$bucket = $secrets["ESUS_PEC_OBJECT_STORAGE_BUCKET"]
$accessKey = $secrets["ESUS_PEC_OBJECT_STORAGE_BACKUP_ACCESS_KEY"]
$secretKey = $secrets["ESUS_PEC_OBJECT_STORAGE_BACKUP_SECRET_KEY"]
$fileName = Split-Path -Path $ObjectKey -Leaf
$remoteObjectStoragePath = "/tmp/esus-pec-restore-$fileName"
$remoteHostPath = "/tmp/esus-pec-restore-$TargetCtid-$fileName"
$remoteTargetDir = "/tmp/esus-pec-restore"
$remoteTargetPath = "$remoteTargetDir/$fileName"

$downloadScript = @"
set -euo pipefail
export MC_CONFIG_DIR=/root/.mc-esus-restore-download
rm -rf "`$MC_CONFIG_DIR"
/usr/local/bin/mc alias set restore "$apiUrl" "$accessKey" "$secretKey" --insecure >/dev/null
/usr/local/bin/mc cp "restore/$bucket/$ObjectKey" "$remoteObjectStoragePath" --insecure >/dev/null
sha256sum "$remoteObjectStoragePath"
stat -c '%s' "$remoteObjectStoragePath"
"@
$downloadOutput = Invoke-ContainerBash -Ctid $ObjectStorageCtid -Script $downloadScript
$downloadHash = (($downloadOutput -split "`n" | Where-Object { $_ -match "^[0-9a-fA-F]{64}\s" } | Select-Object -First 1) -split "\s+")[0].ToUpperInvariant()
$downloadSize = ($downloadOutput -split "`n" | Where-Object { $_ -match "^\d+$" } | Select-Object -First 1).Trim()

if ($ExpectedSha256 -and ($downloadHash -ne $ExpectedSha256.ToUpperInvariant())) {
  throw "Downloaded object checksum mismatch."
}
if ($ExpectedSizeBytes -and ([int64]$downloadSize -ne [int64]$ExpectedSizeBytes)) {
  throw "Downloaded object size mismatch."
}

Invoke-ProxmoxSsh -Command "pct pull $ObjectStorageCtid '$remoteObjectStoragePath' '$remoteHostPath' >/dev/null"
Invoke-ProxmoxSsh -Command "pct exec $TargetCtid -- mkdir -p '$remoteTargetDir' && pct push $TargetCtid '$remoteHostPath' '$remoteTargetPath' --perms 0600 >/dev/null && rm -f '$remoteHostPath'"

$validateScript = @"
set -euo pipefail
PG_BIN=/opt/e-SUS/database/current/bin
BACKUP="$remoteTargetPath"
test -x "`$PG_BIN/pg_restore"
test -x "`$PG_BIN/psql"
test -x "`$PG_BIN/createdb"
test -x "`$PG_BIN/dropdb"
sha256sum "`$BACKUP"
stat -c '%s' "`$BACKUP"
"`$PG_BIN/pg_restore" --list "`$BACKUP" | sed -n '1,20p'
"`$PG_BIN/pg_isready" -h localhost -p 5433 -U postgres
systemctl is-active e-SUS-PEC.service
"@
$validationOutput = Invoke-ContainerBash -Ctid $TargetCtid -Script $validateScript

if (-not $Apply) {
  if (-not $KeepDownloadedBackup) {
    Invoke-ProxmoxSsh -Command "pct exec $TargetCtid -- rm -f '$remoteTargetPath'; pct exec $ObjectStorageCtid -- rm -f '$remoteObjectStoragePath'"
  }
  [ordered]@{
    apply = $false
    targetCtid = $TargetCtid
    objectStorageCtid = $ObjectStorageCtid
    bucket = $bucket
    objectKey = $ObjectKey
    downloadedSha256 = $downloadHash
    downloadedSizeBytes = $downloadSize
    validation = "pg_restore_list_ok"
    destructiveRestoreRequiredFlags = "-Apply -ConfirmDestructiveRestore"
    downloadedBackupKept = $KeepDownloadedBackup.IsPresent
  } | ConvertTo-Json -Depth 4
  exit 0
}

$snapshotName = "pre-pec-restore-$(Get-Date -Format yyyyMMddHHmmss)"
if (-not $SkipSnapshot) {
  Invoke-ProxmoxSsh -Command "pct snapshot $TargetCtid '$snapshotName' --description 'Before e-SUS PEC restore from $ObjectKey' >/dev/null"
}

$restoreScript = @"
set -euo pipefail
PG_BIN=/opt/e-SUS/database/current/bin
BACKUP="$remoteTargetPath"
SERVICE=e-SUS-PEC.service
export PGCLIENTENCODING=UTF8
systemctl stop "`$SERVICE"
"`$PG_BIN/pg_isready" -h localhost -p 5433 -U postgres
"`$PG_BIN/psql" -p 5433 -U postgres -d esus -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND datname = 'esus';"
"`$PG_BIN/dropdb" -p 5433 -U postgres --if-exists esus_new
"`$PG_BIN/createdb" -E UTF8 -T template0 -p 5433 -U postgres esus_new
"`$PG_BIN/pg_restore" -p 5433 -U postgres -1 -Fc -d esus_new -O "`$BACKUP"
"`$PG_BIN/psql" -p 5433 -U postgres -d esus -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND datname = 'esus';"
"`$PG_BIN/dropdb" -p 5433 -U postgres esus
"`$PG_BIN/psql" -p 5433 -U postgres -c "ALTER DATABASE esus_new RENAME TO esus;"
systemctl start "`$SERVICE"
systemctl is-active "`$SERVICE"
"@
$restoreOutput = Invoke-ContainerBash -Ctid $TargetCtid -Script $restoreScript

if (-not $KeepDownloadedBackup) {
  Invoke-ProxmoxSsh -Command "pct exec $TargetCtid -- rm -f '$remoteTargetPath'; pct exec $ObjectStorageCtid -- rm -f '$remoteObjectStoragePath'"
}

[ordered]@{
  apply = $true
  targetCtid = $TargetCtid
  objectStorageCtid = $ObjectStorageCtid
  bucket = $bucket
  objectKey = $ObjectKey
  downloadedSha256 = $downloadHash
  downloadedSizeBytes = $downloadSize
  snapshot = if ($SkipSnapshot) { "" } else { $snapshotName }
  restore = "completed"
  service = "e-SUS-PEC.service"
  downloadedBackupKept = $KeepDownloadedBackup.IsPresent
} | ConvertTo-Json -Depth 4
