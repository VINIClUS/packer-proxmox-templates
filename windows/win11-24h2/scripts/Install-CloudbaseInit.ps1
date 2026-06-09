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
config_drive_raw_hhd=true
config_drive_cdrom=true
config_drive_vfat=true
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
"@

Set-Content -LiteralPath (Join-Path $configDir "cloudbase-init.conf") `
  -Value ($commonConfig + "`r`nlog-file=cloudbase-init.log`r`n") `
  -Encoding ASCII
Set-Content -LiteralPath (Join-Path $configDir "cloudbase-init-unattend.conf") `
  -Value ($commonConfig + "`r`nlog-file=cloudbase-init-unattend.log`r`n") `
  -Encoding ASCII

Set-Service -Name cloudbase-init -StartupType Automatic
& sc.exe failure cloudbase-init reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Host
& sc.exe failureflag cloudbase-init 1 | Out-Host

Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
Write-Host "Cloudbase-Init installed and configured for Proxmox ConfigDrive."
