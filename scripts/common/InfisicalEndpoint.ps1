function Resolve-InfisicalSetting {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [AllowEmptyString()][string]$CurrentValue = "",
    [string]$EnvFilePath = ".env"
  )

  if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
    return $CurrentValue.Trim()
  }

  $environmentValue = [Environment]::GetEnvironmentVariable($Name)
  if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
    return $environmentValue.Trim()
  }

  if (Test-Path -LiteralPath $EnvFilePath -PathType Leaf) {
    $line = Get-Content -LiteralPath $EnvFilePath | Where-Object { $_ -match ("^" + [regex]::Escape($Name) + "\s*=") } | Select-Object -First 1
    if ($line) {
      $value = (($line -split "=", 2)[1]).Trim().Trim('"').Trim("'")
      if (-not [string]::IsNullOrWhiteSpace($value)) {
        return $value
      }
    }
  }

  throw "Missing required Infisical setting '$Name'. Set it in the process environment, declare it in '$EnvFilePath', or pass the matching script parameter."
}

function Resolve-InfisicalUrl {
  param(
    [AllowEmptyString()][string]$CurrentValue = "",
    [string]$EnvFilePath = ".env"
  )

  $value = (Resolve-InfisicalSetting -Name "INFISICAL_URL" -CurrentValue $CurrentValue -EnvFilePath $EnvFilePath).TrimEnd("/")
  if (-not [uri]::IsWellFormedUriString($value, [System.UriKind]::Absolute)) {
    throw "Invalid INFISICAL_URL '$value'. Provide an absolute URL such as https://infisical.example.local."
  }
  return $value
}
