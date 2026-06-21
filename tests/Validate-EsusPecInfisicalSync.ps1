Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$paths = @(
  "scripts/esus-pec/Sync-EsusPecInfisicalVariables.ps1",
  "scripts/esus-pec/Analyze-EsusPecInfisicalVariables.ps1",
  "scripts/esus-pec/Ensure-EsusPecInfisicalFolders.ps1",
  "docs/esus-pec/2026-06-05-infisical-variable-reconciliation.md",
  "docs/credentials/esus-pec-infisical-secrets.html",
  "config/esus-pec.infisical.env.example"
)

foreach ($relativePath in $paths) {
  $path = Join-Path $root $relativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing e-SUS PEC Infisical sync artifact: $relativePath"
  }
}

$scriptPath = Join-Path $root "scripts/esus-pec/Sync-EsusPecInfisicalVariables.ps1"
$scriptErrors = $null
$null = [System.Management.Automation.PSParser]::Tokenize(
  (Get-Content -LiteralPath $scriptPath -Raw),
  [ref]$scriptErrors
)
$analyzerPath = Join-Path $root "scripts/esus-pec/Analyze-EsusPecInfisicalVariables.ps1"
$analyzerErrors = $null
$null = [System.Management.Automation.PSParser]::Tokenize(
  (Get-Content -LiteralPath $analyzerPath -Raw),
  [ref]$analyzerErrors
)
$folderPath = Join-Path $root "scripts/esus-pec/Ensure-EsusPecInfisicalFolders.ps1"
$folderErrors = $null
$null = [System.Management.Automation.PSParser]::Tokenize(
  (Get-Content -LiteralPath $folderPath -Raw),
  [ref]$folderErrors
)
if ($scriptErrors.Count -gt 0 -or $analyzerErrors.Count -gt 0 -or $folderErrors.Count -gt 0) {
  throw "Infisical scripts have parse errors: sync=$($scriptErrors -join '; '); analyzer=$($analyzerErrors -join '; '); folders=$($folderErrors -join '; ')"
}

$combined = ($paths | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $root $_) -Raw
  }) -join "`n"

$requiredFragments = @(
  "Sync-EsusPecInfisicalVariables.ps1",
  "Analyze-EsusPecInfisicalVariables.ps1",
  "Ensure-EsusPecInfisicalFolders.ps1",
  "/test/InstallationConfig",
  "/test/InstallationConfig/FirstRun",
  "/test/InstallationConfig/ImportacaoCNES",
  "/test/InstallationConfig/ImportacaoBolsaFamilia",
  "/test/InstallationConfig/TransmissaoAPI",
  "/test/Monitoring",
  "/test/ObjectStorage",
  "ESUS_PEC_DB_HOST",
  "ESUS_PEC_DB_PASSWORD",
  "ESUS_PEC_DB_READONLY_USER",
  "ESUS_PEC_DB_READONLY_PASSWORD",
  "ESUS_PEC_ADMIN_USERNAME",
  "ESUS_PEC_SMTP_ENABLED",
  "ESUS_PEC_SMTP_HOST",
  "ESUS_PEC_SMTP_USERNAME",
  "ESUS_PEC_SMTP_PASSWORD",
  "ESUS_PEC_HORUS_DISABLE_INTERVAL",
  "ESUS_PEC_LXC_TEST_HTTPS_URL",
  "ESUS_PEC_OBJECT_STORAGE_API_URL",
  "ESUS_PEC_WALG_S3_PREFIX",
  "ESUS_PEC_GOVBR_OAUTH_CLIENT_SECRET",
  "ESUS_PEC_CNES_IMPORT_OBJECT_KEY",
  "ESUS_PEC_BOLSA_FAMILIA_IMPORT_OBJECT_KEY",
  "ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_PERSON_TYPE",
  "ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_RESPONSIBLE_NAME",
  "ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_CPF_CNPJ",
  "ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_EMAIL",
  "ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_NAME",
  "ESUS_PEC_TRANSMISSAO_API_CREDENTIAL_ACTIVE_ONLY",
  "grafana_token",
  "Get-DesiredInfisicalPath",
  "Test-ManagedInfisicalName",
  "expectedRuntimeCount",
  "expectedInstallationCount",
  "expectedMonitoringCount",
  "expectedObjectStorageCount",
  "deletedCount",
  "values were not printed",
  "Runtime values live under <code>/test</code>",
  "Object storage values live under <code>/test/ObjectStorage</code>",
  "Monitoring values live under <code>/test/Monitoring</code>",
  "currentTestSecretCount=15",
  "currentInstallationConfigSecretCount=104",
  "currentMonitoringSecretCount=3",
  "currentObjectStorageSecretCount=38",
  "expectedInstallationCount=110",
  "expectedDuplicateNames=0",
  "expectedMisplacedTestKeys=0",
  "plannedSubpathMigrationCreatedCount=110",
  "plannedSubpathMigrationDeletedCount=104",
  "folderEnsureMissingCount=0",
  "pendingSecretMigrationHttp403=/test/InstallationConfig/FirstRun",
  "postTokenUpdateVisibleTestSecretCount=0",
  "postTokenUpdateVisibleInstallationSecretCount=0",
  "syncGuard=Refusing to sync because /test is readable but has zero visible secrets",
  "AllowBootstrapEmptySources",
  "INFISICAL_URL",
  "INFISICAL_WORKSPACE_ID",
  "INFISICAL_PROJECT_SLUG",
  "INFISICAL_ENVIRONMENT",
  "postSyncDryRunCreatedCount=0",
  "postSyncDryRunDeletedCount=0"
)

foreach ($fragment in $requiredFragments) {
  if ($combined -notmatch [regex]::Escape($fragment)) {
    throw "Missing Infisical sync documentation fragment: $fragment"
  }
}

$forbiddenPatterns = @(
  '-----BEGIN CERTIFICATE-----',
  '-----BEGIN .*PRIVATE KEY-----',
  'ESUS_PEC_.*PASSWORD=[^\r\n]+',
  'JSESSIONID=',
  'XSRF-TOKEN='
)

foreach ($pattern in $forbiddenPatterns) {
  if ($combined -match $pattern) {
    throw "Infisical sync artifacts appear to contain a secret or token pattern: $pattern"
  }
}

Write-Host "e-SUS PEC Infisical sync artifacts are valid."

