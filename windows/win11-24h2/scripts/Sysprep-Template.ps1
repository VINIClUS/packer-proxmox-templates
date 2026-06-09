Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$panther = "C:\Windows\Panther"
New-Item -ItemType Directory -Path $panther -Force | Out-Null

Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue

Stop-Service -Name WinRM -Force -ErrorAction SilentlyContinue

$sysprep = "$env:WINDIR\System32\Sysprep\Sysprep.exe"
$arguments = @("/generalize", "/oobe", "/shutdown", "/quiet")
$cloudbaseUnattend = Join-Path $env:ProgramFiles "Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml"
if (Test-Path -LiteralPath $cloudbaseUnattend) {
  $arguments += "/unattend:`"$cloudbaseUnattend`""
}

Start-Process -FilePath $sysprep -ArgumentList $arguments -Wait
