#!/usr/bin/env bash
set -Eeuo pipefail

BASE="/dados/siha"
GROUP_NAME="siha_faturamento"
SAMBA_USER="siha_user"
ALLOWED_CIDR="none"
ENABLE_TIMER=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/siha-nas"

trap 'echo "Erro em provision.sh na linha $LINENO. Consulte $LOG_DIR/provision-*.log quando disponivel." >&2' ERR

usage() {
  cat <<'USAGE'
Uso: provision.sh [opcoes]

Opcoes:
  --base /dados/siha
  --group siha_faturamento
  --samba-user siha_user
  --allowed-cidr CIDR|none
  --disable-timer

Se SIHA_SAMBA_PASSWORD estiver definido, o usuario Samba inicial sera criado
ou atualizado sem imprimir a senha. Caso contrario, crie a senha manualmente
com: smbpasswd -a siha_user
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    --group) GROUP_NAME="$2"; shift 2 ;;
    --samba-user) SAMBA_USER="$2"; shift 2 ;;
    --allowed-cidr) ALLOWED_CIDR="$2"; shift 2 ;;
    --disable-timer) ENABLE_TIMER=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Argumento desconhecido: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Execute como root dentro do LXC siha-nas." >&2
  exit 1
fi

if [[ -f /proc/1/environ ]] && tr '\0' '\n' </proc/1/environ | grep -q '^container=lxc$'; then
  :
else
  echo "Aviso: nao foi possivel confirmar container=lxc em /proc/1/environ." >&2
fi

if [[ -f /proc/self/uid_map ]] && awk 'NR == 1 { exit !($1 == 0 && $2 != 0) }' /proc/self/uid_map; then
  :
else
  echo "Este provisionamento exige LXC unprivileged. uid_map atual:" >&2
  cat /proc/self/uid_map >&2 || true
  exit 10
fi

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/provision-$(date +%Y%m%dT%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
{ exec 9>/run/siha-nas-provision.lock; } 2>/dev/null ||
  exec 9>"${TMPDIR:-/tmp}/siha-nas-provision.lock"
flock -n 9 || { echo "Outro provisionamento siha-nas esta em execucao." >&2; exit 75; }

export DEBIAN_FRONTEND=noninteractive
command -v apt-get >/dev/null 2>&1 || { echo "apt-get nao encontrado; este script espera Debian." >&2; exit 127; }
apt-get update
apt-get install -y --no-install-recommends \
  samba smbclient ca-certificates zip unzip zstd coreutils findutils gawk acl

if ! getent group "$GROUP_NAME" >/dev/null 2>&1; then
  groupadd --system "$GROUP_NAME"
fi

if ! id -u "$SAMBA_USER" >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin --gid "$GROUP_NAME" "$SAMBA_USER"
else
  usermod -a -G "$GROUP_NAME" "$SAMBA_USER"
fi

install -d -m 2770 -o root -g "$GROUP_NAME" "$BASE"
install -d -m 2770 -o root -g "$GROUP_NAME" \
  "$BASE/00_LEIA-ME" \
  "$BASE/01_REMESSAS_MS" \
  "$BASE/02_RETORNOS_MS" \
  "$BASE/03_BACKUPS_SISTEMAS" \
  "$BASE/04_INSTALADORES_E_UTILITARIOS" \
  "$BASE/05_DOCUMENTACAO_OPERACIONAL" \
  "$BASE/90_ARQUIVO_FECHADO" \
  "$BASE/91_ARQUIVO_COMPACTADO" \
  "$BASE/98_RELATORIOS_DE_AUDITORIA" \
  "$BASE/99_MANIFESTOS_HASHES"

write_readme() {
  local dir="$1"
  local title="$2"
  local save="$3"
  local pattern="$4"
  local examples="$5"
  local avoid="$6"
  local retention="$7"
  local path="$BASE/$dir/.README.txt"
  cat > "$path" <<EOF
$title

O que salvar aqui:
$save

Padrao recomendado de nome:
$pattern

Exemplos:
$examples

O que NAO salvar aqui:
$avoid

Responsavel sugerido:
Equipe de faturamento SUS/SIHA ou responsavel designado pela Secretaria.

Retencao e arquivamento:
$retention

Como encontrar daqui a 2 anos ou mais:
Procure por ano, competencia AAAA-MM, sistema, tipo de documento e status. Consulte tambem os indices em 99_MANIFESTOS_HASHES e os relatorios em 98_RELATORIOS_DE_AUDITORIA.
EOF
  chown root:"$GROUP_NAME" "$path"
  chmod 0660 "$path"
}

common_pattern="AAAA-MM-DD_SISTEMA_COMPETENCIA_TIPO_ORIGEM-OU-DESTINO_DESCRICAO_STATUS.ext"
write_readme "00_LEIA-ME" "00_LEIA-ME" \
  "Regras de uso, convencoes, orientacoes de backup, restauracao e operacao." \
  "$common_pattern" \
  "2026-06-28_SIHA_2026-05_DOCUMENTACAO_INTERNA_CONVENCAO-DE-NOMES_APROVADO.md" \
  "Remessas, backups ou retornos operacionais." \
  "Manter permanentemente e revisar sempre que o processo operacional mudar."
write_readme "01_REMESSAS_MS" "01_REMESSAS_MS" \
  "Arquivos oficiais enviados ao Ministerio da Saude ou gerados para envio." \
  "$common_pattern" \
  "2026-06-28_SIHA_2026-05_REMESSA_MS_ENVIO-OFICIAL.zip" \
  "Protocolos recebidos, backups completos ou instaladores." \
  "Manter em area operacional por ate 730 dias; depois arquivar de forma conservadora."
write_readme "02_RETORNOS_MS" "02_RETORNOS_MS" \
  "Retornos, protocolos, recibos e arquivos processados recebidos do Ministerio da Saude." \
  "$common_pattern" \
  "2026-06-29_SIHA_2026-05_PROTOCOLO_MS_RECEBIDO.pdf; 2026-07-01_SIHA_2026-06_RETORNO_MS_PROCESSADO.xml" \
  "Remessas ainda nao enviadas, backups e instaladores." \
  "Manter em area operacional por ate 730 dias; depois arquivar de forma conservadora."
write_readme "03_BACKUPS_SISTEMAS" "03_BACKUPS_SISTEMAS" \
  "Backups dos sistemas de faturamento antes/depois de fechamento, atualizacao ou importacao." \
  "$common_pattern" \
  "2026-06-30_SIHA_2026-05_BACKUP_SISTEMA_POS-FECHAMENTO.bak" \
  "Arquivos temporarios, exportacoes incompletas ou dumps sem identificacao." \
  "Nunca compactar automaticamente o backup mais recente de cada sistema; manter copia externa nao gravavel pela VM."
write_readme "04_INSTALADORES_E_UTILITARIOS" "04_INSTALADORES_E_UTILITARIOS" \
  "Instaladores oficiais, utilitarios homologados e checksums dos binarios usados." \
  "$common_pattern" \
  "2026-06-28_SIHA_2026-06_INSTALADOR_MS_SIHA_VERSAO-X_OFICIAL.exe" \
  "Executaveis sem origem conhecida ou arquivos baixados sem hash/documentacao." \
  "Manter versoes usadas em producao e registrar origem em 05_DOCUMENTACAO_OPERACIONAL."
write_readme "05_DOCUMENTACAO_OPERACIONAL" "05_DOCUMENTACAO_OPERACIONAL" \
  "Procedimentos, prints operacionais nao sensiveis, atas tecnicas e orientacoes de uso." \
  "$common_pattern" \
  "2026-06-28_SIHA_2026-06_PROCEDIMENTO_INTERNO_FECHAMENTO_MENSAL_APROVADO.md" \
  "Senhas, tokens, chaves privadas, dados clinicos desnecessarios ou arquivos de remessa." \
  "Manter permanentemente; nao compactar automaticamente."
write_readme "90_ARQUIVO_FECHADO" "90_ARQUIVO_FECHADO" \
  "Arquivos historicos fechados, preservados para consulta e auditoria." \
  "$common_pattern" \
  "2024-12-31_SIHA_2024-11_DOSSIE_INTERNO_FECHAMENTO_ANUAL_FECHADO.pdf" \
  "Arquivos ainda em trabalho ou sem manifestos/indice." \
  "Usar para material fechado e compreensivel; manter hashes e indices atualizados."
write_readme "91_ARQUIVO_COMPACTADO" "91_ARQUIVO_COMPACTADO" \
  "Pacotes compactados de anos/categorias antigas criados pelo processo de arquivamento." \
  "SIHA_ARQUIVO_AAAA_CATEGORIA.zip ou .tar.zst" \
  "SIHA_ARQUIVO_2024_REMESSAS_E_RETORNOS.zip" \
  "Arquivos soltos de trabalho ou compactacoes manuais sem relatorio e hash." \
  "Manter junto com SHA256 em 99_MANIFESTOS_HASHES e relatorio em 98_RELATORIOS_DE_AUDITORIA."
write_readme "98_RELATORIOS_DE_AUDITORIA" "98_RELATORIOS_DE_AUDITORIA" \
  "Relatorios de arquivamento, validacao, restauracao e auditoria de integridade." \
  "$common_pattern" \
  "2026-06-28_SIHA_2026-06_RELATORIO_AUDITORIA_INDICE_GERADO.md" \
  "Dados brutos de remessa ou backups." \
  "Manter permanentemente para explicar decisoes futuras."
write_readme "99_MANIFESTOS_HASHES" "99_MANIFESTOS_HASHES" \
  "Indices anuais CSV, hashes SHA256 e manifestos de integridade." \
  "indice_AAAA.csv; NOME_DO_ARQUIVO.sha256" \
  "indice_2026.csv; SIHA_ARQUIVO_2024_REMESSAS_E_RETORNOS.zip.sha256" \
  "Arquivos operacionais sem hash ou documentos sem relacao com integridade." \
  "Manter permanentemente e recriar indices apos mudancas relevantes."

cat > "$BASE/00_LEIA-ME/CONVENCAO_DE_NOMES.md" <<'EOF'
# Convencao de nomes SIHA

Use o formato:

`AAAA-MM-DD_SISTEMA_COMPETENCIA_TIPO_ORIGEM-OU-DESTINO_DESCRICAO_STATUS.ext`

A data inicial ordena os arquivos no Windows e indica quando o evento ocorreu.
Ela nao substitui a competencia. A competencia `AAAA-MM` identifica o mes de
producao/faturamento. Para retorno ou protocolo, use a data de recebimento no
inicio do nome e mantenha a competencia do faturamento no terceiro campo.

Exemplos bons:

- `2026-06-28_SIHA_2026-05_REMESSA_MS_ENVIO-OFICIAL.zip`
- `2026-06-29_SIHA_2026-05_PROTOCOLO_MS_RECEBIDO.pdf`
- `2026-06-30_SIHA_2026-05_BACKUP_SISTEMA_POS-FECHAMENTO.bak`
- `2026-07-01_SIHA_2026-06_RETORNO_MS_PROCESSADO.xml`

Evite nomes como `backup novo.bak`, `retorno.zip`, `final.docx` ou `arquivo do
mes passado.pdf`. Daqui a dois anos, a pessoa que procurar o arquivo precisa
entender sistema, competencia, tipo, origem/destino e status sem abrir o
conteudo.
EOF
chown root:"$GROUP_NAME" "$BASE/00_LEIA-ME/CONVENCAO_DE_NOMES.md"
chmod 0660 "$BASE/00_LEIA-ME/CONVENCAO_DE_NOMES.md"

install -D -m 0755 -o root -g root "$SCRIPT_DIR/gerar-indice-siha.sh" /usr/local/sbin/gerar-indice-siha.sh
install -D -m 0755 -o root -g root "$SCRIPT_DIR/arquivar-antigos-siha.sh" /usr/local/sbin/arquivar-antigos-siha.sh
install -D -m 0644 -o root -g root "$SCRIPT_DIR/siha-arquivar-antigos.service" /etc/systemd/system/siha-arquivar-antigos.service
install -D -m 0644 -o root -g root "$SCRIPT_DIR/siha-arquivar-antigos.timer" /etc/systemd/system/siha-arquivar-antigos.timer

if [[ -f /etc/samba/smb.conf && ! -f /etc/samba/smb.conf.siha-nas-original ]]; then
  cp -a /etc/samba/smb.conf /etc/samba/smb.conf.siha-nas-original
fi
install -m 0644 -o root -g root "$SCRIPT_DIR/smb.conf.template" /etc/samba/smb.conf

if [[ "$ALLOWED_CIDR" != "none" && -n "$ALLOWED_CIDR" ]]; then
  cat > /usr/local/sbin/apply-siha-nas-firewall <<'EOF'
#!/bin/sh
set -eu
allowed_cidr="$1"
command -v nft >/dev/null 2>&1 || exit 0
nft list table inet siha_nas_smb >/dev/null 2>&1 && nft delete table inet siha_nas_smb || true
nft add table inet siha_nas_smb
nft 'add chain inet siha_nas_smb input { type filter hook input priority -50; policy accept; }'
nft add rule inet siha_nas_smb input iifname lo accept
nft add rule inet siha_nas_smb input ip saddr "$allowed_cidr" tcp dport {139,445} accept
nft add rule inet siha_nas_smb input ip saddr "$allowed_cidr" udp dport {137,138} accept
nft add rule inet siha_nas_smb input tcp dport {139,445} drop
nft add rule inet siha_nas_smb input udp dport {137,138} drop
EOF
  chmod 0755 /usr/local/sbin/apply-siha-nas-firewall
  cat > /etc/systemd/system/siha-nas-firewall.service <<EOF
[Unit]
Description=Firewall for SIHA NAS SMB
DefaultDependencies=no
Before=smbd.service nmbd.service
After=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/apply-siha-nas-firewall $ALLOWED_CIDR

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable --now siha-nas-firewall.service
fi

testparm -s /etc/samba/smb.conf >/dev/null
systemctl enable --now smbd.service
systemctl restart smbd.service
systemctl enable --now nmbd.service >/dev/null 2>&1 || true

if [[ -n "${SIHA_SAMBA_PASSWORD_FILE:-}" ]]; then
  if [[ ! -f "$SIHA_SAMBA_PASSWORD_FILE" ]]; then
    echo "SIHA_SAMBA_PASSWORD_FILE informado, mas arquivo nao existe." >&2
    exit 30
  fi
  samba_password="$(head -n 1 "$SIHA_SAMBA_PASSWORD_FILE")"
  {
    printf '%s\n' "$samba_password"
    printf '%s\n' "$samba_password"
  } | smbpasswd -a -s "$SAMBA_USER" >/dev/null
  smbpasswd -e "$SAMBA_USER" >/dev/null
  unset samba_password
  rm -f -- "$SIHA_SAMBA_PASSWORD_FILE"
elif [[ -n "${SIHA_SAMBA_PASSWORD:-}" ]]; then
  {
    printf '%s\n' "$SIHA_SAMBA_PASSWORD"
    printf '%s\n' "$SIHA_SAMBA_PASSWORD"
  } | smbpasswd -a -s "$SAMBA_USER" >/dev/null
  smbpasswd -e "$SAMBA_USER" >/dev/null
  unset SIHA_SAMBA_PASSWORD
else
  echo "Senha Samba nao definida. Execute manualmente: smbpasswd -a $SAMBA_USER"
fi

if [[ "$ENABLE_TIMER" -eq 1 ]]; then
  systemctl daemon-reload
  systemctl enable --now siha-arquivar-antigos.timer
fi

find "$BASE" -type d -exec chown root:"$GROUP_NAME" {} +
find "$BASE" -type d -exec chmod 2770 {} +
find "$BASE" -type f -exec chown root:"$GROUP_NAME" {} +
find "$BASE" -type f -exec chmod 0660 {} +

echo "siha_nas=ready"
echo "base=$BASE"
echo "samba_share=\\\\siha-nas\\SIHA"
