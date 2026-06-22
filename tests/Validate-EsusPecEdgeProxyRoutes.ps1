Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")

$requiredArtifacts = @(
  "scripts/esus-pec/Configure-EdgeProxyRoutes.ps1",
  "scripts/esus-pec/Sync-EsusPecInfisicalVariables.ps1",
  "scripts/esus-pec/Ensure-EsusPecInfisicalFolders.ps1",
  "config/esus-pec.infisical.env.example",
  ".env.example",
  "docs/esus-pec/2026-06-22-edge-proxy-domain-routes.md",
  "docs/credentials/esus-pec-infisical-secrets.html",
  "docs/credentials/esus-pec-object-storage-credentials.html",
  "docs/monitoring/2026-06-14-centralized-monitoring.md"
)

function Get-ArtifactPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $root $RelativePath
}

foreach ($artifact in $requiredArtifacts) {
  if (-not (Test-Path -LiteralPath (Get-ArtifactPath $artifact) -PathType Leaf)) {
    throw "Missing edge proxy route artifact: $artifact"
  }
}

$scriptPaths = @(
  "scripts/esus-pec/Configure-EdgeProxyRoutes.ps1",
  "scripts/esus-pec/Sync-EsusPecInfisicalVariables.ps1",
  "scripts/esus-pec/Ensure-EsusPecInfisicalFolders.ps1"
)

foreach ($scriptPath in $scriptPaths) {
  $errors = $null
  $null = [System.Management.Automation.PSParser]::Tokenize(
    (Get-Content -LiteralPath (Get-ArtifactPath $scriptPath) -Raw),
    [ref]$errors
  )
  if ($errors.Count -gt 0) {
    throw "PowerShell parse errors in ${scriptPath}: $($errors -join '; ')"
  }
}

$combined = ($requiredArtifacts | ForEach-Object {
    Get-Content -LiteralPath (Get-ArtifactPath $_) -Raw
  }) -join "`n"

$requiredFragments = @(
  "Configure-EdgeProxyRoutes.ps1",
  "/test/EdgeProxy",
  "EDGE_PROXY_LXC_CTID=110",
  "EDGE_PROXY_LXC_IP=192.168.1.139",
  "EDGE_PROXY_LXC_NAME=nginx",
  "ESUS_PEC_PUBLIC_DOMAIN=esus.vinisantana.com",
  "ESUS_PEC_PUBLIC_BASE_URL=https://esus.vinisantana.com",
  "ESUS_PEC_PRODUCTION_DOMAIN=esus.presidenteepitacio.sp.gov.br",
  "ESUS_PEC_PRODUCTION_UPSTREAM_URL=http://192.168.1.253:8080",
  "EDGE_PROXY_ESUS_DEV_DOMAIN=esus.vinisantana.com",
  "EDGE_PROXY_ESUS_DEV_UPSTREAM_URL=http://192.168.1.209:8080",
  "EDGE_PROXY_S3_DOMAIN=s3.vinisantana.com",
  "EDGE_PROXY_S3_UPSTREAM_URL=https://192.168.1.210:9000",
  "EDGE_PROXY_MINIO_DOMAIN=minio.vinisantana.com",
  "EDGE_PROXY_MINIO_UPSTREAM_URL=https://192.168.1.210:9001",
  "EDGE_PROXY_INFISICAL_DOMAIN=infisical.vinisantana.com",
  "EDGE_PROXY_INFISICAL_UPSTREAM_URL=http://192.168.1.226:8080",
  "EDGE_PROXY_PROXMOX_DOMAIN=proxmox.vinisantana.com",
  "EDGE_PROXY_PROXMOX_UPSTREAM_URL=https://192.168.1.149:8006",
  "EDGE_PROXY_GRAFANA_DOMAIN=grafana.vinisantana.com",
  "EDGE_PROXY_GRAFANA_UPSTREAM_URL=http://192.168.1.190:3000",
  "EDGE_PROXY_PROMETHEUS_DOMAIN=prometheus.vinisantana.com",
  "EDGE_PROXY_PROMETHEUS_UPSTREAM_URL=http://192.168.1.190:9090",
  "EDGE_PROXY_PROMETHEUS_BASIC_AUTH_HTPASSWD",
  "CLOUDFLARE_ZONE_ID_VINISANTANA",
  "CLOUDFLARE_ZONE_NAME_VINISANTANA=vinisantana.com",
  "CLOUDFLARE_ACCOUNT_ID",
  "CLOUDFLARE_API_TOKEN",
  "CLOUDFLARE_TOKEN",
  "ESUS_PEC_OBJECT_STORAGE_PUBLIC_API_URL=https://s3.vinisantana.com",
  "ESUS_PEC_OBJECT_STORAGE_PUBLIC_CONSOLE_URL=https://minio.vinisantana.com",
  "ESUS_PEC_WALG_AWS_ENDPOINT=https://192.168.1.210:9000",
  "grafana_url=https://grafana.vinisantana.com",
  "prometheus_url=https://prometheus.vinisantana.com",
  "INFISICAL_PUBLIC_URL=https://infisical.vinisantana.com",
  "PROXMOX_PUBLIC_URL=https://proxmox.vinisantana.com",
  "Cloudflare handles TLS for vinisantana.com",
  "Let's Encrypt remains scoped to esus.presidenteepitacio.sp.gov.br",
  "WAL-G remains on the internal MinIO endpoint",
  "nginx -t",
  'ROUTE_`${id}_STATUS',
  "prometheus.vinisantana.com"
)

foreach ($fragment in $requiredFragments) {
  if ($combined -notmatch [regex]::Escape($fragment)) {
    throw "Missing edge proxy route fragment: $fragment"
  }
}

$syncContent = Get-Content -LiteralPath (Get-ArtifactPath "scripts/esus-pec/Sync-EsusPecInfisicalVariables.ps1") -Raw
foreach ($routingTerm in @(
  '$EdgeProxySecretPath',
  'if ($Name -match "^EDGE_PROXY_"',
  'if ($Name -match "^CLOUDFLARE_"',
  'prometheus_url',
  'INFISICAL_PUBLIC_URL',
  'PROXMOX_PUBLIC_URL'
)) {
  if ($syncContent -notmatch [regex]::Escape($routingTerm)) {
    throw "Infisical sync is missing edge route term: $routingTerm"
  }
}

$edgeProxyScriptContent = Get-Content -LiteralPath (Get-ArtifactPath "scripts/esus-pec/Configure-EdgeProxyRoutes.ps1") -Raw
foreach ($scriptTerm in @(
  'Resolve-CloudflareToken',
  'Resolve-CloudflareZoneId',
  'Test-InfisicalSecretPathWritable'
)) {
  if ($edgeProxyScriptContent -notmatch [regex]::Escape($scriptTerm)) {
    throw "Edge proxy script is missing implementation term: $scriptTerm"
  }
}

$forbiddenPatterns = @(
  '-----BEGIN CERTIFICATE-----',
  '-----BEGIN .*PRIVATE KEY-----',
  'CLOUDFLARE_API_TOKEN=[^\r\n]+',
  'CLOUDFLARE_TOKEN=[^\r\n]+',
  'EDGE_PROXY_PROMETHEUS_BASIC_AUTH_HTPASSWD=[^\r\n]+',
  's3\.vinicius\.com'
)

foreach ($pattern in $forbiddenPatterns) {
  if ($combined -match $pattern) {
    throw "Edge proxy artifacts contain forbidden content: $pattern"
  }
}

Write-Host "e-SUS PEC edge proxy route artifacts are valid."
