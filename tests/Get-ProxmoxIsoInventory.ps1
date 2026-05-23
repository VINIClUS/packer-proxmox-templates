Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$varsFile = Join-Path $root "config/Proxmox.pkrvars.hcl"

if (-not (Test-Path -LiteralPath $varsFile)) {
  throw "Missing config/Proxmox.pkrvars.hcl."
}

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
$node = Get-HclStringValue -Name "proxmox_node" -Text $content
$tokenId = Get-HclStringValue -Name "proxmox_api_token_id" -Text $content
$tokenSecret = Get-HclStringValue -Name "proxmox_api_token_secret" -Text $content
$headers = "Authorization: PVEAPIToken=$tokenId=$tokenSecret"

$clusterStorageJson = & curl.exe -k -sS -H $headers "$apiBase/storage"
if ($LASTEXITCODE -ne 0) {
  throw "Could not query Proxmox cluster storage list."
}
$clusterStorages = @((($clusterStorageJson | ConvertFrom-Json).data) | Where-Object { $null -ne $_ })
if ($clusterStorages.Count -eq 0) {
  Write-Host "Cluster storages visible: none"
}
else {
  Write-Host "Cluster storages visible:"
  $clusterStorages | Select-Object storage, type, content, nodes | Format-Table -AutoSize
}

$storagesJson = & curl.exe -k -sS -H $headers "$apiBase/nodes/$node/storage"
if ($LASTEXITCODE -ne 0) {
  throw "Could not query Proxmox storage list."
}

$storages = @((($storagesJson | ConvertFrom-Json).data) | Where-Object { $null -ne $_ })
if ($storages.Count -eq 0) {
  throw "No storages are visible for node '$node'."
}

foreach ($storage in $storages) {
  $storageName = $storage.storage
  $contentTypes = $storage.content
  Write-Host "Storage: $storageName; content: $contentTypes"

  $contentJson = & curl.exe -k -sS -H $headers "$apiBase/nodes/$node/storage/$storageName/content"
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  Could not query content."
    continue
  }

  $items = @((($contentJson | ConvertFrom-Json).data) | Where-Object { $null -ne $_ })
  $isoItems = @($items | Where-Object { $_.content -eq "iso" -or $_.volid -match "\.iso$" })

  if ($isoItems.Count -eq 0) {
    Write-Host "  ISO entries: none"
    continue
  }

  foreach ($item in $isoItems) {
    Write-Host "  ISO: $($item.volid)"
  }
}
