Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")

$requiredArtifacts = @(
  "scripts/siha-nas/Provision-SihaNas.ps1",
  "scripts/siha-nas/provision.sh",
  "scripts/siha-nas/smb.conf.template",
  "scripts/siha-nas/gerar-indice-siha.sh",
  "scripts/siha-nas/arquivar-antigos-siha.sh",
  "scripts/siha-nas/Sync-SihaNasInfisicalEnv.ps1",
  "scripts/siha-nas/siha-arquivar-antigos.service",
  "scripts/siha-nas/siha-arquivar-antigos.timer",
  "scripts/windows/mapear-siha-nas.ps1",
  "docs/siha-nas/README.md",
  "docs/siha-nas/CONVENCAO_DE_NOMES.md",
  "docs/siha-nas/BACKUP_E_RESTAURACAO.md",
  "docs/siha-nas/RETENCAO_E_ARQUIVAMENTO.md",
  "docs/siha-nas/OPERACAO_WINDOWS_SIHA.md",
  "docs/siha-nas/CHECKLIST_TESTES.md",
  "docs/siha-nas/TROUBLESHOOTING.md",
  "docs/siha-nas/ROLLBACK.md"
)

function Get-ArtifactPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  Join-Path $root $RelativePath
}

foreach ($artifact in $requiredArtifacts) {
  if (-not (Test-Path -LiteralPath (Get-ArtifactPath $artifact) -PathType Leaf)) {
    throw "Missing SIHA NAS artifact: $artifact"
  }
}

$contentByPath = @{}
foreach ($artifact in $requiredArtifacts) {
  $contentByPath[$artifact] = Get-Content -LiteralPath (Get-ArtifactPath $artifact) -Raw
}

$combined = ($contentByPath.Values -join "`n")

foreach ($required in @(
  "siha-nas",
  "Debian LXC unprivileged",
  "\\siha-nas\SIHA",
  "/dados/siha",
  "siha_faturamento",
  "siha_user",
  "AAAA-MM-DD_SISTEMA_COMPETENCIA_TIPO_ORIGEM-OU-DESTINO_DESCRICAO_STATUS.ext",
  "99_MANIFESTOS_HASHES",
  "98_RELATORIOS_DE_AUDITORIA",
  "/siha-nas",
  "SIHA_NAS_SAMBA_PASSWORD",
  "pg_exporter_last_scrape_error"
)) {
  if ($required -eq "pg_exporter_last_scrape_error") {
    continue
  }
  if ($combined -notmatch [regex]::Escape($required)) {
    throw "Missing required SIHA NAS term: $required"
  }
}

foreach ($folder in @(
  "00_LEIA-ME",
  "01_REMESSAS_MS",
  "02_RETORNOS_MS",
  "03_BACKUPS_SISTEMAS",
  "04_INSTALADORES_E_UTILITARIOS",
  "05_DOCUMENTACAO_OPERACIONAL",
  "90_ARQUIVO_FECHADO",
  "91_ARQUIVO_COMPACTADO",
  "98_RELATORIOS_DE_AUDITORIA",
  "99_MANIFESTOS_HASHES"
)) {
  if ($contentByPath["scripts/siha-nas/provision.sh"] -notmatch [regex]::Escape($folder)) {
    throw "provision.sh does not create/document required folder: $folder"
  }
}

$smb = $contentByPath["scripts/siha-nas/smb.conf.template"]
foreach ($required in @(
  "map to guest = Never",
  "restrict anonymous = 2",
  "usershare allow guests = no",
  "server min protocol = SMB2_10",
  "valid users = @siha_faturamento",
  "force group = siha_faturamento",
  "create mask = 0660",
  "directory mask = 2770",
  "vfs objects = recycle",
  "recycle:repository = .lixeira/%U",
  "[SIHA]",
  "[SIHA_BACKUPS]",
  "[SIHA_ARQUIVO]",
  "read only = yes"
)) {
  if ($smb -notmatch [regex]::Escape($required)) {
    throw "Missing Samba security/config term: $required"
  }
}

$forbiddenPatterns = @{
  "world-writable 777" = '(?<![0-9])777(?![0-9])'
  "guest ok enabled" = '(?im)^\s*guest\s+ok\s*=\s*yes\s*$'
  "public enabled" = '(?im)^\s*public\s*=\s*yes\s*$'
  "SMB1 minimum" = '(?im)^\s*server\s+min\s+protocol\s*=\s*(NT1|LANMAN)'
  "hardcoded password literal" = '(?im)^\s*(\$?(password|senha)|SIHA_SAMBA_PASSWORD)\s*=\s*["''][^"'']+["'']'
  "private key" = '-----BEGIN .*PRIVATE KEY-----'
}

foreach ($item in $forbiddenPatterns.GetEnumerator()) {
  if ($combined -match $item.Value) {
    throw "Forbidden SIHA NAS pattern found: $($item.Key)"
  }
}

$indexScript = $contentByPath["scripts/siha-nas/gerar-indice-siha.sh"]
foreach ($required in @(
  "--dry-run",
  "--ano",
  "--base",
  "--output",
  "sha256sum",
  "/var/log/siha-nas",
  'indice_${YEAR}.csv',
  "caminho_relativo,nome_arquivo,tamanho,data_modificacao,ano,competencia_detectada,categoria,hash_sha256,observacao,arquivado_sim_nao,arquivo_compactado_destino"
)) {
  if ($indexScript -notmatch [regex]::Escape($required)) {
    throw "Missing index script behavior: $required"
  }
}

$archiveScript = $contentByPath["scripts/siha-nas/arquivar-antigos-siha.sh"]
foreach ($required in @(
  "--dry-run",
  "--older-than-days",
  "--remove-originals-after-verify",
  "--report-only",
  "OLDER_THAN_DAYS=730",
  "ARCHIVE_FORMAT",
  "zip",
  "tar.zst",
  "unzip -t",
  "sha256sum",
  "91_ARQUIVO_COMPACTADO",
  "98_RELATORIOS_DE_AUDITORIA",
  "99_MANIFESTOS_HASHES",
  "gerar-indice-siha.sh"
)) {
  if ($archiveScript -notmatch [regex]::Escape($required)) {
    throw "Missing archive script behavior: $required"
  }
}

foreach ($excluded in @(
  "00_LEIA-ME/*",
  "05_DOCUMENTACAO_OPERACIONAL/*",
  "98_RELATORIOS_DE_AUDITORIA/*",
  "99_MANIFESTOS_HASHES/*",
  "91_ARQUIVO_COMPACTADO/*",
  "*/.lixeira/*"
)) {
  if ($archiveScript -notmatch [regex]::Escape($excluded)) {
    throw "Archive script missing exclusion: $excluded"
  }
}

$provision = $contentByPath["scripts/siha-nas/Provision-SihaNas.ps1"]
foreach ($required in @(
  '[Parameter(Mandatory = $true)][int]$TargetCtid',
  "--unprivileged 1",
  "hostname mismatch",
  "is not unprivileged",
  '[switch]$DryRun',
  "pct push",
  "SIHA_SAMBA_PASSWORD_FILE",
  "Protect-LocalTemporarySecretFile",
  "not a command-line argument",
  "TargetName must be a DNS-safe hostname",
  "AllowedCidr must be 'none' or an IPv4 CIDR"
)) {
  if ($provision -notmatch [regex]::Escape($required)) {
    throw "Missing Proxmox provisioner safety behavior: $required"
  }
}

if ($provision -match 'SIHA_SAMBA_PASSWORD=\$\(ConvertTo-ShellSingleQuoted') {
  throw "Provisioner must not pass Samba passwords through command-line environment assignments."
}

$syncInfisical = $contentByPath["scripts/siha-nas/Sync-SihaNasInfisicalEnv.ps1"]
foreach ($required in @(
  '[string]$InfisicalSettingPrefix = "TEMPLATE_INFISICAL"',
  '[switch]$RemoveOnly',
  'TEMPLATES_INFISICAL',
  'Get-InfisicalSettingNames',
  'Remove-InfisicalSecret',
  'secretPathExists',
  '"/siha-nas"'
)) {
  if ($syncInfisical -notmatch [regex]::Escape($required)) {
    throw "Missing SIHA NAS Infisical sync behavior: $required"
  }
}

$windows = $contentByPath["scripts/windows/mapear-siha-nas.ps1"]
foreach ($required in @(
  "Test-NetConnection",
  "Port 445",
  "New-SmbMapping",
  '-Persistent $true',
  'cmdkey /add:$NasHost',
  "Get-PSDrive",
  "ja existe e nao e um mapeamento SMB",
  "S"
)) {
  if ($windows -notmatch [regex]::Escape($required)) {
    throw "Missing Windows mapping behavior: $required"
  }
}

foreach ($scriptPath in @(
  "scripts/siha-nas/Provision-SihaNas.ps1",
  "scripts/siha-nas/Sync-SihaNasInfisicalEnv.ps1",
  "scripts/windows/mapear-siha-nas.ps1"
)) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile(
    (Get-ArtifactPath $scriptPath),
    [ref]$tokens,
    [ref]$errors
  ) | Out-Null
  if ($errors.Count -gt 0) {
    throw "PowerShell parser errors in ${scriptPath}: $($errors[0].Message)"
  }
}

if (Get-Command bash -ErrorAction SilentlyContinue) {
  foreach ($scriptPath in @(
    "scripts/siha-nas/provision.sh",
    "scripts/siha-nas/gerar-indice-siha.sh",
    "scripts/siha-nas/arquivar-antigos-siha.sh"
  )) {
    & bash -n $scriptPath
    if ($LASTEXITCODE -ne 0) {
      throw "bash -n failed for $scriptPath"
    }
  }
}

foreach ($bashPath in @(
  "scripts/siha-nas/provision.sh",
  "scripts/siha-nas/gerar-indice-siha.sh",
  "scripts/siha-nas/arquivar-antigos-siha.sh"
)) {
  $bashContent = $contentByPath[$bashPath]
  foreach ($required in @("set -Eeuo pipefail", "trap ", "flock")) {
    if ($bashContent -notmatch [regex]::Escape($required)) {
      throw "Bash hardening missing in ${bashPath}: $required"
    }
  }
}

foreach ($required in @(
  'case "$value" in',
  '=*|+*|-*|@*|$''\t''*)',
  'value="''$value"',
  'find "$BASE" -type f',
  '-print0'
)) {
  if ($indexScript -notmatch [regex]::Escape($required)) {
    throw "Index script missing CSV/path robustness behavior: $required"
  }
}

foreach ($required in @(
  'printf ''%s\0%s\0%s\0%s\0''',
  'is_stable_file',
  'Arquivo compactado ja existe; recusando remover originais',
  '[dry-run] Nenhum relatorio, compactado, hash ou arquivo de log sera gravado.',
  'csv_escape',
  'zip -q -r "$archive_path" "${files[@]}"',
  'tar --zstd -cf "$archive_path" "${files[@]}"'
)) {
  if ($archiveScript -notmatch [regex]::Escape($required)) {
    throw "Archive script missing robust archival behavior: $required"
  }
}

if ($archiveScript -match 'zip\s+-q\s+-r\s+"\$archive_path"\s+-@') {
  throw "Archive script must not use line-based zip -@ lists; filenames can contain spaces and special characters."
}

foreach ($required in @(
  "arquivos com espaco",
  "acentuacao",
  "CSV injection",
  "=formula.csv"
)) {
  if ($combined -notmatch [regex]::Escape($required)) {
    throw "Missing SIHA NAS special filename/CSV injection guidance: $required"
  }
}

foreach ($term in @("ransomware", "backup", "restaur", "hash", "bind mount", "uid_map")) {
  if ($combined -notmatch $term) {
    throw "SIHA NAS documentation missing operational term: $term"
  }
}

Write-Host "SIHA NAS static validation passed."
