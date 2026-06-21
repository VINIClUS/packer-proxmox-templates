param(
  [string]$ConfigFile = "config/Proxmox.pkrvars.hcl",
  [int]$Ctid = 133,
  [string]$InfisicalUrl = "",
  [string]$InfisicalWorkspaceId = "",
  [string]$InfisicalProjectSlug = "",
  [string]$InfisicalEnvironment = "",
  [string]$RuntimeSecretPath = "/test",
  [string]$InstallationSecretPath = "/test/InstallationConfig",
  [string]$MonitoringSecretPath = "/test/Monitoring",
  [string]$ObjectStorageSecretPath = "/test/ObjectStorage",
  [switch]$AllowBootstrapEmptySources,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\InfisicalEndpoint.ps1")
$infisicalEnvFile = if (Get-Variable -Name EnvFile -ErrorAction SilentlyContinue) { $EnvFile } else { ".env" }
$InfisicalUrl = Resolve-InfisicalUrl -CurrentValue $InfisicalUrl -EnvFilePath $infisicalEnvFile
$InfisicalWorkspaceId = Resolve-InfisicalSetting -Name "INFISICAL_WORKSPACE_ID" -CurrentValue $InfisicalWorkspaceId -EnvFilePath $infisicalEnvFile
$InfisicalProjectSlug = Resolve-InfisicalSetting -Name "INFISICAL_PROJECT_SLUG" -CurrentValue $InfisicalProjectSlug -EnvFilePath $infisicalEnvFile
$InfisicalEnvironment = Resolve-InfisicalSetting -Name "INFISICAL_ENVIRONMENT" -CurrentValue $InfisicalEnvironment -EnvFilePath $infisicalEnvFile

function Get-HclValue {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Text,
    [string]$Default = $null
  )

  $line = $Text -split "`n" | Where-Object { $_ -match ("^\s*" + [regex]::Escape($Name) + "\s*=") } | Select-Object -First 1
  if (-not $line) { return $Default }
  return (($line -split "=", 2)[1]).Trim().Trim('"')
}

function Invoke-ProxmoxSsh {
  param(
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$Port,
    [Parameter(Mandatory = $true)][string]$KeyFile,
    [Parameter(Mandatory = $true)][string]$RemoteCommand
  )

  $output = & ssh -i $KeyFile -p $Port -o BatchMode=yes -o StrictHostKeyChecking=accept-new $Target $RemoteCommand 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "Remote SSH command failed with exit code $LASTEXITCODE."
  }
  return ($output -join "`n")
}

function Get-InfisicalToken {
  if ($env:infisical_secret_key) { return $env:infisical_secret_key }
  if ($env:INFISICAL_TOKEN) { return $env:INFISICAL_TOKEN }
  if (Test-Path -LiteralPath ".env") {
    foreach ($candidate in @("infisical_secret_key", "INFISICAL_TOKEN")) {
      $line = Get-Content -LiteralPath ".env" | Where-Object { $_ -match ("^" + [regex]::Escape($candidate) + "=") } | Select-Object -First 1
      if ($line) {
        $value = (($line -split "=", 2)[1]).Trim().Trim('"').Trim("'")
        if (-not [string]::IsNullOrWhiteSpace($value)) {
          return $value
        }
      }
    }
  }
  throw "Infisical token not found. Set infisical_secret_key in .env or INFISICAL_TOKEN."
}

function Get-InfisicalSecrets {
  param(
    [Parameter(Mandatory = $true)][string]$SecretPath,
    [Parameter(Mandatory = $true)][hashtable]$Headers
  )

  $uri = "$InfisicalUrl/api/v3/secrets/raw?workspaceId=$InfisicalWorkspaceId&environment=$InfisicalEnvironment&secretPath=$([uri]::EscapeDataString($SecretPath))"
  try {
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -TimeoutSec 30
  } catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) { return @{} }
    throw
  }

  $result = @{}
  foreach ($secret in @($response.secrets)) {
    $result[[string]$secret.secretKey] = [string]$secret.secretValue
  }
  return $result
}

function Ensure-InfisicalFolderPath {
  param(
    [Parameter(Mandatory = $true)][string]$SecretPath,
    [Parameter(Mandatory = $true)][hashtable]$Headers
  )

  $segments = @($SecretPath.Trim("/") -split "/" | Where-Object { $_ -ne "" })
  if ($segments.Count -eq 0) { return }

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
        if (-not $_.Exception.Response -or $_.Exception.Response.StatusCode.value__ -ne 409) { throw }
      }
    }

    if ($parent -eq "/") { $parent = "/$segment" } else { $parent = "$parent/$segment" }
  }
}

function Set-InfisicalSecret {
  param(
    [Parameter(Mandatory = $true)][string]$SecretPath,
    [Parameter(Mandatory = $true)][string]$Name,
    [AllowEmptyString()][Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][hashtable]$Headers,
    [Parameter(Mandatory = $true)][bool]$Exists
  )

  $uri = "$InfisicalUrl/api/v3/secrets/raw/$([uri]::EscapeDataString($Name))"
  $body = @{
    environment = $InfisicalEnvironment
    workspaceId = $InfisicalWorkspaceId
    projectSlug = $InfisicalProjectSlug
    secretPath = $SecretPath
    secretValue = $Value
    skipMultilineEncoding = $true
    type = "shared"
    secretComment = "Managed by scripts/esus-pec/Sync-EsusPecInfisicalVariables.ps1"
  } | ConvertTo-Json -Depth 5

  if (-not $Exists) {
    Ensure-InfisicalFolderPath -SecretPath $SecretPath -Headers $Headers
    $null = Invoke-RestMethod -Method Post -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
    return "created"
  }

  try {
    $null = Invoke-RestMethod -Method Patch -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
    return "updated"
  } catch {
    $status = $_.Exception.Response.StatusCode.value__
    if ($status -ne 404) {
      throw "Failed to update Infisical secret $Name in $SecretPath. HTTP status: $status"
    }
    Ensure-InfisicalFolderPath -SecretPath $SecretPath -Headers $Headers
    $null = Invoke-RestMethod -Method Post -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
    return "created"
  }
}

function Remove-InfisicalSecret {
  param(
    [Parameter(Mandatory = $true)][string]$SecretPath,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][hashtable]$Headers
  )

  $uri = "$InfisicalUrl/api/v3/secrets/raw/$([uri]::EscapeDataString($Name))"
  $body = @{
    environment = $InfisicalEnvironment
    workspaceId = $InfisicalWorkspaceId
    secretPath = $SecretPath
    type = "shared"
  } | ConvertTo-Json -Depth 5

  $null = Invoke-RestMethod -Method Delete -Uri $uri -Headers $Headers -ContentType "application/json" -Body $body -TimeoutSec 30
}

function Test-InfisicalSecretPathWritable {
  param(
    [Parameter(Mandatory = $true)][string]$SecretPath,
    [Parameter(Mandatory = $true)][hashtable]$Headers
  )

  $probeName = "__ESUS_PEC_SYNC_WRITE_TEST_$([guid]::NewGuid().ToString("N"))"
  try {
    $null = Set-InfisicalSecret -SecretPath $SecretPath -Name $probeName -Value "probe" -Headers $Headers -Exists $false
    Remove-InfisicalSecret -SecretPath $SecretPath -Name $probeName -Headers $Headers
  } catch {
    $status = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { "unknown" }
    throw "Infisical path '$SecretPath' is not writable by the current token. Grant create/delete on this exact secret path before running a non-dry-run sync. HTTP status: $status"
  }
}

function Add-Expected {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Target,
    [Parameter(Mandatory = $true)][string]$Name,
    [AllowEmptyString()][Parameter(Mandatory = $true)][string]$Value
  )

  $Target[$Name] = $Value
}

function Merge-SecretMaps {
  param([Parameter(Mandatory = $true)][hashtable[]]$Maps)

  $merged = @{}
  foreach ($map in $Maps) {
    foreach ($key in $map.Keys) {
      if (-not $merged.ContainsKey($key)) {
        $merged[$key] = [string]$map[$key]
      }
    }
  }
  return $merged
}

function Get-ExistingSecretValueFromSources {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][hashtable[]]$Sources,
    [AllowEmptyString()][string]$Default = ""
  )

  foreach ($source in $Sources) {
    if ($source.ContainsKey($Name)) { return [string]$source[$Name] }
  }
  return $Default
}

function Get-ExampleEnvValues {
  param([Parameter(Mandatory = $true)][string]$Path)

  $values = [ordered]@{}
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $values }

  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed.StartsWith("#") -or $trimmed -notmatch "=") { continue }
    $parts = $trimmed -split "=", 2
    $name = $parts[0].Trim()
    if ($name -match "^[A-Za-z_][A-Za-z0-9_]*$") {
      $values[$name] = $parts[1].Trim().Trim('"').Trim("'")
    }
  }

  return $values
}

function Get-InstallationSecretPaths {
  return @(
    $InstallationSecretPath,
    "$InstallationSecretPath/FirstRun",
    "$InstallationSecretPath/TLS",
    "$InstallationSecretPath/Connectivity",
    "$InstallationSecretPath/Security",
    "$InstallationSecretPath/Municipality",
    "$InstallationSecretPath/Files",
    "$InstallationSecretPath/Advanced",
    "$InstallationSecretPath/GovBrOAuth",
    "$InstallationSecretPath/ImportacaoCNES",
    "$InstallationSecretPath/ImportacaoBolsaFamilia",
    "$InstallationSecretPath/Transmissao",
    "$InstallationSecretPath/TransmissaoAPI"
  )
}

function Get-DesiredInfisicalPath {
  param([Parameter(Mandatory = $true)][string]$Name)

  $runtimeExactNames = @(
    "ESUS_PEC_ADMIN_USERNAME",
    "ESUS_PEC_ADMIN_PASSWORD",
    "ESUS_PEC_SMTP_HOST",
    "ESUS_PEC_SMTP_PORT",
    "ESUS_PEC_SMTP_USERNAME",
    "ESUS_PEC_SMTP_PASSWORD",
    "ESUS_PEC_BACKUP_ENCRYPTION_PASSWORD",
    "ESUS_PEC_RESTORE_ARCHIVE_PASSWORD"
  )

  if ($Name -match "^ESUS_PEC_OBJECT_STORAGE_" -or $Name -match "^ESUS_PEC_WALG_") { return $ObjectStorageSecretPath }
  if ($Name -eq "ESUS_PEC_POSTGRES_EXPORTER_PASSWORD" -or $Name -in @("grafana_url", "grafana_token")) { return $MonitoringSecretPath }
  if ($Name -match "^ESUS_PEC_DB_" -or $Name -in $runtimeExactNames) { return $RuntimeSecretPath }
  if ($Name -match "^ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_" -or $Name -eq "ESUS_PEC_TRANSMISSAO_CREDENCIAIS_INTEGRACAO_EXPECTED_COUNT") { return "$InstallationSecretPath/TransmissaoAPI" }
  if ($Name -match "^ESUS_PEC_TRANSMISSAO_") { return "$InstallationSecretPath/Transmissao" }
  if ($Name -match "^ESUS_PEC_CNES_") { return "$InstallationSecretPath/ImportacaoCNES" }
  if ($Name -match "^ESUS_PEC_BOLSA_FAMILIA_") { return "$InstallationSecretPath/ImportacaoBolsaFamilia" }
  if ($Name -match "^ESUS_PEC_GOVBR_") { return "$InstallationSecretPath/GovBrOAuth" }
  if ($Name -match "^ESUS_PEC_TLS_") { return "$InstallationSecretPath/TLS" }
  if ($Name -in @("ESUS_PEC_INTERNET_ENABLED", "ESUS_PEC_CADSUS_ENABLED", "ESUS_PEC_CADSUS_DISABLE_INTERVAL", "ESUS_PEC_HORUS_ENABLED", "ESUS_PEC_HORUS_DISABLE_INTERVAL", "ESUS_PEC_VIDEOCHAMADAS_ENABLED", "ESUS_PEC_AGENDA_ONLINE_ENABLED", "ESUS_PEC_SMTP_ENABLED", "ESUS_PEC_SMTP_FROM_EMAIL", "ESUS_PEC_SMTP_USE_LOGIN_AS_SENDER")) { return "$InstallationSecretPath/Connectivity" }
  if ($Name -in @("ESUS_PEC_ASSINATURA_DIGITAL_ENABLED", "ESUS_PEC_ASSINATURA_DIGITAL_LOGIN", "ESUS_PEC_ASSINATURA_DIGITAL_PASSWORD", "ESUS_PEC_PASSWORD_RESET_PERIOD_MONTHS", "ESUS_PEC_MAX_INACTIVITY_MINUTES", "ESUS_PEC_MAX_LOGIN_ATTEMPTS", "ESUS_PEC_FORCE_PASSWORD_RESET_ON_NEXT_LOGIN")) { return "$InstallationSecretPath/Security" }
  if ($Name -in @("ESUS_PEC_MUNICIPALITY_ID", "ESUS_PEC_RESPONSIBLE_PROFESSIONAL_ID", "ESUS_PEC_MUNICIPAL_RESPONSIBLE_ENABLED")) { return "$InstallationSecretPath/Municipality" }
  if ($Name -match "^ESUS_PEC_FILE_ATTACHMENTS_") { return "$InstallationSecretPath/Files" }
  if ($Name -in @("ESUS_PEC_CONCURRENT_REQUESTS_USE_DEFAULT", "ESUS_PEC_CONCURRENT_REQUESTS", "ESUS_PEC_CITIZEN_SEARCH_BY_PROPERTIES_ENABLED", "ESUS_PEC_CDS_PROPERTY_FAMILY_REGISTRATION_ENABLED", "ESUS_PEC_BASE_UNIFICATION_ENABLED", "ESUS_PEC_BASE_UNIFICATION_MODE", "ESUS_PEC_SERVER_TIMEZONE", "ESUS_PEC_SERVER_TIMEZONE_OFFSET_MINUTES")) { return "$InstallationSecretPath/Advanced" }
  if ($Name -match "^ESUS_PEC_") { return "$InstallationSecretPath/FirstRun" }

  return $null
}

function Test-ManagedInfisicalName {
  param([Parameter(Mandatory = $true)][string]$Name)
  return ($Name -match "^ESUS_PEC_" -or $Name -in @("grafana_url", "grafana_token"))
}

function Get-RemotePecDatabaseValues {
  param(
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$Port,
    [Parameter(Mandatory = $true)][string]$KeyFile,
    [Parameter(Mandatory = $true)][int]$ContainerId
  )

  $remote = "pct exec $ContainerId -- cat /opt/e-SUS/webserver/config/credenciais.txt"
  $content = Invoke-ProxmoxSsh -Target $Target -Port $Port -KeyFile $KeyFile -RemoteCommand $remote

  $urlMatch = [regex]::Match($content, "Url de conex.o:\s*(?<url>\S+)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  $fullUserMatch = [regex]::Match($content, "Usu.rio com acesso completo.*?usu.rio:\s*(?<user>\S+).*?senha:\s*(?<password>\S+)", [System.Text.RegularExpressions.RegexOptions]::Singleline)
  $readOnlyUserMatch = [regex]::Match($content, "Usu.rio com acesso de leitura.*?usu.rio:\s*(?<user>\S+).*?senha:\s*(?<password>\S+)", [System.Text.RegularExpressions.RegexOptions]::Singleline)

  if (-not $urlMatch.Success -or -not $fullUserMatch.Success -or -not $readOnlyUserMatch.Success) {
    throw "Could not parse PEC database credential file."
  }

  $jdbc = $urlMatch.Groups["url"].Value
  $dbMatch = [regex]::Match($jdbc, "jdbc:postgresql://(?<host>[^:/]+)(:(?<port>\d+))?/(?<name>[^?\s]+)")
  if (-not $dbMatch.Success) { throw "Could not parse PEC database JDBC URL." }

  return @{
    ESUS_PEC_DB_HOST = $dbMatch.Groups["host"].Value
    ESUS_PEC_DB_PORT = if ($dbMatch.Groups["port"].Success) { $dbMatch.Groups["port"].Value } else { "5432" }
    ESUS_PEC_DB_NAME = $dbMatch.Groups["name"].Value
    ESUS_PEC_DB_USER = $fullUserMatch.Groups["user"].Value
    ESUS_PEC_DB_PASSWORD = $fullUserMatch.Groups["password"].Value
    ESUS_PEC_DB_READONLY_USER = $readOnlyUserMatch.Groups["user"].Value
    ESUS_PEC_DB_READONLY_PASSWORD = $readOnlyUserMatch.Groups["password"].Value
  }
}

function Find-ExistingSecretPath {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [Parameter(Mandatory = $true)][hashtable]$ExistingByPath
  )

  foreach ($path in $ExistingByPath.Keys) {
    if ($path -ne $TargetPath -and $ExistingByPath[$path].ContainsKey($Name)) {
      return [string]$path
    }
  }
  return $null
}

function Reconcile-ExpectedSecrets {
  param(
    [Parameter(Mandatory = $true)][hashtable]$ExpectedByPath,
    [Parameter(Mandatory = $true)][hashtable]$ExistingByPath,
    [Parameter(Mandatory = $true)][hashtable]$Headers,
    [System.Collections.Generic.List[string]]$Created,
    [System.Collections.Generic.List[string]]$Updated,
    [System.Collections.Generic.List[string]]$Deleted,
    [Parameter(Mandatory = $true)][bool]$IsDryRun
  )

  foreach ($path in $ExpectedByPath.Keys) {
    foreach ($name in $ExpectedByPath[$path].Keys) {
      $value = [string]$ExpectedByPath[$path][$name]
      $targetExists = $ExistingByPath[$path].ContainsKey($name)

      if ($IsDryRun) {
        if (-not $targetExists) { $Created.Add("$path/$name") }
        foreach ($sourcePath in $ExistingByPath.Keys) {
          if ($sourcePath -ne $path -and $ExistingByPath[$sourcePath].ContainsKey($name)) {
            $Deleted.Add("$sourcePath/$name")
          }
        }
        continue
      }

      if (-not $targetExists) {
        $sourcePath = Find-ExistingSecretPath -Name $name -TargetPath $path -ExistingByPath $ExistingByPath
        $null = Set-InfisicalSecret -SecretPath $path -Name $name -Value $value -Headers $Headers -Exists $false
        $Created.Add("$path/$name")
        if ($sourcePath) {
          Remove-InfisicalSecret -SecretPath $sourcePath -Name $name -Headers $Headers
          $Deleted.Add("$sourcePath/$name")
          $ExistingByPath[$sourcePath].Remove($name)
        }
        $ExistingByPath[$path][$name] = $value
      } else {
        if ([string]$ExistingByPath[$path][$name] -ne $value) {
          $action = Set-InfisicalSecret -SecretPath $path -Name $name -Value $value -Headers $Headers -Exists $true
          if ($action -eq "created") { $Created.Add("$path/$name") } else { $Updated.Add("$path/$name") }
        }
      }
    }
  }
}

$configText = Get-Content -LiteralPath $ConfigFile -Raw
$sshHost = Get-HclValue -Name "proxmox_ssh_host" -Text $configText
$sshPort = Get-HclValue -Name "proxmox_ssh_port" -Text $configText -Default "22"
$sshUser = Get-HclValue -Name "proxmox_ssh_user" -Text $configText -Default "root"
$sshKey = Get-HclValue -Name "proxmox_ssh_private_key_file" -Text $configText
$sshTarget = "$sshUser@$sshHost"

$headers = @{ Authorization = "Bearer $(Get-InfisicalToken)" }
$installationPaths = @(Get-InstallationSecretPaths)
$managedPaths = @($RuntimeSecretPath) + $installationPaths + @($MonitoringSecretPath, $ObjectStorageSecretPath)

$existingByPath = @{}
foreach ($path in $managedPaths) {
  $existingByPath[$path] = Get-InfisicalSecrets -SecretPath $path -Headers $headers
}

$existingRuntime = $existingByPath[$RuntimeSecretPath]
$existingInstall = Merge-SecretMaps -Maps @($installationPaths | ForEach-Object { $existingByPath[$_] })
$existingMonitoring = $existingByPath[$MonitoringSecretPath]
$existingObjectStorage = $existingByPath[$ObjectStorageSecretPath]
$allSources = @($existingRuntime, $existingInstall, $existingMonitoring, $existingObjectStorage)

$expectedRuntime = @{}
foreach ($entry in (Get-RemotePecDatabaseValues -Target $sshTarget -Port $sshPort -KeyFile $sshKey -ContainerId $Ctid).GetEnumerator()) {
  Add-Expected -Target $expectedRuntime -Name $entry.Key -Value $entry.Value
}

Add-Expected -Target $expectedRuntime -Name "ESUS_PEC_ADMIN_USERNAME" -Value (Get-ExistingSecretValueFromSources -Name "ESUS_PEC_INSTALLER_CPF" -Sources @($existingInstall, $existingRuntime))
Add-Expected -Target $expectedRuntime -Name "ESUS_PEC_ADMIN_PASSWORD" -Value (Get-ExistingSecretValueFromSources -Name "ESUS_PEC_INITIAL_PASSWORD" -Sources @($existingInstall, $existingRuntime))
Add-Expected -Target $expectedRuntime -Name "ESUS_PEC_SMTP_HOST" -Value (Get-ExistingSecretValueFromSources -Name "ESUS_PEC_SMTP_HOST" -Sources $allSources)
Add-Expected -Target $expectedRuntime -Name "ESUS_PEC_SMTP_PORT" -Value (Get-ExistingSecretValueFromSources -Name "ESUS_PEC_SMTP_PORT" -Sources $allSources -Default "587")
Add-Expected -Target $expectedRuntime -Name "ESUS_PEC_SMTP_USERNAME" -Value (Get-ExistingSecretValueFromSources -Name "ESUS_PEC_SMTP_USERNAME" -Sources $allSources)
Add-Expected -Target $expectedRuntime -Name "ESUS_PEC_SMTP_PASSWORD" -Value (Get-ExistingSecretValueFromSources -Name "ESUS_PEC_SMTP_PASSWORD" -Sources $allSources)
Add-Expected -Target $expectedRuntime -Name "ESUS_PEC_BACKUP_ENCRYPTION_PASSWORD" -Value (Get-ExistingSecretValueFromSources -Name "ESUS_PEC_BACKUP_ENCRYPTION_PASSWORD" -Sources $allSources)
Add-Expected -Target $expectedRuntime -Name "ESUS_PEC_RESTORE_ARCHIVE_PASSWORD" -Value (Get-ExistingSecretValueFromSources -Name "ESUS_PEC_RESTORE_ARCHIVE_PASSWORD" -Sources $allSources)

$exampleValues = Get-ExampleEnvValues -Path "config/esus-pec.infisical.env.example"
$expectedByPath = @{}
foreach ($path in $managedPaths) { $expectedByPath[$path] = @{} }
foreach ($entry in $expectedRuntime.GetEnumerator()) {
  Add-Expected -Target $expectedByPath[$RuntimeSecretPath] -Name $entry.Key -Value $entry.Value
}

foreach ($entry in $exampleValues.GetEnumerator()) {
  $desiredPath = Get-DesiredInfisicalPath -Name $entry.Key
  if ($null -eq $desiredPath) { continue }
  if ($desiredPath -eq $RuntimeSecretPath -and $expectedByPath[$RuntimeSecretPath].ContainsKey($entry.Key)) { continue }
  $value = Get-ExistingSecretValueFromSources -Name $entry.Key -Sources $allSources -Default ([string]$entry.Value)
  Add-Expected -Target $expectedByPath[$desiredPath] -Name $entry.Key -Value $value
}

if (-not $DryRun -and -not $AllowBootstrapEmptySources) {
  if ($existingRuntime.Count -eq 0 -and $expectedByPath[$RuntimeSecretPath].Count -gt 0) {
    throw "Refusing to sync because '$RuntimeSecretPath' is readable but has zero visible secrets. Restore token read access or rerun with -AllowBootstrapEmptySources only after confirming a deliberate bootstrap."
  }
  $expectedInstallVisibleCount = 0
  foreach ($path in $installationPaths) {
    $expectedInstallVisibleCount += $expectedByPath[$path].Count
  }
  if ($existingInstall.Count -eq 0 -and $expectedInstallVisibleCount -gt 0) {
    throw "Refusing to sync because '$InstallationSecretPath' and its managed subfolders have zero visible secrets. Restore token read access before moving existing InstallationConfig values."
  }
}

$allowedByPath = @{}
foreach ($path in $managedPaths) {
  $allowedByPath[$path] = [string[]]$expectedByPath[$path].Keys
}

$created = New-Object System.Collections.Generic.List[string]
$updated = New-Object System.Collections.Generic.List[string]
$deleted = New-Object System.Collections.Generic.List[string]

Reconcile-ExpectedSecrets -ExpectedByPath $expectedByPath -ExistingByPath $existingByPath -Headers $headers -Created $created -Updated $updated -Deleted $deleted -IsDryRun $DryRun.IsPresent

foreach ($path in $managedPaths) {
  foreach ($name in @($existingByPath[$path].Keys | Sort-Object)) {
    if ($name -notin $allowedByPath[$path] -and (Test-ManagedInfisicalName -Name $name)) {
      $deleteKey = "$path/$name"
      if ($deleted.Contains($deleteKey)) { continue }
      if ($DryRun) {
        $deleted.Add($deleteKey)
      } else {
        Remove-InfisicalSecret -SecretPath $path -Name $name -Headers $headers
        $deleted.Add($deleteKey)
      }
    }
  }
}

$expectedInstallationCount = 0
foreach ($path in $installationPaths) {
  $expectedInstallationCount += $expectedByPath[$path].Count
}

[ordered]@{
  dryRun = $DryRun.IsPresent
  runtimePath = $RuntimeSecretPath
  installationPath = $InstallationSecretPath
  installationPaths = @($installationPaths)
  monitoringPath = $MonitoringSecretPath
  objectStoragePath = $ObjectStorageSecretPath
  expectedRuntimeCount = $expectedByPath[$RuntimeSecretPath].Count
  expectedInstallationCount = $expectedInstallationCount
  expectedMonitoringCount = $expectedByPath[$MonitoringSecretPath].Count
  expectedObjectStorageCount = $expectedByPath[$ObjectStorageSecretPath].Count
  createdCount = $created.Count
  updatedCount = $updated.Count
  deletedCount = $deleted.Count
  created = @($created)
  deleted = @($deleted)
} | ConvertTo-Json -Depth 6

