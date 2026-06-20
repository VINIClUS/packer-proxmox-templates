param(
  [string]$EnvFile = ".env",
  [string]$DashboardDirectory = "scripts/monitoring/dashboards",
  [string]$FolderUid = "esus-pec-monitoring",
  [string]$FolderTitle = "e-SUS PEC Monitoring",
  [string]$DefaultGrafanaUrl = "http://192.168.1.190:3000"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-EnvFileValues {
  param([string]$Path)

  $values = @{}
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $values
  }

  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed.StartsWith("#") -or $trimmed -notmatch "=") {
      continue
    }

    $parts = $trimmed -split "=", 2
    $values[$parts[0].Trim()] = $parts[1].Trim().Trim('"').Trim("'")
  }

  return $values
}

function Get-ConfigValue {
  param(
    [hashtable]$Values,
    [string]$Name,
    [string]$Default = $null
  )

  $upperName = $Name.ToUpperInvariant()
  foreach ($candidate in @($Name, $upperName)) {
    $environmentValue = [Environment]::GetEnvironmentVariable($candidate)
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
      return $environmentValue.Trim()
    }
  }

  foreach ($candidate in @($Name, $upperName)) {
    if ($Values.ContainsKey($candidate) -and -not [string]::IsNullOrWhiteSpace([string]$Values[$candidate])) {
      return [string]$Values[$candidate]
    }
  }

  return $Default
}

function Invoke-GrafanaApi {
  param(
    [string]$Method,
    [string]$Path,
    [hashtable]$Headers,
    [object]$Body = $null,
    [string]$GrafanaUrl
  )

  $uri = $GrafanaUrl.TrimEnd("/") + $Path
  $parameters = @{
    Method = $Method
    Uri = $uri
    Headers = $Headers
    TimeoutSec = 30
  }

  if ($null -ne $Body) {
    $parameters["ContentType"] = "application/json"
    $parameters["Body"] = ($Body | ConvertTo-Json -Depth 100)
  }

  Invoke-RestMethod @parameters
}

function Test-GrafanaDashboardExists {
  param(
    [string]$DashboardUid,
    [hashtable]$Headers,
    [string]$GrafanaUrl
  )

  try {
    $null = Invoke-GrafanaApi -Method Get -Path "/api/dashboards/uid/$DashboardUid" -Headers $Headers -GrafanaUrl $GrafanaUrl
    return $true
  } catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 404) {
      return $false
    }
    throw
  }
}

function Ensure-GrafanaFolder {
  param(
    [string]$Uid,
    [string]$Title,
    [hashtable]$Headers,
    [string]$GrafanaUrl
  )

  try {
    $null = Invoke-GrafanaApi -Method Get -Path "/api/folders/$Uid" -Headers $Headers -GrafanaUrl $GrafanaUrl
    return "exists"
  } catch {
    if (-not $_.Exception.Response -or $_.Exception.Response.StatusCode.value__ -ne 404) {
      throw
    }
  }

  try {
    $null = Invoke-GrafanaApi -Method Post -Path "/api/folders" -Headers $Headers -GrafanaUrl $GrafanaUrl -Body @{
      uid = $Uid
      title = $Title
    }
    return "created"
  } catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 409) {
      return "exists"
    }
    throw
  }
}

$envValues = Get-EnvFileValues -Path $EnvFile
$grafanaUrl = Get-ConfigValue -Values $envValues -Name "grafana_url" -Default $DefaultGrafanaUrl
$grafanaCredential = Get-ConfigValue -Values $envValues -Name "grafana_token"

if ([string]::IsNullOrWhiteSpace($grafanaCredential)) {
  throw "grafana_token not found. Set grafana_token in .env or GRAFANA_TOKEN before publishing dashboards."
}

if (-not (Test-Path -LiteralPath $DashboardDirectory -PathType Container)) {
  throw "Dashboard directory not found: $DashboardDirectory"
}

$headers = @{
  Authorization = "Bearer $grafanaCredential"
  Accept = "application/json"
}

$health = Invoke-GrafanaApi -Method Get -Path "/api/health" -Headers $headers -GrafanaUrl $grafanaUrl
$folderState = Ensure-GrafanaFolder -Uid $FolderUid -Title $FolderTitle -Headers $headers -GrafanaUrl $grafanaUrl

$published = New-Object System.Collections.Generic.List[object]
foreach ($file in Get-ChildItem -LiteralPath $DashboardDirectory -Filter "*.json" | Sort-Object Name) {
  $dashboard = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
  if ($dashboard.PSObject.Properties.Name -contains "id") {
    $dashboard.id = $null
  } else {
    $dashboard | Add-Member -NotePropertyName "id" -NotePropertyValue $null
  }

  $existed = Test-GrafanaDashboardExists -DashboardUid $dashboard.uid -Headers $headers -GrafanaUrl $grafanaUrl
  $body = @{
    dashboard = $dashboard
    folderUid = $FolderUid
    overwrite = $true
    message = "Managed by scripts/monitoring/Publish-GrafanaDashboards.ps1"
  }

  $result = Invoke-GrafanaApi -Method Post -Path "/api/dashboards/db" -Headers $headers -GrafanaUrl $grafanaUrl -Body $body
  $published.Add([pscustomobject]@{
      uid = [string]$dashboard.uid
      title = [string]$dashboard.title
      action = if ($existed) { "updated" } else { "created" }
      url = [string]$result.url
    })
}

$report = @{
  grafanaUrl = $grafanaUrl
  database = [string]$health.database
  folderUid = $FolderUid
  folderState = $folderState
  dashboardCount = [int]$published.Count
  dashboards = @($published.ToArray())
}

$report | ConvertTo-Json -Depth 5
