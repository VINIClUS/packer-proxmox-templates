Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "Configuring EMS serial console and OpenSSH Server..."

# Enable Emergency Management Services on Proxmox serial0 / COM1 for headless SAC access.
& bcdedit.exe /emssettings EMSPORT:1 EMSBAUDRATE:115200 | Out-Host
if ($LASTEXITCODE -ne 0) {
  throw "Failed to configure EMS serial settings."
}

& bcdedit.exe /ems `{current`} ON | Out-Host
if ($LASTEXITCODE -ne 0) {
  throw "Failed to enable EMS for the current boot entry."
}

# Install the native Windows OpenSSH Server capability only when it is absent.
$openSshCapabilityName = "OpenSSH.Server~~~~0.0.1.0"
$openSshCapability = Get-WindowsCapability -Online -Name $openSshCapabilityName
if ($openSshCapability.State -ne "Installed") {
  Add-WindowsCapability -Online -Name $openSshCapabilityName | Out-Host
}

$sshd = Get-Service -Name sshd -ErrorAction Stop
Set-Service -Name sshd -StartupType Automatic
if ($sshd.Status -ne "Running") {
  Start-Service -Name sshd
}

# Prefer PowerShell 7 if present; otherwise keep SSH sessions in Windows PowerShell instead of cmd.exe.
$pwshPath = Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe"
if (Test-Path -LiteralPath $pwshPath) {
  $defaultShell = $pwshPath
}
else {
  $defaultShell = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
}

$openSshRegistryPath = "HKLM:\SOFTWARE\OpenSSH"
New-Item -Path $openSshRegistryPath -Force | Out-Null
New-ItemProperty `
  -Path $openSshRegistryPath `
  -Name DefaultShell `
  -Value $defaultShell `
  -PropertyType String `
  -Force | Out-Null

# Keep the inbound SSH firewall rule deterministic for Ansible/Terraform pipelines.
$sshFirewallRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if ($sshFirewallRule) {
  Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -Enabled True -Direction Inbound -Action Allow
  Set-NetFirewallPortFilter -AssociatedNetFirewallRule $sshFirewallRule -Protocol TCP -LocalPort 22
}
else {
  New-NetFirewallRule `
    -Name "OpenSSH-Server-In-TCP" `
    -DisplayName "OpenSSH Server (sshd)" `
    -Enabled True `
    -Direction Inbound `
    -Protocol TCP `
    -Action Allow `
    -LocalPort 22 | Out-Null
}

Write-Host "EMS serial console and OpenSSH Server configured."
