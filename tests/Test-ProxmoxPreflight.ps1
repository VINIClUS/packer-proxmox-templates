Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$varsFile = Join-Path $root "config/Proxmox.pkrvars.hcl"

if (-not (Test-Path -LiteralPath $varsFile)) {
  throw "Missing config/Proxmox.pkrvars.hcl. Copy config/Proxmox.pkrvars.hcl.example and fill local values."
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

$proxmoxUrl = Get-HclStringValue -Name "proxmox_url" -Text $content
$node = Get-HclStringValue -Name "proxmox_node" -Text $content
$tokenId = Get-HclStringValue -Name "proxmox_api_token_id" -Text $content
$tokenSecret = Get-HclStringValue -Name "proxmox_api_token_secret" -Text $content
$isoStoragePool = Get-HclStringValue -Name "proxmox_iso_storage_pool" -Text $content
$windowsIsoFile = Get-HclStringValue -Name "windows_iso_file" -Text $content
$virtioIsoFile = Get-HclStringValue -Name "virtio_iso_file" -Text $content
$winrmPassword = Get-HclStringValue -Name "winrm_password" -Text $content

foreach ($pair in @{
    proxmox_api_token_secret = $tokenSecret
    winrm_password           = $winrmPassword
  }.GetEnumerator()) {
  if ($pair.Value -match "^REPLACE_WITH_") {
    throw "$($pair.Key) still contains an example placeholder."
  }
}

$apiBase = $proxmoxUrl.TrimEnd("/")
if ($apiBase -notmatch "/api2/json$") {
  throw "proxmox_url must include /api2/json."
}

$headers = @{
  Authorization = "PVEAPIToken=$tokenId=$tokenSecret"
}

if (-not (Get-Command oscdimg, xorriso, mkisofs, hdiutil -ErrorAction SilentlyContinue)) {
  throw "Missing local ISO creation tool. Install oscdimg, xorriso, mkisofs, or hdiutil before running packer build."
}

try {
  $version = Invoke-RestMethod -Method Get -Uri "$apiBase/version" -Headers $headers -SkipCertificateCheck
}
catch {
  if ($_.Exception.Message -match "SkipCertificateCheck") {
    $version = (& curl.exe -k -sS -H "Authorization: PVEAPIToken=$tokenId=$tokenSecret" "$apiBase/version" | ConvertFrom-Json)
  }
  else {
    throw
  }
}

if (-not $version.data.version) {
  throw "Could not read Proxmox version from API response."
}

$storagesJson = & curl.exe -k -sS `
  -H "Authorization: PVEAPIToken=$tokenId=$tokenSecret" `
  "$apiBase/nodes/$node/storage"
if ($LASTEXITCODE -ne 0) {
  throw "Could not query Proxmox storages for node '$node'."
}
$storages = @((($storagesJson | ConvertFrom-Json).data) | Where-Object { $null -ne $_ })
if (-not ($storages | Where-Object { $_.storage -eq $isoStoragePool })) {
  throw "Storage '$isoStoragePool' is not visible to this API token on node '$node'. Grant storage access before building."
}

$storageContentJson = & curl.exe -k -sS `
  -H "Authorization: PVEAPIToken=$tokenId=$tokenSecret" `
  "$apiBase/nodes/$node/storage/$isoStoragePool/content?content=iso"
if ($LASTEXITCODE -ne 0) {
  throw "Could not query Proxmox ISO storage content."
}
$storageContent = $storageContentJson | ConvertFrom-Json
$items = @($storageContent.data | Where-Object { $null -ne $_ })
if ($items.Count -eq 0) {
  throw "Proxmox ISO storage '$isoStoragePool' returned no ISO entries. Required: $windowsIsoFile and $virtioIsoFile"
}
$firstItem = $items | Select-Object -First 1
if (-not $firstItem -or -not ($firstItem.PSObject.Properties.Name -contains "volid")) {
  $properties = if ($firstItem) { ($firstItem.PSObject.Properties.Name -join ", ") } else { "none" }
  throw "Proxmox ISO storage response did not include volid entries. Available first-item properties: $properties"
}
$volids = @($items | ForEach-Object { $_.volid })

foreach ($iso in @($windowsIsoFile, $virtioIsoFile)) {
  if ($volids -notcontains $iso) {
    throw "Required ISO is not present in Proxmox storage '$isoStoragePool': $iso"
  }
}

Write-Host "Proxmox API reachable and required ISO files are present."
Write-Host "Node: $node"
Write-Host "ISO storage: $isoStoragePool"
Write-Host "Proxmox version: $($version.data.version)"
