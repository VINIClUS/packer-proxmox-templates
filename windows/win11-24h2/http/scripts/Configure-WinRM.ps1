Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "Configuring WinRM for Packer..."

Write-Host "Starting WinRM service..."
Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM

Write-Host "Applying WinRM listener and authentication settings..."
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

Write-Host "WinRM configuration complete."
