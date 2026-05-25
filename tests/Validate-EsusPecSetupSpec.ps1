Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$setupPath = Join-Path $root "Setup.md"
$sourcePath = Join-Path $root "appEsusPEC.md"
$releaseDocPath = Join-Path $root "docs/esus-pec/2026-05-25-pec-5.4.37.md"
$downloadScriptPath = Join-Path $root "shared/scripts/Get-EsusPecInstaller.ps1"

foreach ($path in @($setupPath, $sourcePath, $releaseDocPath, $downloadScriptPath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing required e-SUS PEC artifact: $path"
  }
}

$setup = Get-Content -LiteralPath $setupPath -Raw
$source = Get-Content -LiteralPath $sourcePath -Raw
$releaseDoc = Get-Content -LiteralPath $releaseDocPath -Raw
$downloadScript = Get-Content -LiteralPath $downloadScriptPath -Raw

$requiredFragments = @(
  "https://sisaps.saude.gov.br/sistemas/esusaps/blog/versao-5-4-37/",
  "https://arquivos.esusaps.ufsc.br/PEC/687651a247e537a3/5.4.37/eSUS-AB-PEC-5.4.37-Linux64.jar",
  "https://arquivos.esusaps.ufsc.br/PEC/687651a247e537a3/5.4.37/eSUS-AB-PEC-5.4.37-Win64.jar",
  "APP-REQ-011",
  "APP-REQ-012",
  "SHA-256",
  "read-only",
  "Get-EsusPecInstaller.ps1",
  "No installer was downloaded or executed"
)

$combined = "$setup`n$source`n$releaseDoc`n$downloadScript"
foreach ($fragment in $requiredFragments) {
  if ($combined -notmatch [regex]::Escape($fragment)) {
    throw "Missing required e-SUS PEC documentation fragment: $fragment"
  }
}

$approvalGatedPatterns = @(
  "systemctl restart",
  "systemctl stop",
  "nginx -s reload",
  "ufw allow",
  "iptables ",
  "pct reboot",
  "qm stop",
  "java -jar https://"
)

foreach ($pattern in $approvalGatedPatterns) {
  if ($releaseDoc -match [regex]::Escape($pattern)) {
    throw "Release documentation contains approval-gated command text: $pattern"
  }
}

Write-Host "e-SUS PEC setup specification artifacts are valid."
