param(
  [string]$ConfigFile,
  [string]$TargetVarsFile,
  [switch]$Force,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "../../..")
if (-not $TargetVarsFile) {
  $TargetVarsFile = Join-Path $root "linux/ubuntu-26.04-cloudinit/ubuntu-26.04-cloudinit.pkrvars.hcl.example"
}

$arguments = @{
  TargetVarsFile = $TargetVarsFile
}
if ($ConfigFile) { $arguments.ConfigFile = $ConfigFile }
if ($Force) { $arguments.Force = $true }
if ($DryRun) { $arguments.DryRun = $true }

& (Join-Path $root "shared/scripts/New-ProxmoxCloudInitTemplate.ps1") @arguments
