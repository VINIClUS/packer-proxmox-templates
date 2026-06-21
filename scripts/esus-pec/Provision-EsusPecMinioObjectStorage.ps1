param(
  [string]$ConfigFile = "config/Proxmox.pkrvars.hcl",
  [int]$Ctid = 134,
  [string]$Hostname = "esus-pec-minio",
  [string]$IpCidr = "192.168.1.210/24",
  [string]$Gateway = "192.168.1.1",
  [string]$Bridge = "vmbr0",
  [string]$Storage = "rpool",
  [string]$Template = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst",
  [string]$RootfsSize = "64",
  [int]$MemoryMb = 2048,
  [int]$Cores = 2,
  [int]$SwapMb = 512,
  [string]$Bucket = "esus-pec-backups",
  [string]$InfisicalUrl = "http://192.168.1.226:8080",
  [string]$InfisicalWorkspaceId = "2c83cfe9-e794-4961-977d-23000ae14461",
  [string]$InfisicalProjectSlug = "esus-pec-z-px-c",
  [string]$InfisicalEnvironment = "dev",
  [string]$InfisicalSecretPath = "/test/ObjectStorage"
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

function New-SecretValue {
  param([int]$Bytes = 32)
  $buffer = New-Object byte[] $Bytes
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $rng.GetBytes($buffer)
  } finally {
    $rng.Dispose()
  }
  return [Convert]::ToBase64String($buffer).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

function Invoke-ProxmoxSsh {
  param(
    [Parameter(Mandatory = $true)][string]$Command
  )

  $output = & ssh -i $script:SshKey -p $script:SshPort -o BatchMode=yes -o StrictHostKeyChecking=accept-new $script:SshTarget $Command 2>&1
  if ($LASTEXITCODE -ne 0) {
    $output
    throw "Remote Proxmox command failed with exit code $LASTEXITCODE."
  }
  return ($output -join "`n")
}

function Invoke-ProxmoxBash {
  param([Parameter(Mandatory = $true)][string]$Script)
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
  & ssh -i $script:SshKey -p $script:SshPort -o BatchMode=yes -o StrictHostKeyChecking=accept-new $script:SshTarget "echo $encoded | base64 -d | bash -se" 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "Remote Proxmox bash script failed with exit code $LASTEXITCODE."
  }
}

function Invoke-ContainerBash {
  param(
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
  try {
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -TimeoutSec 30
  } catch {
    return @{}
  }
  $result = @{}
  foreach ($secret in @($response.secrets)) {
    $result[[string]$secret.secretKey] = [string]$secret.secretValue
  }
  return $result
}

function Ensure-InfisicalFolder {
  param([Parameter(Mandatory = $true)][hashtable]$Headers)
  $normalizedPath = "/" + ($InfisicalSecretPath.Trim("/") -replace "\\", "/")
  $lastSlash = $normalizedPath.LastIndexOf("/")
  $parent = if ($lastSlash -le 0) { "/" } else { $normalizedPath.Substring(0, $lastSlash) }
  $name = $normalizedPath.Substring($lastSlash + 1)
  $listUri = "$InfisicalUrl/api/v1/folders?workspaceId=$InfisicalWorkspaceId&environment=$InfisicalEnvironment&path=$([uri]::EscapeDataString($parent))"
  $folders = Invoke-RestMethod -Method Get -Uri $listUri -Headers $Headers -TimeoutSec 30
  if (@($folders.folders | Where-Object { $_.name -eq $name }).Count -gt 0) { return }
  $body = @{
    workspaceId = $InfisicalWorkspaceId
    environment = $InfisicalEnvironment
    name = $name
    path = $parent
  } | ConvertTo-Json -Compress
  $null = Invoke-RestMethod -Method Post -Uri "$InfisicalUrl/api/v1/folders" -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
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
    secretComment = "Managed by scripts/esus-pec/Provision-EsusPecMinioObjectStorage.ps1"
  } | ConvertTo-Json -Depth 5
  if ($Exists) {
    $null = Invoke-RestMethod -Method Patch -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
  } else {
    $null = Invoke-RestMethod -Method Post -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
  }
}

$configText = Get-Content -LiteralPath $ConfigFile -Raw
$sshHost = Get-HclValue -Name "proxmox_ssh_host" -Text $configText
$script:SshPort = Get-HclValue -Name "proxmox_ssh_port" -Text $configText -Default "22"
$sshUser = Get-HclValue -Name "proxmox_ssh_user" -Text $configText -Default "root"
$script:SshKey = Get-HclValue -Name "proxmox_ssh_private_key_file" -Text $configText
$script:SshTarget = "$sshUser@$sshHost"
$publicKey = "$script:SshKey.pub"
if (-not (Test-Path -LiteralPath $publicKey)) {
  throw "SSH public key not found: $publicKey"
}
$publicKeyText = (Get-Content -LiteralPath $publicKey -Raw).Trim()

$token = Get-InfisicalToken
$headers = @{ Authorization = "Bearer $token" }
Ensure-InfisicalFolder -Headers $headers
$existing = Get-InfisicalSecrets -Headers $headers

$rootUser = if ($existing.ContainsKey("ESUS_PEC_OBJECT_STORAGE_ROOT_USER")) { $existing["ESUS_PEC_OBJECT_STORAGE_ROOT_USER"] } else { "minio-root" }
$rootPassword = if ($existing.ContainsKey("ESUS_PEC_OBJECT_STORAGE_ROOT_PASSWORD")) { $existing["ESUS_PEC_OBJECT_STORAGE_ROOT_PASSWORD"] } else { New-SecretValue -Bytes 36 }
$backupAccessKey = if ($existing.ContainsKey("ESUS_PEC_OBJECT_STORAGE_BACKUP_ACCESS_KEY")) { $existing["ESUS_PEC_OBJECT_STORAGE_BACKUP_ACCESS_KEY"] } else { "esus-pec-backup" }
$backupSecretKey = if ($existing.ContainsKey("ESUS_PEC_OBJECT_STORAGE_BACKUP_SECRET_KEY")) { $existing["ESUS_PEC_OBJECT_STORAGE_BACKUP_SECRET_KEY"] } else { New-SecretValue -Bytes 36 }

$ipAddress = ($IpCidr -split "/", 2)[0]
$apiUrl = "https://$ipAddress`:9000"
$consoleUrl = "https://$ipAddress`:9001"

$ctExists = (Invoke-ProxmoxSsh -Command "pct status $Ctid >/dev/null 2>&1; echo `$?").Trim() -eq "0"
if (-not $ctExists) {
  $remotePublicKey = "/tmp/codex-$Ctid-ssh.pub"
  $publicKeyBytes = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($publicKeyText))
  $createScript = @"
echo "$publicKeyBytes" | base64 -d > "$remotePublicKey"
pct create $Ctid $Template \
  --hostname $Hostname \
  --rootfs $Storage`:$RootfsSize \
  --memory $MemoryMb \
  --cores $Cores \
  --swap $SwapMb \
  --net0 name=eth0,bridge=$Bridge,firewall=1,ip=$IpCidr,gw=$Gateway,type=veth \
  --unprivileged 1 \
  --features nesting=1,keyctl=1 \
  --onboot 1 \
  --description "MinIO object storage for e-SUS PEC backups. Created by Provision-EsusPecMinioObjectStorage.ps1. No secrets." \
  --ssh-public-keys "$remotePublicKey"
rm -f "$remotePublicKey"
pct start $Ctid
"@
  Invoke-ProxmoxBash -Script $createScript
} else {
  Invoke-ProxmoxSsh -Command "pct start $Ctid >/dev/null 2>&1 || true"
}

Start-Sleep -Seconds 5

$containerScript = @"
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
apt-get update -qq
apt-get install -y -qq ca-certificates curl openssl >/dev/null

id minio-user >/dev/null 2>&1 || useradd --system --user-group --home-dir /var/lib/minio --shell /usr/sbin/nologin minio-user
install -d -o minio-user -g minio-user -m 0750 /var/lib/minio/data
install -d -o root -g minio-user -m 0750 /etc/minio/certs
install -d -o root -g root -m 0750 /etc/minio/policies

curl -fsSL https://dl.min.io/server/minio/release/linux-amd64/minio -o /tmp/minio.bin
curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /tmp/mc.bin
install -m 0755 /tmp/minio.bin /usr/local/bin/minio
install -m 0755 /tmp/mc.bin /usr/local/bin/mc
rm -f /tmp/minio.bin /tmp/mc.bin

if [ ! -s /etc/minio/certs/public.crt ] || [ ! -s /etc/minio/certs/private.key ]; then
  openssl req -x509 -nodes -newkey rsa:4096 -sha256 -days 825 \
    -subj "/CN=$Hostname" \
    -addext "subjectAltName=DNS:$Hostname,DNS:localhost,IP:$ipAddress,IP:127.0.0.1" \
    -keyout /etc/minio/certs/private.key \
    -out /etc/minio/certs/public.crt >/dev/null 2>&1
  chown root:minio-user /etc/minio/certs/private.key
  chown root:root /etc/minio/certs/public.crt
  chmod 0640 /etc/minio/certs/private.key
  chmod 0644 /etc/minio/certs/public.crt
fi
chown root:minio-user /etc/minio/certs/private.key
chown root:minio-user /etc/minio/certs
chmod 0750 /etc/minio/certs
chmod 0640 /etc/minio/certs/private.key

cat >/etc/default/minio <<'MINIOENV'
MINIO_ROOT_USER="$rootUser"
MINIO_ROOT_PASSWORD="$rootPassword"
MINIO_VOLUMES="/var/lib/minio/data"
MINIO_OPTS="--address :9000 --console-address :9001 --certs-dir /etc/minio/certs"
MINIO_BROWSER_REDIRECT_URL="$consoleUrl"
MINIO_SERVER_URL="$apiUrl"
MINIO_PROMETHEUS_AUTH_TYPE="public"
MINIOENV
chmod 0600 /etc/default/minio

cat >/etc/systemd/system/minio.service <<'UNIT'
[Unit]
Description=MinIO Object Storage
Documentation=https://min.io/docs/minio/linux/index.html
Wants=network-online.target
After=network-online.target

[Service]
User=minio-user
Group=minio-user
EnvironmentFile=/etc/default/minio
ExecStart=/usr/local/bin/minio server `$MINIO_OPTS `$MINIO_VOLUMES
Restart=always
RestartSec=5
LimitNOFILE=65536
TasksMax=infinity
TimeoutStopSec=infinity
SendSIGKILL=no

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable minio >/dev/null
systemctl restart minio
for i in `$(seq 1 30); do
  if curl -kfSs "$apiUrl/minio/health/ready" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
curl -kfsS "$apiUrl/minio/health/ready" >/dev/null

export MC_CONFIG_DIR=/root/.mc-esus-provision
rm -rf "`$MC_CONFIG_DIR"
mc alias set local "$apiUrl" "$rootUser" "$rootPassword" --insecure >/dev/null
mc mb --ignore-existing --with-lock local/$Bucket --insecure >/dev/null
mc version enable local/$Bucket --insecure >/dev/null

cat >/etc/minio/policies/esus-pec-backup-rw.json <<'POLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": ["arn:aws:s3:::$Bucket"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": ["arn:aws:s3:::$Bucket/*"]
    }
  ]
}
POLICY
mc admin user add local "$backupAccessKey" "$backupSecretKey" --insecure >/dev/null 2>&1 || true
mc admin policy create local esus-pec-backup-rw /etc/minio/policies/esus-pec-backup-rw.json --insecure >/dev/null 2>&1 || true
mc admin policy attach local esus-pec-backup-rw --user "$backupAccessKey" --insecure >/dev/null

printf 'MINIO_READY=1\n'
printf 'MINIO_VERSION=%s\n' "`$(minio --version | head -1)"
printf 'MC_VERSION=%s\n' "`$(mc --version | head -1)"
openssl x509 -in /etc/minio/certs/public.crt -noout -enddate -ext subjectAltName -fingerprint -sha256
"@

$provisionOutput = Invoke-ContainerBash -Script $containerScript

$certPem = Invoke-ProxmoxSsh -Command "pct exec $Ctid -- cat /etc/minio/certs/public.crt"
$keyPem = Invoke-ProxmoxSsh -Command "pct exec $Ctid -- cat /etc/minio/certs/private.key"
$certSha = (($provisionOutput -split "`n" | Where-Object { $_ -match "^sha256 Fingerprint=" } | Select-Object -First 1) -replace "^sha256 Fingerprint=", "").Trim()
$certNotAfter = (($provisionOutput -split "`n" | Where-Object { $_ -match "^notAfter=" } | Select-Object -First 1) -replace "^notAfter=", "").Trim()
$certSan = (($provisionOutput -split "`n" | Select-String -Pattern "DNS:|IP Address:" | Select-Object -First 1).Line).Trim()
$minioVersion = (($provisionOutput -split "`n" | Where-Object { $_ -match "^MINIO_VERSION=" } | Select-Object -First 1) -replace "^MINIO_VERSION=", "").Trim()
$mcVersion = (($provisionOutput -split "`n" | Where-Object { $_ -match "^MC_VERSION=" } | Select-Object -First 1) -replace "^MC_VERSION=", "").Trim()

$desired = [ordered]@{
  ESUS_PEC_OBJECT_STORAGE_PROVIDER = "minio"
  ESUS_PEC_OBJECT_STORAGE_CTID = [string]$Ctid
  ESUS_PEC_OBJECT_STORAGE_HOSTNAME = $Hostname
  ESUS_PEC_OBJECT_STORAGE_IP = $ipAddress
  ESUS_PEC_OBJECT_STORAGE_ZFS_STORAGE = $Storage
  ESUS_PEC_OBJECT_STORAGE_API_URL = $apiUrl
  ESUS_PEC_OBJECT_STORAGE_CONSOLE_URL = $consoleUrl
  ESUS_PEC_OBJECT_STORAGE_BUCKET = $Bucket
  ESUS_PEC_OBJECT_STORAGE_ROOT_USER = $rootUser
  ESUS_PEC_OBJECT_STORAGE_ROOT_PASSWORD = $rootPassword
  ESUS_PEC_OBJECT_STORAGE_BACKUP_ACCESS_KEY = $backupAccessKey
  ESUS_PEC_OBJECT_STORAGE_BACKUP_SECRET_KEY = $backupSecretKey
  ESUS_PEC_OBJECT_STORAGE_TLS_CERTIFICATE_PEM = $certPem.Trim()
  ESUS_PEC_OBJECT_STORAGE_TLS_PRIVATE_KEY_PEM = $keyPem.Trim()
  ESUS_PEC_OBJECT_STORAGE_TLS_CERTIFICATE_SHA256 = $certSha
  ESUS_PEC_OBJECT_STORAGE_TLS_CERTIFICATE_NOT_AFTER = $certNotAfter
  ESUS_PEC_OBJECT_STORAGE_TLS_CERTIFICATE_SAN = $certSan
  ESUS_PEC_OBJECT_STORAGE_TLS_CERTIFICATE_KIND = "self-signed"
  ESUS_PEC_OBJECT_STORAGE_TLS_TERMINATION = "minio-native"
  ESUS_PEC_OBJECT_STORAGE_MINIO_VERSION = $minioVersion
  ESUS_PEC_OBJECT_STORAGE_MC_VERSION = $mcVersion
}

$existing = Get-InfisicalSecrets -Headers $headers
foreach ($entry in $desired.GetEnumerator()) {
  Set-InfisicalSecret -Name $entry.Key -Value ([string]$entry.Value) -Headers $headers -Exists $existing.ContainsKey($entry.Key)
}

[ordered]@{
  ctid = $Ctid
  hostname = $Hostname
  ip = $ipAddress
  storage = $Storage
  apiUrl = $apiUrl
  consoleUrl = $consoleUrl
  bucket = $Bucket
  secretPath = $InfisicalSecretPath
  minioReady = $true
  secretCount = $desired.Count
  minioVersion = $minioVersion
  mcVersion = $mcVersion
} | ConvertTo-Json -Depth 4
