Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$script = Join-Path $root "linux/debian-13-cloudinit/scripts/New-DebianCloudInitTemplate.ps1"

if (-not (Test-Path -LiteralPath $script)) {
  throw "Missing Debian cloud-init template script: $script"
}

$dryRun = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -DryRun
if ($LASTEXITCODE -ne 0) {
  throw "Dry-run generation failed with exit code $LASTEXITCODE."
}
$dryRunText = $dryRun -join "`n"

$requiredFragments = @(
  "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2",
  "VMID='9200'",
  "qm create",
  "--serial0 socket",
  "--vga serial0",
  "--scsihw virtio-scsi-single",
  '--scsi0 "$DISK_STORAGE:0,import-from=$IMAGE_PATH,discard=on,ssd=1,iothread=1"',
  '--ide2 "$CI_STORAGE:cloudinit"',
  '--ipconfig0 "ip=dhcp"',
  "qm template"
)

foreach ($fragment in $requiredFragments) {
  if ($dryRunText -notmatch [regex]::Escape($fragment)) {
    throw "Dry-run output is missing expected fragment: $fragment"
  }
}

Write-Host "Debian cloud-init template script dry-run is valid."
