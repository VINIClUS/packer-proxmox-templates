Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "Configuring WinRM for Packer..."

Write-Host "Installing VirtIO network driver if available..."
$netKvmInf = Get-PSDrive -PSProvider FileSystem |
  ForEach-Object { Join-Path $_.Root "NetKVM\w11\amd64\netkvm.inf" } |
  Where-Object { Test-Path -LiteralPath $_ } |
  Select-Object -First 1
if ($netKvmInf) {
  & pnputil.exe /add-driver $netKvmInf /install | Out-Host
  Write-Host "VirtIO network driver installed from $netKvmInf"
} else {
  Write-Host "VirtIO network driver not found on mounted media."
}
& ipconfig.exe /renew | Out-Host

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
