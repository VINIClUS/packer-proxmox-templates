Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$targets = @(
  @{
    Name      = "Debian"
    Script    = "linux/debian-13-cloudinit/scripts/New-DebianCloudInitTemplate.ps1"
    Fragments = @(
      "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2",
      "VMID='9200'",
      "TEMPLATE_NAME='tpl-debian-13-cloudinit'",
      "CLOUD_INIT_USER='debian'",
      "CHECKSUM_COMMAND='sha512sum'"
    )
  },
  @{
    Name      = "AlmaLinux"
    Script    = "linux/almalinux-10-cloudinit/scripts/New-AlmaLinuxCloudInitTemplate.ps1"
    Fragments = @(
      "https://repo.almalinux.org/almalinux/10.1/cloud/x86_64_v2/images/AlmaLinux-10-GenericCloud-latest.x86_64_v2.qcow2",
      "VMID='9201'",
      "TEMPLATE_NAME='tpl-almalinux-10-cloudinit'",
      "CLOUD_INIT_USER='almalinux'",
      "CHECKSUM_FILE='CHECKSUM'"
    )
  },
  @{
    Name      = "Ubuntu"
    Script    = "linux/ubuntu-26.04-cloudinit/scripts/New-UbuntuCloudInitTemplate.ps1"
    Fragments = @(
      "https://cloud-images.ubuntu.com/releases/server/server/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img",
      "VMID='9202'",
      "TEMPLATE_NAME='tpl-ubuntu-26-04-cloudinit'",
      "CLOUD_INIT_USER='ubuntu'",
      "CHECKSUM_FILE='SHA256SUMS'"
    )
  }
)

$commonFragments = @(
  "qm create",
  "--serial0 socket",
  "--vga serial0",
  "--scsihw virtio-scsi-single",
  '--scsi0 "$DISK_STORAGE:0,import-from=$IMAGE_PATH,discard=on,ssd=1,iothread=1"',
  '--ide2 "$CI_STORAGE:cloudinit"',
  '--ipconfig0 "ip=dhcp"',
  "qm template"
)

foreach ($target in $targets) {
  $script = Join-Path $root $target.Script
  if (-not (Test-Path -LiteralPath $script)) {
    throw "Missing $($target.Name) cloud-init template script: $script"
  }

  $dryRun = & powershell -NoProfile -ExecutionPolicy Bypass -File $script -DryRun
  if ($LASTEXITCODE -ne 0) {
    throw "$($target.Name) dry-run generation failed with exit code $LASTEXITCODE."
  }
  $dryRunText = $dryRun -join "`n"

  foreach ($fragment in @($target.Fragments + $commonFragments)) {
    if ($dryRunText -notmatch [regex]::Escape($fragment)) {
      throw "$($target.Name) dry-run output is missing expected fragment: $fragment"
    }
  }
}

Write-Host "Cloud-init template script dry-runs are valid."
