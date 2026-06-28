param(
  [string]$ConfigFile = "config/Proxmox.pkrvars.hcl",
  [Parameter(Mandatory = $true)][int]$TargetCtid,
  [string]$TargetName = "siha-nas",
  [string]$DebianTemplate,
  [string]$StoragePool = "local-lvm",
  [int]$RootFsSizeGb = 16,
  [int]$MemoryMb = 1024,
  [int]$Cores = 1,
  [string]$Bridge = "vmbr0",
  [string]$IpConfig = "dhcp",
  [string]$AllowedCidr = "none",
  [switch]$CreateContainer,
  [switch]$StartContainer,
  [switch]$SetInitialSambaPassword,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($TargetCtid -lt 100 -or $TargetCtid -gt 999999999) {
  throw "TargetCtid must be a positive Proxmox CTID >= 100."
}
if ($TargetName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$') {
  throw "TargetName must be a DNS-safe hostname."
}
if ($StoragePool -notmatch '^[A-Za-z0-9_.:-]+$') {
  throw "StoragePool contains unsupported characters."
}
if ($RootFsSizeGb -lt 8) {
  throw "RootFsSizeGb must be at least 8."
}
if ($MemoryMb -lt 512) {
  throw "MemoryMb must be at least 512."
}
if ($Cores -lt 1) {
  throw "Cores must be at least 1."
}
if ($Bridge -notmatch '^[A-Za-z0-9_.:-]+$') {
  throw "Bridge contains unsupported characters."
}
if ($IpConfig -ne "dhcp" -and $IpConfig -notmatch '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}(?:,gw=(?:[0-9]{1,3}\.){3}[0-9]{1,3})?$') {
  throw "IpConfig must be 'dhcp' or Proxmox ip/cidr with optional ,gw=x.x.x.x."
}
if ($AllowedCidr -ne "none" -and $AllowedCidr -notmatch '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$') {
  throw "AllowedCidr must be 'none' or an IPv4 CIDR."
}

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

  if ($DryRun) {
    Write-Host "[dry-run][$Label] $Command"
    return ""
  }

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

function Copy-ToProxmox {
  param(
    [Parameter(Mandatory = $true)][string]$LocalPath,
    [Parameter(Mandatory = $true)][string]$RemotePath
  )

  if ($DryRun) {
    Write-Host "[dry-run][scp] $LocalPath -> $($script:SshTarget):$RemotePath"
    return
  }

  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & scp -i $script:SshKey -P $script:SshPort -o BatchMode=yes -o StrictHostKeyChecking=accept-new $LocalPath "$($script:SshTarget):$RemotePath" 2>&1 |
      ForEach-Object { $_.ToString() }
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($exitCode -ne 0) {
    $output
    throw "SCP failed with exit code $exitCode."
  }
}

function Protect-LocalTemporarySecretFile {
  param([Parameter(Mandatory = $true)][string]$Path)

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
}

$root = Resolve-Path (Join-Path $PSScriptRoot "../..")
$configText = Get-Content -LiteralPath (Join-Path $root $ConfigFile) -Raw
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

if ($CreateContainer -and [string]::IsNullOrWhiteSpace($DebianTemplate)) {
  throw "Use -DebianTemplate when -CreateContainer is set, for example local:vztmpl/debian-12-standard_*.tar.zst."
}
if ($CreateContainer -and $DebianTemplate -notmatch '^[A-Za-z0-9_.:/@+-]+$') {
  throw "DebianTemplate contains unsupported characters."
}

$ctExistsCommand = "pct status $TargetCtid >/dev/null 2>&1; echo `$?"
$ctExists = if ($DryRun) { $false } else { (Invoke-ProxmoxSsh -Command $ctExistsCommand -Label "ct-exists").Trim() -eq "0" }

if (-not $ctExists -and -not $CreateContainer) {
  throw "CTID $TargetCtid does not exist. Re-run with -CreateContainer after selecting the Debian template."
}

if (-not $ctExists -and $CreateContainer) {
  $ipPart = if ($IpConfig -eq "dhcp") { "ip=dhcp" } else { "ip=$IpConfig" }
  $createCommand = @(
    "pct create $TargetCtid $(ConvertTo-ShellSingleQuoted $DebianTemplate)",
    "--hostname $(ConvertTo-ShellSingleQuoted $TargetName)",
    "--unprivileged 1",
    "--ostype debian",
    "--memory $MemoryMb",
    "--cores $Cores",
    "--rootfs $(ConvertTo-ShellSingleQuoted "${StoragePool}:${RootFsSizeGb}")",
    "--net0 $(ConvertTo-ShellSingleQuoted "name=eth0,bridge=$Bridge,$ipPart,firewall=1")",
    "--onboot 1",
    "--features $(ConvertTo-ShellSingleQuoted "nesting=0")"
  ) -join " "
  Invoke-ProxmoxSsh -Command $createCommand -Label "ct-create" | Out-Null
  $ctExists = $true
}

$config = if ($DryRun) { "hostname: $TargetName`nunprivileged: 1" } else { Invoke-ProxmoxSsh -Command "pct config $TargetCtid" -Label "ct-config" }
if ($config -notmatch "(?m)^hostname:\s+$([regex]::Escape($TargetName))\s*$") {
  throw "CTID $TargetCtid hostname mismatch. Expected '$TargetName'. Refusing to mutate an unrelated container."
}
if ($config -notmatch "(?m)^unprivileged:\s+1\s*$") {
  throw "CTID $TargetCtid is not unprivileged. Refusing to provision Samba NAS."
}

if ($StartContainer) {
  Invoke-ProxmoxSsh -Command "pct start $TargetCtid >/dev/null 2>&1 || true" -Label "ct-start" | Out-Null
}

$status = if ($DryRun) { "status: running" } else { Invoke-ProxmoxSsh -Command "pct status $TargetCtid" -Label "ct-status" }
if ($status -notmatch "status:\s+running") {
  throw "CTID $TargetCtid is not running. Start it or use -StartContainer."
}

$remoteDir = "/root/siha-nas-provision"
Invoke-ProxmoxSsh -Command "rm -rf $remoteDir; mkdir -p $remoteDir" -Label "remote-dir" | Out-Null
foreach ($artifact in @(
  "provision.sh",
  "smb.conf.template",
  "gerar-indice-siha.sh",
  "arquivar-antigos-siha.sh",
  "siha-arquivar-antigos.service",
  "siha-arquivar-antigos.timer"
)) {
  Copy-ToProxmox -LocalPath (Join-Path $PSScriptRoot $artifact) -RemotePath "$remoteDir/$artifact"
}

$containerPasswordPath = ""
$localPasswordTemp = $null
$remotePasswordTemp = ""
if ($SetInitialSambaPassword -and $DryRun) {
  Write-Host "[dry-run] Initial Samba password would be transferred through a restricted temporary file, not a command-line argument."
}
elseif ($SetInitialSambaPassword) {
  $secure = Read-Host -AsSecureString "Senha inicial Samba para siha_user"
  $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  )
  try {
    $localPasswordTemp = [System.IO.Path]::GetTempFileName()
    Protect-LocalTemporarySecretFile -Path $localPasswordTemp
    [System.IO.File]::WriteAllText($localPasswordTemp, $plain + "`n", [System.Text.UTF8Encoding]::new($false))
    $remotePasswordTemp = (Invoke-ProxmoxSsh -Command "umask 077; mktemp /root/siha-nas-samba-password.XXXXXXXXXX" -Label "password-tempfile").Trim()
    Copy-ToProxmox -LocalPath $localPasswordTemp -RemotePath $remotePasswordTemp
    $containerPasswordPath = "/run/siha-nas-samba-password"
  } finally {
    if ($plain) { $plain = $null }
    if ($localPasswordTemp -and (Test-Path -LiteralPath $localPasswordTemp -PathType Leaf)) {
      Remove-Item -LiteralPath $localPasswordTemp -Force
    }
  }
}

$allowed = ConvertTo-ShellSingleQuoted $AllowedCidr
$provisionShellPrefix = ""
$provisionSteps = @(
  "pct exec $TargetCtid -- mkdir -p /opt/siha-nas",
  "pct push $TargetCtid $remoteDir/provision.sh /opt/siha-nas/provision.sh --perms 0755 >/dev/null",
  "pct push $TargetCtid $remoteDir/smb.conf.template /opt/siha-nas/smb.conf.template --perms 0644 >/dev/null",
  "pct push $TargetCtid $remoteDir/gerar-indice-siha.sh /opt/siha-nas/gerar-indice-siha.sh --perms 0755 >/dev/null",
  "pct push $TargetCtid $remoteDir/arquivar-antigos-siha.sh /opt/siha-nas/arquivar-antigos-siha.sh --perms 0755 >/dev/null",
  "pct push $TargetCtid $remoteDir/siha-arquivar-antigos.service /opt/siha-nas/siha-arquivar-antigos.service --perms 0644 >/dev/null",
  "pct push $TargetCtid $remoteDir/siha-arquivar-antigos.timer /opt/siha-nas/siha-arquivar-antigos.timer --perms 0644 >/dev/null"
)

if ($containerPasswordPath) {
  # Keep the Samba password out of command-line arguments and process listings.
  $provisionSteps += "pct push $TargetCtid $remotePasswordTemp $containerPasswordPath --perms 0600 >/dev/null"
  $provisionShellPrefix = "SIHA_SAMBA_PASSWORD_FILE=$containerPasswordPath "
}

$provisionShell = "${provisionShellPrefix}/opt/siha-nas/provision.sh --allowed-cidr $allowed"
$provisionSteps += "pct exec $TargetCtid -- bash -lc $(ConvertTo-ShellSingleQuoted $provisionShell)"
$provisionCommand = $provisionSteps -join " && "

try {
  Invoke-ProxmoxSsh -Command $provisionCommand -Label "ct-provision" | Write-Output
} finally {
  $cleanupTargets = @($remoteDir)
  if ($remotePasswordTemp) {
    $cleanupTargets += $remotePasswordTemp
  }
  $cleanupCommand = "rm -rf " + (($cleanupTargets | ForEach-Object { ConvertTo-ShellSingleQuoted $_ }) -join " ")
  Invoke-ProxmoxSsh -Command $cleanupCommand -Label "remote-cleanup" | Out-Null
}
