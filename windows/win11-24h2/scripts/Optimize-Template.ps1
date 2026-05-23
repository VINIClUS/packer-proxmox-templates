Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

powercfg /hibernate off
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance" -Name "fAllowToGetHelp" -Type DWord -Value 0

Get-Service -Name "DiagTrack", "dmwappushservice" -ErrorAction SilentlyContinue |
  ForEach-Object {
    Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
    Set-Service -Name $_.Name -StartupType Disabled
  }

Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
wevtutil el | ForEach-Object { wevtutil cl $_ 2>$null }

Write-Host "Windows template optimization completed."
