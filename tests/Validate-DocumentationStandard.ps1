Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  Join-Path $root $RelativePath
}

function Assert-File {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  if (-not (Test-Path -LiteralPath (Get-RepoPath $RelativePath) -PathType Leaf)) {
    throw "Missing required documentation artifact: $RelativePath"
  }
}

function Assert-Content {
  param(
    [Parameter(Mandatory = $true)][string]$RelativePath,
    [Parameter(Mandatory = $true)][string[]]$Terms
  )

  $content = Get-Content -LiteralPath (Get-RepoPath $RelativePath) -Raw
  foreach ($term in $Terms) {
    if ($content -notmatch [regex]::Escape($term)) {
      throw "Missing required documentation term in ${RelativePath}: $term"
    }
  }
}

$requiredFiles = @(
  "AGENTS.md",
  ".agents/skills/documentar-operacao/SKILL.md",
  "docs/README.md",
  "docs/_templates/CHECKLIST_DOCUMENTACAO_OPERACIONAL.md",
  "docs/_templates/OPERACAO_ADMINISTRATIVA.md",
  "docs/_templates/PLANO_IMPLANTACAO.md",
  "docs/_templates/RELATORIO_VALIDACAO.md",
  "docs/_templates/VARIAVEIS_INFISICAL.md"
)

foreach ($file in $requiredFiles) {
  Assert-File $file
}

Assert-Content "AGENTS.md" @(
  "Operational Documentation Standard",
  ".agents/skills/documentar-operacao/SKILL.md",
  "docs/_templates/",
  "same commit",
  "Keep commits atomic"
)

Assert-Content ".agents/skills/documentar-operacao/SKILL.md" @(
  "name: documentar-operacao",
  "docs/README.md",
  "docs/_templates/CHECKLIST_DOCUMENTACAO_OPERACIONAL.md",
  "Nao coloque senhas",
  "rtk git diff --check"
)

Assert-Content "docs/README.md" @(
  "Padrao obrigatorio",
  "docs/_templates/",
  "..\sus-siha-bootstrap",
  "tests\Validate-DocumentationStandard.ps1",
  "Nunca registre valores reais"
)

Assert-Content "docs/_templates/CHECKLIST_DOCUMENTACAO_OPERACIONAL.md" @(
  "Nenhuma senha",
  'Comandos usam prefixo `rtk`',
  "Rollback preserva dados",
  "Mudancas nao relacionadas ficaram fora do commit"
)

Assert-Content "docs/_templates/OPERACAO_ADMINISTRATIVA.md" @(
  "Objetivo",
  "Escopo",
  "Pre-requisitos e seguranca",
  "Validacao",
  "Rollback"
)

Assert-Content "docs/_templates/PLANO_IMPLANTACAO.md" @(
  "Checklist pre-producao",
  "Dry-run",
  "Backup e restore obrigatorios",
  "Aceite final"
)

Assert-Content "docs/_templates/RELATORIO_VALIDACAO.md" @(
  "Evidencias",
  "Comandos executados",
  "Riscos residuais",
  "Nada sensivel foi registrado"
)

Assert-Content "docs/_templates/VARIAVEIS_INFISICAL.md" @(
  "Nunca registre valores reais",
  "valuePresent",
  'Arquivos `.example` rastreados'
)

$trackedDocumentation = @(
  "README.md",
  "docs/README.md",
  "AGENTS.md"
)

foreach ($file in $trackedDocumentation) {
  $content = Get-Content -LiteralPath (Get-RepoPath $file) -Raw
  if ($content -match "-----BEGIN .*PRIVATE KEY-----") {
    throw "Private key material found in documentation: $file"
  }
  if ($content -match '(?i)(password|senha|token)\s*=\s*["''][^"'']+["'']') {
    throw "Possible secret assignment found in documentation: $file"
  }
}

Write-Host "Documentation standard validation passed."
