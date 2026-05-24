param(
  [string]$ConfigFile,
  [string]$TargetVarsFile,
  [switch]$Force,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "../../..")
if (-not $ConfigFile) {
  $ConfigFile = Join-Path $root "config/Proxmox.pkrvars.hcl"
}
if (-not $TargetVarsFile) {
  $TargetVarsFile = Join-Path $root "linux/debian-13-cloudinit/debian-13-cloudinit.pkrvars.hcl.example"
}

function Read-HclVars {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing variable file: $Path"
  }

  $vars = @{}
  foreach ($line in Get-Content -LiteralPath $Path) {
    if ($line -match '^\s*#' -or $line -match '^\s*$') {
      continue
    }
    $match = [regex]::Match($line, '^\s*([A-Za-z0-9_]+)\s*=\s*(.+?)\s*$')
    if (-not $match.Success) {
      continue
    }

    $name = $match.Groups[1].Value
    $rawValue = $match.Groups[2].Value.Trim()
    if ($rawValue -match '^"(.*)"$') {
      $vars[$name] = $matches[1]
    }
    elseif ($rawValue -match '^(true|false)$') {
      $vars[$name] = [bool]::Parse($rawValue)
    }
    elseif ($rawValue -match '^\d+$') {
      $vars[$name] = [int]$rawValue
    }
    else {
      $vars[$name] = $rawValue
    }
  }

  return $vars
}

function Get-Var {
  param(
    [Parameter(Mandatory = $true)][hashtable[]]$Sources,
    [Parameter(Mandatory = $true)][string]$Name,
    [object]$Default = $null,
    [switch]$Required
  )

  foreach ($source in $Sources) {
    if ($source.ContainsKey($Name) -and $null -ne $source[$Name] -and "$($source[$Name])" -ne "") {
      return $source[$Name]
    }
  }

  if ($Required) {
    throw "Missing required variable: $Name"
  }
  return $Default
}

function ConvertTo-ShellLiteral {
  param([AllowNull()][string]$Value)
  if ($null -eq $Value) {
    $Value = ""
  }
  return "'" + $Value.Replace("'", "'\''") + "'"
}

$globalVars = Read-HclVars -Path $ConfigFile
$targetVars = Read-HclVars -Path $TargetVarsFile
$sources = @($targetVars, $globalVars)

$proxmoxUrl = [string](Get-Var -Sources $sources -Name "proxmox_url" -Required)
$proxmoxUri = [uri]$proxmoxUrl
$sshHost = [string](Get-Var -Sources $sources -Name "proxmox_ssh_host" -Default $proxmoxUri.Host)
$sshPort = [int](Get-Var -Sources $sources -Name "proxmox_ssh_port" -Default 22)
$sshUser = [string](Get-Var -Sources $sources -Name "proxmox_ssh_user" -Default "root")
$sshKey = [string](Get-Var -Sources $sources -Name "proxmox_ssh_private_key_file" -Default "")

$vmId = [int](Get-Var -Sources $sources -Name "vm_id" -Default 9200)
$vmName = [string](Get-Var -Sources $sources -Name "vm_name" -Default "debian-13-cloudinit-packer")
$templateName = [string](Get-Var -Sources $sources -Name "template_name" -Default "tpl-debian-13-cloudinit")
$templateDescription = [string](Get-Var -Sources $sources -Name "template_description" -Default "Debian 13 trixie genericcloud cloud-init template for Proxmox.")
$cpuCores = [int](Get-Var -Sources $sources -Name "cpu_cores" -Default 2)
$cpuSockets = [int](Get-Var -Sources $sources -Name "cpu_sockets" -Default 1)
$memoryMb = [int](Get-Var -Sources $sources -Name "memory_mb" -Default 2048)
$diskSize = [string](Get-Var -Sources $sources -Name "disk_size" -Default "16G")
$diskStorage = [string](Get-Var -Sources $sources -Name "proxmox_vm_storage_pool" -Default "local-lvm")
$cloudInitStorage = [string](Get-Var -Sources $sources -Name "cloud_init_storage_pool" -Default $diskStorage)
$bridge = [string](Get-Var -Sources $sources -Name "proxmox_network_bridge" -Default "vmbr0")
$imageUrl = [string](Get-Var -Sources $sources -Name "debian_cloud_image_url" -Default "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2")
$imageDirectory = [string](Get-Var -Sources $sources -Name "debian_cloud_image_directory" -Default "/var/lib/vz/template/qcow2")
$imageFile = [string](Get-Var -Sources $sources -Name "debian_cloud_image_file" -Default "debian-13-genericcloud-amd64.qcow2")
$cloudInitUser = [string](Get-Var -Sources $sources -Name "cloud_init_user" -Default "debian")
$sshKeysFile = [string](Get-Var -Sources $sources -Name "ssh_keys_file" -Default "")

$forceFlag = if ($Force) { "1" } else { "0" }
$imagePath = "$imageDirectory/$imageFile"
$description = "$templateDescription Built from $imageUrl on $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')."

$remoteScript = @"
set -Eeuo pipefail

VMID=$(ConvertTo-ShellLiteral "$vmId")
VM_NAME=$(ConvertTo-ShellLiteral $vmName)
TEMPLATE_NAME=$(ConvertTo-ShellLiteral $templateName)
DESCRIPTION=$(ConvertTo-ShellLiteral $description)
FORCE=$(ConvertTo-ShellLiteral $forceFlag)
IMAGE_URL=$(ConvertTo-ShellLiteral $imageUrl)
IMAGE_DIR=$(ConvertTo-ShellLiteral $imageDirectory)
IMAGE_FILE=$(ConvertTo-ShellLiteral $imageFile)
IMAGE_PATH=$(ConvertTo-ShellLiteral $imagePath)
DISK_STORAGE=$(ConvertTo-ShellLiteral $diskStorage)
CI_STORAGE=$(ConvertTo-ShellLiteral $cloudInitStorage)
BRIDGE=$(ConvertTo-ShellLiteral $bridge)
CLOUD_INIT_USER=$(ConvertTo-ShellLiteral $cloudInitUser)
SSH_KEYS_FILE=$(ConvertTo-ShellLiteral $sshKeysFile)
DISK_SIZE=$(ConvertTo-ShellLiteral $diskSize)

require_command() {
  command -v "`$1" >/dev/null 2>&1 || {
    echo "Required command not found on Proxmox node: `$1" >&2
    exit 127
  }
}

require_command qm
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  echo "Required command not found on Proxmox node: curl or wget" >&2
  exit 127
fi

if qm status "`$VMID" >/dev/null 2>&1; then
  if [ "`$FORCE" = "1" ]; then
    qm stop "`$VMID" >/dev/null 2>&1 || true
    qm destroy "`$VMID" --purge 1 --destroy-unreferenced-disks 1
  else
    echo "VMID `$VMID already exists. Re-run with -Force to replace it." >&2
    exit 10
  fi
fi

mkdir -p "`$IMAGE_DIR"
tmp_image="`$IMAGE_PATH.tmp"
if command -v curl >/dev/null 2>&1; then
  curl -fL --retry 3 --connect-timeout 20 -o "`$tmp_image" "`$IMAGE_URL"
else
  wget -O "`$tmp_image" "`$IMAGE_URL"
fi

sums_file="`$IMAGE_DIR/SHA512SUMS"
sums_url="`$(dirname "`$IMAGE_URL")/SHA512SUMS"
if command -v curl >/dev/null 2>&1; then
  curl -fsL -o "`$sums_file" "`$sums_url" || true
else
  wget -q -O "`$sums_file" "`$sums_url" || true
fi

if [ -s "`$sums_file" ] && command -v sha512sum >/dev/null 2>&1; then
  mv "`$tmp_image" "`$IMAGE_PATH"
  (cd "`$IMAGE_DIR" && sha512sum -c SHA512SUMS --ignore-missing)
else
  echo "Warning: SHA512SUMS could not be verified; keeping downloaded image." >&2
  mv "`$tmp_image" "`$IMAGE_PATH"
fi

qm create "`$VMID" \
  --name "`$VM_NAME" \
  --memory $memoryMb \
  --cores $cpuCores \
  --sockets $cpuSockets \
  --cpu host \
  --net0 "virtio,bridge=`$BRIDGE,firewall=1" \
  --serial0 socket \
  --vga serial0 \
  --ostype l26 \
  --agent "enabled=1,fstrim_cloned_disks=1" \
  --scsihw virtio-scsi-single \
  --tags "debian;trixie;cloudinit;template"

qm set "`$VMID" --scsi0 "`$DISK_STORAGE:0,import-from=`$IMAGE_PATH,discard=on,ssd=1,iothread=1"
qm set "`$VMID" --ide2 "`$CI_STORAGE:cloudinit" --boot "order=scsi0"
qm set "`$VMID" --ipconfig0 "ip=dhcp" --ciuser "`$CLOUD_INIT_USER"

if [ -n "`$SSH_KEYS_FILE" ]; then
  if [ ! -f "`$SSH_KEYS_FILE" ]; then
    echo "SSH keys file not found on Proxmox node: `$SSH_KEYS_FILE" >&2
    exit 11
  fi
  qm set "`$VMID" --sshkeys "`$SSH_KEYS_FILE"
fi

qm resize "`$VMID" scsi0 "`$DISK_SIZE"
qm set "`$VMID" --name "`$TEMPLATE_NAME" --description "`$DESCRIPTION"
qm template "`$VMID"

echo "Created Debian cloud-init template `$TEMPLATE_NAME at VMID `$VMID."
qm config "`$VMID"
"@

if ($DryRun) {
  Write-Output $remoteScript
  exit 0
}

$sshArgs = @(
  "-p", "$sshPort",
  "-o", "BatchMode=yes",
  "-o", "StrictHostKeyChecking=accept-new"
)
if ($sshKey) {
  if (-not (Test-Path -LiteralPath $sshKey)) {
    throw "Configured SSH private key does not exist: $sshKey"
  }
  $sshArgs += @("-i", $sshKey)
}

$target = "$sshUser@$sshHost"
Write-Host "Creating Debian cloud-init template on $target with VMID $vmId..."
$remoteScript | & ssh @sshArgs $target "bash -s"
if ($LASTEXITCODE -ne 0) {
  throw "Remote Proxmox template creation failed with exit code $LASTEXITCODE."
}
