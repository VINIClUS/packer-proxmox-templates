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
  "scripts/monitoring/Publish-GrafanaDashboards.ps1",
  "scripts/monitoring/Sync-GrafanaInfisicalEnv.ps1",
  "scripts/monitoring/dashboards/esus-monitoring-overview.json",
  "scripts/monitoring/dashboards/monitoring-core-ct190.json",
  "scripts/monitoring/dashboards/esus-pec-ct133.json",
  "scripts/monitoring/dashboards/logs-diagnostics.json",
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

$artifactByPath = @{}
foreach ($artifact in $artifacts) {
  $artifactByPath[$artifact.Path] = $artifact
}

function Assert-ArtifactContainsTerm {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RelativePath,

    [Parameter(Mandatory = $true)]
    [string]$Term,

    [Parameter(Mandatory = $true)]
    [string]$RequirementName
  )

  if ($artifactByPath[$RelativePath].Content -notmatch [regex]::Escape($Term)) {
    throw "Missing $RequirementName term in ${RelativePath}: $Term"
  }
}

function Get-RelativeArtifactPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FullPath
  )

  $rootPath = (Resolve-Path -LiteralPath $root).Path.TrimEnd("\", "/")
  $resolvedPath = (Resolve-Path -LiteralPath $FullPath).Path
  $relativePath = $resolvedPath.Substring($rootPath.Length).TrimStart("\", "/")
  $relativePath -replace "\\", "/"
}

$narrativeContent = (
  $artifacts |
    Where-Object { $_.Path -match '^docs/' } |
    Select-Object -ExpandProperty Content
) -join "`n"

$requiredNarrativeTerms = @(
  "CTID 190",
  "monitoring-core",
  "Prometheus",
  "Grafana",
  "Loki",
  "Alloy",
  "133",
  "esus-pec-lxc-5437"
)

foreach ($term in $requiredNarrativeTerms) {
  if ($narrativeContent -notmatch [regex]::Escape($term)) {
    throw "Missing monitoring stack narrative term: $term"
  }
}

Assert-ArtifactContainsTerm "scripts/monitoring/Provision-MonitoringCore.ps1" "CTID 190" "monitoring core script"
Assert-ArtifactContainsTerm "scripts/monitoring/Provision-MonitoringCore.ps1" "monitoring-core" "monitoring core script"
Assert-ArtifactContainsTerm "scripts/monitoring/Install-MonitoringTargetAgent.ps1" "133" "monitoring target script"
Assert-ArtifactContainsTerm "scripts/monitoring/Install-MonitoringTargetAgent.ps1" "esus-pec-lxc-5437" "monitoring target script"
Assert-ArtifactContainsTerm "scripts/monitoring/templates/prometheus.yml" "Prometheus" "Prometheus template"
Assert-ArtifactContainsTerm "scripts/monitoring/templates/loki.yml" "Loki" "Loki template"
Assert-ArtifactContainsTerm "scripts/monitoring/templates/alloy-core.alloy" "Alloy" "Alloy core template"
Assert-ArtifactContainsTerm "scripts/monitoring/templates/alloy-linux-target.alloy" "Alloy" "Alloy target template"
Assert-ArtifactContainsTerm "scripts/monitoring/templates/grafana-datasources.yml" "Grafana" "Grafana datasource template"
Assert-ArtifactContainsTerm "scripts/monitoring/templates/grafana-datasources.yml" "uid: prometheus" "Grafana Prometheus datasource UID"
Assert-ArtifactContainsTerm "scripts/monitoring/templates/grafana-datasources.yml" "uid: loki" "Grafana Loki datasource UID"
Assert-ArtifactContainsTerm "scripts/monitoring/Publish-GrafanaDashboards.ps1" "grafana_url" "Grafana publish env"
Assert-ArtifactContainsTerm "scripts/monitoring/Publish-GrafanaDashboards.ps1" "grafana_token" "Grafana publish env"
Assert-ArtifactContainsTerm "scripts/monitoring/Sync-GrafanaInfisicalEnv.ps1" "/test/InstallationConfig" "Grafana Infisical path"
Assert-ArtifactContainsTerm "scripts/monitoring/Sync-GrafanaInfisicalEnv.ps1" "grafana_url" "Grafana Infisical env"
Assert-ArtifactContainsTerm "scripts/monitoring/Sync-GrafanaInfisicalEnv.ps1" "grafana_token" "Grafana Infisical env"
Assert-ArtifactContainsTerm "scripts/monitoring/Sync-GrafanaInfisicalEnv.ps1" "api/v1/folders" "Grafana Infisical folder creation"

$dashboardArtifacts = $artifacts | Where-Object { $_.Path -match '^scripts/monitoring/dashboards/.*\.json$' }
if ($dashboardArtifacts.Count -ne 4) {
  throw "Expected exactly 4 managed Grafana dashboards; found $($dashboardArtifacts.Count)."
}

foreach ($dashboardArtifact in $dashboardArtifacts) {
  try {
    $dashboard = $dashboardArtifact.Content | ConvertFrom-Json
  } catch {
    throw "Grafana dashboard is not valid JSON: $($dashboardArtifact.Path)"
  }

  foreach ($property in @("uid", "title", "panels", "templating", "time")) {
    if (-not ($dashboard.PSObject.Properties.Name -contains $property)) {
      throw "Grafana dashboard '$($dashboardArtifact.Path)' is missing property: $property"
    }
  }
  if (@($dashboard.panels).Count -lt 8) {
    throw "Grafana dashboard '$($dashboard.title)' must be dense enough for operations; expected at least 8 panels."
  }
  if ($dashboardArtifact.Content -notmatch '"uid"\s*:\s*"prometheus"' -or $dashboardArtifact.Content -notmatch '"uid"\s*:\s*"loki"') {
    throw "Grafana dashboard '$($dashboard.title)' must reference both Prometheus and Loki datasources by UID."
  }
}

$ct133Dashboard = $artifactByPath["scripts/monitoring/dashboards/esus-pec-ct133.json"].Content
foreach ($obsoleteCt133Job in @("esus-pec-lxc-5437-node", "esus-pec-lxc-5437-nginx")) {
  if ($ct133Dashboard -match [regex]::Escape($obsoleteCt133Job)) {
    throw "CT 133 dashboard references obsolete Prometheus job label: $obsoleteCt133Job"
  }
}
foreach ($requiredCt133Selector in @(
  'host=\"esus-pec-lxc-5437\"',
  'instance=\"192.168.1.209:9100\"',
  'instance=\"192.168.1.209:9113\"'
)) {
  if ($ct133Dashboard -notmatch [regex]::Escape($requiredCt133Selector)) {
    throw "CT 133 dashboard must use observed Prometheus selector: $requiredCt133Selector"
  }
}

$coreProvisioner = $artifactByPath["scripts/monitoring/Provision-MonitoringCore.ps1"].Content
foreach ($obsoletePrometheusConsoleReference in @("--web.console.templates", "--web.console.libraries", "/usr/local/share/prometheus/consoles", "/usr/local/share/prometheus/console_libraries")) {
  if ($coreProvisioner -match [regex]::Escape($obsoletePrometheusConsoleReference)) {
    throw "Prometheus 3.x console assets are not bundled; remove obsolete provisioner reference: $obsoletePrometheusConsoleReference"
  }
}

foreach ($requiredDownloadHardeningTerm in @("download_url()", "curl -4", "--retry", "--retry-all-errors", "--connect-timeout")) {
  if ($coreProvisioner -notmatch [regex]::Escape($requiredDownloadHardeningTerm)) {
    throw "Monitoring core provisioner downloads must include transient network hardening: $requiredDownloadHardeningTerm"
  }
}

foreach ($requiredSshWrapperTerm in @('$nativeErrorActionPreference', '$ErrorActionPreference = "Continue"', '$LASTEXITCODE')) {
  if ($coreProvisioner -notmatch [regex]::Escape($requiredSshWrapperTerm)) {
    throw "Monitoring core provisioner SSH wrapper must safely capture native stderr and check exit code: $requiredSshWrapperTerm"
  }
}

foreach ($requiredReadinessTerm in @("wait_http_ready()", "for attempt in", "sleep 2")) {
  if ($coreProvisioner -notmatch [regex]::Escape($requiredReadinessTerm)) {
    throw "Monitoring core readiness checks must wait for services instead of using a single curl attempt: $requiredReadinessTerm"
  }
}

$alloyCoreTemplate = $artifactByPath["scripts/monitoring/templates/alloy-core.alloy"].Content
$alloyTargetTemplate = $artifactByPath["scripts/monitoring/templates/alloy-linux-target.alloy"].Content
foreach ($requiredAlloySyntaxTerm in @(
  'job  = "monitoring-core-journal",',
  'host = "monitoring-core",',
  'job  = "linux-target-journal",',
  'host = "ESUS_PEC_TARGET_NAME",',
  '__path__ = "/var/log/nginx/*.log",',
  '__path__ = "/opt/e-SUS/**/*.log",'
)) {
  if (($alloyCoreTemplate + "`n" + $alloyTargetTemplate) -notmatch [regex]::Escape($requiredAlloySyntaxTerm)) {
    throw "Alloy River object fields must use comma separators: $requiredAlloySyntaxTerm"
  }
}

$nonDocumentationArtifacts = $artifacts | Where-Object { $_.Path -notmatch '^docs/' }
foreach ($artifact in $nonDocumentationArtifacts) {
  if ($artifact.Content -match '(?im)\bpromtail\b') {
    throw "Promtail agent configuration is not allowed in monitoring artifact: $($artifact.Path)"
  }
}

$secretScanFiles = @()
foreach ($directory in @("scripts/monitoring", "docs/monitoring")) {
  $directoryPath = Get-ArtifactPath $directory
  if (Test-Path -LiteralPath $directoryPath -PathType Container) {
    $secretScanFiles += Get-ChildItem -LiteralPath $directoryPath -Recurse -File | Select-Object -ExpandProperty FullName
  }
}

foreach ($file in @(
  "docs/superpowers/specs/2026-06-14-esus-pec-centralized-monitoring-design.md",
  "tests/Validate-MonitoringStack.ps1"
)) {
  $filePath = Get-ArtifactPath $file
  if (Test-Path -LiteralPath $filePath -PathType Leaf) {
    $secretScanFiles += (Resolve-Path -LiteralPath $filePath).Path
  }
}

$secretScanArtifacts = $secretScanFiles |
  Sort-Object -Unique |
  ForEach-Object {
    [pscustomobject]@{
      Path = Get-RelativeArtifactPath $_
      Content = Get-Content -LiteralPath $_ -Raw
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
    Pattern = '(?i)\b(password|passwd|token|secret|api[_-]?key)\b\s*[:=]\s*["'']?(?!\s*(<|\$\{|\$env:|\$script:|\$global:|\$local:|\$[A-Za-z_][A-Za-z0-9_]*|%[A-Za-z_][A-Za-z0-9_]*%|REDACTED|redacted|CHANGE_ME|changeme|placeholder|example|your-|YOUR_|__))[A-Za-z0-9+/_=.-]{12,}["'']?'
  }
)

foreach ($artifact in $secretScanArtifacts) {
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
