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
foreach ($eventLog in @(wevtutil.exe el)) {
  if ([string]::IsNullOrWhiteSpace($eventLog)) {
    continue
  }

  try {
    $clearOutput = & wevtutil.exe cl $eventLog 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Skipping event log '$eventLog': $($clearOutput -join ' ')"
    }
  }
  catch {
    Write-Host "Skipping event log '$eventLog': $($_.Exception.Message)"
  }
}

Write-Host "Windows template optimization completed."
