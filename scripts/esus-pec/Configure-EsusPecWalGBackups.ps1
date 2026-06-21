param(
  [string]$ConfigFile = "config/Proxmox.pkrvars.hcl",
  [int]$TargetCtid = 133,
  [string]$WalGVersion = "v3.0.8",
  [string]$WalGDownloadUrl = "https://github.com/wal-g/wal-g/releases/download/v3.0.8/wal-g-pg-20.04-amd64",
  [string]$InfisicalUrl = "",
  [string]$InfisicalWorkspaceId = "",
  [string]$InfisicalEnvironment = "",
  [string]$InfisicalSecretPath = "/test/ObjectStorage",
  [string]$Schedule = "Sun 02:00:00 America/Sao_Paulo",
  [int]$RetentionFullBackups = 4,
  [switch]$Apply,
  [switch]$RunInitialBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\InfisicalEndpoint.ps1")
$infisicalEnvFile = if (Get-Variable -Name EnvFile -ErrorAction SilentlyContinue) { $EnvFile } else { ".env" }
$InfisicalUrl = Resolve-InfisicalUrl -CurrentValue $InfisicalUrl -EnvFilePath $infisicalEnvFile
$InfisicalWorkspaceId = Resolve-InfisicalSetting -Name "INFISICAL_WORKSPACE_ID" -CurrentValue $InfisicalWorkspaceId -EnvFilePath $infisicalEnvFile
$InfisicalEnvironment = Resolve-InfisicalSetting -Name "INFISICAL_ENVIRONMENT" -CurrentValue $InfisicalEnvironment -EnvFilePath $infisicalEnvFile

function Get-HclValue {
  param([string]$Name, [string]$Text, [string]$Default = $null)
  $line = $Text -split "`n" | Where-Object { $_ -match ("^\s*" + [regex]::Escape($Name) + "\s*=") } | Select-Object -First 1
  if (-not $line) { return $Default }
  return (($line -split "=", 2)[1]).Trim().Trim('"')
}

function Invoke-ProxmoxSsh {
  param([Parameter(Mandatory = $true)][string]$Command)
  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & ssh -i $script:SshKey -p $script:SshPort -o BatchMode=yes -o StrictHostKeyChecking=accept-new $script:SshTarget $Command 2>&1 |
      ForEach-Object { $_.ToString() }
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previous
  }
  if ($exitCode -ne 0) {
    $tail = ($output | Select-Object -Last 120) -join "`n"
    throw "Remote Proxmox command failed with exit code $exitCode.`n$tail"
  }
  return ($output -join "`n")
}

function Invoke-ContainerBash {
  param([int]$Ctid, [string]$Script)
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
  Invoke-ProxmoxSsh -Command "pct exec $Ctid -- bash -lc 'echo $encoded | base64 -d | bash'"
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
  param([hashtable]$Headers)
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

$headers = @{ Authorization = "Bearer $(Get-InfisicalToken)" }
$secrets = Get-InfisicalSecrets -Headers $headers

foreach ($name in @(
    "ESUS_PEC_OBJECT_STORAGE_API_URL",
    "ESUS_PEC_OBJECT_STORAGE_BUCKET",
    "ESUS_PEC_OBJECT_STORAGE_BACKUP_ACCESS_KEY",
    "ESUS_PEC_OBJECT_STORAGE_BACKUP_SECRET_KEY",
    "ESUS_PEC_OBJECT_STORAGE_TLS_CERTIFICATE_PEM"
  )) {
  if (-not $secrets.ContainsKey($name)) {
    throw "Missing required Infisical secret: $name"
  }
}

$endpoint = $secrets["ESUS_PEC_OBJECT_STORAGE_API_URL"]
$bucket = $secrets["ESUS_PEC_OBJECT_STORAGE_BUCKET"]
$accessKey = $secrets["ESUS_PEC_OBJECT_STORAGE_BACKUP_ACCESS_KEY"]
$secretKey = $secrets["ESUS_PEC_OBJECT_STORAGE_BACKUP_SECRET_KEY"]
$caCertificatePem = $secrets["ESUS_PEC_OBJECT_STORAGE_TLS_CERTIFICATE_PEM"]
$s3Prefix = if ($secrets.ContainsKey("ESUS_PEC_WALG_S3_PREFIX") -and $secrets["ESUS_PEC_WALG_S3_PREFIX"]) {
  $secrets["ESUS_PEC_WALG_S3_PREFIX"]
} else {
  "s3://$bucket/wal-g/ct$TargetCtid"
}

$mode = if ($Apply) { "apply" } else { "validate" }

$configureScript = @"
set -euo pipefail
MODE="$mode"
RUN_INITIAL_BACKUP="$($RunInitialBackup.IsPresent.ToString().ToLowerInvariant())"
WALG_VERSION="$WalGVersion"
WALG_URL="$WalGDownloadUrl"
PGDATA=/opt/e-SUS/database/current/data
PG_BIN=/opt/e-SUS/database/current/bin
SERVICE=e-SUS-PEC.service
ENV_DIR=/etc/esus-pec
ENV_FILE=`$ENV_DIR/walg.env
CA_FILE=`$ENV_DIR/minio-ca.pem
LOG_DIR=/var/log/esus-pec-walg
BACKUP_WRAPPER=/usr/local/bin/esus-pec-walg-full-backup
WAL_PUSH_WRAPPER=/usr/local/bin/esus-pec-walg-wal-push
DB_OWNER=`$(stat -c %U "`$PGDATA")
DB_GROUP=`$(stat -c %G "`$PGDATA")

read_pg_password() {
  python3 - <<'PY'
import re
from pathlib import Path
text = Path("/opt/e-SUS/webserver/config/credenciais.txt").read_text(encoding="utf-8", errors="ignore")
for pattern in [r"Usu.rio com acesso completo.*?senha:\s*([^\s]+)", r"acesso completo.*?senha:\s*([^\s]+)"]:
    match = re.search(pattern, text, re.IGNORECASE | re.DOTALL)
    if match:
        print(match.group(1))
        raise SystemExit(0)
raise SystemExit(1)
PY
}

if [ "`$MODE" != "apply" ]; then
  test -d "`$PGDATA"
  test -x "`$PG_BIN/psql"
  read_pg_password >/dev/null
  printf 'mode=validate\npgdata=%s\nschedule=%s\nretention_full=%s\ns3_prefix=%s\n' "`$PGDATA" "$Schedule" "$RetentionFullBackups" "$s3Prefix"
  exit 0
fi

install -d -m 0750 -o root -g "`$DB_GROUP" "`$ENV_DIR"
install -d -m 0770 -o root -g "`$DB_GROUP" "`$LOG_DIR"

tmp_walg=`$(mktemp)
python3 - "`$WALG_URL" "`$tmp_walg" <<'PY'
import sys
import urllib.request

url, target = sys.argv[1], sys.argv[2]
with urllib.request.urlopen(url, timeout=120) as response:
    with open(target, "wb") as handle:
        handle.write(response.read())
PY
install -m 0755 "`$tmp_walg" /usr/local/bin/wal-g
rm -f "`$tmp_walg"
/usr/local/bin/wal-g --version

cat > "`$CA_FILE" <<'EOF_CA'
$caCertificatePem
EOF_CA
chmod 0644 "`$CA_FILE"

PGPASSWORD_VALUE=`$(read_pg_password)
cat > "`$ENV_FILE" <<EOF_ENV
AWS_ACCESS_KEY_ID=$accessKey
AWS_SECRET_ACCESS_KEY=$secretKey
AWS_ENDPOINT=$endpoint
AWS_S3_FORCE_PATH_STYLE=true
AWS_REGION=us-east-1
WALG_S3_PREFIX=$s3Prefix
WALG_S3_CA_CERT_FILE=`$CA_FILE
WALG_PREVENT_WAL_OVERWRITE=true
WALG_UPLOAD_CONCURRENCY=4
WALG_DOWNLOAD_CONCURRENCY=4
PGHOST=localhost
PGPORT=5433
PGUSER=postgres
PGDATABASE=esus
PGPASSWORD=`$PGPASSWORD_VALUE
PGDATA=`$PGDATA
ESUS_PEC_WALG_RETENTION_FULL=$RetentionFullBackups
EOF_ENV
chown root:"`$DB_GROUP" "`$ENV_FILE"
chmod 0640 "`$ENV_FILE"

cat > "`$WAL_PUSH_WRAPPER" <<'EOF_WAL_PUSH'
#!/usr/bin/env bash
set -euo pipefail
set -a
. /etc/esus-pec/walg.env
set +a
exec /usr/local/bin/wal-g wal-push "`$1"
EOF_WAL_PUSH
chmod 0755 "`$WAL_PUSH_WRAPPER"

cat > "`$BACKUP_WRAPPER" <<'EOF_BACKUP'
#!/usr/bin/env bash
set -euo pipefail
set -a
. /etc/esus-pec/walg.env
set +a
mkdir -p /var/log/esus-pec-walg
exec >>/var/log/esus-pec-walg/full-backup.log 2>&1
date -Is
/usr/local/bin/wal-g backup-push "`$PGDATA"
/usr/local/bin/wal-g delete retain FULL "`$ESUS_PEC_WALG_RETENTION_FULL" --confirm
/usr/local/bin/wal-g backup-list
EOF_BACKUP
chmod 0755 "`$BACKUP_WRAPPER"

cat > /etc/systemd/system/esus-pec-walg-full-backup.service <<'EOF_SERVICE'
[Unit]
Description=e-SUS PEC WAL-G weekly full backup
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/esus-pec-walg-full-backup
EOF_SERVICE

cat > /etc/systemd/system/esus-pec-walg-full-backup.timer <<EOF_TIMER
[Unit]
Description=e-SUS PEC WAL-G weekly full backup timer

[Timer]
OnCalendar=$Schedule
Persistent=true
Unit=esus-pec-walg-full-backup.service

[Install]
WantedBy=timers.target
EOF_TIMER

python3 - <<'PY'
import re
from pathlib import Path
conf = Path("/opt/e-SUS/database/current/data/postgresql.conf")
text = conf.read_text(encoding="utf-8", errors="ignore").splitlines()
managed_keys = ("archive_mode", "archive_command", "archive_timeout", "wal_level")
kept = [line for line in text if not re.match(r"^\s*(%s)\s*=" % "|".join(managed_keys), line)]
block = [
    "",
    "# Managed by Configure-EsusPecWalGBackups.ps1",
    "wal_level = replica",
    "archive_mode = on",
    "archive_timeout = '60s'",
    "archive_command = '/usr/local/bin/esus-pec-walg-wal-push %p'",
]
backup = conf.with_suffix(conf.suffix + ".pre-walg")
if not backup.exists():
    backup.write_text("\n".join(text) + "\n", encoding="utf-8")
conf.write_text("\n".join(kept + block) + "\n", encoding="utf-8")
PY

systemctl daemon-reload
systemctl enable --now esus-pec-walg-full-backup.timer

run_pg_ctl() {
  if [ "`$DB_OWNER" = "root" ]; then
    "`$PG_BIN/pg_ctl" -D "`$PGDATA" "`$@"
  else
    runuser -u "`$DB_OWNER" -- "`$PG_BIN/pg_ctl" -D "`$PGDATA" "`$@"
  fi
}

systemctl stop "`$SERVICE" || true
run_pg_ctl -l "`$LOG_DIR/postgres-restart.log" restart -m fast -w
systemctl start "`$SERVICE"

set -a
. "`$ENV_FILE"
set +a
timeout 60 /usr/local/bin/wal-g backup-list || true
"`$PG_BIN/psql" -w -p 5433 -U postgres -d esus -Atc "show archive_mode; show archive_command; show archive_timeout; show wal_level;"
"`$PG_BIN/psql" -w -p 5433 -U postgres -d esus -Atc "select pg_switch_xlog();"
systemctl list-timers esus-pec-walg-full-backup.timer --no-pager

if [ "`$RUN_INITIAL_BACKUP" = "true" ]; then
  systemctl start esus-pec-walg-full-backup.service
fi
"@

$output = Invoke-ContainerBash -Ctid $TargetCtid -Script $configureScript

[ordered]@{
  mode = $mode
  targetCtid = $TargetCtid
  walGVersion = $WalGVersion
  s3Prefix = $s3Prefix
  schedule = $Schedule
  retentionFullBackups = $RetentionFullBackups
  runInitialBackup = $RunInitialBackup.IsPresent
  output = ($output -split "`n" | Select-Object -Last 40)
} | ConvertTo-Json -Depth 4
