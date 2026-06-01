param(
  [string]$BaseUrl = $(if ($env:ESUS_PEC_BASE_URL) { $env:ESUS_PEC_BASE_URL } else { "http://192.168.1.209:8080" }),
  [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RequiredEnv {
  param([Parameter(Mandatory = $true)][string]$Name)

  $value = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "Missing required environment variable: $Name"
  }
  return $value.Trim()
}

function Normalize-Url {
  param([Parameter(Mandatory = $true)][string]$Value)

  if ($Value -notmatch '^https?://') {
    return "http://$Value"
  }
  return $Value
}

function Normalize-Cpf {
  param([Parameter(Mandatory = $true)][string]$Value)

  $digits = ($Value -replace '\D', '')
  if ($digits.Length -ne 11) {
    throw "ESUS_PEC_INSTALLER_CPF must contain 11 digits."
  }
  return $digits
}

function Assert-PasswordPolicy {
  param(
    [Parameter(Mandatory = $true)][string]$Password,
    [Parameter(Mandatory = $true)][string]$Cpf,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if ($Password.Length -lt 8 -or $Password.Length -gt 20) {
    throw "ESUS_PEC_INITIAL_PASSWORD must have 8 to 20 characters."
  }
  if ($Password -notmatch '[A-Za-z]' -or $Password -notmatch '\d') {
    throw "ESUS_PEC_INITIAL_PASSWORD must include at least one letter and one number."
  }
  if ($Password.Contains($Cpf)) {
    throw "ESUS_PEC_INITIAL_PASSWORD must not contain the CPF."
  }

  foreach ($part in ($Name -split '\s+' | Where-Object { $_.Length -ge 3 })) {
    if ($Password.IndexOf($part, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
      throw "ESUS_PEC_INITIAL_PASSWORD must not contain personal name fragments."
    }
  }
}

$installationName = Get-RequiredEnv "ESUS_PEC_INSTALLATION_NAME"
$installationUrl = Normalize-Url (Get-RequiredEnv "ESUS_PEC_INSTALLATION_URL")
$installationType = (Get-RequiredEnv "ESUS_PEC_INSTALLATION_TYPE").ToUpperInvariant()
$installerName = Get-RequiredEnv "ESUS_PEC_INSTALLER_NAME_CIVIL"
$installerCpf = Normalize-Cpf (Get-RequiredEnv "ESUS_PEC_INSTALLER_CPF")
$initialPassword = Get-RequiredEnv "ESUS_PEC_INITIAL_PASSWORD"

if ($installationType -notin @("PRONTUARIO", "CENTRALIZADORA")) {
  throw "ESUS_PEC_INSTALLATION_TYPE must be PRONTUARIO or CENTRALIZADORA."
}

Assert-PasswordPolicy -Password $initialPassword -Cpf $installerCpf -Name $installerName

$inputObject = [ordered]@{
  dadosInstalacao = [ordered]@{
    linkInstalacao = $installationUrl
    nomeInstalacao = $installationName
  }
  tipoInstalacao = $installationType
  novaSenha = $initialPassword
  profissional = [ordered]@{
    nomeCivil = $installerName
    cpf = $installerCpf
    endereco = $null
  }
}

$requestBody = @(
  [ordered]@{
    operationName = "Instalar"
    variables = [ordered]@{
      input = $inputObject
    }
    query = "mutation Instalar(`$input: InstalacaoInput!) {`n  instalar(input: `$input)`n}`n"
  }
)

$sanitizedInput = [ordered]@{}
foreach ($key in $inputObject.Keys) {
  $sanitizedInput[$key] = $inputObject[$key]
}
$sanitizedInput["novaSenha"] = "[REDACTED]"

if (-not $Apply) {
  Write-Host "Dry-run only. Re-run with -Apply to submit the first-run configuration."
  Write-Host "Target: $BaseUrl/api/graphql"
  Write-Host "Sanitized input:"
  $sanitizedInput | ConvertTo-Json -Depth 10
  return
}

$headers = @{
  "Content-Type" = "application/json"
  "ApolloGraphQL-Client-Version" = "5.4.37"
  "ApolloGraphQL-Client-Name" = "PEC Web"
}

$uri = ($BaseUrl.TrimEnd('/')) + "/api/graphql"
$json = $requestBody | ConvertTo-Json -Depth 20 -Compress
$response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $json
$errorProperty = $response.PSObject.Properties["errors"]

if ($errorProperty -and $errorProperty.Value) {
  $safeErrors = $response.errors | ConvertTo-Json -Depth 20
  throw "e-SUS PEC first-run configuration failed: $safeErrors"
}

Write-Host "e-SUS PEC first-run configuration submitted successfully."
