param(
  [string]$ConfigFile = "config/Proxmox.pkrvars.hcl",
  [int]$TargetCtid = 133,
  [string]$TargetName = "esus-pec-lxc-5437",
  [string]$TargetMetricsHost = "192.168.1.209",
  [string]$MonitoringCoreHost = "192.168.1.190",
  [string]$InfisicalUrl = "",
  [string]$InfisicalWorkspaceId = "",
  [string]$InfisicalProjectSlug = "",
  [string]$InfisicalEnvironment = "",
  [string]$RuntimeSecretPath = "/test",
  [string]$InstallationSecretPath = "/test/Monitoring",
  [switch]$ConfigurePostgresExporter,
  [switch]$ConfigureJmxExporter,
  [switch]$ApplyJavaServiceChange
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\InfisicalEndpoint.ps1")
$infisicalEnvFile = if (Get-Variable -Name EnvFile -ErrorAction SilentlyContinue) { $EnvFile } else { ".env" }
$InfisicalUrl = Resolve-InfisicalUrl -CurrentValue $InfisicalUrl -EnvFilePath $infisicalEnvFile
$InfisicalWorkspaceId = Resolve-InfisicalSetting -Name "INFISICAL_WORKSPACE_ID" -CurrentValue $InfisicalWorkspaceId -EnvFilePath $infisicalEnvFile
$InfisicalProjectSlug = Resolve-InfisicalSetting -Name "INFISICAL_PROJECT_SLUG" -CurrentValue $InfisicalProjectSlug -EnvFilePath $infisicalEnvFile
$InfisicalEnvironment = Resolve-InfisicalSetting -Name "INFISICAL_ENVIRONMENT" -CurrentValue $InfisicalEnvironment -EnvFilePath $infisicalEnvFile

$postgresExporterVersion = "0.19.1"
$postgresExporterSha256 = "229096c7988df6ca41fe5b4bf66865089971535e7f0d819c12c920ec64dd2bd0"
$postgresExporterUrl = "https://github.com/prometheus-community/postgres_exporter/releases/download/v0.19.1/postgres_exporter-0.19.1.linux-amd64.tar.gz"

$jmxExporterVersion = "1.6.0"
$jmxExporterSha256 = "a95983fd96e865d2bcdf911cc500e7c82808c27ab9fd226bf96732b6c3d8c46e"
$jmxExporterUrl = "https://github.com/prometheus/jmx_exporter/releases/download/v1.6.0/jmx_prometheus_javaagent-1.6.0.jar"

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

function ConvertTo-ShellSingleQuoted {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
  return "'" + ($Value -replace "'", "'\''") + "'"
}

function Invoke-ProxmoxSsh {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [string]$Label = "proxmox-ssh"
  )

  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & ssh -i $script:SshKey -p $script:SshPort -o BatchMode=yes -o StrictHostKeyChecking=accept-new $script:SshTarget $Command 2>&1 |
      ForEach-Object { $_.ToString() }
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }

  if ($exitCode -ne 0) {
    $output
    throw "Remote Proxmox command '$Label' failed with exit code $exitCode."
  }
  return ($output -join "`n")
}

function Copy-TextToProxmoxTempFile {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [string]$Prefix = "codex-monitoring-script"
  )

  $localTemp = [System.IO.Path]::GetTempFileName()
  $remoteTemp = $null
  try {
    Protect-LocalTemporarySecretFile -Path $localTemp
    $normalizedText = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    [System.IO.File]::WriteAllText($localTemp, $normalizedText, [System.Text.UTF8Encoding]::new($false))
    $remoteTemp = (Invoke-ProxmoxSsh -Command "umask 077; mktemp /root/$Prefix.XXXXXXXXXX" -Label "remote-tempfile").Trim()
    $scpTarget = "{0}:{1}" -f $script:SshTarget, $remoteTemp

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
      $scpOutput = & scp -i $script:SshKey -P $script:SshPort -o BatchMode=yes -o StrictHostKeyChecking=accept-new $localTemp $scpTarget 2>&1 |
        ForEach-Object { $_.ToString() }
      $scpExitCode = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($scpExitCode -ne 0) {
      $scpOutput
      throw "SCP transfer for remote script failed with exit code $scpExitCode."
    }

    return $remoteTemp
  } catch {
    if (-not [string]::IsNullOrWhiteSpace($remoteTemp)) {
      $remoteTempQuoted = ConvertTo-ShellSingleQuoted -Value $remoteTemp
      try {
        Invoke-ProxmoxSsh -Command "rm -f $remoteTempQuoted" -Label "remote-tempfile-cleanup" | Out-Null
      } catch {
      }
    }
    throw
  } finally {
    if (Test-Path -LiteralPath $localTemp -PathType Leaf) {
      Remove-Item -LiteralPath $localTemp -Force
    }
  }
}

function Invoke-ProxmoxBash {
  param(
    [Parameter(Mandatory = $true)][string]$Script,
    [string]$Label = "proxmox-bash"
  )

  $remoteTemp = Copy-TextToProxmoxTempFile -Text $Script
  $remoteTempQuoted = ConvertTo-ShellSingleQuoted -Value $remoteTemp
  try {
    Invoke-ProxmoxSsh -Command "bash $remoteTempQuoted" -Label $Label
  } finally {
    Invoke-ProxmoxSsh -Command "rm -f $remoteTempQuoted" -Label "$Label-cleanup" | Out-Null
  }
}

function Invoke-ContainerBash {
  param(
    [Parameter(Mandatory = $true)][string]$Script,
    [string]$Label = "container-bash"
  )

  $remoteTemp = Copy-TextToProxmoxTempFile -Text $Script
  $remoteTempQuoted = ConvertTo-ShellSingleQuoted -Value $remoteTemp
  try {
    Invoke-ProxmoxSsh -Command "pct exec $TargetCtid -- bash -se < $remoteTempQuoted" -Label $Label
  } finally {
    Invoke-ProxmoxSsh -Command "rm -f $remoteTempQuoted" -Label "$Label-cleanup" | Out-Null
  }
}

function Push-ContainerFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content,
    [string]$Owner = "root",
    [string]$Group = "root",
    [string]$Mode = "0644"
  )

  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Content))
  $remotePath = ConvertTo-ShellSingleQuoted -Value $Path
  $remoteDir = ConvertTo-ShellSingleQuoted -Value (Split-Path -Parent $Path).Replace("\", "/")
  $remoteOwner = ConvertTo-ShellSingleQuoted -Value "${Owner}:${Group}"
  $remoteMode = ConvertTo-ShellSingleQuoted -Value $Mode

  $pushScript = @"
set -euo pipefail
umask 077
work_dir="`$(mktemp -d /root/codex-monitoring-target-push.XXXXXX)"
trap 'rm -rf "`$work_dir"' EXIT HUP INT TERM
payload_b64="`$work_dir/payload.b64"
payload_file="`$work_dir/payload"
cat > "`$payload_b64" <<'PUSH_PAYLOAD'
$encoded
PUSH_PAYLOAD
base64 -d "`$payload_b64" > "`$payload_file"
pct exec $TargetCtid -- mkdir -p $remoteDir
pct push $TargetCtid "`$payload_file" $remotePath --perms $remoteMode >/dev/null
pct exec $TargetCtid -- chown $remoteOwner $remotePath
"@
  Invoke-ProxmoxBash -Script $pushScript -Label "push-container-file:$Path" | Out-Null
}

function Protect-LocalTemporarySecretFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
    $acl = Get-Acl -LiteralPath $Path
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) {
      [void]$acl.RemoveAccessRuleAll($rule)
    }

    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $system = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList "S-1-5-18"
    $administrators = New-Object System.Security.Principal.SecurityIdentifier -ArgumentList "S-1-5-32-544"
    foreach ($identity in @($currentUser, $system, $administrators)) {
      $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule -ArgumentList @(
        $identity,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        [System.Security.AccessControl.AccessControlType]::Allow
      )
      $acl.AddAccessRule($accessRule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
    return
  }

  & chmod 600 -- $Path
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to restrict local temporary secret file permissions."
  }
}

function Push-ContainerSecretFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content,
    [string]$Owner = "root",
    [string]$Group = "root",
    [string]$Mode = "0600"
  )

  $localTemp = [System.IO.Path]::GetTempFileName()
  $remoteTemp = $null
  try {
    Protect-LocalTemporarySecretFile -Path $localTemp
    [System.IO.File]::WriteAllText($localTemp, $Content, [System.Text.UTF8Encoding]::new($false))

    $remoteTemp = (Invoke-ProxmoxSsh -Command "umask 077; mktemp /root/codex-monitoring-secret.XXXXXXXXXX" -Label "secret-remote-tempfile").Trim()
    $scpTarget = "{0}:{1}" -f $script:SshTarget, $remoteTemp

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
      $scpOutput = & scp -i $script:SshKey -P $script:SshPort -o BatchMode=yes -o StrictHostKeyChecking=accept-new $localTemp $scpTarget 2>&1 |
        ForEach-Object { $_.ToString() }
      $scpExitCode = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($scpExitCode -ne 0) {
      $scpOutput
      throw "SCP transfer for container secret file failed with exit code $scpExitCode."
    }

    $remotePath = ConvertTo-ShellSingleQuoted -Value $Path
    $remoteDir = ConvertTo-ShellSingleQuoted -Value (Split-Path -Parent $Path).Replace("\", "/")
    $remoteOwner = ConvertTo-ShellSingleQuoted -Value "${Owner}:${Group}"
    $remoteMode = ConvertTo-ShellSingleQuoted -Value $Mode
    $remoteTempQuoted = ConvertTo-ShellSingleQuoted -Value $remoteTemp

    $pushScript = @"
set -euo pipefail
chmod 0600 $remoteTempQuoted
pct exec $TargetCtid -- mkdir -p $remoteDir
pct push $TargetCtid $remoteTempQuoted $remotePath --perms $remoteMode >/dev/null
pct exec $TargetCtid -- chown $remoteOwner $remotePath
"@
    Invoke-ProxmoxBash -Script $pushScript -Label "push-container-secret:$Path" | Out-Null
  } finally {
    if (-not [string]::IsNullOrWhiteSpace($remoteTemp)) {
      $remoteTempQuoted = ConvertTo-ShellSingleQuoted -Value $remoteTemp
      try {
        Invoke-ProxmoxSsh -Command "rm -f $remoteTempQuoted" -Label "secret-remote-tempfile-cleanup" | Out-Null
      } catch {
        Write-Warning "Failed to remove temporary Proxmox host secret file; remove it manually if present."
      }
    }

    if (Test-Path -LiteralPath $localTemp -PathType Leaf) {
      Remove-Item -LiteralPath $localTemp -Force
    }
  }
}

function Get-TemplateContent {
  param([Parameter(Mandatory = $true)][string]$Name)

  $path = Join-Path $PSScriptRoot "templates/$Name"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Missing monitoring template: $path"
  }
  Get-Content -LiteralPath $path -Raw
}

function Read-KeyValueOutput {
  param([Parameter(Mandatory = $true)][string]$Output)

  $result = [ordered]@{}
  foreach ($line in ($Output -split "`n")) {
    if ($line -match "^(?<name>[^=]+)=(?<value>.*)$") {
      $result[$matches.name.Trim()] = $matches.value.Trim()
    }
  }
  return $result
}

function Get-EnvFileValues {
  param([string]$Path)

  $values = @{}
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $values
  }

  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed.StartsWith("#") -or $trimmed -notmatch "=") {
      continue
    }

    $parts = $trimmed -split "=", 2
    $values[$parts[0].Trim()] = $parts[1].Trim().Trim('"').Trim("'")
  }

  return $values
}

function Get-InfisicalToken {
  $envValues = Get-EnvFileValues -Path ".env"

  foreach ($candidate in @("infisical_secret_key", "INFISICAL_TOKEN")) {
    $environmentValue = [Environment]::GetEnvironmentVariable($candidate)
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
      return $environmentValue.Trim()
    }
    if ($envValues.ContainsKey($candidate) -and -not [string]::IsNullOrWhiteSpace([string]$envValues[$candidate])) {
      return [string]$envValues[$candidate]
    }
  }

  throw "Infisical token not found. Set infisical_secret_key in .env or INFISICAL_TOKEN."
}

function Get-InfisicalSecrets {
  param(
    [string]$SecretPath,
    [hashtable]$Headers
  )

  $uri = "$InfisicalUrl/api/v3/secrets/raw?workspaceId=$InfisicalWorkspaceId&environment=$InfisicalEnvironment&secretPath=$([uri]::EscapeDataString($SecretPath))"
  try {
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -TimeoutSec 30
  } catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
      return @{}
    }
    throw
  }

  $result = @{}
  foreach ($item in @($response.secrets)) {
    $result[[string]$item.secretKey] = [string]$item.secretValue
  }
  return $result
}

function Ensure-InfisicalFolderPath {
  param(
    [string]$SecretPath,
    [hashtable]$Headers
  )

  $segments = @($SecretPath.Trim("/") -split "/" | Where-Object { $_ -ne "" })
  if ($segments.Count -eq 0) {
    return
  }

  $parent = "/"
  foreach ($segment in $segments) {
    $listUri = "$InfisicalUrl/api/v1/folders?workspaceId=$InfisicalWorkspaceId&environment=$InfisicalEnvironment&path=$([uri]::EscapeDataString($parent))"
    $folders = Invoke-RestMethod -Method Get -Uri $listUri -Headers $Headers -TimeoutSec 30

    if (@($folders.folders | Where-Object { $_.name -eq $segment }).Count -eq 0) {
      $body = @{
        workspaceId = $InfisicalWorkspaceId
        environment = $InfisicalEnvironment
        name = $segment
        path = $parent
      } | ConvertTo-Json -Compress

      try {
        $null = Invoke-RestMethod -Method Post -Uri "$InfisicalUrl/api/v1/folders" -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
      } catch {
        if (-not $_.Exception.Response -or $_.Exception.Response.StatusCode.value__ -ne 409) {
          throw
        }
      }
    }

    if ($parent -eq "/") {
      $parent = "/$segment"
    } else {
      $parent = "$parent/$segment"
    }
  }
}

function Set-InfisicalSecret {
  param(
    [string]$SecretPath,
    [string]$Name,
    [AllowEmptyString()][string]$Value,
    [hashtable]$Headers,
    [bool]$Exists
  )

  if (-not $Exists) {
    Ensure-InfisicalFolderPath -SecretPath $SecretPath -Headers $Headers
  }

  $uri = "$InfisicalUrl/api/v3/secrets/raw/$([uri]::EscapeDataString($Name))"
  $body = @{
    environment = $InfisicalEnvironment
    workspaceId = $InfisicalWorkspaceId
    projectSlug = $InfisicalProjectSlug
    secretPath = $SecretPath
    secretValue = $Value
    skipMultilineEncoding = $true
    type = "shared"
    secretComment = "Managed by scripts/monitoring/Configure-EsusPecApplicationExporters.ps1"
  } | ConvertTo-Json -Depth 5

  if (-not $Exists) {
    $null = Invoke-RestMethod -Method Post -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
    return "created"
  }

  try {
    $null = Invoke-RestMethod -Method Patch -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
    return "updated"
  } catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
      Ensure-InfisicalFolderPath -SecretPath $SecretPath -Headers $Headers
      $null = Invoke-RestMethod -Method Post -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
      return "created"
    }
    throw
  }
}

function New-ExporterPassword {
  $bytes = New-Object byte[] 32
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $rng.GetBytes($bytes)
  } finally {
    $rng.Dispose()
  }
  return [Convert]::ToBase64String($bytes).
    TrimEnd("=").
    Replace("+", "-").
    Replace("/", "_")
}

function Get-OrCreatePostgresExporterPassword {
  param([hashtable]$Headers)

  $name = "ESUS_PEC_POSTGRES_EXPORTER_PASSWORD"
  $existing = Get-InfisicalSecrets `
    -SecretPath $InstallationSecretPath `
    -Headers $Headers

  if ($existing.ContainsKey($name) -and
      -not [string]::IsNullOrWhiteSpace([string]$existing[$name])) {
    return [string]$existing[$name]
  }

  $password = New-ExporterPassword
  $null = Set-InfisicalSecret `
    -SecretPath $InstallationSecretPath `
    -Name $name `
    -Value $password `
    -Headers $Headers `
    -Exists $false
  return $password
}

function Assert-TargetContainerIdentity {
  param([Parameter(Mandatory = $true)][string]$ConfigText)

  $hostnameLine = $ConfigText -split "`n" | Where-Object {
    $_ -match "^\s*hostname:\s*(?<hostname>\S+)\s*$"
  } | Select-Object -First 1

  if (-not $hostnameLine) {
    throw "CTID $TargetCtid exists but its Proxmox hostname could not be read. Refusing to mutate an unverified container."
  }

  $configuredName = ([regex]::Match($hostnameLine, "^\s*hostname:\s*(?<hostname>\S+)\s*$")).Groups["hostname"].Value
  if ($configuredName -ne $TargetName) {
    throw "CTID $TargetCtid exists but hostname is '$configuredName', expected '$TargetName'. Refusing to mutate an unrelated container."
  }
}

function Assert-TargetContainerRuntime {
  $ctExists = (Invoke-ProxmoxSsh -Command "pct status $TargetCtid >/dev/null 2>&1; echo `$?" -Label "target-exists").Trim() -eq "0"
  if (-not $ctExists) {
    throw "CTID $TargetCtid ($TargetName) does not exist on the Proxmox host."
  }

  $ctConfig = Invoke-ProxmoxSsh -Command "pct config $TargetCtid" -Label "target-config"
  Assert-TargetContainerIdentity -ConfigText $ctConfig

  $ctStatus = (Invoke-ProxmoxSsh -Command "pct status $TargetCtid" -Label "target-status").Trim()
  if ($ctStatus -notmatch "status:\s+running") {
    throw "CTID $TargetCtid ($TargetName) is not running. Start and verify the container manually before installing application exporters; this script will not mutate CT power state."
  }

  $runtimeHostname = (Invoke-ContainerBash -Script "hostname -s" -Label "target-runtime-hostname").Trim()
  if ($runtimeHostname -ne $TargetName) {
    throw "CTID $TargetCtid runtime hostname is '$runtimeHostname', expected '$TargetName'. Refusing to continue."
  }

  $targetMetricsHostShell = ConvertTo-ShellSingleQuoted -Value $TargetMetricsHost
  Invoke-ContainerBash -Label "target-metrics-host" -Script @"
set -euo pipefail
target_metrics_host=$targetMetricsHostShell
addresses="`$(hostname -I 2>/dev/null || true)"
if command -v ip >/dev/null 2>&1; then
  addresses="`$addresses `$(ip -o -4 addr show | awk '{ split(`$4, cidr, "/"); print cidr[1] }')"
fi
if ! printf ' %s ' "`$addresses" | grep -Fq " `$target_metrics_host "; then
  echo "CTID $TargetCtid ($TargetName) does not have expected TargetMetricsHost IP `$target_metrics_host." >&2
  exit 1
fi
"@ | Out-Null
}

function Configure-PostgresExporter {
  $headers = @{ Authorization = "Bearer $(Get-InfisicalToken)" }
  $runtimeSecrets = Get-InfisicalSecrets `
    -SecretPath $RuntimeSecretPath `
    -Headers $headers

  foreach ($requiredName in @(
    "ESUS_PEC_DB_USER",
    "ESUS_PEC_DB_PASSWORD"
  )) {
    if (-not $runtimeSecrets.ContainsKey($requiredName) -or
        [string]::IsNullOrWhiteSpace([string]$runtimeSecrets[$requiredName])) {
      throw "Infisical runtime secret is missing: $requiredName"
    }
  }

  $adminUser = [string]$runtimeSecrets["ESUS_PEC_DB_USER"]
  $adminPassword = [string]$runtimeSecrets["ESUS_PEC_DB_PASSWORD"]
  $exporterPassword = Get-OrCreatePostgresExporterPassword -Headers $headers

  $sqlPassword = $exporterPassword.Replace("'", "''")
  $postgresSql = (Get-TemplateContent -Name "postgres-exporter-9.6.sql").
    Replace("__POSTGRES_EXPORTER_PASSWORD__", $sqlPassword)

  Push-ContainerSecretFile `
    -Path "/etc/monitoring/postgres-exporter-bootstrap.sql" `
    -Content $postgresSql `
    -Mode "0600"

  Push-ContainerSecretFile `
    -Path "/etc/monitoring/postgres-bootstrap-password" `
    -Content ($adminPassword + "`n") `
    -Mode "0600"

  Push-ContainerSecretFile `
    -Path "/etc/monitoring/postgres-exporter-password" `
    -Content ($exporterPassword + "`n") `
    -Owner "root" `
    -Group "root" `
    -Mode "0600"

  $dataSourceUri = "127.0.0.1:5433/postgres?sslmode=disable"
  $environmentContent = @"
DATA_SOURCE_URI=$dataSourceUri
DATA_SOURCE_USER=prometheus_exporter
DATA_SOURCE_PASS_FILE=/etc/monitoring/postgres-exporter-password
PG_EXPORTER_COLLECTION_TIMEOUT=15s
"@

  Push-ContainerFile `
    -Path "/etc/monitoring/postgres-exporter.env" `
    -Content $environmentContent `
    -Owner "root" `
    -Group "root" `
    -Mode "0600"

  $adminUserShell = ConvertTo-ShellSingleQuoted -Value $adminUser
  $monitoringCoreHostShell = ConvertTo-ShellSingleQuoted -Value $MonitoringCoreHost
  $postgresScript = @'
set -euo pipefail
pg_root=/opt/e-SUS/database/postgresql-9.6.13-1-linux-x64
admin_user=__ADMIN_USER__
admin_password_file=/etc/monitoring/postgres-bootstrap-password
exporter_user=prometheus-postgres-exporter
monitoring_core_host=__MONITORING_CORE_HOST__

cleanup_bootstrap_secrets() {
  unset PGPASSWORD || true
  rm -f "$admin_password_file" /etc/monitoring/postgres-exporter-bootstrap.sql
}
trap cleanup_bootstrap_secrets EXIT HUP INT TERM

export PGPASSWORD="$(cat "$admin_password_file")"
"$pg_root/bin/psql" \
  -h 127.0.0.1 \
  -p 5433 \
  -U "$admin_user" \
  -d postgres \
  -v ON_ERROR_STOP=1 \
  -Atc "SELECT rolsuper FROM pg_catalog.pg_roles WHERE rolname = current_user" |
  grep -qx t

"$pg_root/bin/psql" \
  -h 127.0.0.1 \
  -p 5433 \
  -U "$admin_user" \
  -d postgres \
  -f /etc/monitoring/postgres-exporter-bootstrap.sql
cleanup_bootstrap_secrets
trap - EXIT HUP INT TERM

if ! getent group "$exporter_user" >/dev/null 2>&1; then
  groupadd --system "$exporter_user"
fi
if ! id -u "$exporter_user" >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin --gid "$exporter_user" "$exporter_user"
fi

chown root:"$exporter_user" /etc/monitoring/postgres-exporter.env /etc/monitoring/postgres-exporter-password
chmod 0640 /etc/monitoring/postgres-exporter.env /etc/monitoring/postgres-exporter-password

apply_postgres_exporter_firewall() {
  if ! command -v nft >/dev/null 2>&1; then
    systemctl disable --now prometheus-postgres-exporter >/dev/null 2>&1 || true
    echo "nft command is required before exposing prometheus-postgres-exporter on tcp dport 9187." >&2
    exit 1
  fi

  cat >/usr/local/sbin/apply-pec-postgres-exporter-firewall <<'FIREWALL'
#!/bin/sh
set -eu
monitoring_core_host="$1"
if ! command -v nft >/dev/null 2>&1; then
  echo "nft command is required before exposing prometheus-postgres-exporter on tcp dport 9187." >&2
  exit 1
fi
nft list table inet pec_postgres_exporter >/dev/null 2>&1 &&
  nft delete table inet pec_postgres_exporter || true
nft add table inet pec_postgres_exporter
nft 'add chain inet pec_postgres_exporter input { type filter hook input priority -50; policy accept; }'
nft add rule inet pec_postgres_exporter input iifname "lo" tcp dport 9187 accept
nft add rule inet pec_postgres_exporter input ip saddr "$monitoring_core_host" tcp dport 9187 accept
nft add rule inet pec_postgres_exporter input tcp dport 9187 drop
FIREWALL
  chmod 0755 /usr/local/sbin/apply-pec-postgres-exporter-firewall

  cat >/etc/systemd/system/prometheus-postgres-exporter-firewall.service <<'UNIT'
[Unit]
Description=Firewall for Prometheus PostgreSQL Exporter
DefaultDependencies=no
Before=prometheus-postgres-exporter.service
After=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/apply-pec-postgres-exporter-firewall __MONITORING_CORE_HOST__

[Install]
WantedBy=multi-user.target
UNIT

  /usr/local/sbin/apply-pec-postgres-exporter-firewall "$monitoring_core_host"
}

work_dir="$(mktemp -d /tmp/postgres-exporter.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
download="$work_dir/postgres_exporter.tar.gz"
curl -4 -fL --retry 5 --retry-all-errors --connect-timeout 15 \
  '__POSTGRES_EXPORTER_URL__' -o "$download"
echo '__POSTGRES_EXPORTER_SHA256__  '"$download" | sha256sum -c -
tar -xzf "$download" -C "$work_dir"
install -m 0755 \
  "$work_dir/postgres_exporter-0.19.1.linux-amd64/postgres_exporter" \
  /usr/local/bin/postgres_exporter

cat >/etc/systemd/system/prometheus-postgres-exporter.service <<'UNIT'
[Unit]
Description=Prometheus PostgreSQL Exporter for e-SUS PEC
Wants=network-online.target prometheus-postgres-exporter-firewall.service
After=network-online.target prometheus-postgres-exporter-firewall.service e-SUS-AB-PostgreSQL.service

[Service]
Type=simple
User=prometheus-postgres-exporter
Group=prometheus-postgres-exporter
EnvironmentFile=/etc/monitoring/postgres-exporter.env
ExecStart=/usr/local/bin/postgres_exporter --web.listen-address=0.0.0.0:9187 --no-collector.wal --no-collector.replication --no-collector.replication_slot --no-collector.stat_progress_vacuum
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadOnlyPaths=/etc/monitoring/postgres-exporter-password

[Install]
WantedBy=multi-user.target
UNIT

chown root:prometheus-postgres-exporter /etc/monitoring/postgres-exporter.env /etc/monitoring/postgres-exporter-password
chmod 0640 /etc/monitoring/postgres-exporter.env /etc/monitoring/postgres-exporter-password
apply_postgres_exporter_firewall
systemctl daemon-reload
systemctl enable --now prometheus-postgres-exporter-firewall
systemctl enable --now prometheus-postgres-exporter
systemctl restart prometheus-postgres-exporter
for attempt in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:9187/metrics |
      grep -q '^pg_up 1$'; then
    printf 'postgres_exporter=ready\n'
    exit 0
  fi
  sleep 2
done
systemctl disable --now prometheus-postgres-exporter >/dev/null 2>&1 || true
journalctl -u prometheus-postgres-exporter -n 30 --no-pager >&2
exit 1
'@.
    Replace("__ADMIN_USER__", $adminUserShell).
    Replace("__MONITORING_CORE_HOST__", $monitoringCoreHostShell).
    Replace("__POSTGRES_EXPORTER_URL__", $postgresExporterUrl).
    Replace("__POSTGRES_EXPORTER_SHA256__", $postgresExporterSha256)

  try {
    $output = Invoke-ContainerBash -Script $postgresScript -Label "postgres-exporter"
  } finally {
    try {
      Invoke-ContainerBash -Script 'rm -f /etc/monitoring/postgres-bootstrap-password /etc/monitoring/postgres-exporter-bootstrap.sql' -Label "postgres-bootstrap-cleanup" | Out-Null
    } catch {
      Write-Warning "Failed to remove PostgreSQL bootstrap temporary files; remove them manually if present."
    }
  }

  $state = Read-KeyValueOutput -Output $output
  if ($state.Contains("postgres_exporter")) {
    return $state["postgres_exporter"]
  }

  return "unknown"
}

function Configure-JmxExporter {
  $jmxExporterConfig = Get-TemplateContent -Name "jmx-exporter.yml"
  Push-ContainerFile `
    -Path "/etc/monitoring/jmx-exporter.yml" `
    -Content $jmxExporterConfig `
    -Owner "root" `
    -Group "root" `
    -Mode "0644"

  $applyRequested = if ($ApplyJavaServiceChange) { "true" } else { "false" }
  $monitoringCoreHostShell = ConvertTo-ShellSingleQuoted -Value $MonitoringCoreHost
  $jmxScript = @'
set -euo pipefail
apply_requested="__APPLY_JAVA_SERVICE_CHANGE__"
monitoring_core_host=__MONITORING_CORE_HOST__
dropin_dir=/etc/systemd/system/e-SUS-PEC.service.d
dropin_file="$dropin_dir/monitoring-jmx.conf"
wrapper_file=/opt/monitoring/run-esus-pec-with-jmx.sh
jmx_tmp="$(mktemp -d /tmp/jmx-exporter.XXXXXX)"
dropin_backup="$(mktemp)"
wrapper_backup="$(mktemp)"
trap 'rm -rf "$jmx_tmp" "$dropin_backup" "$wrapper_backup"' EXIT HUP INT TERM

wait_http_ready() {
  url="$1"
  attempts="$2"
  for attempt in $(seq 1 "$attempts"); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

rollback_jmx() {
  if [ -f "$dropin_backup" ]; then
    install -d -m 0755 "$dropin_dir"
    install -m 0644 "$dropin_backup" "$dropin_file"
  else
    rm -f "$dropin_file"
  fi
  if [ -f "$wrapper_backup" ]; then
    install -m 0755 "$wrapper_backup" "$wrapper_file"
  else
    rm -f "$wrapper_file"
  fi
  systemctl daemon-reload
  systemctl restart e-SUS-PEC.service
  wait_http_ready http://127.0.0.1:8080 180
}

apply_jmx_exporter_firewall() {
  if ! command -v nft >/dev/null 2>&1; then
    echo "nft command is required before exposing JMX exporter on tcp dport 9404." >&2
    exit 1
  fi

  cat >/usr/local/sbin/apply-pec-jmx-exporter-firewall <<'FIREWALL'
#!/bin/sh
set -eu
monitoring_core_host="$1"
if ! command -v nft >/dev/null 2>&1; then
  echo "nft command is required before exposing JMX exporter on tcp dport 9404." >&2
  exit 1
fi
nft list table inet pec_jmx_exporter >/dev/null 2>&1 &&
  nft delete table inet pec_jmx_exporter || true
nft add table inet pec_jmx_exporter
nft 'add chain inet pec_jmx_exporter input { type filter hook input priority -49; policy accept; }'
nft add rule inet pec_jmx_exporter input iifname "lo" tcp dport 9404 accept
nft add rule inet pec_jmx_exporter input ip saddr "$monitoring_core_host" tcp dport 9404 accept
nft add rule inet pec_jmx_exporter input tcp dport 9404 reject
FIREWALL
  chmod 0755 /usr/local/sbin/apply-pec-jmx-exporter-firewall

  cat >/etc/systemd/system/pec-jmx-exporter-firewall.service <<'UNIT'
[Unit]
Description=Firewall for e-SUS PEC JMX Exporter
DefaultDependencies=no
Before=e-SUS-PEC.service
After=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/apply-pec-jmx-exporter-firewall __MONITORING_CORE_HOST__

[Install]
WantedBy=multi-user.target
UNIT

  /usr/local/sbin/apply-pec-jmx-exporter-firewall "$monitoring_core_host"
  systemctl daemon-reload
  systemctl enable --now pec-jmx-exporter-firewall.service >/dev/null
}

if ! command -v nft >/dev/null 2>&1; then
  echo "nft command is required before exposing JMX exporter on tcp dport 9404." >&2
  exit 1
fi

install -d -m 0755 /opt/monitoring /etc/monitoring
chown root:root /etc/monitoring/jmx-exporter.yml
chmod 0644 /etc/monitoring/jmx-exporter.yml
curl -4 -fL --retry 5 --retry-all-errors --connect-timeout 15 \
  '__JMX_EXPORTER_URL__' \
  -o "$jmx_tmp/jmx_prometheus_javaagent.jar"
echo '__JMX_EXPORTER_SHA256__  '"$jmx_tmp/jmx_prometheus_javaagent.jar" |
  sha256sum -c -
install -m 0644 "$jmx_tmp/jmx_prometheus_javaagent.jar" /opt/monitoring/jmx_prometheus_javaagent.jar
apply_jmx_exporter_firewall

if [ "$apply_requested" != "true" ]; then
  printf 'jmx=staged-awaiting-apply\n'
  exit 0
fi

systemctl is-active e-SUS-PEC.service >/dev/null
wait_http_ready http://127.0.0.1:8080 5
/opt/e-SUS/jre/current/bin/java -version 2>&1 | grep -q '17\.'

install -d -m 0755 "$dropin_dir"
if [ -f "$dropin_file" ]; then
  cp -p "$dropin_file" "$dropin_backup"
else
  rm -f "$dropin_backup"
fi
if [ -f "$wrapper_file" ]; then
  cp -p "$wrapper_file" "$wrapper_backup"
else
  rm -f "$wrapper_backup"
fi

cat >"$wrapper_file" <<'WRAPPER'
#!/bin/sh
set -eu

JAVA_OPTS="-Xms2048M -Xmx4096M -XX:MetaspaceSize=256M -XX:MaxMetaspaceSize=512M -XX:ReservedCodeCacheSize=512M"
JAVA_OPTS="$JAVA_OPTS -Djava.net.preferIPv4Stack=true"
JAVA_OPTS="$JAVA_OPTS -Dfile.encoding=UTF-8"
JAVA_OPTS="$JAVA_OPTS -Djava.awt.headless=true -XX:CompressedClassSpaceSize=256M -Djboss.threads.eqe.statistics.active=true"

BUNDLE_HOME=/opt/e-SUS/webserver
PEC_HOME=/opt/e-SUS
JAVA_HOME=$PEC_HOME/jre/current
CERTMGR_HOME=$BUNDLE_HOME/certmgr
CERTMGR_CONFIG_FILE=$CERTMGR_HOME/config/ssl.properties

if [ -f "$CERTMGR_CONFIG_FILE" ]; then
  export SPRING_CONFIG_ADDITIONAL_LOCATION=$CERTMGR_CONFIG_FILE
  cd "$CERTMGR_HOME"
  "$JAVA_HOME/bin/java" -jar "$CERTMGR_HOME/certmgr.jar" --renew
fi

cd "$BUNDLE_HOME"
exec "$JAVA_HOME/bin/java" $JAVA_OPTS \
  -javaagent:/opt/monitoring/jmx_prometheus_javaagent.jar=9404:/etc/monitoring/jmx-exporter.yml \
  -jar "$BUNDLE_HOME/pec-bundle.jar"
WRAPPER
chmod 0755 "$wrapper_file"

cat >"$dropin_file" <<'UNIT'
[Service]
ExecStart=
ExecStart=/opt/monitoring/run-esus-pec-with-jmx.sh
UNIT
chmod 0644 "$dropin_file"

systemctl daemon-reload
if ! systemctl restart e-SUS-PEC.service; then
  rollback_jmx
  echo "e-SUS-PEC.service restart failed after JMX drop-in; restored previous JMX state." >&2
  exit 1
fi

if ! wait_http_ready http://127.0.0.1:8080 180; then
  rollback_jmx || echo "Rollback completed but PEC HTTP readiness was not observed within the rollback window." >&2
  echo "PEC HTTP endpoint failed readiness after JMX drop-in; restored previous JMX state." >&2
  exit 1
fi

if ! wait_http_ready http://127.0.0.1:9404/metrics 180; then
  rollback_jmx || echo "Rollback completed but PEC HTTP readiness was not observed within the rollback window." >&2
  echo "JMX endpoint failed readiness after JMX drop-in; restored previous JMX state." >&2
  exit 1
fi

metrics_sample="$(mktemp)"
if ! curl -fsS http://127.0.0.1:9404/metrics >"$metrics_sample"; then
  rm -f "$metrics_sample"
  rollback_jmx || echo "Rollback completed but PEC HTTP readiness was not observed within the rollback window." >&2
  echo "JMX exporter metrics endpoint was not readable; restored previous JMX state." >&2
  exit 1
fi

if ! grep -Eq '^jvm_(memory|gc|threads)_' "$metrics_sample"; then
  sed -n -E 's/^# (HELP|TYPE) ([^ ]+).*/jmx_metric_name=\2/p' "$metrics_sample" | head -n 30 >&2
  rm -f "$metrics_sample"
  rollback_jmx || echo "Rollback completed but PEC HTTP readiness was not observed within the rollback window." >&2
  echo "JMX exporter metrics did not include expected JVM memory, GC, or thread metrics; restored previous JMX state." >&2
  exit 1
fi
rm -f "$metrics_sample"

printf 'jmx=ready\n'
'@.
    Replace("__APPLY_JAVA_SERVICE_CHANGE__", $applyRequested).
    Replace("__MONITORING_CORE_HOST__", $monitoringCoreHostShell).
    Replace("__JMX_EXPORTER_URL__", $jmxExporterUrl).
    Replace("__JMX_EXPORTER_SHA256__", $jmxExporterSha256)

  $output = Invoke-ContainerBash -Script $jmxScript -Label "jmx-exporter"
  $state = Read-KeyValueOutput -Output $output
  if ($state.Contains("jmx")) {
    return $state["jmx"]
  }
  return "unknown"
}

$configText = Get-Content -LiteralPath $ConfigFile -Raw
$sshHost = Get-HclValue -Name "proxmox_ssh_host" -Text $configText
$script:SshPort = Get-HclValue -Name "proxmox_ssh_port" -Text $configText -Default "22"
$sshUser = Get-HclValue -Name "proxmox_ssh_user" -Text $configText -Default "root"
$script:SshKey = Get-HclValue -Name "proxmox_ssh_private_key_file" -Text $configText

if ([string]::IsNullOrWhiteSpace($sshHost) -or [string]::IsNullOrWhiteSpace($script:SshKey)) {
  throw "Missing proxmox_ssh_host or proxmox_ssh_private_key_file in $ConfigFile."
}
if (-not (Test-Path -LiteralPath $script:SshKey -PathType Leaf)) {
  throw "SSH private key file not found: $script:SshKey"
}

$script:SshTarget = "$sshUser@$sshHost"

Assert-TargetContainerRuntime

$summary = [ordered]@{
  target = [ordered]@{
    ctid = $TargetCtid
    name = $TargetName
    metrics_host = $TargetMetricsHost
    monitoring_core_host = $MonitoringCoreHost
  }
  postgres_exporter = "skipped"
  jmx = "skipped"
}

if ($ConfigurePostgresExporter) {
  $summary["postgres_exporter"] = Configure-PostgresExporter
}

if ($ConfigureJmxExporter) {
  $summary["jmx"] = Configure-JmxExporter
}

$summary | ConvertTo-Json -Depth 4
