#!/usr/bin/env bash
set -Eeuo pipefail

BASE="/dados/siha"
YEAR="$(date +%Y)"
OUTPUT=""
DRY_RUN=0
LOG_DIR="/var/log/siha-nas"

trap 'echo "Erro em gerar-indice-siha.sh na linha $LINENO." >&2' ERR

usage() {
  cat <<'USAGE'
Uso: gerar-indice-siha.sh [--dry-run] [--ano AAAA] [--base /dados/siha] [--output arquivo.csv]

Gera indice anual CSV com metadados e SHA256 dos arquivos SIHA.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --ano|--year) YEAR="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Argumento desconhecido: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$YEAR" =~ ^[0-9]{4}$ ]] || { echo "--ano deve estar no formato AAAA." >&2; exit 2; }
[[ -d "$BASE" ]] || { echo "Base nao encontrada: $BASE" >&2; exit 3; }
command -v find >/dev/null 2>&1 || { echo "Comando obrigatorio ausente: find" >&2; exit 127; }
command -v sha256sum >/dev/null 2>&1 || { echo "Comando obrigatorio ausente: sha256sum" >&2; exit 127; }
command -v stat >/dev/null 2>&1 || { echo "Comando obrigatorio ausente: stat" >&2; exit 127; }
command -v tee >/dev/null 2>&1 || { echo "Comando obrigatorio ausente: tee" >&2; exit 127; }

if [[ -z "$OUTPUT" ]]; then
  OUTPUT="$BASE/99_MANIFESTOS_HASHES/indice_${YEAR}.csv"
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  command -v flock >/dev/null 2>&1 || { echo "Comando obrigatorio ausente: flock" >&2; exit 127; }
  if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
    LOG_DIR="${TMPDIR:-/tmp}/siha-nas-logs"
    mkdir -p "$LOG_DIR"
    echo "Aviso: sem permissao para /var/log/siha-nas; usando $LOG_DIR." >&2
  fi
  mkdir -p "$(dirname "$OUTPUT")"
  LOG_FILE="$LOG_DIR/gerar-indice-${YEAR}-$(date +%Y%m%dT%H%M%S).log"
  exec > >(tee -a "$LOG_FILE") 2>&1
  { exec 9>/run/siha-nas-gerar-indice.lock; } 2>/dev/null ||
    exec 9>"${TMPDIR:-/tmp}/siha-nas-gerar-indice.lock"
  flock -n 9 || { echo "Outro gerar-indice-siha.sh esta em execucao." >&2; exit 75; }
fi

export LC_ALL="${LC_ALL:-C.UTF-8}"

csv_escape() {
  local value="${1-}"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  case "$value" in
    =*|+*|-*|@*|$'\t'*) value="'$value" ;;
  esac
  value="${value//\"/\"\"}"
  printf '"%s"' "$value"
}

detect_category() {
  local rel="$1"
  case "$rel" in
    01_REMESSAS_MS/*) echo "REMESSA_MS" ;;
    02_RETORNOS_MS/*) echo "RETORNO_MS" ;;
    03_BACKUPS_SISTEMAS/*) echo "BACKUP_SISTEMA" ;;
    04_INSTALADORES_E_UTILITARIOS/*) echo "INSTALADOR_UTILITARIO" ;;
    05_DOCUMENTACAO_OPERACIONAL/*) echo "DOCUMENTACAO_OPERACIONAL" ;;
    90_ARQUIVO_FECHADO/*) echo "ARQUIVO_FECHADO" ;;
    91_ARQUIVO_COMPACTADO/*) echo "ARQUIVO_COMPACTADO" ;;
    98_RELATORIOS_DE_AUDITORIA/*) echo "RELATORIO_AUDITORIA" ;;
    99_MANIFESTOS_HASHES/*) echo "MANIFESTO_HASH" ;;
    *) echo "GERAL" ;;
  esac
}

detect_competence() {
  local name="$1"
  if [[ "$name" =~ (20[0-9]{2})[-_](0[1-9]|1[0-2]) ]]; then
    printf '%s-%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    printf ''
  fi
}

is_archived() {
  local rel="$1"
  case "$rel" in
    90_ARQUIVO_FECHADO/*|91_ARQUIVO_COMPACTADO/*) echo "sim" ;;
    *) echo "nao" ;;
  esac
}

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT HUP INT TERM

{
  echo "caminho_relativo,nome_arquivo,tamanho,data_modificacao,ano,competencia_detectada,categoria,hash_sha256,observacao,arquivado_sim_nao,arquivo_compactado_destino"
  find "$BASE" -type f \
    ! -path "$BASE/.lixeira/*" \
    ! -path "*/.lixeira/*" \
    ! -path "$BASE/tmp/*" \
    ! -path "$BASE/cache/*" \
    ! -name "*.tmp" ! -name "*.temp" ! -name "*.partial" ! -name "~$*" ! -name "*.lock" ! -name "*.lck" \
    ! -name "indice_*.csv" \
    ! -name "arquivamento_*.tmp" \
    -newermt "${YEAR}-01-01" ! -newermt "$((YEAR + 1))-01-01" \
    -print0 |
  sort -z |
  while IFS= read -r -d '' file; do
    rel="${file#"$BASE"/}"
    name="$(basename "$file")"
    size="$(stat -c '%s' "$file")"
    mtime="$(stat -c '%y' "$file" | cut -d'.' -f1)"
    category="$(detect_category "$rel")"
    competence="$(detect_competence "$name")"
    hash="$(sha256sum "$file" | awk '{print $1}')"
    archived="$(is_archived "$rel")"

    csv_escape "$rel"; printf ','
    csv_escape "$name"; printf ','
    csv_escape "$size"; printf ','
    csv_escape "$mtime"; printf ','
    csv_escape "$YEAR"; printf ','
    csv_escape "$competence"; printf ','
    csv_escape "$category"; printf ','
    csv_escape "$hash"; printf ','
    csv_escape ""; printf ','
    csv_escape "$archived"; printf ','
    csv_escape ""
    printf '\n'
  done
} > "$tmp"

count="$(( $(wc -l < "$tmp") - 1 ))"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[dry-run] indice seria gravado em: $OUTPUT"
  echo "[dry-run] arquivos indexados: $count"
  exit 0
fi

install -m 0660 "$tmp" "$OUTPUT"
if getent group siha_faturamento >/dev/null 2>&1; then
  chgrp siha_faturamento "$OUTPUT"
fi
chmod 0660 "$OUTPUT"
echo "Indice gravado em $OUTPUT com $count arquivo(s)."
