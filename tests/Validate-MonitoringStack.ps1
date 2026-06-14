Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")

$requiredArtifacts = @(
  "scripts/monitoring/Provision-MonitoringCore.ps1",
  "scripts/monitoring/Install-MonitoringTargetAgent.ps1",
  "scripts/monitoring/templates/prometheus.yml",
  "scripts/monitoring/templates/loki.yml",
  "scripts/monitoring/templates/alloy-core.alloy",
  "scripts/monitoring/templates/alloy-linux-target.alloy",
  "scripts/monitoring/templates/grafana-datasources.yml",
  "docs/monitoring/2026-06-14-centralized-monitoring.md",
  "docs/superpowers/specs/2026-06-14-esus-pec-centralized-monitoring-design.md"
)

function Get-ArtifactPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RelativePath
  )

  Join-Path $root $RelativePath
}

foreach ($artifact in $requiredArtifacts) {
  if (-not (Test-Path -LiteralPath (Get-ArtifactPath $artifact) -PathType Leaf)) {
    throw "Missing monitoring artifact: $artifact"
  }
}

$artifacts = foreach ($artifact in $requiredArtifacts) {
  [pscustomobject]@{
    Path = $artifact
    Content = Get-Content -LiteralPath (Get-ArtifactPath $artifact) -Raw
  }
}

$combined = ($artifacts.Content) -join "`n"
$requiredTerms = @(
  "CTID 190",
  "monitoring-core",
  "Prometheus",
  "Grafana",
  "Loki",
  "Alloy",
  "133",
  "esus-pec-lxc-5437"
)

foreach ($term in $requiredTerms) {
  if ($combined -notmatch [regex]::Escape($term)) {
    throw "Missing monitoring stack term: $term"
  }
}

$nonDocumentationArtifacts = $artifacts | Where-Object { $_.Path -notmatch '^docs/' }
foreach ($artifact in $nonDocumentationArtifacts) {
  if ($artifact.Content -match '(?im)\bpromtail\b') {
    throw "Promtail agent configuration is not allowed in monitoring artifact: $($artifact.Path)"
  }
}

$secretPatterns = @(
  @{
    Name = "private key"
    Pattern = '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  },
  @{
    Name = "session token"
    Pattern = '(?i)\b(JSESSIONID|XSRF-TOKEN)\s*[:=]\s*[A-Za-z0-9+/_=-]{16,}'
  },
  @{
    Name = "authorization token"
    Pattern = '(?i)\bAuthorization\s*[:=]\s*(Bearer|Basic)\s+[A-Za-z0-9+/_=-]{16,}'
  },
  @{
    Name = "secret assignment"
    Pattern = '(?i)\b(password|passwd|token|secret|api[_-]?key)\b\s*[:=]\s*["'']?(?!\s*(<|\$\{|REDACTED|redacted|CHANGE_ME|changeme|placeholder|example|your-|YOUR_|__))[^\s#"'''']{12,}'
  }
)

foreach ($artifact in $artifacts) {
  foreach ($secretPattern in $secretPatterns) {
    if ($artifact.Content -match $secretPattern.Pattern) {
      throw "Monitoring artifact appears to contain an obvious committed secret ($($secretPattern.Name)): $($artifact.Path)"
    }
  }
}

$prometheusTemplate = Get-Content -LiteralPath (Get-ArtifactPath "scripts/monitoring/templates/prometheus.yml") -Raw
foreach ($term in @("monitoring-core", "esus-pec-lxc-5437", "localhost:9090", "133")) {
  if ($prometheusTemplate -notmatch [regex]::Escape($term)) {
    throw "Missing Prometheus template term: $term"
  }
}

Write-Host "Monitoring stack static validation passed."
