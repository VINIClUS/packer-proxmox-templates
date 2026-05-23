Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$panther = "C:\Windows\Panther"
New-Item -ItemType Directory -Path $panther -Force | Out-Null

Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue

Stop-Service -Name WinRM -Force -ErrorAction SilentlyContinue

$sysprep = "$env:WINDIR\System32\Sysprep\Sysprep.exe"
Start-Process -FilePath $sysprep -ArgumentList "/generalize", "/oobe", "/shutdown", "/quiet" -Wait
