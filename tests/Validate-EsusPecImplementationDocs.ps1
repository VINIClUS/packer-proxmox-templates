Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$docs = @(
  "docs/esus-pec/2026-05-25-readonly-implementation-evidence.md",
  "docs/esus-pec/2026-05-25-action-classification.md",
  "docs/esus-pec/2026-05-25-risk-rollback-and-next-steps.md",
  "docs/setup-readonly/2026-05-25-implementation-plan.md"
)

foreach ($relativePath in $docs) {
  $path = Join-Path $root $relativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing implementation documentation: $relativePath"
  }
}

$combined = ($docs | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $root $_) -Raw
  }) -join "`n"

$requiredFragments = @(
  'pve-manager/9.1.1/42db4a6cf33dac83',
  'VM `101`: `ESUS-TESTE`, stopped',
  'CT `120`: `infisical`, running, protected',
  'nginx -t',
  'pve-01.cpd.internal',
  'No staged `eSUS-AB-PEC-*.jar`',
  'Starting VM `101`',
  'explicit approval',
  'Read-Only Actions',
  'Approval-Gated Changes',
  'Rollback Design',
  'Pending Approvals'
)

foreach ($fragment in $requiredFragments) {
  if ($combined -notmatch [regex]::Escape($fragment)) {
    throw "Missing required implementation documentation fragment: $fragment"
  }
}

Write-Host "e-SUS PEC implementation documentation is valid."
