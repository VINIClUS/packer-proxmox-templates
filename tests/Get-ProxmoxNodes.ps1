Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$varsFile = Join-Path $root "config/Proxmox.pkrvars.hcl"
$content = Get-Content -LiteralPath $varsFile -Raw

function Get-HclStringValue {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Text
  )
  $pattern = "(?m)^\s*$([regex]::Escape($Name))\s*=\s*`"([^`"]+)`"\s*$"
  $match = [regex]::Match($Text, $pattern)
  if (-not $match.Success) {
    throw "Missing required string variable: $Name"
  }
  return $match.Groups[1].Value
}

$apiBase = (Get-HclStringValue -Name "proxmox_url" -Text $content).TrimEnd("/")
$tokenId = Get-HclStringValue -Name "proxmox_api_token_id" -Text $content
$tokenSecret = Get-HclStringValue -Name "proxmox_api_token_secret" -Text $content

$nodesJson = & curl.exe -k -sS -H "Authorization: PVEAPIToken=$tokenId=$tokenSecret" "$apiBase/nodes"
if ($LASTEXITCODE -ne 0) {
  throw "Could not query Proxmox nodes."
}

$nodes = @((($nodesJson | ConvertFrom-Json).data) | Where-Object { $null -ne $_ })
if ($nodes.Count -eq 0) {
  throw "No Proxmox nodes are visible to this API token."
}

$nodes | Select-Object node, status, type | Format-Table -AutoSize
