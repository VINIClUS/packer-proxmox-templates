Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$virtioDrive = Get-Volume |
  Where-Object { $_.DriveLetter -and $_.FileSystemLabel -match "virtio|VIRTIO" } |
  Select-Object -First 1

if (-not $virtioDrive) {
  Write-Host "VirtIO ISO was not detected; skipping guest tools installation."
  exit 0
}

$driveRoot = "$($virtioDrive.DriveLetter):\"
$guestTools = Join-Path $driveRoot "virtio-win-guest-tools.exe"

if (Test-Path -LiteralPath $guestTools) {
  Start-Process -FilePath $guestTools -ArgumentList "/quiet", "/norestart" -Wait
}

$qemuAgent = Get-Service -Name "QEMU-GA" -ErrorAction SilentlyContinue
if ($qemuAgent) {
  Set-Service -Name "QEMU-GA" -StartupType Automatic
  Start-Service -Name "QEMU-GA" -ErrorAction SilentlyContinue
}
