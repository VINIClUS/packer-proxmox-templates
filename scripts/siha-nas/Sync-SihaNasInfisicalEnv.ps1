param(
  [string]$EnvFile = ".env",
  [string]$SecondaryEnvFile = "",
  [string]$InfisicalUrl = "",
  [string]$InfisicalWorkspaceId = "",
  [string]$InfisicalProjectSlug = "",
  [string]$InfisicalEnvironment = "",
  [string]$InfisicalSecretPath = "/siha-nas",
  [ValidatePattern("^[A-Za-z][A-Za-z0-9_]*$")]
  [string]$InfisicalSettingPrefix = "TEMPLATE_INFISICAL",
  [switch]$RemoveOnly,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\InfisicalEndpoint.ps1")

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ([string]::IsNullOrWhiteSpace($SecondaryEnvFile)) {
  $SecondaryEnvFile = Join-Path (Split-Path $repoRoot -Parent) "sus-siha-bootstrap\.env"
}

function Get-EnvFileValues {
  param([string[]]$Paths)

  $values = @{}
  foreach ($path in $Paths) {
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
      continue
    }

    foreach ($line in Get-Content -LiteralPath $path) {
      $trimmed = $line.Trim()
      if ($trimmed -eq "" -or $trimmed.StartsWith("#") -or $trimmed -notmatch "=") {
        continue
      }

      $parts = $trimmed -split "=", 2
      $key = $parts[0].Trim()
      if (-not $values.ContainsKey($key)) {
        $values[$key] = $parts[1].Trim().Trim('"').Trim("'")
      }
    }
  }

  return $values
}

function Get-ConfigValue {
  param(
    [hashtable]$Values,
    [string[]]$Names,
    [string]$Default = $null
  )

  foreach ($name in $Names) {
    foreach ($candidate in @($name, $name.ToUpperInvariant())) {
      $environmentValue = [Environment]::GetEnvironmentVariable($candidate)
      if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
        return $environmentValue.Trim()
      }
    }
  }

  foreach ($name in $Names) {
    foreach ($candidate in @($name, $name.ToUpperInvariant())) {
      if ($Values.ContainsKey($candidate) -and -not [string]::IsNullOrWhiteSpace([string]$Values[$candidate])) {
        return [string]$Values[$candidate]
      }
    }
  }

  return $Default
}

function Get-InfisicalSettingNames {
  param([Parameter(Mandatory = $true)][string]$SettingSuffix)

  $prefixes = New-Object System.Collections.Generic.List[string]
  $prefixes.Add($InfisicalSettingPrefix)

  # The intended namespace is TEMPLATE_INFISICAL_*. The local bootstrap env has
  # historically used TEMPLATES_INFISICAL_*; accept it only as a compatibility
  # alias for the template project, never as a fallback for INFISICAL_*.
  if ($InfisicalSettingPrefix -eq "TEMPLATE_INFISICAL") {
    $prefixes.Add("TEMPLATES_INFISICAL")
  }

  $names = New-Object System.Collections.Generic.List[string]
  foreach ($prefix in ($prefixes | Select-Object -Unique)) {
    $names.Add("${prefix}_${SettingSuffix}")
  }

  return @($names.ToArray())
}

function Resolve-PrefixedInfisicalSetting {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Values,
    [Parameter(Mandatory = $true)][string]$SettingSuffix,
    [AllowEmptyString()][string]$CurrentValue = ""
  )

  if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
    return $CurrentValue.Trim()
  }

  $names = Get-InfisicalSettingNames -SettingSuffix $SettingSuffix
  $value = Get-ConfigValue -Values $Values -Names $names
  if (-not [string]::IsNullOrWhiteSpace($value)) {
    return $value.Trim()
  }

  throw "Missing required Infisical setting for '$SettingSuffix'. Set one of: $($names -join ', ')."
}

function Get-InfisicalCredential {
  param([hashtable]$Values)

  $candidates = @(Get-InfisicalSettingNames -SettingSuffix "TOKEN")
  if ($InfisicalSettingPrefix -eq "INFISICAL") {
    $candidates += "infisical_secret_key"
  }

  foreach ($candidate in $candidates) {
    $environmentValue = [Environment]::GetEnvironmentVariable($candidate)
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
      return $environmentValue.Trim()
    }
    if ($Values.ContainsKey($candidate) -and -not [string]::IsNullOrWhiteSpace([string]$Values[$candidate])) {
      return [string]$Values[$candidate]
    }
  }

  throw "Infisical token not found. Set one of: $($candidates -join ', ')."
}

function Get-InfisicalSecrets {
  param(
    [string]$SecretPath,
    [hashtable]$Headers
  )

  $uri = "$InfisicalUrl/api/v3/secrets/raw?workspaceId=$InfisicalWorkspaceId&environment=$InfisicalEnvironment&secretPath=$([uri]::EscapeDataString($SecretPath))"
  $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -TimeoutSec 30
  $result = @{}
  foreach ($item in @($response.secrets)) {
    $result[[string]$item.secretKey] = [string]$item.secretValue
  }
  return $result
}

function Join-InfisicalPath {
  param(
    [string]$ParentPath,
    [string]$Name
  )

  if ($ParentPath -eq "/") {
    return "/$Name"
  }
  return "$ParentPath/$Name"
}

function Ensure-InfisicalFolderPath {
  param(
    [string]$SecretPath,
    [hashtable]$Headers
  )

  $segments = @($SecretPath.Trim("/") -split "/" | Where-Object { $_ -ne "" })
  if ($segments.Count -eq 0) {
    return
  }

  $parent = "/"
  foreach ($segment in $segments) {
    $listUri = "$InfisicalUrl/api/v1/folders?workspaceId=$InfisicalWorkspaceId&environment=$InfisicalEnvironment&path=$([uri]::EscapeDataString($parent))"
    $folders = Invoke-RestMethod -Method Get -Uri $listUri -Headers $Headers -TimeoutSec 30

    if (@($folders.folders | Where-Object { $_.name -eq $segment }).Count -eq 0) {
      $body = @{
        workspaceId = $InfisicalWorkspaceId
        environment = $InfisicalEnvironment
        name = $segment
        path = $parent
      } | ConvertTo-Json -Compress

      try {
        $null = Invoke-RestMethod -Method Post -Uri "$InfisicalUrl/api/v1/folders" -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
      } catch {
        if (-not $_.Exception.Response -or $_.Exception.Response.StatusCode.value__ -ne 409) {
          throw
        }
      }
    }

    $parent = Join-InfisicalPath -ParentPath $parent -Name $segment
  }
}

function Set-InfisicalSecret {
  param(
    [string]$Name,
    [AllowEmptyString()][string]$Value,
    [hashtable]$Headers,
    [bool]$Exists
  )

  $uri = "$InfisicalUrl/api/v3/secrets/raw/$([uri]::EscapeDataString($Name))"
  $body = @{
    environment = $InfisicalEnvironment
    workspaceId = $InfisicalWorkspaceId
    projectSlug = $InfisicalProjectSlug
    secretPath = $InfisicalSecretPath
    secretValue = $Value
    skipMultilineEncoding = $true
    type = "shared"
    secretComment = "Managed by scripts/siha-nas/Sync-SihaNasInfisicalEnv.ps1"
  } | ConvertTo-Json -Depth 5

  if (-not $Exists) {
    $null = Invoke-RestMethod -Method Post -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
    return "created"
  }

  try {
    $null = Invoke-RestMethod -Method Patch -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
    return "updated"
  } catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
      $null = Invoke-RestMethod -Method Post -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
      return "created"
    }
    throw
  }
}

$envValues = Get-EnvFileValues -Paths @($EnvFile, $SecondaryEnvFile)

$InfisicalUrl = (Resolve-PrefixedInfisicalSetting -Values $envValues -SettingSuffix "URL" -CurrentValue $InfisicalUrl).TrimEnd("/")
if (-not [uri]::IsWellFormedUriString($InfisicalUrl, [System.UriKind]::Absolute)) {
  throw "Invalid Infisical URL for prefix '$InfisicalSettingPrefix'. Provide an absolute URL such as https://infisical.example.local."
}
$InfisicalWorkspaceId = Resolve-PrefixedInfisicalSetting -Values $envValues -SettingSuffix "WORKSPACE_ID" -CurrentValue $InfisicalWorkspaceId
$InfisicalProjectSlug = Resolve-PrefixedInfisicalSetting -Values $envValues -SettingSuffix "PROJECT_SLUG" -CurrentValue $InfisicalProjectSlug
$InfisicalEnvironment = Resolve-PrefixedInfisicalSetting -Values $envValues -SettingSuffix "ENVIRONMENT" -CurrentValue $InfisicalEnvironment

$headers = @{ Authorization = "Bearer $(Get-InfisicalCredential -Values $envValues)" }

$desired = [ordered]@{
  SIHA_NAS_CTID = "7010"
  SIHA_NAS_HOSTNAME = "siha-nas"
  SIHA_NAS_IP = "192.168.1.163"
  SIHA_NAS_CIDR = "192.168.1.163/24"
  SIHA_NAS_GATEWAY = "192.168.1.1"
  SIHA_NAS_ALLOWED_CIDR = "192.168.1.0/24"
  SIHA_NAS_TEMPLATE = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
  SIHA_NAS_STORAGE_ROOTFS = "rpool"
  SIHA_NAS_STORAGE_DADOS = "rpool"
  SIHA_NAS_ROOTFS_GB = "64"
  SIHA_NAS_DATA_PATH = "/dados/siha"
  SIHA_NAS_SAMBA_SHARE = "SIHA"
  SIHA_NAS_SAMBA_UNC = "\\siha-nas\SIHA"
  SIHA_NAS_SAMBA_GROUP = "siha_faturamento"
  SIHA_NAS_SAMBA_USER = "siha_user"
  SIHA_NAS_WINDOWS_VM_ID = "7001"
  SIHA_NAS_WINDOWS_HOST = "SIHA"
  SIHA_NAS_WINDOWS_IP = "192.168.1.97"
  SIHA_NAS_WINDOWS_USER = "Administrator"
  SIHA_NAS_WINDOWS_DRIVE = "S:"
  SIHA_NAS_BACKUP_POLICY = "weekly-rotating-4-weeks"
  SIHA_NAS_BACKUP_RETENTION_WEEKS = "4"
}

$sambaPassword = Get-ConfigValue -Values $envValues -Names @("SIHA_NAS_SAMBA_PASSWORD", "siha_password")
if (-not [string]::IsNullOrWhiteSpace($sambaPassword)) {
  $desired["SIHA_NAS_SAMBA_PASSWORD"] = $sambaPassword
}

function Remove-InfisicalSecret {
  param(
    [string]$Name,
    [hashtable]$Headers
  )

  $uri = "$InfisicalUrl/api/v3/secrets/raw/$([uri]::EscapeDataString($Name))"
  $body = @{
    environment = $InfisicalEnvironment
    workspaceId = $InfisicalWorkspaceId
    projectSlug = $InfisicalProjectSlug
    secretPath = $InfisicalSecretPath
    type = "shared"
  } | ConvertTo-Json -Depth 5

  try {
    $null = Invoke-RestMethod -Method Delete -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
    return "deleted"
  } catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
      return "missing"
    }
    throw
  }
}

$secretPathExists = $true
try {
  $existing = Get-InfisicalSecrets -SecretPath $InfisicalSecretPath -Headers $headers
} catch {
  if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
    $secretPathExists = $false
  } else {
    throw
  }

  if ($DryRun -or $RemoveOnly) {
    $existing = @{}
  } else {
    Ensure-InfisicalFolderPath -SecretPath $InfisicalSecretPath -Headers $headers
    $existing = Get-InfisicalSecrets -SecretPath $InfisicalSecretPath -Headers $headers
    $secretPathExists = $true
  }
}

$changes = New-Object System.Collections.Generic.List[object]
foreach ($entry in $desired.GetEnumerator()) {
  $exists = $existing.ContainsKey($entry.Key)
  $action = if ($RemoveOnly) {
    if (-not $exists) {
      "missing"
    } elseif ($DryRun) {
      "would-delete"
    } else {
      Remove-InfisicalSecret -Name $entry.Key -Headers $headers
    }
  } elseif ($DryRun) {
    if ($exists) { "would-update" } else { "would-create" }
  } else {
    Set-InfisicalSecret -Name $entry.Key -Value ([string]$entry.Value) -Headers $headers -Exists $exists
  }

  $changes.Add([pscustomobject][ordered]@{
      path = "$InfisicalSecretPath/$($entry.Key)"
      action = $action
      valuePresent = -not [string]::IsNullOrWhiteSpace([string]$entry.Value)
      sensitive = ($entry.Key -match "PASSWORD|TOKEN|SECRET|KEY")
    })
}

$skipped = @()
if ([string]::IsNullOrWhiteSpace($sambaPassword)) {
  $skipped = @("$InfisicalSecretPath/SIHA_NAS_SAMBA_PASSWORD")
}

[ordered]@{
  dryRun = [bool]$DryRun.IsPresent
  operation = if ($RemoveOnly) { "remove" } else { "sync" }
  infisicalSettingPrefix = $InfisicalSettingPrefix
  infisicalUrl = $InfisicalUrl
  environment = $InfisicalEnvironment
  secretPath = $InfisicalSecretPath
  secretPathExists = [bool]$secretPathExists
  syncedCount = [int]$changes.Count
  changes = @($changes.ToArray())
  skipped = @($skipped)
} | ConvertTo-Json -Depth 5
