param(
  [string]$ConfigFile = "config/Proxmox.pkrvars.hcl",
  [int]$Ctid = 133,
  [string]$InfisicalUrl = "http://192.168.1.226:8080",
  [string]$InfisicalWorkspaceId = "2c83cfe9-e794-4961-977d-23000ae14461",
  [string]$InfisicalProjectSlug = "esus-pec-z-px-c",
  [string]$InfisicalEnvironment = "dev",
  [string]$RuntimeSecretPath = "/test",
  [string]$InstallationSecretPath = "/test/InstallationConfig",
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-HclValue {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Text,
    [string]$Default = $null
  )

  $line = $Text -split "`n" | Where-Object {
    $_ -match ("^\s*" + [regex]::Escape($Name) + "\s*=")
  } | Select-Object -First 1

  if (-not $line) {
    return $Default
  }

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
  if ($env:infisical_secret_key) {
    return $env:infisical_secret_key
  }
  if ($env:INFISICAL_TOKEN) {
    return $env:INFISICAL_TOKEN
  }
  if (Test-Path -LiteralPath ".env") {
    $line = Get-Content -LiteralPath ".env" | Where-Object { $_ -match "^infisical_secret_key=" } | Select-Object -First 1
    if ($line) {
      return (($line -split "=", 2)[1]).Trim()
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
  $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -TimeoutSec 30
  $result = @{}
  foreach ($secret in @($response.secrets)) {
    $result[[string]$secret.secretKey] = [string]$secret.secretValue
  }
  return $result
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

function Move-InfisicalSecret {
  param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [Parameter(Mandatory = $true)][string]$Name,
    [AllowEmptyString()][Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][hashtable]$Headers
  )

  # Create the target first so a denied target path cannot delete the source secret.
  $null = Set-InfisicalSecret -SecretPath $TargetPath -Name $Name -Value $Value -Headers $Headers -Exists $false
  Remove-InfisicalSecret -SecretPath $SourcePath -Name $Name -Headers $Headers
}

function Add-Expected {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Target,
    [Parameter(Mandatory = $true)][string]$Name,
    [AllowEmptyString()][Parameter(Mandatory = $true)][string]$Value
  )

  $Target[$Name] = $Value
}

function Get-ExistingSecretValue {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][hashtable]$Primary,
    [Parameter(Mandatory = $true)][hashtable]$Fallback,
    [AllowEmptyString()][string]$Default = ""
  )

  if ($Primary.ContainsKey($Name)) {
    return [string]$Primary[$Name]
  }
  if ($Fallback.ContainsKey($Name)) {
    return [string]$Fallback[$Name]
  }
  return $Default
}

function Get-ExampleEnvValues {
  param([Parameter(Mandatory = $true)][string]$Path)

  $values = [ordered]@{}
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $values
  }

  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed.StartsWith("#") -or $trimmed -notmatch "=") {
      continue
    }

    $parts = $trimmed -split "=", 2
    $name = $parts[0].Trim()
    if ($name -notmatch "^[A-Za-z_][A-Za-z0-9_]*$") {
      continue
    }

    $values[$name] = $parts[1].Trim().Trim('"').Trim("'")
  }

  return $values
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

  if ($Name -match "^ESUS_PEC_DB_" -or
      $Name -match "^ESUS_PEC_OBJECT_STORAGE_" -or
      $Name -match "^ESUS_PEC_WALG_" -or
      $Name -in $runtimeExactNames) {
    return $RuntimeSecretPath
  }

  if ($Name -match "^ESUS_PEC_" -or $Name -in @("grafana_url", "grafana_token")) {
    return $InstallationSecretPath
  }

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
  if (-not $dbMatch.Success) {
    throw "Could not parse PEC database JDBC URL."
  }

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

$configText = Get-Content -LiteralPath $ConfigFile -Raw
$sshHost = Get-HclValue -Name "proxmox_ssh_host" -Text $configText
$sshPort = Get-HclValue -Name "proxmox_ssh_port" -Text $configText -Default "22"
$sshUser = Get-HclValue -Name "proxmox_ssh_user" -Text $configText -Default "root"
$sshKey = Get-HclValue -Name "proxmox_ssh_private_key_file" -Text $configText
$sshTarget = "$sshUser@$sshHost"

$token = Get-InfisicalToken
$headers = @{ Authorization = "Bearer $token" }

$sameSecretPath = $RuntimeSecretPath -eq $InstallationSecretPath
$existingRuntime = Get-InfisicalSecrets -SecretPath $RuntimeSecretPath -Headers $headers
$existingInstall = if ($sameSecretPath) { $existingRuntime } else { Get-InfisicalSecrets -SecretPath $InstallationSecretPath -Headers $headers }

if (-not $DryRun) {
  Test-InfisicalSecretPathWritable -SecretPath $RuntimeSecretPath -Headers $headers
  if (-not $sameSecretPath) {
    Test-InfisicalSecretPathWritable -SecretPath $InstallationSecretPath -Headers $headers
  }
}

$expectedRuntime = @{}
foreach ($entry in (Get-RemotePecDatabaseValues -Target $sshTarget -Port $sshPort -KeyFile $sshKey -ContainerId $Ctid).GetEnumerator()) {
  Add-Expected -Target $expectedRuntime -Name $entry.Key -Value $entry.Value
}

Add-Expected -Target $expectedRuntime -Name "ESUS_PEC_ADMIN_USERNAME" -Value $existingInstall["ESUS_PEC_INSTALLER_CPF"]
Add-Expected -Target $expectedRuntime -Name "ESUS_PEC_ADMIN_PASSWORD" -Value $existingInstall["ESUS_PEC_INITIAL_PASSWORD"]
Add-Expected -Target $expectedRuntime -Name "ESUS_PEC_SMTP_HOST" -Value ""
Add-Expected -Target $expectedRuntime -Name "ESUS_PEC_SMTP_PORT" -Value "587"
Add-Expected -Target $expectedRuntime -Name "ESUS_PEC_SMTP_USERNAME" -Value ""
Add-Expected -Target $expectedRuntime -Name "ESUS_PEC_SMTP_PASSWORD" -Value ""
Add-Expected -Target $expectedRuntime -Name "ESUS_PEC_BACKUP_ENCRYPTION_PASSWORD" -Value ""
Add-Expected -Target $expectedRuntime -Name "ESUS_PEC_RESTORE_ARCHIVE_PASSWORD" -Value ""

$expectedInstall = @{}
$installValueAliases = @{
  ESUS_PEC_BASE_URL = "ESUS_PEC_EXTERNAL_BASE_URL"
  ESUS_PEC_INITIAL_PASSWORD = "ESUS_PEC_ADMIN_PASSWORD"
  ESUS_PEC_INSTALLATION_URL = "ESUS_PEC_EXTERNAL_BASE_URL"
  ESUS_PEC_INSTALLER_CPF = "ESUS_PEC_ADMIN_USERNAME"
}

foreach ($name in @(
    "ESUS_PEC_BASE_URL",
    "ESUS_PEC_INITIAL_PASSWORD",
    "ESUS_PEC_INSTALLATION_NAME",
    "ESUS_PEC_INSTALLATION_TYPE",
    "ESUS_PEC_INSTALLATION_URL",
    "ESUS_PEC_INSTALLER_CPF",
    "ESUS_PEC_INSTALLER_NAME_CIVIL",
    "ESUS_PEC_TLS_CERTIFICATE_KIND",
    "ESUS_PEC_TLS_CERTIFICATE_NOT_AFTER",
    "ESUS_PEC_TLS_CERTIFICATE_PEM",
    "ESUS_PEC_TLS_CERTIFICATE_SAN",
    "ESUS_PEC_TLS_CERTIFICATE_SHA256",
    "ESUS_PEC_TLS_HTTPS_URL",
    "ESUS_PEC_TLS_PRIVATE_KEY_PEM",
    "ESUS_PEC_TLS_TERMINATION"
  )) {
  $value = Get-ExistingSecretValue -Name $name -Primary $existingInstall -Fallback $existingRuntime
  if (($value -eq "") -and $installValueAliases.ContainsKey($name)) {
    $value = Get-ExistingSecretValue -Name $installValueAliases[$name] -Primary $existingInstall -Fallback $existingRuntime
  }
  Add-Expected -Target $expectedInstall -Name $name -Value $value
}

$installDefaults = [ordered]@{
  ESUS_PEC_INSTALLER_SOURCE_URL = "https://arquivos.esusaps.ufsc.br/PEC/687651a247e537a3/5.4.37/eSUS-AB-PEC-5.4.37-Linux64.jar"
  ESUS_PEC_INSTALLER_SHA256 = "9975a55184a6dd1f66d8a837bbc533376e0400069485e8acb45100c23a535bfb"
  ESUS_PEC_LXC_TEST_URL = "http://192.168.1.209:8080/"
  ESUS_PEC_LXC_TEST_HTTPS_URL = "https://192.168.1.209/"
  ESUS_PEC_LXC_CREDENTIALS_FILE = "/opt/e-SUS/webserver/config/credenciais.txt"
  ESUS_PEC_EXTERNAL_BASE_URL = ""
  ESUS_PEC_INTERNET_ENABLED = "true"
  ESUS_PEC_CADSUS_ENABLED = "true"
  ESUS_PEC_CADSUS_DISABLE_INTERVAL = ""
  ESUS_PEC_HORUS_ENABLED = "false"
  ESUS_PEC_HORUS_DISABLE_INTERVAL = "INDETERMINADO"
  ESUS_PEC_VIDEOCHAMADAS_ENABLED = "false"
  ESUS_PEC_AGENDA_ONLINE_ENABLED = "false"
  ESUS_PEC_ASSINATURA_DIGITAL_ENABLED = "false"
  ESUS_PEC_ASSINATURA_DIGITAL_LOGIN = ""
  ESUS_PEC_ASSINATURA_DIGITAL_PASSWORD = ""
  ESUS_PEC_PASSWORD_RESET_PERIOD_MONTHS = "6"
  ESUS_PEC_MAX_INACTIVITY_MINUTES = "60"
  ESUS_PEC_MAX_LOGIN_ATTEMPTS = "5"
  ESUS_PEC_FORCE_PASSWORD_RESET_ON_NEXT_LOGIN = "false"
  ESUS_PEC_SMTP_ENABLED = "false"
  ESUS_PEC_SMTP_FROM_EMAIL = ""
  ESUS_PEC_SMTP_USE_LOGIN_AS_SENDER = "false"
  ESUS_PEC_MUNICIPALITY_ID = ""
  ESUS_PEC_RESPONSIBLE_PROFESSIONAL_ID = ""
  ESUS_PEC_MUNICIPAL_RESPONSIBLE_ENABLED = "false"
  ESUS_PEC_FILE_ATTACHMENTS_ENABLED = "false"
  ESUS_PEC_FILE_ATTACHMENTS_DIRECTORY = ""
  ESUS_PEC_CONCURRENT_REQUESTS_USE_DEFAULT = "true"
  ESUS_PEC_CONCURRENT_REQUESTS = "16"
  ESUS_PEC_CITIZEN_SEARCH_BY_PROPERTIES_ENABLED = "false"
  ESUS_PEC_CDS_PROPERTY_FAMILY_REGISTRATION_ENABLED = "false"
  ESUS_PEC_BASE_UNIFICATION_ENABLED = "false"
  ESUS_PEC_BASE_UNIFICATION_MODE = ""
}

foreach ($entry in $installDefaults.GetEnumerator()) {
  $value = Get-ExistingSecretValue -Name $entry.Key -Primary $existingInstall -Fallback $existingRuntime -Default $entry.Value
  Add-Expected -Target $expectedInstall -Name $entry.Key -Value $value
}

$exampleValues = Get-ExampleEnvValues -Path "config/esus-pec.infisical.env.example"
foreach ($entry in $exampleValues.GetEnumerator()) {
  $desiredPath = Get-DesiredInfisicalPath -Name $entry.Key
  if ($null -eq $desiredPath) {
    continue
  }

  if ($desiredPath -eq $RuntimeSecretPath) {
    if (-not $expectedRuntime.ContainsKey($entry.Key)) {
      $value = Get-ExistingSecretValue -Name $entry.Key -Primary $existingRuntime -Fallback $existingInstall -Default ([string]$entry.Value)
      Add-Expected -Target $expectedRuntime -Name $entry.Key -Value $value
    }
    continue
  }

  if (-not $expectedInstall.ContainsKey($entry.Key)) {
    $value = Get-ExistingSecretValue -Name $entry.Key -Primary $existingInstall -Fallback $existingRuntime -Default ([string]$entry.Value)
    Add-Expected -Target $expectedInstall -Name $entry.Key -Value $value
  }
}

$runtimeAllowed = [string[]]$expectedRuntime.Keys
$installAllowed = [string[]]$expectedInstall.Keys
$combinedAllowed = @($runtimeAllowed + $installAllowed | Sort-Object -Unique)
$preserveSourceValueOnMove = @(
  "ESUS_PEC_SMTP_HOST",
  "ESUS_PEC_SMTP_PORT",
  "ESUS_PEC_SMTP_USERNAME",
  "ESUS_PEC_SMTP_PASSWORD",
  "ESUS_PEC_BACKUP_ENCRYPTION_PASSWORD",
  "ESUS_PEC_RESTORE_ARCHIVE_PASSWORD"
)

if ($sameSecretPath) {
  $runtimeExtra = @()
  $installExtra = @($existingInstall.Keys | Where-Object { $_ -notin $combinedAllowed -and (Test-ManagedInfisicalName -Name $_) } | Sort-Object)
} else {
  $runtimeExtra = @($existingRuntime.Keys | Where-Object { $_ -notin $runtimeAllowed -and (Test-ManagedInfisicalName -Name $_) } | Sort-Object)
  $installExtra = @($existingInstall.Keys | Where-Object { $_ -notin $installAllowed -and (Test-ManagedInfisicalName -Name $_) } | Sort-Object)
}

$created = New-Object System.Collections.Generic.List[string]
$updated = New-Object System.Collections.Generic.List[string]
$deleted = New-Object System.Collections.Generic.List[string]

foreach ($entry in $expectedRuntime.GetEnumerator()) {
  if ($DryRun) {
    if (-not $existingRuntime.ContainsKey($entry.Key)) { $created.Add("$RuntimeSecretPath/$($entry.Key)") }
    if ($existingInstall.ContainsKey($entry.Key)) { $deleted.Add("$InstallationSecretPath/$($entry.Key)") }
  } else {
    if (-not $existingRuntime.ContainsKey($entry.Key) -and $existingInstall.ContainsKey($entry.Key)) {
      $moveValue = [string]$entry.Value
      if ($entry.Key -in $preserveSourceValueOnMove) {
        $moveValue = [string]$existingInstall[$entry.Key]
      }
      Move-InfisicalSecret -SourcePath $InstallationSecretPath -TargetPath $RuntimeSecretPath -Name $entry.Key -Value $moveValue -Headers $headers
      $created.Add("$RuntimeSecretPath/$($entry.Key)")
      $deleted.Add("$InstallationSecretPath/$($entry.Key)")
    } else {
      $action = Set-InfisicalSecret -SecretPath $RuntimeSecretPath -Name $entry.Key -Value ([string]$entry.Value) -Headers $headers -Exists $existingRuntime.ContainsKey($entry.Key)
      if ($action -eq "created") { $created.Add("$RuntimeSecretPath/$($entry.Key)") } else { $updated.Add("$RuntimeSecretPath/$($entry.Key)") }
    }
  }
}

foreach ($entry in $expectedInstall.GetEnumerator()) {
  if ($sameSecretPath -and $expectedRuntime.ContainsKey($entry.Key)) {
    continue
  }
  if ($DryRun) {
    if (-not $existingInstall.ContainsKey($entry.Key)) { $created.Add("$InstallationSecretPath/$($entry.Key)") }
  } else {
    $exists = if ($sameSecretPath) { ($existingInstall.ContainsKey($entry.Key) -or $expectedRuntime.ContainsKey($entry.Key)) } else { $existingInstall.ContainsKey($entry.Key) }
    $action = Set-InfisicalSecret -SecretPath $InstallationSecretPath -Name $entry.Key -Value ([string]$entry.Value) -Headers $headers -Exists $exists
    if ($action -eq "created") { $created.Add("$InstallationSecretPath/$($entry.Key)") } else { $updated.Add("$InstallationSecretPath/$($entry.Key)") }
  }
}

foreach ($name in $runtimeExtra) {
  $deleteKey = "$RuntimeSecretPath/$name"
  if ($deleted.Contains($deleteKey)) {
    continue
  }
  if ($DryRun) {
    $deleted.Add($deleteKey)
  } else {
    Remove-InfisicalSecret -SecretPath $RuntimeSecretPath -Name $name -Headers $headers
    $deleted.Add($deleteKey)
  }
}

foreach ($name in $installExtra) {
  $deleteKey = "$InstallationSecretPath/$name"
  if ($deleted.Contains($deleteKey)) {
    continue
  }
  if ($DryRun) {
    $deleted.Add($deleteKey)
  } else {
    Remove-InfisicalSecret -SecretPath $InstallationSecretPath -Name $name -Headers $headers
    $deleted.Add($deleteKey)
  }
}

[ordered]@{
  dryRun = $DryRun.IsPresent
  runtimePath = $RuntimeSecretPath
  installationPath = $InstallationSecretPath
  expectedRuntimeCount = $expectedRuntime.Count
  expectedInstallationCount = $expectedInstall.Count
  createdCount = $created.Count
  updatedCount = $updated.Count
  deletedCount = $deleted.Count
  created = @($created)
  deleted = @($deleted)
} | ConvertTo-Json -Depth 5
