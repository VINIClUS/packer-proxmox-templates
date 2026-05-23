Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "Installing QEMU Guest Agent for Proxmox IP discovery..."

Write-Host "Finalizing WinRM network profile and HTTP settings..."
try {
  Get-NetConnectionProfile -ErrorAction SilentlyContinue |
    Where-Object { $_.NetworkCategory -eq "Public" } |
    Set-NetConnectionProfile -NetworkCategory Private
}
catch {
  Write-Host "Unable to change network profile: $($_.Exception.Message)"
}
winrm set winrm/config/service '@{AllowUnencrypted="true"}' | Out-Host

$vioSerialInf = Get-PSDrive -PSProvider FileSystem |
  ForEach-Object { Join-Path $_.Root "vioserial\w11\amd64\vioser.inf" } |
  Where-Object { Test-Path -LiteralPath $_ } |
  Select-Object -First 1

if ($vioSerialInf) {
  Write-Host "Installing VirtIO serial driver from $vioSerialInf..."
  & pnputil.exe /add-driver $vioSerialInf /install | Out-Host
}
else {
  Write-Host "VirtIO serial driver was not found on mounted media."
}

$qemuGuestAgentMsi = Get-PSDrive -PSProvider FileSystem |
  ForEach-Object { Join-Path $_.Root "guest-agent\qemu-ga-x86_64.msi" } |
  Where-Object { Test-Path -LiteralPath $_ } |
  Select-Object -First 1

if (-not $qemuGuestAgentMsi) {
  Write-Host "QEMU Guest Agent installer not found on mounted media."
  exit 0
}

$process = Start-Process msiexec.exe `
  -ArgumentList @("/i", $qemuGuestAgentMsi, "/qn", "/norestart") `
  -Wait `
  -PassThru

Write-Host "QEMU Guest Agent installer exit code: $($process.ExitCode)"
if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
  exit $process.ExitCode
}

$service = Get-Service -Name QEMU-GA -ErrorAction SilentlyContinue
if ($service) {
  Set-Service -Name QEMU-GA -StartupType Automatic
  Restart-Service -Name QEMU-GA -ErrorAction SilentlyContinue
  Start-Service -Name QEMU-GA -ErrorAction SilentlyContinue
  Write-Host "QEMU Guest Agent service started."
}
