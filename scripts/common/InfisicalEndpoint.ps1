function Resolve-InfisicalUrl {
  param(
    [Parameter(Mandatory = $true)][string]$CurrentValue,
    [string]$EnvFilePath = ".env"
  )

  $environmentValue = [Environment]::GetEnvironmentVariable("INFISICAL_URL")
  if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
    return $environmentValue.Trim().TrimEnd("/")
  }

  if (Test-Path -LiteralPath $EnvFilePath -PathType Leaf) {
    $line = Get-Content -LiteralPath $EnvFilePath | Where-Object { $_ -match "^INFISICAL_URL\s*=" } | Select-Object -First 1
    if ($line) {
      $value = (($line -split "=", 2)[1]).Trim().Trim('"').Trim("'").TrimEnd("/")
      if (-not [string]::IsNullOrWhiteSpace($value)) {
        return $value
      }
    }
  }

  return $CurrentValue.TrimEnd("/")
}
