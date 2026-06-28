#!/usr/bin/env bash
set -Eeuo pipefail

BASE="/dados/siha"
OLDER_THAN_DAYS=730
YEAR=""
ARCHIVE_FORMAT="${ARCHIVE_FORMAT:-zip}"
REMOVE_ORIGINALS=0
DRY_RUN=0
REPORT_ONLY=0
VERBOSE=0
LOG_DIR="/var/log/siha-nas"

trap 'echo "Erro em arquivar-antigos-siha.sh na linha $LINENO." >&2' ERR

usage() {
  cat <<'USAGE'
Uso: arquivar-antigos-siha.sh [opcoes]

Opcoes:
  --dry-run
  --base /dados/siha
  --older-than-days 730
  --year AAAA
  --format zip|tar.zst
  --remove-originals-after-verify
  --report-only
  --verbose
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --base) BASE="$2"; shift 2 ;;
    --older-than-days) OLDER_THAN_DAYS="$2"; shift 2 ;;
    --year|--ano) YEAR="$2"; shift 2 ;;
    --format) ARCHIVE_FORMAT="$2"; shift 2 ;;
    --remove-originals-after-verify) REMOVE_ORIGINALS=1; shift ;;
    --report-only) REPORT_ONLY=1; shift ;;
    --verbose) VERBOSE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Argumento desconhecido: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -d "$BASE" ]] || { echo "Base nao encontrada: $BASE" >&2; exit 3; }
[[ "$OLDER_THAN_DAYS" =~ ^[0-9]+$ ]] || { echo "--older-than-days deve ser numerico." >&2; exit 2; }
[[ -z "$YEAR" || "$YEAR" =~ ^[0-9]{4}$ ]] || { echo "--year deve estar no formato AAAA." >&2; exit 2; }
[[ "$ARCHIVE_FORMAT" == "zip" || "$ARCHIVE_FORMAT" == "tar.zst" ]] || { echo "--format deve ser zip ou tar.zst." >&2; exit 2; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || { echo "Comando obrigatorio ausente: $1" >&2; exit 127; }
}

for command_name in find sha256sum stat df sort mktemp awk sleep tee; do
  require_command "$command_name"
done
if [[ "$ARCHIVE_FORMAT" == "zip" ]]; then
  require_command zip
  require_command unzip
else
  require_command tar
  require_command zstd
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  require_command flock
  if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
    LOG_DIR="${TMPDIR:-/tmp}/siha-nas-logs"
    mkdir -p "$LOG_DIR"
    echo "Aviso: sem permissao para /var/log/siha-nas; usando $LOG_DIR." >&2
  fi
  mkdir -p "$BASE/98_RELATORIOS_DE_AUDITORIA" "$BASE/99_MANIFESTOS_HASHES" "$BASE/91_ARQUIVO_COMPACTADO"
  LOG_FILE="$LOG_DIR/arquivar-antigos-$(date +%Y%m%dT%H%M%S).log"
  exec > >(tee -a "$LOG_FILE") 2>&1
  { exec 9>/run/siha-nas-arquivar-antigos.lock; } 2>/dev/null ||
    exec 9>"${TMPDIR:-/tmp}/siha-nas-arquivar-antigos.lock"
  flock -n 9 || { echo "Outro arquivar-antigos-siha.sh esta em execucao." >&2; exit 75; }
else
  echo "[dry-run] Nenhum relatorio, compactado, hash ou arquivo de log sera gravado."
fi

export LC_ALL="${LC_ALL:-C.UTF-8}"

display_text() {
  local value="${1-}"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  printf '%s' "$value"
}

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

category_for_rel() {
  case "$1" in
    01_REMESSAS_MS/*) echo "REMESSAS_E_RETORNOS" ;;
    02_RETORNOS_MS/*) echo "REMESSAS_E_RETORNOS" ;;
    03_BACKUPS_SISTEMAS/*) echo "BACKUPS_SISTEMAS" ;;
    90_ARQUIVO_FECHADO/*) echo "ARQUIVO_FECHADO" ;;
    *) echo "OUTROS" ;;
  esac
}

file_year() {
  local rel="$1"
  if [[ "$rel" =~ ^[0-9]{4}[-_/] ]]; then
    echo "${rel:0:4}"
  elif [[ "$rel" =~ (20[0-9]{2}) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    stat -c '%y' "$BASE/$rel" | cut -c1-4
  fi
}

backup_key_for_rel() {
  local rel="$1"
  local name
  name="$(basename "$rel")"
  if [[ "$name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_([^_]+)_ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "${name%.*}"
  fi
}

is_excluded_file() {
  local rel="$1"
  case "$rel" in
    00_LEIA-ME/*|05_DOCUMENTACAO_OPERACIONAL/*|98_RELATORIOS_DE_AUDITORIA/*|99_MANIFESTOS_HASHES/*|.lixeira/*|*/.lixeira/*) return 0 ;;
    91_ARQUIVO_COMPACTADO/*) return 0 ;;
    *.zip|*.7z|*.rar|*.tar|*.tar.gz|*.tgz|*.tar.zst|*.zst|*.gz|*.bz2|*.xz) return 0 ;;
    *.tmp|*.temp|*.partial|~$*|*.lock|*.lck) return 0 ;;
  esac
  return 1
}

is_stable_file() {
  local file="$1"
  local first second
  first="$(stat -c '%s:%Y' "$file")"
  sleep 1
  second="$(stat -c '%s:%Y' "$file")"
  [[ "$first" == "$second" ]]
}

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/siha-nas-archive.XXXXXXXXXX")"
candidate_list="$work_dir/candidates.nul"
trap 'rm -rf "$work_dir"; echo "Erro em arquivar-antigos-siha.sh na linha $LINENO." >&2' ERR
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

declare -A newest_backup_by_key=()
declare -A newest_backup_mtime=()
while IFS= read -r -d '' backup_file; do
  rel="${backup_file#"$BASE"/}"
  key="$(backup_key_for_rel "$rel")"
  mtime="$(stat -c '%Y' "$backup_file")"
  if [[ -z "${newest_backup_mtime[$key]+set}" || "$mtime" -gt "${newest_backup_mtime[$key]}" ]]; then
    newest_backup_mtime[$key]="$mtime"
    newest_backup_by_key[$key]="$rel"
  fi
done < <(find "$BASE/03_BACKUPS_SISTEMAS" -type f -print0 2>/dev/null || true)

candidate_count=0
declare -A group_seen=()
find "$BASE" -type f -mtime +"$OLDER_THAN_DAYS" -print0 |
while IFS= read -r -d '' file; do
  rel="${file#"$BASE"/}"
  is_excluded_file "$rel" && continue
  y="$(file_year "$rel")"
  [[ -z "$YEAR" || "$y" == "$YEAR" ]] || continue

  if [[ "$rel" == 03_BACKUPS_SISTEMAS/* ]]; then
    key="$(backup_key_for_rel "$rel")"
    [[ "${newest_backup_by_key[$key]-}" == "$rel" ]] && continue
  fi

  if ! is_stable_file "$file"; then
    echo "Ignorando arquivo ainda em alteracao: $(display_text "$rel")" >&2
    continue
  fi

  category="$(category_for_rel "$rel")"
  size="$(stat -c '%s' "$file")"
  printf '%s\0%s\0%s\0%s\0' "$y" "$category" "$rel" "$size" >> "$candidate_list"
done

if [[ -f "$candidate_list" ]]; then
  while IFS= read -r -d '' y &&
        IFS= read -r -d '' category &&
        IFS= read -r -d '' rel &&
        IFS= read -r -d '' size; do
    candidate_count=$((candidate_count + 1))
    group_seen["$y|$category"]=1
  done < "$candidate_list"
fi

echo "Candidatos encontrados: $candidate_count"

if [[ "$DRY_RUN" -eq 1 ]]; then
  if [[ -f "$candidate_list" ]]; then
    while IFS= read -r -d '' y &&
          IFS= read -r -d '' category &&
          IFS= read -r -d '' rel &&
          IFS= read -r -d '' size; do
      printf '[dry-run] %s | %s | %s | %s bytes\n' "$y" "$category" "$(display_text "$rel")" "$size"
    done < "$candidate_list"
  fi
  exit 0
fi

stamp="$(date +%Y%m%dT%H%M%S)"
scope="${YEAR:-todos}"
report_md="$BASE/98_RELATORIOS_DE_AUDITORIA/arquivamento_${scope}_${stamp}.md"
report_csv="$BASE/98_RELATORIOS_DE_AUDITORIA/arquivamento_${scope}_${stamp}.csv"

{
  echo "# Relatorio de arquivamento SIHA"
  echo
  echo "- Data: $(date --iso-8601=seconds)"
  echo "- Base: $BASE"
  echo "- Mais antigo que: $OLDER_THAN_DAYS dias"
  echo "- Ano: ${YEAR:-todos}"
  echo "- Formato: $ARCHIVE_FORMAT"
  echo "- Modo dry-run: $DRY_RUN"
  echo "- Report-only: $REPORT_ONLY"
  echo "- Remover originais apos verificacao: $REMOVE_ORIGINALS"
  echo
  echo "| Ano | Categoria | Caminho relativo | Tamanho |"
  echo "|---|---|---|---:|"
  if [[ -f "$candidate_list" ]]; then
    while IFS= read -r -d '' y &&
          IFS= read -r -d '' category &&
          IFS= read -r -d '' rel &&
          IFS= read -r -d '' size; do
      echo "| $y | $category | \`$(display_text "$rel")\` | $size |"
    done < "$candidate_list"
  fi
} > "$report_md"

{
  echo "ano,categoria,caminho_relativo,tamanho"
  if [[ -f "$candidate_list" ]]; then
    while IFS= read -r -d '' y &&
          IFS= read -r -d '' category &&
          IFS= read -r -d '' rel &&
          IFS= read -r -d '' size; do
      csv_escape "$y"; printf ','
      csv_escape "$category"; printf ','
      csv_escape "$rel"; printf ','
      csv_escape "$size"; printf '\n'
    done < "$candidate_list"
  fi
} > "$report_csv"

chgrp siha_faturamento "$report_md" "$report_csv" 2>/dev/null || true
chmod 0660 "$report_md" "$report_csv" 2>/dev/null || true
echo "Relatorios: $report_md ; $report_csv"

if [[ "$candidate_count" -eq 0 || "$REPORT_ONLY" -eq 1 ]]; then
  echo "Nenhum arquivo compactado neste modo."
  exit 0
fi

declare -a archived_years=()
for group_key in "${!group_seen[@]}"; do
  group_year="${group_key%%|*}"
  group_category="${group_key#*|}"
  group_dir="$BASE/91_ARQUIVO_COMPACTADO/$group_year"
  mkdir -p "$group_dir"
  archive_name="SIHA_ARQUIVO_${group_year}_${group_category}.${ARCHIVE_FORMAT}"
  archive_path="$group_dir/$archive_name"

  if [[ -e "$archive_path" ]]; then
    if [[ "$REMOVE_ORIGINALS" -eq 1 ]]; then
      echo "Arquivo compactado ja existe; recusando remover originais com base em artefato preexistente: $archive_path" >&2
      exit 21
    fi
    echo "Arquivo compactado ja existe; grupo ignorado para evitar sobrescrita: $archive_path"
    continue
  fi

  declare -a files=()
  total_size=0
  while IFS= read -r -d '' y &&
        IFS= read -r -d '' category &&
        IFS= read -r -d '' rel &&
        IFS= read -r -d '' size; do
    if [[ "$y" == "$group_year" && "$category" == "$group_category" ]]; then
      files+=("$rel")
      total_size=$((total_size + size))
    fi
  done < "$candidate_list"

  available="$(df -P "$group_dir" | awk 'NR == 2 { print $4 * 1024 }')"
  if [[ "$available" -lt "$total_size" ]]; then
    echo "Espaco insuficiente para $archive_path: livre=$available necessario_minimo=$total_size" >&2
    exit 20
  fi

  if [[ "$ARCHIVE_FORMAT" == "zip" ]]; then
    (cd "$BASE" && zip -q -r "$archive_path" "${files[@]}")
    unzip -t "$archive_path" >/dev/null
  else
    (cd "$BASE" && tar --zstd -cf "$archive_path" "${files[@]}")
    tar -tf "$archive_path" >/dev/null
  fi

  archive_hash="$(sha256sum "$archive_path" | awk '{print $1}')"
  hash_file="$BASE/99_MANIFESTOS_HASHES/$(basename "$archive_path").sha256"
  printf '%s  %s\n' "$archive_hash" "$archive_path" > "$hash_file"
  chgrp siha_faturamento "$archive_path" "$hash_file" 2>/dev/null || true
  chmod 0660 "$archive_path" "$hash_file" 2>/dev/null || true
  echo "Compactado e verificado: $archive_path"
  printf '\n- Compactado: `%s`\n- SHA256: `%s`\n' "$archive_path" "$archive_hash" >> "$report_md"
  archived_years+=("$group_year")

  if [[ "$REMOVE_ORIGINALS" -eq 1 ]]; then
    for rel in "${files[@]}"; do
      rm -f -- "$BASE/$rel"
    done
    echo "Originais removidos apos verificacao para grupo $group_year/$group_category."
  fi
done

if command -v gerar-indice-siha.sh >/dev/null 2>&1; then
  if [[ -n "$YEAR" ]]; then
    gerar-indice-siha.sh --base "$BASE" --ano "$YEAR"
  else
    printf '%s\n' "${archived_years[@]}" | sort -u | while read -r indexed_year; do
      [[ -n "$indexed_year" ]] && gerar-indice-siha.sh --base "$BASE" --ano "$indexed_year"
    done
  fi
fi
