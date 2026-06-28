param(
  [string]$NasHost = "siha-nas",
  [string]$Share = "SIHA",
  [string]$DriveLetter = "S",
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$driveName = $DriveLetter.TrimEnd(":")
$remotePath = "\\$NasHost\$Share"

Write-Host "Validando conectividade SMB com $NasHost:445..."
$tcpTest = Test-NetConnection -ComputerName $NasHost -Port 445 -InformationLevel Quiet
if (-not $tcpTest) {
  throw "Nao foi possivel conectar em $NasHost na porta TCP 445. Verifique DNS, rede, firewall e se o servico Samba esta ativo."
}

$existingMapping = Get-SmbMapping -LocalPath "${driveName}:" -ErrorAction SilentlyContinue
if ($existingMapping) {
  if ($existingMapping.RemotePath -ieq $remotePath) {
    Write-Host "Mapeamento ${driveName}: ja aponta para $remotePath."
    return
  }

  if (-not $Force) {
    throw "A unidade ${driveName}: ja esta mapeada para '$($existingMapping.RemotePath)'. Use -Force para remover e recriar."
  }

  Remove-SmbMapping -LocalPath "${driveName}:" -Force
}
else {
  $existingDrive = Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue
  if ($existingDrive) {
    throw "A unidade ${driveName}: ja existe e nao e um mapeamento SMB gerenciado por Get-SmbMapping. Escolha outra letra ou libere a unidade manualmente."
  }
}

Write-Host "Mapeando ${driveName}: para $remotePath..."
try {
  New-SmbMapping -LocalPath "${driveName}:" -RemotePath $remotePath -Persistent $true -ErrorAction Stop | Out-Null
} catch {
  Write-Host "Se o Windows solicitar credenciais, use o usuario Samba autorizado, por exemplo: siha_user."
  Write-Host "Para salvar credenciais sem senha em script, use o Gerenciador de Credenciais do Windows: cmdkey /add:$NasHost /user:siha_user /pass"
  throw
}

if (-not (Test-Path -LiteralPath "${driveName}:\")) {
  throw "O mapeamento ${driveName}: foi criado, mas o caminho nao respondeu no Explorer/PowerShell. Verifique credenciais e permissoes Samba."
}

Write-Host "Unidade ${driveName}: mapeada para $remotePath."
