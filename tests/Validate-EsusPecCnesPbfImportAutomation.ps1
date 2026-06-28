Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$paths = @(
  "scripts/esus-pec/Upload-EsusPecImportArtifactToMinio.ps1",
  "scripts/esus-pec/Import-EsusPecCnesAndBolsaFamilia.mjs",
  "docs/esus-pec/2026-06-21-cnes-pbf-import-automation.md",
  "docs/credentials/esus-pec-infisical-secrets.html",
  "config/esus-pec.infisical.env.example"
)

foreach ($relativePath in $paths) {
  $path = Join-Path $root $relativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing CNES/PBF import automation artifact: $relativePath"
  }
}

$combined = ($paths | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $root $_) -Raw
  }) -join "`n"

$requiredFragments = @(
  "POST /api/cnes/{municipioId}",
  "POST /api/bolsa-familia/importar",
  "ImportacoesCnes",
  "ImportacoesBolsaFamilia",
  "ESUS_PEC_CNES_IMPORT_OBJECT_KEY",
  "ESUS_PEC_CNES_IMPORT_LAST_STATUS",
  "ESUS_PEC_CNES_IMPORT_LAST_PROCESS_ID",
  "ESUS_PEC_BOLSA_FAMILIA_IMPORT_OBJECT_KEY",
  "ESUS_PEC_BOLSA_FAMILIA_IMPORT_LAST_STATUS",
  "ESUS_PEC_BOLSA_FAMILIA_IMPORT_LAST_VIGENCIA",
  "XmlParaESUS31_354130.zip",
  "pbf_354130_12026_0.zip",
  "imports/cnes/2026/06/XmlParaESUS31_354130.zip",
  "imports/bolsa-familia/2026/06/pbf_354130_12026_0.zip"
)

foreach ($fragment in $requiredFragments) {
  if ($combined -notmatch [regex]::Escape($fragment)) {
    throw "Missing CNES/PBF import automation fragment: $fragment"
  }
}

$forbiddenPatterns = @(
  'password_esus_presidenteepitacio\s*=\s*[^`\r\n]+',
  'user_esus_presidenteepitacio\s*=\s*[^`\r\n]+',
  'JSESSIONID=',
  'XSRF-TOKEN=',
  '-----BEGIN .*PRIVATE KEY-----',
  'ESUS_PEC_[A-Z0-9_]*PASSWORD=[^\r\n]+',
  'ESUS_PEC_[A-Z0-9_]*SECRET=[^\r\n]+'
)

foreach ($pattern in $forbiddenPatterns) {
  if ($combined -match $pattern) {
    throw "CNES/PBF import automation artifacts appear to contain a secret pattern: $pattern"
  }
}

Write-Host "e-SUS PEC CNES/PBF import automation artifacts are valid."
