param(
  [ValidateSet("Linux", "Windows")]
  [string]$Platform = "Linux",
  [string]$Version = "5.4.37",
  [string]$DestinationDirectory = ".downloads/esus-pec",
  [switch]$Force,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$release = @{
  Version     = "5.4.37"
  ReleasePage = "https://sisaps.saude.gov.br/sistemas/esusaps/blog/versao-5-4-37/"
  Downloads  = @{
    Linux   = "https://arquivos.esusaps.ufsc.br/PEC/687651a247e537a3/5.4.37/eSUS-AB-PEC-5.4.37-Linux64.jar"
    Windows = "https://arquivos.esusaps.ufsc.br/PEC/687651a247e537a3/5.4.37/eSUS-AB-PEC-5.4.37-Win64.jar"
  }
}

if ($Version -ne $release.Version) {
  throw "Unsupported e-SUS PEC version '$Version'. Update this script from the official release page before use."
}

$downloadUri = [uri]$release.Downloads[$Platform]
$fileName = Split-Path -Leaf $downloadUri.AbsolutePath
$destinationRoot = if ([System.IO.Path]::IsPathRooted($DestinationDirectory)) {
  $DestinationDirectory
}
else {
  Join-Path (Get-Location) $DestinationDirectory
}
$destinationPath = Join-Path $destinationRoot $fileName

$plan = [ordered]@{
  Version     = $release.Version
  Platform    = $Platform
  ReleasePage = $release.ReleasePage
  Uri         = $downloadUri.AbsoluteUri
  Destination = $destinationPath
}

if ($DryRun) {
  $plan.GetEnumerator() | ForEach-Object { Write-Host "$($_.Key): $($_.Value)" }
  Write-Host "DryRun: no download performed."
  return
}

if ((Test-Path -LiteralPath $destinationPath) -and -not $Force) {
  throw "Destination already exists: $destinationPath. Use -Force to replace it."
}

New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
Invoke-WebRequest -UseBasicParsing -Uri $downloadUri.AbsoluteUri -OutFile $destinationPath

$item = Get-Item -LiteralPath $destinationPath
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $destinationPath

Write-Host "Downloaded: $($item.FullName)"
Write-Host "SizeBytes: $($item.Length)"
Write-Host "SHA256: $($hash.Hash)"
Write-Host "Source: $($release.ReleasePage)"
