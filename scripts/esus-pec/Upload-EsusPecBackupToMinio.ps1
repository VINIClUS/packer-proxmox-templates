param(
  [string]$ConfigFile = "config/Proxmox.pkrvars.hcl",
  [int]$Ctid = 134,
  [string]$BackupFile = "20260519192557-esus-postgres.backup",
  [string]$ObjectKey = "postgres/2026/05/20260519192557-esus-postgres.backup",
  [string]$InfisicalUrl = "http://192.168.1.226:8080",
  [string]$InfisicalWorkspaceId = "2c83cfe9-e794-4961-977d-23000ae14461",
  [string]$InfisicalProjectSlug = "esus-pec-z-px-c",
  [string]$InfisicalEnvironment = "dev",
  [string]$InfisicalSecretPath = "/test/ObjectStorage",
  [switch]$RemoveLocalAfterValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\InfisicalEndpoint.ps1")
$infisicalEnvFile = if (Get-Variable -Name EnvFile -ErrorAction SilentlyContinue) { $EnvFile } else { ".env" }
$InfisicalUrl = Resolve-InfisicalUrl -CurrentValue $InfisicalUrl -EnvFilePath $infisicalEnvFile

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

function Get-InfisicalToken {
  if ($env:infisical_secret_key) { return $env:infisical_secret_key }
  if ($env:INFISICAL_TOKEN) { return $env:INFISICAL_TOKEN }
  if (Test-Path -LiteralPath ".env") {
    foreach ($candidate in @("infisical_secret_key", "INFISICAL_TOKEN")) {
      $line = Get-Content -LiteralPath ".env" | Where-Object { $_ -match ("^" + [regex]::Escape($candidate) + "=") } | Select-Object -First 1
      if ($line) {
        $value = (($line -split "=", 2)[1]).Trim().Trim('"').Trim("'")
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
      }
    }
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

function Set-InfisicalSecret {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [AllowEmptyString()][Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][hashtable]$Headers,
    [Parameter(Mandatory = $true)][bool]$Exists
  )
  $uri = "$InfisicalUrl/api/v3/secrets/raw/$([uri]::EscapeDataString($Name))"
  $body = @{
    environment = $InfisicalEnvironment
    workspaceId = $InfisicalWorkspaceId
    projectSlug = $InfisicalProjectSlug
    secretPath = $InfisicalSecretPath
    secretValue = $Value
    skipMultilineEncoding = $true
    type = "shared"
    secretComment = "Managed by scripts/esus-pec/Upload-EsusPecBackupToMinio.ps1"
  } | ConvertTo-Json -Depth 5
  if ($Exists) {
    $null = Invoke-RestMethod -Method Patch -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
  } else {
    $null = Invoke-RestMethod -Method Post -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
  }
}

$backupPath = Resolve-Path -LiteralPath $BackupFile
$backupItem = Get-Item -LiteralPath $backupPath
$backupHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $backupPath).Hash.ToUpperInvariant()

$configText = Get-Content -LiteralPath $ConfigFile -Raw
$sshHost = Get-HclValue -Name "proxmox_ssh_host" -Text $configText
$script:SshPort = Get-HclValue -Name "proxmox_ssh_port" -Text $configText -Default "22"
$sshUser = Get-HclValue -Name "proxmox_ssh_user" -Text $configText -Default "root"
$script:SshKey = Get-HclValue -Name "proxmox_ssh_private_key_file" -Text $configText
$script:SshTarget = "$sshUser@$sshHost"

$token = Get-InfisicalToken
$headers = @{ Authorization = "Bearer $token" }
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

$apiUrl = $secrets["ESUS_PEC_OBJECT_STORAGE_API_URL"]
$bucket = $secrets["ESUS_PEC_OBJECT_STORAGE_BUCKET"]
$accessKey = $secrets["ESUS_PEC_OBJECT_STORAGE_BACKUP_ACCESS_KEY"]
$secretKey = $secrets["ESUS_PEC_OBJECT_STORAGE_BACKUP_SECRET_KEY"]
$remoteHostPath = "/tmp/$($backupItem.Name)"
$remoteCtPath = "/tmp/$($backupItem.Name)"

& scp -i $script:SshKey -P $script:SshPort -o BatchMode=yes -o StrictHostKeyChecking=accept-new $backupPath $script:SshTarget`:$remoteHostPath 2>&1
if ($LASTEXITCODE -ne 0) {
  throw "Backup copy to Proxmox failed with exit code $LASTEXITCODE."
}

Invoke-ProxmoxSsh -Command "pct push $Ctid '$remoteHostPath' '$remoteCtPath' --perms 0600 >/dev/null && rm -f '$remoteHostPath'"

$uploadScript = @"
set -euo pipefail
export MC_CONFIG_DIR=/root/.mc-esus-backup-upload
rm -rf "`$MC_CONFIG_DIR"
mc alias set backup "$apiUrl" "$accessKey" "$secretKey" --insecure >/dev/null
mc cp --checksum SHA256 "$remoteCtPath" "backup/$bucket/$ObjectKey" --insecure >/dev/null
object_hash="`$(mc cat "backup/$bucket/$ObjectKey" --insecure | sha256sum | awk '{print `$1}' | tr '[:lower:]' '[:upper:]')"
object_size="`$(mc stat --json "backup/$bucket/$ObjectKey" --insecure | sed -n 's/.*"size":[[:space:]]*\([0-9]*\).*/\1/p' | head -1)"
rm -f "$remoteCtPath"
printf 'OBJECT_HASH=%s\n' "`$object_hash"
printf 'OBJECT_SIZE=%s\n' "`$object_size"
"@
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($uploadScript))
$uploadOutput = Invoke-ProxmoxSsh -Command "pct exec $Ctid -- bash -lc 'echo $encoded | base64 -d | bash'"
$objectHash = (($uploadOutput -split "`n" | Where-Object { $_ -match "^OBJECT_HASH=" } | Select-Object -First 1) -replace "^OBJECT_HASH=", "").Trim()
$objectSize = (($uploadOutput -split "`n" | Where-Object { $_ -match "^OBJECT_SIZE=" } | Select-Object -First 1) -replace "^OBJECT_SIZE=", "").Trim()

if ($objectHash -ne $backupHash) {
  throw "Uploaded object checksum mismatch."
}
if ([int64]$objectSize -ne [int64]$backupItem.Length) {
  throw "Uploaded object size mismatch."
}

$uploadedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$metadata = [ordered]@{
  ESUS_PEC_OBJECT_STORAGE_BACKUP_OBJECT_KEY = $ObjectKey
  ESUS_PEC_OBJECT_STORAGE_BACKUP_SOURCE_FILENAME = $backupItem.Name
  ESUS_PEC_OBJECT_STORAGE_BACKUP_SHA256 = $backupHash
  ESUS_PEC_OBJECT_STORAGE_BACKUP_SIZE_BYTES = [string]$backupItem.Length
  ESUS_PEC_OBJECT_STORAGE_BACKUP_UPLOADED_AT = $uploadedAt
}

$secrets = Get-InfisicalSecrets -Headers $headers
foreach ($entry in $metadata.GetEnumerator()) {
  Set-InfisicalSecret -Name $entry.Key -Value ([string]$entry.Value) -Headers $headers -Exists $secrets.ContainsKey($entry.Key)
}

if ($RemoveLocalAfterValidation) {
  Remove-Item -LiteralPath $backupPath -Force
}

[ordered]@{
  bucket = $bucket
  objectKey = $ObjectKey
  sizeBytes = $backupItem.Length
  sha256 = $backupHash
  checksumValidated = $true
  localRemoved = $RemoveLocalAfterValidation.IsPresent
} | ConvertTo-Json -Depth 4
