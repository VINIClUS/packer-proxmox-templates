param(
  [string]$BaseUrl = "http://192.168.1.209:8080"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$body = @(
  [ordered]@{
    operationName = "Configuracoes"
    variables = [ordered]@{}
    query = "query Configuracoes { info { ativado linkInstalacaoConfigurado smtpConfigurado internetHabilitada } }"
  }
) | ConvertTo-Json -Depth 10 -Compress

try {
  $response = Invoke-WebRequest -UseBasicParsing -Method Post -Uri (($BaseUrl.TrimEnd("/")) + "/api/graphql") -ContentType "application/json" -Body $body
  Write-Host "graphql_http=$([int]$response.StatusCode)"
  Write-Host "graphql_contains_config=$($response.Content -match 'linkInstalacaoConfigurado')"
  Write-Host "graphql_contains_errors=$($response.Content -match 'errors')"
  $payload = $response.Content | ConvertFrom-Json
  $info = $payload[0].data.info
  if ($info) {
    Write-Host "ativado=$($info.ativado)"
    Write-Host "linkInstalacaoConfigurado=$($info.linkInstalacaoConfigurado)"
    Write-Host "smtpConfigurado=$($info.smtpConfigurado)"
    Write-Host "internetHabilitada=$($info.internetHabilitada)"
  }
} catch {
  Write-Host "graphql_error=$($_.Exception.Message)"
  exit 1
}
