Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")

$requiredArtifacts = @(
  "scripts/monitoring/Provision-MonitoringCore.ps1",
  "scripts/monitoring/Install-MonitoringTargetAgent.ps1",
  "scripts/monitoring/Configure-EsusPecApplicationExporters.ps1",
  "scripts/monitoring/templates/prometheus.yml",
  "scripts/monitoring/templates/loki.yml",
  "scripts/monitoring/templates/alloy-core.alloy",
  "scripts/monitoring/templates/alloy-linux-target.alloy",
  "scripts/monitoring/templates/grafana-datasources.yml",
  "scripts/monitoring/templates/postgres-exporter-9.6.sql",
  "scripts/monitoring/templates/jmx-exporter.yml",
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

$applicationExporterProvisioner =
  $artifactByPath["scripts/monitoring/Configure-EsusPecApplicationExporters.ps1"].Content

$activeApplicationExporterProvisioner = (
  $applicationExporterProvisioner -split "`r?`n" |
    Where-Object { $_ -notmatch '^\s*#' } |
    ForEach-Object { $_ -replace '\s+#.*$', '' }
) -join "`n"

$pinnedApplicationExporterPatterns = @{
  postgres_exporter_version = '(?im)^\s*\$postgresExporterVersion\s*=\s*["'']0\.19\.1["'']\s*$'
  postgres_exporter_checksum = '(?im)^\s*\$postgresExporterSha256\s*=\s*["'']229096c7988df6ca41fe5b4bf66865089971535e7f0d819c12c920ec64dd2bd0["'']\s*$'
  postgres_exporter_url = '(?im)^\s*\$postgresExporterUrl\s*=\s*["'']https://github\.com/prometheus-community/postgres_exporter/releases/download/v0\.19\.1/postgres_exporter-0\.19\.1\.linux-amd64\.tar\.gz["'']\s*$'
  jmx_exporter_version = '(?im)^\s*\$jmxExporterVersion\s*=\s*["'']1\.6\.0["'']\s*$'
  jmx_exporter_checksum = '(?im)^\s*\$jmxExporterSha256\s*=\s*["'']a95983fd96e865d2bcdf911cc500e7c82808c27ab9fd226bf96732b6c3d8c46e["'']\s*$'
  jmx_exporter_url = '(?im)^\s*\$jmxExporterUrl\s*=\s*["'']https://github\.com/prometheus/jmx_exporter/releases/download/v1\.6\.0/jmx_prometheus_javaagent-1\.6\.0\.jar["'']\s*$'
}

foreach ($pinnedArtifact in $pinnedApplicationExporterPatterns.GetEnumerator()) {
  if ($activeApplicationExporterProvisioner -notmatch $pinnedArtifact.Value) {
    throw "Missing pinned application exporter artifact relation: $($pinnedArtifact.Key)"
  }
}

$downloadIntegrityPatterns = @{
  postgres_exporter_download = '(?im)^\s*curl\b(?:[^\r\n]*\\\s*\r?\n\s*)*[^\r\n]*https://github\.com/prometheus-community/postgres_exporter/releases/download/v0\.19\.1/postgres_exporter-0\.19\.1\.linux-amd64\.tar\.gz(?:[^\r\n]*\\\s*\r?\n\s*)*[^\r\n]*-o\s+"\$download"\s*$'
  postgres_exporter_checksum = '(?im)^\s*(?:echo|printf)\b[^\r\n|]*229096c7988df6ca41fe5b4bf66865089971535e7f0d819c12c920ec64dd2bd0[^\r\n|]*"\$download"[^\r\n|]*(?:\r?\n\s*)?\|\s*sha256sum\s+-c\b'
  jmx_exporter_download = '(?im)^\s*curl\b(?:[^\r\n]*\\\s*\r?\n\s*)*[^\r\n]*https://github\.com/prometheus/jmx_exporter/releases/download/v1\.6\.0/jmx_prometheus_javaagent-1\.6\.0\.jar(?:[^\r\n]*\\\s*\r?\n\s*)*[^\r\n]*-o\s+"\$jmx_tmp"\s*$'
  jmx_exporter_checksum = '(?im)^\s*(?:echo|printf)\b[^\r\n|]*a95983fd96e865d2bcdf911cc500e7c82808c27ab9fd226bf96732b6c3d8c46e[^\r\n|]*"\$jmx_tmp"[^\r\n|]*(?:\r?\n\s*)?\|\s*sha256sum\s+-c\b'
}

foreach ($downloadIntegrity in $downloadIntegrityPatterns.GetEnumerator()) {
  if ($activeApplicationExporterProvisioner -notmatch $downloadIntegrity.Value) {
    throw "Missing bound application exporter download integrity check: $($downloadIntegrity.Key)"
  }
}

foreach ($term in @(
  "ESUS_PEC_POSTGRES_EXPORTER_PASSWORD",
  "/test/InstallationConfig",
  "prometheus_exporter",
  "127.0.0.1:5433",
  "DATA_SOURCE_PASS_FILE",
  "monitoring-jmx.conf",
  "JAVA_TOOL_OPTIONS"
)) {
  if ($activeApplicationExporterProvisioner -notmatch [regex]::Escape($term)) {
    throw "Missing application exporter provisioner term: $term"
  }
}

foreach ($requiredFunctionUse in @("wait_http_ready", "rollback_jmx")) {
  $escapedFunctionName = [regex]::Escape($requiredFunctionUse)
  $functionDeclarationPattern =
    "(?im)^\s*(?:function\s+$escapedFunctionName\b|$escapedFunctionName\s*\(\))"

  if ($activeApplicationExporterProvisioner -notmatch $functionDeclarationPattern) {
    throw "Application exporter provisioner must declare function: $requiredFunctionUse"
  }

  $nonDeclarationLines = (
    $activeApplicationExporterProvisioner -split "`r?`n" |
      Where-Object { $_ -notmatch $functionDeclarationPattern }
  ) -join "`n"

  $functionCallPattern =
    "(?im)^\s*(?![^\r\n]*=)(?![^\r\n]*\bfunction\b)(?![^\r\n]*\(\)\s*\{\s*$)(?:if\s+!?\s*|!\s*)?$escapedFunctionName(?:\s+[^\r\n]+)?\s*$"

  if ($nonDeclarationLines -notmatch $functionCallPattern) {
    throw "Application exporter provisioner must call function: $requiredFunctionUse"
  }
}

$forbiddenApplicationExporterPatterns = @{
  SUPERUSER = '(?i)(?<!NO)\bSUPERUSER\b'
  "ALTER SYSTEM" = '(?i)\bALTER\s+SYSTEM\b'
  "listen_addresses = '*'" = "(?i)\blisten_addresses\s*=\s*['""]\*['""]"
}

foreach ($forbiddenTerm in $forbiddenApplicationExporterPatterns.GetEnumerator()) {
  if ($activeApplicationExporterProvisioner -match $forbiddenTerm.Value) {
    throw "Application exporter provisioner contains forbidden term: $($forbiddenTerm.Key)"
  }
}

$postgresSql =
  $artifactByPath["scripts/monitoring/templates/postgres-exporter-9.6.sql"].Content

foreach ($term in @(
  "CREATE SCHEMA IF NOT EXISTS postgres_exporter",
  "SECURITY DEFINER",
  "get_pg_stat_activity",
  "get_pg_stat_replication",
  "GRANT SELECT ON postgres_exporter.pg_stat_activity",
  "GRANT SELECT ON postgres_exporter.pg_stat_replication"
)) {
  if ($postgresSql -notmatch [regex]::Escape($term)) {
    throw "Missing PostgreSQL 9.6 exporter SQL term: $term"
  }
}

if ($postgresSql -match '(?is)\bCREATE\s+EXTENSION\b.*?\bpg_stat_statements\b') {
  throw "PostgreSQL exporter bootstrap must not enable pg_stat_statements implicitly."
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
$ct133DashboardObject = $ct133Dashboard | ConvertFrom-Json
$ct133Expressions = @(
  foreach ($panel in $ct133DashboardObject.panels) {
    if ($panel.PSObject.Properties.Name -notcontains "targets") {
      continue
    }
    foreach ($target in $panel.targets) {
      if ($target.PSObject.Properties.Name -contains "expr") {
        [string]$target.expr
      }
    }
  }
)
$ct133NormalizedExpressions = @(
  $ct133Expressions | ForEach-Object { $_ -replace '\s+', '' }
)
$ct133NormalizedExpressionSet = $ct133NormalizedExpressions -join "`n"

foreach ($term in @(
  'instance="192.168.1.209:9187"',
  'instance="192.168.1.209:9404"'
)) {
  $normalizedTerm = $term -replace '\s+', ''
  if ($ct133NormalizedExpressionSet -notmatch [regex]::Escape($normalizedTerm)) {
    throw "Missing CT 133 application exporter dashboard term: $term"
  }
}

foreach ($metricPattern in @(
  '\bpg_up\b',
  '\bpg_stat_database',
  '\bjvm_memory',
  '\bjvm_gc',
  '\bjvm_threads'
)) {
  if ($ct133NormalizedExpressionSet -notmatch $metricPattern) {
    throw "Missing CT 133 application exporter dashboard metric pattern: $metricPattern"
  }
}

foreach ($obsoleteCt133Job in @("esus-pec-lxc-5437-node", "esus-pec-lxc-5437-nginx")) {
  if ($ct133NormalizedExpressionSet -match [regex]::Escape($obsoleteCt133Job)) {
    throw "CT 133 dashboard references obsolete Prometheus job label: $obsoleteCt133Job"
  }
}
foreach ($requiredCt133Selector in @(
  'host="esus-pec-lxc-5437"',
  'instance="192.168.1.209:9100"',
  'instance="192.168.1.209:9113"'
)) {
  $normalizedSelector = $requiredCt133Selector -replace '\s+', ''
  if ($ct133NormalizedExpressionSet -notmatch [regex]::Escape($normalizedSelector)) {
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
$activePrometheusTemplate = (
  $prometheusTemplate -split "`r?`n" |
    Where-Object { $_ -notmatch '^\s*#' }
) -join "`n"

$esusPecJobPattern =
  '(?ms)^\s*-\s*job_name:\s*["'']?esus-pec-lxc-5437["'']?\s*$.*?(?=^\s*-\s*job_name:|\z)'
$esusPecJobMatch = [regex]::Match($activePrometheusTemplate, $esusPecJobPattern)
if (-not $esusPecJobMatch.Success) {
  throw "Missing active Prometheus job block: esus-pec-lxc-5437"
}

$esusPecJobBlock = $esusPecJobMatch.Value
$targetsMatch = [regex]::Match(
  $esusPecJobBlock,
  '(?ms)^\s*(?:-\s*)?targets:\s*$.*?(?=^\s*[A-Za-z_][A-Za-z0-9_-]*:\s*|\z)'
)
if (-not $targetsMatch.Success) {
  throw "Prometheus job esus-pec-lxc-5437 is missing an active targets block."
}

$esusPecTargetsBlock = $targetsMatch.Value
foreach ($term in @(
  "ESUS_PEC_LXC_TARGET_METRICS_HOST:9187",
  "ESUS_PEC_LXC_TARGET_METRICS_HOST:9404"
)) {
  $activeTargetPattern = "(?m)^\s*-\s*$([regex]::Escape($term))\s*$"
  if ($esusPecTargetsBlock -notmatch $activeTargetPattern) {
    throw "Missing application exporter Prometheus target: $term"
  }
}

foreach ($term in @("monitoring-core", "esus-pec-lxc-5437", "localhost:9090", "133")) {
  if ($prometheusTemplate -notmatch [regex]::Escape($term)) {
    throw "Missing Prometheus template term: $term"
  }
}

Write-Host "Monitoring stack static validation passed."
