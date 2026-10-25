#!/usr/bin/env bash
# =============================================================================
# Qdrant Backup & Restore Script - powered by pc-fee.com
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Sichert und restauriert Collections einer mit install-qdrant.sh
# installierten Qdrant-Instanz ueber die Snapshot-API - im laufenden Betrieb,
# ohne Ausfallzeit:
#
#   Backup:  je Collection ein Snapshot (POST /collections/<name>/snapshots),
#            Pruefsumme verifiziert, als "Backup-Satz" nach
#            <backup-verzeichnis>/snapshots_<zeitstempel>/ kopiert, danach im
#            Qdrant-Arbeitsordner wieder geloescht. Aliase werden mitgesichert.
#   Restore: einzelne oder alle Collections eines Backup-Satzes zurueckspielen
#            (Upload mit priority=snapshot). Eine bestehende Collection gleichen
#            Namens wird dabei UEBERSCHRIEBEN - vorher wird auf Wunsch ihr
#            aktueller Stand gesichert.
#
# Wichtig - Versions-Kompatibilitaet (laut Qdrant-Doku):
#   Ein Snapshot laesst sich nur auf derselben oder der naechsten Minor-Version
#   zurueckspielen (Snapshot von v1.18.x -> v1.18.x oder v1.19.x).
#   Quelle: https://qdrant.tech/documentation/snapshots/
#   Das Script prueft das vor jedem Restore.
#
# Das Update-Script (update-qdrant.sh) sichert dagegen bei gestopptem Dienst
# das komplette storage/ als tar.gz - fuer einen Rollback nach einem Update.
#
# Nutzung als 1-Zeiler (von ueberall, kein vorheriger Download noetig):
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/backup/backup-qdrant.sh)"
#
# Modi (ohne Modus: interaktives Menue):
#   --backup             Backup-Satz erstellen
#   --restore [<satz>]   Backup-Satz zurueckspielen (ohne Angabe: Auswahl)
#   --list               Vorhandene Backup-Saetze anzeigen
#
# Optionen:
#   --collection <name>  Nur diese Collection (mehrfach angebbar)
#   --dir <pfad>         Installationspfad fest vorgeben (ueberspringt die Erkennung)
#   --backup-dir <pfad>  Backup-Verzeichnis (Default: aus .env, sonst /opt/qdrant-backups)
#   --keep <n>           Anzahl aufzubewahrender Backup-Saetze (Default: 5)
#   --dry-run            Zeigt nur, was passieren wuerde - aendert nichts
#   --yes                Ueberspringt die Rueckfragen (wie ASSUME_YES=1, fuer Cron)
#   --help               Diese Hilfe anzeigen
#
# Umgebungsvariablen (fuer unbeaufsichtigten Betrieb, z.B. Cron):
#   INSTALL_DIR, QDRANT_BACKUP_DIR, KEEP_SNAPSHOTS, ASSUME_YES,
#   QDRANT_API_KEY (falls nicht in der .env), LOG_FILE (Default: /var/log/qdrant-backup.log)
#
# Voraussetzungen: root (bzw. sudo), Docker + Docker Compose, curl, sha256sum.
#
# Autor: Nils Weber (n8n Automation Architect, pc-fee.com)
#
# AI Transparency: Dieses Script wurde mit Unterstuetzung von KI erstellt und
# vor Veroeffentlichung geprueft. Ein Restore ueberschreibt Daten unwiderruflich -
# bitte vorher mit --dry-run pruefen. Nutzung auf eigene Gefahr.
# =============================================================================
set -euo pipefail

# -- Farben --------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# -- Konstanten ----------------------------------------------------------------
readonly BLOG_URL="https://pc-fee.com/blog"
readonly DEFAULT_DIR="/opt/qdrant"
readonly DEFAULT_BACKUP_DIR="/opt/qdrant-backups"
readonly IMAGE_REPO="qdrant/qdrant"
readonly STORAGE_MOUNT="/qdrant/storage"
readonly SNAPSHOT_MOUNT="/qdrant/snapshots"
readonly SNAPSHOT_DOC="https://qdrant.tech/documentation/snapshots/"

# -- Optionen ------------------------------------------------------------------
MODE=""
RESTORE_SET=""
DRY_RUN=0
KEEP="${KEEP_SNAPSHOTS:-}"
BACKUP_DIR_OPT="${QDRANT_BACKUP_DIR:-}"
LOG="${LOG_FILE:-/var/log/qdrant-backup.log}"
declare -a SEL_COLLECTIONS=()

usage() {
  cat <<'USAGE'
Qdrant Backup & Restore Script - powered by pc-fee.com

Sichert Collections im laufenden Betrieb per Snapshot-API und spielt sie bei
Bedarf einzeln oder komplett zurueck. Ohne Modus startet ein Menue.

Modi:
  --backup             Backup-Satz erstellen
  --restore [<satz>]   Backup-Satz zurueckspielen (ohne Angabe: Auswahl)
  --list               Vorhandene Backup-Saetze anzeigen

Optionen:
  --collection <name>  Nur diese Collection (mehrfach angebbar)
  --dir <pfad>         Installationspfad fest vorgeben (ueberspringt die Erkennung)
  --backup-dir <pfad>  Backup-Verzeichnis (Default: aus .env, sonst /opt/qdrant-backups)
  --keep <n>           Anzahl aufzubewahrender Backup-Saetze (Default: 5)
  --dry-run            Zeigt nur, was passieren wuerde - aendert nichts
  --yes                Ueberspringt die Rueckfragen (wie ASSUME_YES=1, fuer Cron)
  --help               Diese Hilfe anzeigen

Umgebungsvariablen: INSTALL_DIR, QDRANT_BACKUP_DIR, KEEP_SNAPSHOTS, ASSUME_YES,
                    QDRANT_API_KEY, LOG_FILE

Beispiele:
  sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/backup/backup-qdrant.sh)"
  sudo ./backup-qdrant.sh --backup --yes                  # z.B. taeglich per Cron
  sudo ./backup-qdrant.sh --restore --collection docs --dry-run
  sudo ./backup-qdrant.sh --list
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup)        MODE="backup"; shift ;;
    --restore)       MODE="restore"; shift
                     if [[ $# -gt 0 && "$1" != --* ]]; then RESTORE_SET="$1"; shift; fi ;;
    --restore=*)     MODE="restore"; RESTORE_SET="${1#*=}"; shift ;;
    --list)          MODE="list"; shift ;;
    --collection)    SEL_COLLECTIONS+=("${2:-}"); shift 2 || true ;;
    --collection=*)  SEL_COLLECTIONS+=("${1#*=}"); shift ;;
    --dir)           INSTALL_DIR="${2:-}"; shift 2 || true ;;
    --dir=*)         INSTALL_DIR="${1#*=}"; shift ;;
    --backup-dir)    BACKUP_DIR_OPT="${2:-}"; shift 2 || true ;;
    --backup-dir=*)  BACKUP_DIR_OPT="${1#*=}"; shift ;;
    --keep)          KEEP="${2:-}"; shift 2 || true ;;
    --keep=*)        KEEP="${1#*=}"; shift ;;
    --dry-run)       DRY_RUN=1; shift ;;
    --yes|-y)        ASSUME_YES=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               echo "Unbekannte Option: $1 (siehe --help)" >&2; exit 1 ;;
  esac
done
readonly DRY_RUN

KEEP_GIVEN=1
if [[ -z "${KEEP}" ]]; then
  KEEP=5
  KEEP_GIVEN=0
fi
if ! [[ "${KEEP}" =~ ^[0-9]+$ ]] || [[ "${KEEP}" -lt 1 ]]; then
  echo "--keep erwartet eine positive Ganzzahl (erhalten: '${KEEP}')." >&2
  exit 1
fi
for c in ${SEL_COLLECTIONS[@]+"${SEL_COLLECTIONS[@]}"}; do
  [[ -n "${c}" ]] || { echo "--collection erwartet einen Namen." >&2; exit 1; }
done

# -- Eingabequelle -------------------------------------------------------------
# Wird das Script per 'curl ... | bash' gestartet, liegt auf stdin der Script-
# Text selbst - ein 'read' wuerde ihn verschlucken. Deshalb immer vom Terminal
# lesen. Ohne Terminal (z.B. Cron) wird nichts ueberschrieben, ausser
# ASSUME_YES=1 ist ausdruecklich gesetzt.
# Achtung: '[[ -r /dev/tty ]]' prueft nur die Rechtebits und ist auch dann wahr,
# wenn es gar kein steuerndes Terminal gibt (z.B. Cron). Deshalb wirklich oeffnen.
if { : </dev/tty; } 2>/dev/null; then
  TTY=/dev/tty
  INTERACTIVE=1
else
  TTY=/dev/null
  INTERACTIVE=0
fi
readonly TTY INTERACTIVE

# -- Hilfsfunktionen -----------------------------------------------------------
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[FEHLER]${RESET} $*"; }
die()     { error "$*"; exit 1; }

# ask_yesno <prompt> <default: j|n> -> Rueckgabewert via $? (0 = ja)
ask_yesno() {
  local prompt="$1" default="${2:-n}" input="" hint="j/N"
  [[ "${default,,}" == "j" ]] && hint="J/n"
  if [[ "${ASSUME_YES:-0}" == "1" ]]; then
    info "ASSUME_YES gesetzt - uebersprungene Abfrage: ${prompt}"
    return 0
  fi
  if [[ "${INTERACTIVE}" -eq 0 ]]; then
    warn "Kein Terminal fuer die Rueckfrage verfuegbar: ${prompt}"
    warn "Ohne Bestaetigung wird nichts veraendert (fuer Cron: --yes bzw. ASSUME_YES=1)."
    return 1
  fi
  echo ""
  echo -ne "${BOLD}${prompt}${RESET} [${CYAN}${hint}${RESET}]: "
  read -r input <"${TTY}" || true
  input="${input:-${default}}"
  [[ "${input,,}" == "j" || "${input,,}" == "y" ]]
}

# ask_value <variable> <prompt> <default> - ohne Terminal/mit ASSUME_YES: Default
ask_value() {
  local var="$1" prompt="$2" default="$3" input=""
  if [[ "${ASSUME_YES:-0}" != "1" && "${INTERACTIVE}" -eq 1 ]]; then
    echo ""
    echo -ne "${BOLD}${prompt}${RESET} [${CYAN}${default}${RESET}]: "
    read -r input <"${TTY}" || true
  fi
  printf -v "${var}" '%s' "${input:-${default}}"
}

# run <befehl...> - im Dry-Run nur anzeigen, sonst ausfuehren.
run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo -e "${YELLOW}   [DRY-RUN]${RESET} $*"
  else
    "$@"
  fi
}

minor_of() { local v="${1#v}"; v="${v#*.}"; echo "${v%%.*}"; }
major_of() { local v="${1#v}"; echo "${v%%.*}"; }

# urlencode <text> - Collection-Namen sicher in eine URL einsetzen
urlencode() {
  local LC_ALL=C s="$1" o="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "${c}" in
      [a-zA-Z0-9._~-]) o+="${c}" ;;
      *) printf -v c '%%%02X' "'${c}"; o+="${c}" ;;
    esac
  done
  printf '%s' "${o}"
}

# json_escape <text> - fuer Werte in einem JSON-String
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "${s}"
}

# safe_name <collection> - Dateiname fuer den Backup-Satz
safe_name() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }

human() { numfmt --to=iec "$1" 2>/dev/null || echo "$1 B"; }

# -- Banner --------------------------------------------------------------------
printf '%b' "${CYAN}"
cat <<'LOGO'
                  __
 _ __   ___      / _| ___  ___   ___ ___  _ __ ___
| '_ \ / __|____| |_ / _ \/ _ \ / __/ _ \| '_ ` _ \
| |_) | (_|_____|  _|  __/  __/| (_| (_) | | | | | |
| .__/ \___|    |_|  \___|\___(_)___\___/|_| |_| |_|
|_|
LOGO
printf '%b\n' "${RESET}"
printf '%b\n' "${BOLD} Qdrant Backup & Restore - powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo -e " ${YELLOW}${BOLD}DRY-RUN aktiv:${RESET} es wird nichts veraendert, nur angezeigt."
fi
echo "------------------------------------------------------------"

# -- Root-Check ----------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  die "Bitte als root oder mit sudo ausfuehren."
fi
cd / 2>/dev/null || die "Konnte nicht nach / wechseln."

# -- Voraussetzungen pruefen ---------------------------------------------------
command -v docker &>/dev/null || die "Docker ist nicht installiert."
docker info &>/dev/null || die "Docker-Daemon laeuft nicht. Bitte starten: systemctl start docker"
if docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
else
  die "Docker Compose nicht gefunden."
fi
readonly COMPOSE_CMD
command -v curl &>/dev/null || die "'curl' nicht gefunden - wird fuer die Snapshot-API gebraucht."
command -v sha256sum &>/dev/null || die "'sha256sum' nicht gefunden - wird fuer die Pruefsummen gebraucht."

# -- Installationspfad ermitteln -----------------------------------------------
# Identische Erkennung wie im Update-Script: Container-Label -> Volume-Quelle
# -> Standardpfad.
compose_file_of() {
  local d="$1" f
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    if [[ -f "${d}/${f}" ]] && grep -qE "image:[[:space:]]*[\"']?${IMAGE_REPO}(:|[\"']?[[:space:]]*$)" "${d}/${f}"; then
      echo "${d}/${f}"
      return 0
    fi
  done
  return 1
}

detect_dirs() {
  local -a raw=() out=()
  local cid d existing seen
  while IFS= read -r cid; do
    [[ -n "${cid}" ]] || continue
    d=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "${cid}" 2>/dev/null || true)
    [[ -n "${d}" && "${d}" == /* ]] && raw+=("${d}")
    d=$(docker inspect --format "{{range .Mounts}}{{if eq .Destination \"${STORAGE_MOUNT}\"}}{{.Source}}{{end}}{{end}}" "${cid}" 2>/dev/null || true)
    [[ -n "${d}" && "${d}" == /* ]] && raw+=("$(dirname "${d}")")
  done < <(docker ps -a --format '{{.ID}} {{.Image}}' | awk -v img="${IMAGE_REPO}" 'index($2, img) == 1 {print $1}')
  raw+=("${DEFAULT_DIR}")
  for d in "${raw[@]}"; do
    compose_file_of "${d}" >/dev/null 2>&1 || continue
    seen=0
    for existing in ${out[@]+"${out[@]}"}; do
      [[ "${existing}" == "${d}" ]] && seen=1
    done
    [[ "${seen}" -eq 0 ]] && out+=("${d}")
  done
  [[ "${#out[@]}" -gt 0 ]] && printf '%s\n' "${out[@]}"
  return 0
}

if [[ -n "${INSTALL_DIR:-}" ]]; then
  INSTALL_DIR="${INSTALL_DIR%/}"
  [[ -d "${INSTALL_DIR}" ]] || die "Angegebener Pfad existiert nicht: ${INSTALL_DIR}"
  compose_file_of "${INSTALL_DIR}" >/dev/null \
    || die "In ${INSTALL_DIR} liegt keine Compose-Datei mit einem ${IMAGE_REPO}-Image."
else
  mapfile -t FOUND < <(detect_dirs)
  case "${#FOUND[@]}" in
    0) die "Keine Qdrant-Installation gefunden.\n  Erwartet wurde eine Compose-Datei mit ${IMAGE_REPO}-Image, z.B. unter ${DEFAULT_DIR}.\n  Pfad ggf. direkt angeben: --dir /pfad/zur/installation" ;;
    1) INSTALL_DIR="${FOUND[0]}" ;;
    *)
      echo ""
      warn "Mehrere Qdrant-Installationen gefunden:"
      for i in "${!FOUND[@]}"; do
        echo -e "   ${BOLD}$((i + 1)))${RESET} ${CYAN}${FOUND[$i]}${RESET}"
      done
      [[ "${INTERACTIVE}" -eq 1 ]] || die "Kein Terminal fuer die Rueckfrage verfuegbar. Bitte --dir <pfad> setzen."
      choice=""
      echo ""
      echo -ne "${BOLD}Welche Installation?${RESET} [${CYAN}1${RESET}]: "
      read -r choice <"${TTY}" || true
      choice="${choice:-1}"
      { [[ "${choice}" =~ ^[0-9]+$ ]] && [[ "${choice}" -ge 1 ]] && [[ "${choice}" -le "${#FOUND[@]}" ]]; } \
        || die "Ungueltige Auswahl: ${choice}"
      INSTALL_DIR="${FOUND[$((choice - 1))]}"
      ;;
  esac
fi
readonly INSTALL_DIR
COMPOSE_FILE="$(compose_file_of "${INSTALL_DIR}")"
readonly COMPOSE_FILE
ENV_FILE="${INSTALL_DIR}/.env"

env_value() {
  [[ -f "${ENV_FILE}" ]] || return 0
  sed -n "s/^[[:space:]]*$1=//p" "${ENV_FILE}" | tail -n 1 | sed -e 's/^["'\'']//' -e 's/["'\'']$//'
}

BACKUP_DIR="${BACKUP_DIR_OPT:-$(env_value QDRANT_BACKUP_DIR)}"
BACKUP_DIR="${BACKUP_DIR:-${DEFAULT_BACKUP_DIR}}"
BACKUP_DIR="${BACKUP_DIR%/}"
readonly BACKUP_DIR
[[ "${BACKUP_DIR}" == /* ]] || die "Das Backup-Verzeichnis muss ein absoluter Pfad sein: ${BACKUP_DIR}"
API_KEY="${QDRANT_API_KEY:-$(env_value QDRANT_API_KEY)}"
readonly API_KEY

info "Installation:       ${INSTALL_DIR}"
info "Backup-Verzeichnis: ${BACKUP_DIR}"

# Host-Pfad des Snapshot-Arbeitsordners (dort legt Qdrant neue Snapshots ab).
CID="$(${COMPOSE_CMD} -f "${COMPOSE_FILE}" ps -q 2>/dev/null | head -n 1 || true)"
SNAP_HOST_DIR=""
if [[ -n "${CID}" ]]; then
  SNAP_HOST_DIR=$(docker inspect --format "{{range .Mounts}}{{if eq .Destination \"${SNAPSHOT_MOUNT}\"}}{{.Source}}{{end}}{{end}}" "${CID}" 2>/dev/null || true)
fi

QIP=""
QVERSION=""

connect() {
  # Verbindung zur laufenden Instanz herstellen (IP im Bridge-Netzwerk).
  [[ -n "${CID}" ]] || die "Kein laufender Qdrant-Container zu ${COMPOSE_FILE}.\n  Snapshots brauchen eine laufende Instanz: ${COMPOSE_CMD} -f ${COMPOSE_FILE} up -d"
  [[ "$(docker inspect -f '{{.State.Running}}' "${CID}" 2>/dev/null)" == "true" ]] \
    || die "Qdrant laeuft nicht.\n  Snapshots brauchen eine laufende Instanz: ${COMPOSE_CMD} -f ${COMPOSE_FILE} up -d"
  QIP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "${CID}" 2>/dev/null | awk '{print $1}')"
  [[ -n "${QIP}" ]] || die "Die IP des Qdrant-Containers konnte nicht ermittelt werden."
  curl -fsS --max-time 5 "http://${QIP}:6333/readyz" >/dev/null 2>&1 \
    || die "Qdrant antwortet nicht auf http://${QIP}:6333/readyz."
  QVERSION="$(curl -fsS --max-time 5 "http://${QIP}:6333/" 2>/dev/null | grep -oE '"version": *"[^"]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"
  [[ -n "${QVERSION}" ]] || die "Die Qdrant-Version konnte nicht gelesen werden."
  QVERSION="v${QVERSION}"
  local code
  local -a hdr=()
  [[ -n "${API_KEY}" ]] && hdr=(-H "api-key: ${API_KEY}")
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 ${hdr[@]+"${hdr[@]}"} "http://${QIP}:6333/collections" || true)"
  case "${code}" in
    200) ;;
    401|403) die "Qdrant lehnt den API-Key ab (HTTP ${code}).\n  Erwartet in ${ENV_FILE} als QDRANT_API_KEY=... oder per Umgebungsvariable QDRANT_API_KEY." ;;
    *) die "Unerwartete Antwort von Qdrant (HTTP ${code})." ;;
  esac
  success "Verbunden mit Qdrant ${QVERSION} (${QIP}:6333)."
}

api() {
  # api <methode> <pfad> [curl-optionen...]
  local m="$1" p="$2"
  shift 2
  local -a hdr=()
  [[ -n "${API_KEY}" ]] && hdr=(-H "api-key: ${API_KEY}")
  curl -fsS -X "${m}" ${hdr[@]+"${hdr[@]}"} "$@" "http://${QIP}:6333${p}"
}

list_collections() {
  api GET /collections --max-time 30 | grep -oE '"name": *"[^"]*"' | sed -E 's/"name": *"(.*)"/\1/' || true
}

points_of() {
  api GET "/collections/$(urlencode "$1")" --max-time 30 2>/dev/null \
    | grep -oE '"points_count": *[0-9]+' | head -n 1 | grep -oE '[0-9]+$' || true
}

collection_exists() {
  printf '%s\n' "${EXISTING[@]+"${EXISTING[@]}"}" | grep -qxF -- "$1"
}

# =============================================================================
# Backup
# =============================================================================
# create_set <ziel-satzverzeichnis> <collection...>
# Erzeugt je Collection einen Snapshot, kopiert ihn in den Satz, prueft die
# Pruefsumme und loescht den Snapshot danach im Qdrant-Arbeitsordner.
create_set() {
  local set_dir="$1"
  shift
  local c resp name sum file src got pts aliases
  mkdir -p "${set_dir}"
  chmod 700 "${set_dir}"
  : > "${set_dir}/manifest.tsv"
  for c in "$@"; do
    info "Snapshot von '${c}'..."
    pts="$(points_of "${c}")"
    resp="$(api POST "/collections/$(urlencode "${c}")/snapshots?wait=true")" \
      || { rm -rf "${set_dir}"; die "Snapshot von '${c}' fehlgeschlagen - Backup-Satz verworfen."; }
    name="$(printf '%s' "${resp}" | grep -oE '"name": *"[^"]+"' | head -n 1 | sed -E 's/"name": *"(.*)"/\1/')"
    sum="$(printf '%s' "${resp}" | grep -oE '"checksum": *"[0-9a-f]{64}"' | grep -oE '[0-9a-f]{64}' || true)"
    [[ -n "${name}" ]] || { rm -rf "${set_dir}"; die "Unerwartete Antwort auf den Snapshot von '${c}': ${resp}"; }
    file="$(safe_name "${c}").snapshot"
    src="${SNAP_HOST_DIR:+${SNAP_HOST_DIR}/${c}/${name}}"
    if [[ -n "${src}" && -f "${src}" ]]; then
      cp "${src}" "${set_dir}/${file}"
    else
      # Snapshot-Ordner nicht auf dem Host gemountet: ueber die API laden.
      api GET "/collections/$(urlencode "${c}")/snapshots/$(urlencode "${name}")" -o "${set_dir}/${file}" \
        || { rm -rf "${set_dir}"; die "Download des Snapshots von '${c}' fehlgeschlagen."; }
    fi
    chmod 600 "${set_dir}/${file}"
    got="$(sha256sum "${set_dir}/${file}" | cut -d' ' -f1)"
    if [[ -n "${sum}" && "${got}" != "${sum}" ]]; then
      rm -rf "${set_dir}"
      die "Pruefsumme von '${c}' stimmt nicht (Qdrant: ${sum}, Kopie: ${got}) - Backup-Satz verworfen."
    fi
    api DELETE "/collections/$(urlencode "${c}")/snapshots/$(urlencode "${name}")?wait=true" >/dev/null 2>&1 \
      || warn "Snapshot ${name} konnte im Qdrant-Arbeitsordner nicht geloescht werden."
    printf '%s\t%s\t%s\t%s\n' "${c}" "${file}" "${got}" "${pts:-?}" >> "${set_dir}/manifest.tsv"
    success "'${c}' gesichert: ${pts:-?} Punkte, $(du -h "${set_dir}/${file}" | cut -f1)"
  done
  aliases="$(api GET /aliases --max-time 30 2>/dev/null || echo '{}')"
  printf '%s\n' "${aliases}" > "${set_dir}/aliases.json"
  cat > "${set_dir}/info.txt" <<EOF
QDRANT_VERSION=${QVERSION}
CREATED=$(date '+%F %T')
HOST=$(hostname 2>/dev/null || echo unbekannt)
INSTALL_DIR=${INSTALL_DIR}
COLLECTIONS=$#
EOF
  chmod 600 "${set_dir}/manifest.tsv" "${set_dir}/aliases.json" "${set_dir}/info.txt"
}

list_sets() {
  # Backup-Saetze, neueste zuerst
  [[ -d "${BACKUP_DIR}" ]] || return 0
  find "${BACKUP_DIR}" -maxdepth 1 -mindepth 1 -type d -name 'snapshots_*' -printf '%f\n' 2>/dev/null | sort -r || true
}

set_info() {
  # set_info <satz> <KEY>
  sed -n "s/^$2=//p" "${BACKUP_DIR}/$1/info.txt" 2>/dev/null | head -n 1
}

do_backup() {
  echo ""
  echo "------------------------------------------------------------"
  echo -e "${BOLD} Backup erstellen${RESET}"
  echo "------------------------------------------------------------"
  connect
  mapfile -t EXISTING < <(list_collections)
  [[ "${#EXISTING[@]}" -gt 0 ]] || { success "Keine Collections vorhanden - nichts zu sichern."; return 0; }

  local -a todo=()
  local c input
  if [[ "${#SEL_COLLECTIONS[@]}" -gt 0 ]]; then
    for c in "${SEL_COLLECTIONS[@]}"; do
      collection_exists "${c}" || die "Collection '${c}' existiert nicht. Vorhanden: ${EXISTING[*]}"
      todo+=("${c}")
    done
  else
    info "Vorhandene Collections:"
    for c in "${EXISTING[@]}"; do echo -e "   - ${CYAN}${c}${RESET} ($(points_of "${c}") Punkte)"; done
    if ask_yesno "Alle ${#EXISTING[@]} Collections sichern?" "j"; then
      todo=("${EXISTING[@]}")
    else
      [[ "${INTERACTIVE}" -eq 1 ]] || die "Ohne Terminal bitte --collection <name> angeben."
      echo ""
      echo -ne "${BOLD}Welche Collections? (durch Komma getrennt)${RESET}: "
      read -r input <"${TTY}" || true
      IFS=',' read -r -a todo <<<"${input}"
      local -a clean=()
      for c in "${todo[@]}"; do
        c="$(echo "${c}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
        [[ -n "${c}" ]] || continue
        collection_exists "${c}" || die "Collection '${c}' existiert nicht."
        clean+=("${c}")
      done
      [[ "${#clean[@]}" -gt 0 ]] || die "Keine Collection ausgewaehlt."
      todo=("${clean[@]}")
    fi
  fi

  if [[ "${KEEP_GIVEN}" -eq 0 ]]; then
    while true; do
      ask_value KEEP "Wie viele Backup-Saetze sollen aufbewahrt werden?" "${KEEP}"
      [[ "${KEEP}" =~ ^[0-9]+$ ]] && [[ "${KEEP}" -ge 1 ]] && break
      warn "Bitte eine positive Ganzzahl eingeben."
      KEEP=5
    done
  fi

  local set_name set_dir storage_bytes avail
  set_name="snapshots_$(date +%F_%H-%M-%S)"
  set_dir="${BACKUP_DIR}/${set_name}"
  storage_bytes=$(du -s -B1 "${INSTALL_DIR}/storage" 2>/dev/null | cut -f1 || echo 0)
  mkdir -p "${BACKUP_DIR}" 2>/dev/null || true
  avail=$(df -PB1 "${BACKUP_DIR}" 2>/dev/null | awk 'NR == 2 {print $4}' || echo 0)

  local -a drop=()
  mapfile -t drop < <(list_sets | tail -n "+${KEEP}")

  echo ""
  echo -e " ${BOLD}Es wird:${RESET}"
  echo -e "   1. je Collection ein Snapshot erstellt (Qdrant laeuft dabei weiter): ${CYAN}${todo[*]}${RESET}"
  echo -e "   2. alles gesichert nach ${CYAN}${set_dir}/${RESET}"
  if [[ "${#drop[@]}" -gt 0 ]]; then
    echo -e "   3. ${#drop[@]} alte(r) Backup-Satz/Saetze entfernt (es bleiben die ${KEEP} neuesten), aeltester: ${CYAN}${drop[-1]}${RESET}"
  else
    echo -e "   3. kein alter Backup-Satz entfernt (es bleiben bis zu ${KEEP})"
  fi
  echo -e " Platz: storage/ belegt $(human "${storage_bytes}"), frei in ${BACKUP_DIR}: $(human "${avail}")"
  if [[ "${avail:-0}" -lt "${storage_bytes:-0}" ]]; then
    warn "Moeglicherweise zu wenig Platz - Snapshots koennen so gross werden wie storage/."
    warn "Qdrant legt jeden Snapshot zusaetzlich kurz im eigenen Arbeitsordner ab."
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo ""
    echo -e "${YELLOW}${BOLD} DRY-RUN beendet - es wurde nichts veraendert.${RESET}"
    return 0
  fi
  ask_yesno "Backup jetzt erstellen?" "j" || { warn "Abgebrochen. Es wurde nichts veraendert."; return 0; }

  echo ""
  create_set "${set_dir}" "${todo[@]}"
  success "Backup-Satz erstellt: ${set_dir} ($(du -sh "${set_dir}" | cut -f1))"

  mapfile -t drop < <(list_sets | tail -n "+$((KEEP + 1))")
  if [[ "${#drop[@]}" -gt 0 ]]; then
    info "Entferne ${#drop[@]} alte(n) Backup-Satz/Saetze (behalte die letzten ${KEEP})."
    local d
    for d in "${drop[@]}"; do
      [[ -n "${d}" && "${d}" == snapshots_* ]] && rm -rf "${BACKUP_DIR:?}/${d}"
    done
  fi

  echo ""
  echo -e " ${BOLD}Zurueckspielen:${RESET}"
  echo -e "   ${CYAN}sudo bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/backup/backup-qdrant.sh)\" -- --restore ${set_name}${RESET}"
  echo -e " Kompatibel mit Qdrant ${QVERSION%.*}.x und v$(major_of "${QVERSION}").$(( $(minor_of "${QVERSION}") + 1 )).x."
}

# =============================================================================
# Liste
# =============================================================================
do_list() {
  echo ""
  echo "------------------------------------------------------------"
  echo -e "${BOLD} Backup-Saetze in ${BACKUP_DIR}${RESET}"
  echo "------------------------------------------------------------"
  local -a sets=()
  mapfile -t sets < <(list_sets)
  if [[ "${#sets[@]}" -eq 0 ]]; then
    info "Keine Backup-Saetze vorhanden."
  else
    local s i=1
    for s in "${sets[@]}"; do
      printf " %2d) ${CYAN}%s${RESET}  Qdrant %-8s %3s Collection(s)  %s\n" \
        "${i}" "${s}" "$(set_info "${s}" QDRANT_VERSION)" "$(set_info "${s}" COLLECTIONS)" "$(du -sh "${BACKUP_DIR}/${s}" 2>/dev/null | cut -f1)"
      while IFS=$'\t' read -r c _ _ pts; do
        [[ -n "${c}" ]] && echo -e "       - ${c} (${pts} Punkte)"
      done < "${BACKUP_DIR}/${s}/manifest.tsv"
      i=$((i + 1))
    done
  fi
  local n
  n=$(find "${BACKUP_DIR}" -maxdepth 1 -name 'qdrant-update_*.tar.gz' -type f 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${n}" -gt 0 ]]; then
    echo ""
    info "Ausserdem ${n} Update-Backup(s) (qdrant-update_*.tar.gz) des Update-Scripts -"
    info "die werden komplett zurueckgespielt, siehe Rollback-Hinweis von update-qdrant.sh."
  fi
}

# =============================================================================
# Restore
# =============================================================================
do_restore() {
  echo ""
  echo "------------------------------------------------------------"
  echo -e "${BOLD} Backup zurueckspielen${RESET}"
  echo "------------------------------------------------------------"
  local -a sets=()
  mapfile -t sets < <(list_sets)
  [[ "${#sets[@]}" -gt 0 ]] || die "Keine Backup-Saetze in ${BACKUP_DIR} gefunden."

  local set_name="${RESTORE_SET}" choice
  if [[ -z "${set_name}" ]]; then
    [[ "${INTERACTIVE}" -eq 1 && "${ASSUME_YES:-0}" != "1" ]] \
      || die "Ohne Terminal bitte den Backup-Satz angeben: --restore <satz> (siehe --list)."
    do_list
    echo ""
    echo -ne "${BOLD}Welcher Backup-Satz?${RESET} [${CYAN}1${RESET}]: "
    read -r choice <"${TTY}" || true
    choice="${choice:-1}"
    { [[ "${choice}" =~ ^[0-9]+$ ]] && [[ "${choice}" -ge 1 ]] && [[ "${choice}" -le "${#sets[@]}" ]]; } \
      || die "Ungueltige Auswahl: ${choice}"
    set_name="${sets[$((choice - 1))]}"
  fi
  set_name="$(basename "${set_name}")"
  local set_dir="${BACKUP_DIR}/${set_name}"
  [[ -f "${set_dir}/manifest.tsv" && -f "${set_dir}/info.txt" ]] \
    || die "Kein gueltiger Backup-Satz: ${set_dir} (manifest.tsv/info.txt fehlen)."

  connect

  # Versions-Kompatibilitaet: gleiche oder naechste Minor-Version.
  local bver
  bver="$(set_info "${set_name}" QDRANT_VERSION)"
  [[ "${bver}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Version des Backup-Satzes unbekannt (${bver:-leer})."
  local dmin=$(( $(minor_of "${QVERSION}") - $(minor_of "${bver}") ))
  if [[ "$(major_of "${QVERSION}")" != "$(major_of "${bver}")" ]] || [[ "${dmin}" -lt 0 || "${dmin}" -gt 1 ]] \
     || { [[ "${dmin}" -eq 0 ]] && [[ "$(printf '%s\n%s\n' "${bver#v}" "${QVERSION#v}" | sort -V | head -n 1)" != "${bver#v}" ]]; }; then
    die "Backup-Satz von Qdrant ${bver} passt nicht zur laufenden Version ${QVERSION}.\n  Qdrant spielt Snapshots nur auf derselben oder der naechsten Minor-Version zurueck\n  (Snapshot ${bver} -> ${bver%.*}.x ab ${bver} oder v$(major_of "${bver}").$(( $(minor_of "${bver}") + 1 )).x).\n  Quelle: ${SNAPSHOT_DOC}"
  fi
  success "Version passt: Backup ${bver} -> laufend ${QVERSION}."

  # Inhalt des Satzes einlesen
  local -a s_coll=() s_file=() s_sum=() s_pts=()
  local c f s p
  while IFS=$'\t' read -r c f s p; do
    [[ -n "${c}" ]] || continue
    s_coll+=("${c}"); s_file+=("${f}"); s_sum+=("${s}"); s_pts+=("${p}")
  done < "${set_dir}/manifest.tsv"
  [[ "${#s_coll[@]}" -gt 0 ]] || die "Der Backup-Satz enthaelt keine Collections."

  # Auswahl
  local -a pick=()
  local i input
  if [[ "${#SEL_COLLECTIONS[@]}" -gt 0 ]]; then
    for c in "${SEL_COLLECTIONS[@]}"; do
      local hit=-1
      for i in "${!s_coll[@]}"; do [[ "${s_coll[$i]}" == "${c}" ]] && hit="${i}"; done
      [[ "${hit}" -ge 0 ]] || die "Collection '${c}' ist nicht im Backup-Satz ${set_name}. Enthalten: ${s_coll[*]}"
      pick+=("${hit}")
    done
  else
    info "Im Backup-Satz ${set_name}:"
    for i in "${!s_coll[@]}"; do
      echo -e "   $((i + 1))) ${CYAN}${s_coll[$i]}${RESET} (${s_pts[$i]} Punkte)"
    done
    if [[ "${#s_coll[@]}" -eq 1 ]] || ask_yesno "Alle ${#s_coll[@]} Collections zurueckspielen?" "j"; then
      pick=("${!s_coll[@]}")
    else
      [[ "${INTERACTIVE}" -eq 1 ]] || die "Ohne Terminal bitte --collection <name> angeben."
      echo ""
      echo -ne "${BOLD}Welche Nummern? (durch Komma getrennt)${RESET}: "
      read -r input <"${TTY}" || true
      local -a nums=()
      IFS=',' read -r -a nums <<<"${input// /}"
      for i in "${nums[@]}"; do
        { [[ "${i}" =~ ^[0-9]+$ ]] && [[ "${i}" -ge 1 ]] && [[ "${i}" -le "${#s_coll[@]}" ]]; } || die "Ungueltige Nummer: ${i}"
        pick+=("$((i - 1))")
      done
      [[ "${#pick[@]}" -gt 0 ]] || die "Keine Collection ausgewaehlt."
    fi
  fi

  mapfile -t EXISTING < <(list_collections)

  # Pruefsummen vorab - ein beschaedigter Satz soll scheitern, bevor etwas
  # ueberschrieben wird.
  for i in "${pick[@]}"; do
    [[ -f "${set_dir}/${s_file[$i]}" ]] || die "Datei fehlt im Backup-Satz: ${s_file[$i]}"
    [[ "$(sha256sum "${set_dir}/${s_file[$i]}" | cut -d' ' -f1)" == "${s_sum[$i]}" ]] \
      || die "Pruefsumme von ${s_file[$i]} stimmt nicht - Backup-Satz beschaedigt. Es wurde nichts veraendert."
  done
  success "Pruefsummen der ausgewaehlten Snapshots in Ordnung."

  local -a overwrite=()
  echo ""
  echo -e " ${BOLD}Es wird zurueckgespielt:${RESET}"
  for i in "${pick[@]}"; do
    c="${s_coll[$i]}"
    if collection_exists "${c}"; then
      overwrite+=("${c}")
      echo -e "   - ${CYAN}${c}${RESET}: ${RED}UEBERSCHREIBT${RESET} die bestehende Collection ($(points_of "${c}") Punkte jetzt -> ${s_pts[$i]} Punkte aus dem Backup)"
    else
      echo -e "   - ${CYAN}${c}${RESET}: wird neu angelegt (${s_pts[$i]} Punkte)"
    fi
  done

  # Aliase des Satzes, die auf ausgewaehlte Collections zeigen
  local -a al_name=() al_coll=()
  local pair a ac
  while IFS= read -r pair; do
    a="$(printf '%s' "${pair}" | sed -E 's/.*"alias_name": *"([^"]*)".*/\1/')"
    ac="$(printf '%s' "${pair}" | sed -E 's/.*"collection_name": *"([^"]*)".*/\1/')"
    for i in "${pick[@]}"; do
      if [[ "${s_coll[$i]}" == "${ac}" ]]; then al_name+=("${a}"); al_coll+=("${ac}"); fi
    done
  done < <(grep -oE '\{"alias_name": *"[^"]*", *"collection_name": *"[^"]*"\}' "${set_dir}/aliases.json" 2>/dev/null || true)

  # Rueckfragen - jede einzeln
  local safety=0 restore_aliases=0
  if [[ "${#overwrite[@]}" -gt 0 ]]; then
    echo ""
    info "Vor dem Ueberschreiben kann der aktuelle Stand dieser Collections gesichert"
    info "werden: ${overwrite[*]}"
    if ask_yesno "Aktuellen Stand vorher sichern (empfohlen)?" "j"; then safety=1; fi
  fi
  if [[ "${#al_name[@]}" -gt 0 ]]; then
    echo ""
    info "Gesicherte Aliase: $(for i in "${!al_name[@]}"; do printf '%s -> %s  ' "${al_name[$i]}" "${al_coll[$i]}"; done)"
    if ask_yesno "Aliase ebenfalls wiederherstellen (bestehende gleichnamige werden umgehaengt)?" "j"; then restore_aliases=1; fi
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo ""
    [[ "${safety}" -eq 1 ]] && echo -e "${YELLOW}   [DRY-RUN]${RESET} Sicherheits-Backup von: ${overwrite[*]}"
    for i in "${pick[@]}"; do
      echo -e "${YELLOW}   [DRY-RUN]${RESET} Upload ${s_file[$i]} -> /collections/${s_coll[$i]}/snapshots/upload?priority=snapshot"
    done
    [[ "${restore_aliases}" -eq 1 ]] && echo -e "${YELLOW}   [DRY-RUN]${RESET} Aliase: ${al_name[*]}"
    echo ""
    echo -e "${YELLOW}${BOLD} DRY-RUN beendet - es wurde nichts veraendert.${RESET}"
    return 0
  fi

  echo ""
  echo "------------------------------------------------------------"
  if [[ "${#overwrite[@]}" -gt 0 ]]; then
    ask_yesno "${RED}${BOLD}Wirklich zurueckspielen? ${#overwrite[@]} bestehende Collection(s) werden unwiderruflich ueberschrieben.${RESET}" "n" \
      || { warn "Abgebrochen. Es wurde nichts veraendert."; return 0; }
  else
    ask_yesno "${BOLD}Jetzt zurueckspielen?${RESET}" "n" || { warn "Abgebrochen. Es wurde nichts veraendert."; return 0; }
  fi

  echo ""
  if [[ "${safety}" -eq 1 ]]; then
    local safety_dir
    safety_dir="${BACKUP_DIR}/snapshots_$(date +%F_%H-%M-%S)_vor-restore"
    info "Sichere den aktuellen Stand nach ${safety_dir}..."
    create_set "${safety_dir}" "${overwrite[@]}"
    success "Sicherheits-Backup erstellt (wird bei der Rotation wie jeder andere Satz behandelt)."
    echo ""
  fi

  local up resp got errors=0 leftover
  for i in "${pick[@]}"; do
    c="${s_coll[$i]}"
    up="restore-$(date +%s)-$(safe_name "${c}").snapshot"
    info "Spiele '${c}' zurueck (das kann bei grossen Collections dauern)..."
    # Hochladen unter eindeutigem Namen, damit die Kopie danach gezielt
    # aus dem Qdrant-Arbeitsordner entfernt werden kann.
    if ! resp="$(api POST "/collections/$(urlencode "${c}")/snapshots/upload?priority=snapshot&wait=true&checksum=${s_sum[$i]}" \
                   -F "snapshot=@${set_dir}/${s_file[$i]};filename=${up}")"; then
      error "Zurueckspielen von '${c}' fehlgeschlagen."
      errors=1
      continue
    fi
    if ! printf '%s' "${resp}" | grep -q '"result": *true'; then
      error "Unerwartete Antwort fuer '${c}': ${resp}"
      errors=1
      continue
    fi
    leftover="$(api GET "/collections/$(urlencode "${c}")/snapshots" --max-time 30 2>/dev/null | grep -oE "\"name\": *\"${up}\"" || true)"
    if [[ -n "${leftover}" ]]; then
      api DELETE "/collections/$(urlencode "${c}")/snapshots/$(urlencode "${up}")?wait=true" >/dev/null 2>&1 || true
    fi
    got="$(points_of "${c}")"
    if [[ "${got}" == "${s_pts[$i]}" || "${s_pts[$i]}" == "?" ]]; then
      success "'${c}' zurueckgespielt: ${got} Punkte."
    else
      warn "'${c}' zurueckgespielt, aber ${got} statt ${s_pts[$i]} Punkte - bitte pruefen."
      errors=1
    fi
  done

  if [[ "${restore_aliases}" -eq 1 ]]; then
    local actions=""
    for i in "${!al_name[@]}"; do
      [[ -n "${actions}" ]] && actions+=","
      actions+="{\"create_alias\":{\"collection_name\":\"$(json_escape "${al_coll[$i]}")\",\"alias_name\":\"$(json_escape "${al_name[$i]}")\"}}"
    done
    if api POST /collections/aliases -H 'Content-Type: application/json' -d "{\"actions\":[${actions}]}" >/dev/null; then
      success "Aliase wiederhergestellt: ${al_name[*]}"
    else
      error "Aliase konnten nicht wiederhergestellt werden."
      errors=1
    fi
  fi

  echo ""
  echo "------------------------------------------------------------"
  if [[ "${errors}" -eq 0 ]]; then
    echo -e "${GREEN}${BOLD} Restore abgeschlossen.${RESET}  $(date '+%F %T')"
  else
    echo -e "${YELLOW}${BOLD} Restore mit Fehlern beendet - siehe oben.${RESET}"
  fi
  echo "------------------------------------------------------------"
  echo -e " Laufende n8n-Workflows greifen sofort auf den zurueckgespielten Stand zu."
  echo ""
  return "${errors}"
}

# -- Logging -------------------------------------------------------------------
if [[ "${DRY_RUN}" -eq 0 && "${MODE}" != "list" ]]; then
  if touch "${LOG}" 2>/dev/null; then
    exec > >(tee -a "${LOG}") 2>&1
  else
    warn "Logdatei ${LOG} nicht beschreibbar - Ausgabe nur auf der Konsole."
  fi
fi

# -- Modus ---------------------------------------------------------------------
if [[ -z "${MODE}" ]]; then
  [[ "${INTERACTIVE}" -eq 1 ]] || die "Ohne Terminal bitte einen Modus angeben: --backup, --restore <satz> oder --list (siehe --help)."
  echo ""
  echo -e " ${BOLD}1)${RESET} Backup erstellen"
  echo -e " ${BOLD}2)${RESET} Backup zurueckspielen"
  echo -e " ${BOLD}3)${RESET} Backups anzeigen"
  echo -e " ${BOLD}4)${RESET} Beenden"
  echo ""
  echo -ne "${BOLD}Auswahl${RESET} [${CYAN}1${RESET}]: "
  read -r choice <"${TTY}" || true
  case "${choice:-1}" in
    1) MODE="backup" ;;
    2) MODE="restore" ;;
    3) MODE="list" ;;
    *) exit 0 ;;
  esac
fi

case "${MODE}" in
  backup)  do_backup ;;
  restore) do_restore ;;
  list)    do_list ;;
esac
echo ""
echo -e " Mehr Tipps & Tutorials: ${CYAN}${BLOG_URL}${RESET}"
echo ""
