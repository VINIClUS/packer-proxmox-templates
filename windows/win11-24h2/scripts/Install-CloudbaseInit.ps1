Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$installerUri = "https://cloudbase.it/downloads/CloudbaseInitSetup_Stable_x64.msi"
$installerPath = Join-Path $env:TEMP "CloudbaseInitSetup_Stable_x64.msi"
$installerLogPath = Join-Path $env:TEMP "CloudbaseInitSetup.log"
$installRoot = Join-Path $env:ProgramFiles "Cloudbase Solutions\Cloudbase-Init"
$configDir = Join-Path $installRoot "conf"
$logDir = Join-Path $installRoot "log"
$localScriptsDir = Join-Path $installRoot "LocalScripts"

Write-Host "Downloading Cloudbase-Init installer..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $installerUri -OutFile $installerPath -UseBasicParsing
Unblock-File -Path $installerPath -ErrorAction SilentlyContinue

Write-Host "Installing Cloudbase-Init..."
$arguments = @(
  "/i",
  "`"$installerPath`"",
  "/qn",
  "/norestart",
  "/l*v",
  "`"$installerLogPath`"",
  "RUN_SERVICE_AS_LOCAL_SYSTEM=1"
)
$process = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru
if ($process.ExitCode -notin @(0, 3010)) {
  throw "Cloudbase-Init installer failed with exit code $($process.ExitCode)."
}

New-Item -ItemType Directory -Path $configDir, $logDir, $localScriptsDir -Force | Out-Null

$commonConfig = @"
[DEFAULT]
username=Admin
groups=Administrators
inject_user_password=true
first_logon_behaviour=no
config_drive_raw_hhd=false
config_drive_cdrom=true
config_drive_vfat=false
bsdtar_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin\bsdtar.exe
mtools_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin\
verbose=true
debug=false
log-dir=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\
default_log_levels=comtypes=INFO,suds=INFO,iso8601=WARN,requests=WARN
logging_serial_port_settings=
mtu_use_dhcp_config=true
ntp_use_dhcp_config=true
local_scripts_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\LocalScripts\
metadata_services=cloudbaseinit.metadata.services.configdrive.ConfigDriveService
plugins=cloudbaseinit.plugins.common.mtu.MTUPlugin,cloudbaseinit.plugins.windows.ntpclient.NTPClientPlugin,cloudbaseinit.plugins.common.sethostname.SetHostNamePlugin,cloudbaseinit.plugins.windows.createuser.CreateUserPlugin,cloudbaseinit.plugins.common.networkconfig.NetworkConfigPlugin,cloudbaseinit.plugins.common.sshpublickeys.SetUserSSHPublicKeysPlugin,cloudbaseinit.plugins.windows.extendvolumes.ExtendVolumesPlugin,cloudbaseinit.plugins.common.userdata.UserDataPlugin,cloudbaseinit.plugins.common.setuserpassword.SetUserPasswordPlugin,cloudbaseinit.plugins.common.localscripts.LocalScriptsPlugin
allow_reboot=false
stop_service_on_exit=false
check_latest_version=false

[config_drive]
raw_hdd=false
cdrom=true
vfat=false
types=iso
locations=cdrom
"@

Set-Content -LiteralPath (Join-Path $configDir "cloudbase-init.conf") `
  -Value ($commonConfig + "`r`nlog-file=cloudbase-init.log`r`n") `
  -Encoding ASCII
Set-Content -LiteralPath (Join-Path $configDir "cloudbase-init-unattend.conf") `
  -Value ($commonConfig + "`r`nlog-file=cloudbase-init-unattend.log`r`n") `
  -Encoding ASCII

$proxmoxCloudInitScript = @'
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-CompatLog {
  param([string]$Message)
  $logPath = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\proxmox-cloudinit.log"
  $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
  Add-Content -LiteralPath $logPath -Value "$timestamp $Message" -Encoding ASCII
}

function Get-ProxmoxUserDataPath {
  $volumes = Get-Volume | Where-Object {
    $_.DriveLetter -and $_.FileSystemLabel -in @("config-2", "cidata", "CONFIG-2", "CIDATA")
  }

  foreach ($volume in $volumes) {
    $root = "$($volume.DriveLetter):\"
  foreach ($relativePath in @("openstack\latest\user_data", "user-data", "USER_DATA")) {
      $candidate = Join-Path $root $relativePath
      if (Test-Path -LiteralPath $candidate) {
        return $candidate
      }
    }
  }

  return $null
}

function New-RandomPassword {
  $bytes = New-Object byte[] 24
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  return ([Convert]::ToBase64String($bytes) + "aA1!")
}

$userDataPath = Get-ProxmoxUserDataPath
if (-not $userDataPath) {
  Write-CompatLog "No Proxmox ConfigDrive user_data found."
  exit 0
}

$userData = Get-Content -LiteralPath $userDataPath -Raw
$userMatch = [regex]::Match($userData, "(?m)^\s*user:\s*['""]?([^'""\r\n#]+)")
if (-not $userMatch.Success) {
  Write-CompatLog "No ciuser entry found in Proxmox user_data."
  exit 0
}

$cloudUser = $userMatch.Groups[1].Value.Trim()
if ($cloudUser -notmatch "^[A-Za-z0-9._-]{1,20}$") {
  Write-CompatLog "Refusing invalid ciuser value."
  exit 1
}

$passwordMatch = [regex]::Match($userData, "(?m)^\s*password:\s*['""]?(.+?)['""]?\s*$")
$plainPassword = $null
if ($passwordMatch.Success) {
  $plainPassword = $passwordMatch.Groups[1].Value.Trim()
}
if ([string]::IsNullOrWhiteSpace($plainPassword)) {
  $plainPassword = New-RandomPassword
}
$securePassword = ConvertTo-SecureString -String $plainPassword -AsPlainText -Force

$existingUser = Get-LocalUser -Name $cloudUser -ErrorAction SilentlyContinue
if ($existingUser) {
  Set-LocalUser -Name $cloudUser -Password $securePassword
  Enable-LocalUser -Name $cloudUser
  Write-CompatLog "Updated Proxmox ciuser account."
} else {
  New-LocalUser -Name $cloudUser -Password $securePassword -AccountNeverExpires -PasswordNeverExpires | Out-Null
  Write-CompatLog "Created Proxmox ciuser account."
}

Add-LocalGroupMember -Group "Administrators" -Member $cloudUser -ErrorAction SilentlyContinue

# Proxmox writes keys under the cloud-config ssh_authorized_keys list.
$keyMatches = [regex]::Matches($userData, "(?m)^\s*-\s*((?:ssh-rsa|ssh-ed25519)\s+\S+(?:\s+.*)?)\s*$")
$keys = @($keyMatches | ForEach-Object { $_.Groups[1].Value.Trim() } | Where-Object { $_ })
if ($keys.Count -gt 0) {
  $userProfile = Join-Path "C:\Users" $cloudUser
  $userSshDir = Join-Path $userProfile ".ssh"
  New-Item -ItemType Directory -Path $userSshDir -Force | Out-Null
  $userAuthorizedKeys = Join-Path $userSshDir "authorized_keys"
  Set-Content -LiteralPath $userAuthorizedKeys -Value $keys -Encoding ASCII
  & icacls.exe $userSshDir /inheritance:r /grant "${cloudUser}:F" "SYSTEM:F" "Administrators:F" | Out-Null
  & icacls.exe $userAuthorizedKeys /inheritance:r /grant "${cloudUser}:F" "SYSTEM:F" "Administrators:F" | Out-Null

  $adminSshDir = Join-Path $env:ProgramData "ssh"
  New-Item -ItemType Directory -Path $adminSshDir -Force | Out-Null
  $adminAuthorizedKeys = Join-Path $adminSshDir "administrators_authorized_keys"
  $mergedKeys = @()
  if (Test-Path -LiteralPath $adminAuthorizedKeys) {
    $mergedKeys += Get-Content -LiteralPath $adminAuthorizedKeys
  }
  $mergedKeys += $keys
  $mergedKeys = $mergedKeys | Where-Object { $_ } | Select-Object -Unique
  Set-Content -LiteralPath $adminAuthorizedKeys -Value $mergedKeys -Encoding ASCII
  & icacls.exe $adminAuthorizedKeys /inheritance:r /grant "Administrators:F" "SYSTEM:F" | Out-Null
  Write-CompatLog "Applied Proxmox SSH authorized keys."
}
'@

Set-Content -LiteralPath (Join-Path $localScriptsDir "Apply-ProxmoxCloudInit.ps1") `
  -Value $proxmoxCloudInitScript `
  -Encoding ASCII

$proxmoxCloudInitWrapper = @"
@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$localScriptsDir\Apply-ProxmoxCloudInit.ps1"
exit /b %ERRORLEVEL%
"@
Set-Content -LiteralPath (Join-Path $localScriptsDir "Apply-ProxmoxCloudInit.cmd") `
  -Value $proxmoxCloudInitWrapper `
  -Encoding ASCII

Set-Service -Name cloudbase-init -StartupType Automatic
& sc.exe failure cloudbase-init reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Host
& sc.exe failureflag cloudbase-init 1 | Out-Host

Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
Write-Host "Cloudbase-Init installed and configured for Proxmox ConfigDrive."
