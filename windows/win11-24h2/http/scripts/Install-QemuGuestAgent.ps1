Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "Installing QEMU Guest Agent for Proxmox IP discovery..."

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
  Start-Service -Name QEMU-GA -ErrorAction SilentlyContinue
  Write-Host "QEMU Guest Agent service started."
}
