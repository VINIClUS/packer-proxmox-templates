param(
  [string]$ConfigFile,
  [Parameter(Mandatory = $true)][string]$TargetVarsFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
if (-not $ConfigFile) {
  $ConfigFile = Join-Path $root "config/Proxmox.pkrvars.hcl"
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

$globalVars = Read-HclVars -Path $ConfigFile
$targetVars = Read-HclVars -Path $TargetVarsFile
$sources = @($targetVars, $globalVars)

$proxmoxUrl = [string](Get-Var -Sources $sources -Name "proxmox_url" -Required)
$proxmoxUri = [uri]$proxmoxUrl
$sshHost = [string](Get-Var -Sources $sources -Name "proxmox_ssh_host" -Default $proxmoxUri.Host)
$sshPort = [int](Get-Var -Sources $sources -Name "proxmox_ssh_port" -Default 22)
$sshUser = [string](Get-Var -Sources $sources -Name "proxmox_ssh_user" -Default "root")
$sshKey = [string](Get-Var -Sources $sources -Name "proxmox_ssh_private_key_file" -Default "")
$vmId = [int](Get-Var -Sources $sources -Name "vm_id" -Required)
$templateName = [string](Get-Var -Sources $sources -Name "template_name" -Required)
$cloudInitUser = [string](Get-Var -Sources $sources -Name "cloud_init_user" -Required)
$diskSize = [string](Get-Var -Sources $sources -Name "disk_size" -Default "16G")

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

$configLines = & ssh @sshArgs "$sshUser@$sshHost" "qm config $vmId"
if ($LASTEXITCODE -ne 0) {
  throw "Could not query Proxmox VM config for VMID $vmId."
}

$config = @{}
foreach ($line in $configLines) {
  $match = [regex]::Match($line, '^([^:]+):\s*(.*)$')
  if ($match.Success) {
    $config[$match.Groups[1].Value] = $match.Groups[2].Value
  }
}

$checks = [ordered]@{
  template = { $config["template"] -eq "1" }
  name     = { $config["name"] -eq $templateName }
  serial0  = { $config["serial0"] -eq "socket" }
  vga      = { $config["vga"] -eq "serial0" }
  ostype   = { $config["ostype"] -eq "l26" }
  agent    = { $config["agent"] -match "enabled=1" }
  scsihw   = { $config["scsihw"] -eq "virtio-scsi-single" }
  scsi0    = { $config["scsi0"] -match "base-$vmId-disk-0" -and $config["scsi0"] -match "size=$diskSize" }
  ide2     = { $config["ide2"] -match "cloudinit" }
  ciuser   = { $config["ciuser"] -eq $cloudInitUser }
  ipconfig = { $config["ipconfig0"] -eq "ip=dhcp" }
}

foreach ($check in $checks.GetEnumerator()) {
  if (-not (& $check.Value)) {
    throw "Cloud-init template validation failed for VMID ${vmId}: $($check.Key)"
  }
}

Write-Host "Cloud-init template is valid."
Write-Host "VMID: $vmId"
Write-Host "Name: $($config["name"])"
Write-Host "Disk: $($config["scsi0"])"
Write-Host "Cloud-init: $($config["ide2"])"
