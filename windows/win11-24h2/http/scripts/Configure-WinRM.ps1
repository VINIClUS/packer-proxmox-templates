Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Get-NetConnectionProfile -ErrorAction SilentlyContinue |
  Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
Enable-PSRemoting -Force -SkipNetworkProfileCheck

winrm quickconfig -quiet
winrm set winrm/config '@{MaxTimeoutms="1800000"}'
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="2048"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'

if (-not (Get-NetFirewallRule -DisplayName "Packer WinRM HTTP" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule `
    -DisplayName "Packer WinRM HTTP" `
    -Direction Inbound `
    -LocalPort 5985 `
    -Protocol TCP `
    -Action Allow `
    -Profile Any | Out-Null
}

Set-Service -Name WinRM -StartupType Automatic
Restart-Service -Name WinRM
