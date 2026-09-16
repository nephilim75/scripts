#!/usr/bin/env bash
# =============================================================================
# LibreCodeInterpreter Update Script - powered by pc-fee.com
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Aktualisiert eine mit install-librecodeinterpreter.sh installierte Instanz.
# Ablauf auf dem Bildschirm:
#   1. Zusammenfassung - wo liegt die Installation, was ist geplant
#   2. Pruefung auf Neuerungen (git fetch + compose pull) - der laufende Stack
#      bleibt dabei unberuehrt
#   3. Aktueller Stand und zukuenftiger Stand mit Versionen je Komponente
#   4. Rueckfragen: Anzahl aufzubewahrender Backups, dann die Bestaetigung
#   5. Durchfuehrung: Backup der Konfiguration, merge --ff-only,
#      Compose-Validierung, Stack neu hochfahren, aufraeumen
#
# Ohne Bestaetigung wird nichts veraendert. Fuer Cron: --yes bzw. ASSUME_YES=1.
#
# Nutzung als 1-Zeiler (von ueberall, kein vorheriger Download noetig):
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/usnavy13/update/update-librecodeinterpreter.sh)"
#
# Optionen:
#   --dir <pfad>   Installationspfad fest vorgeben (ueberspringt die Erkennung)
#   --keep <n>     Anzahl aufzubewahrender Backups - ohne Angabe wird gefragt
#   --dry-run      Zeigt nur, was passieren wuerde - aendert nichts
#   --yes          Ueberspringt die Rueckfragen (wie ASSUME_YES=1, fuer Cron)
#   --help         Diese Hilfe anzeigen
#
# Umgebungsvariablen (fuer unbeaufsichtigten Betrieb, z.B. Cron):
#   INSTALL_DIR    wie --dir
#   KEEP_BACKUPS   wie --keep
#   ASSUME_YES=1   wie --yes
#   LOG_FILE       Logdatei (Default: /var/log/librecodeinterpreter-update.log)
#
# Der Installationspfad wird automatisch ermittelt (Container-Label ->
# Bind-Mount-Quelle -> /opt/LibreCodeInterpreter). Nur wenn mehrere Installationen
# gefunden werden, fragt das Script nach.
#
# Voraussetzungen: root (bzw. sudo), Docker + Docker Compose, git, tar.
#
# AI Transparency: Dieses Script wurde mit Unterstuetzung von KI erstellt und
# vor Veroeffentlichung geprueft. Nutzung auf eigene Gefahr.
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
readonly LCI_GUIDE="https://github.com/nephilim75/scripts/tree/main/librechat/codeInterpreter/usnavy13"
readonly DEFAULT_DIR="/opt/LibreCodeInterpreter"
# Marker, an dem eine Compose-Datei als LibreCodeInterpreter-Stack erkannt wird.
readonly IMAGE_MARKER="usnavy13/LibreCodeInterpreter"
readonly BACKUP_PREFIX="librecodeinterpreter"
readonly DEFAULT_KEEP=5

# -- Optionen ------------------------------------------------------------------
DRY_RUN=0
KEEP=""
KEEP_EXPLICIT=0
LOG="${LOG_FILE:-/var/log/librecodeinterpreter-update.log}"

if [[ -n "${KEEP_BACKUPS:-}" ]]; then
  KEEP="${KEEP_BACKUPS}"
  KEEP_EXPLICIT=1
fi

usage() {
  cat <<'USAGE'
LibreCodeInterpreter Update Script - powered by pc-fee.com

Aktualisiert eine mit install-librecodeinterpreter.sh installierte Instanz.
Zeigt erst eine Zusammenfassung, danach den aktuellen und den zukuenftigen
Stand mit Versionen je Komponente, und fragt dann nach - vorher wird nichts
veraendert.

Optionen:
  --dir <pfad>   Installationspfad fest vorgeben (ueberspringt die Erkennung)
  --keep <n>     Anzahl aufzubewahrender Backups - ohne Angabe wird gefragt
  --dry-run      Zeigt nur, was passieren wuerde - aendert nichts
  --yes          Ueberspringt die Rueckfragen (wie ASSUME_YES=1, fuer Cron)
  --help         Diese Hilfe anzeigen

Umgebungsvariablen: INSTALL_DIR, KEEP_BACKUPS, ASSUME_YES, LOG_FILE

Beispiele:
  sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/usnavy13/update/update-librecodeinterpreter.sh)"
  sudo ./update-librecodeinterpreter.sh --dry-run
  sudo ./update-librecodeinterpreter.sh --dir /srv/LibreCodeInterpreter --keep 10
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)     INSTALL_DIR="${2:-}"; shift 2 || true ;;
    --dir=*)   INSTALL_DIR="${1#*=}"; shift ;;
    --keep)    KEEP="${2:-}"; KEEP_EXPLICIT=1; shift 2 || true ;;
    --keep=*)  KEEP="${1#*=}"; KEEP_EXPLICIT=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y)  ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         echo "Unbekannte Option: $1 (siehe --help)" >&2; exit 1 ;;
  esac
done
readonly DRY_RUN KEEP_EXPLICIT

if [[ "${KEEP_EXPLICIT}" -eq 1 ]]; then
  if ! [[ "${KEEP}" =~ ^[0-9]+$ ]] || [[ "${KEEP}" -lt 1 ]]; then
    echo "--keep erwartet eine positive Ganzzahl (erhalten: '${KEEP}')." >&2
    exit 1
  fi
fi

# -- Eingabequelle -------------------------------------------------------------
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

ask_number() {
  local prompt="$1" default="$2" input=""
  if [[ "${INTERACTIVE}" -eq 0 || "${ASSUME_YES:-0}" == "1" ]]; then
    printf '%s' "${default}"
    return 0
  fi
  while :; do
    echo "" >&2
    echo -ne "${BOLD}${prompt}${RESET} [${CYAN}${default}${RESET}]: " >&2
    read -r input <"${TTY}" || true
    input="${input:-${default}}"
    if [[ "${input}" =~ ^[0-9]+$ ]] && [[ "${input}" -ge 1 ]]; then
      printf '%s' "${input}"
      return 0
    fi
    echo -e "${YELLOW}[WARN]${RESET}  Bitte eine ganze Zahl ab 1 eingeben." >&2
  done
}

run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo -e "${YELLOW}   [DRY-RUN]${RESET} $*"
  else
    "$@"
  fi
}

# -- Banner --------------------------------------------------------------------
clear 2>/dev/null || true
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
printf '%b\n' "${BOLD} LibreCodeInterpreter Update - powered by pc-fee.com${RESET}"
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

command -v tar &>/dev/null || die "'tar' nicht gefunden - wird fuer das Backup gebraucht."

HAVE_GIT=1
command -v git &>/dev/null || HAVE_GIT=0

# -- Installationspfad ermitteln -----------------------------------------------
compose_file_of() {
  local d="$1" f
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    if [[ -f "${d}/${f}" ]] && grep -qi "${IMAGE_MARKER}" "${d}/${f}"; then
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
    d=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/.env"}}{{.Source}}{{end}}{{end}}' "${cid}" 2>/dev/null || true)
    [[ -n "${d}" && "${d}" == /* ]] && raw+=("$(dirname "${d}")")
  done < <(docker ps -a --format '{{.ID}} {{.Image}}' | awk -v img="${IMAGE_MARKER}" 'index($2, img) {print $1}')

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
  [[ -d "${INSTALL_DIR}" ]] || die "Angegebener Pfad existiert nicht: ${INSTALL_DIR}"
  compose_file_of "${INSTALL_DIR}" >/dev/null \
    || die "In ${INSTALL_DIR} liegt keine Compose-Datei mit einem ${IMAGE_MARKER}-Image."
else
  mapfile -t FOUND < <(detect_dirs)
  case "${#FOUND[@]}" in
    0)
      die "Keine LibreCodeInterpreter-Installation gefunden.\n  Erwartet wurde eine Compose-Datei mit ${IMAGE_MARKER}-Image,\n  z.B. unter ${DEFAULT_DIR}.\n  Pfad ggf. direkt angeben: --dir /pfad/zur/installation"
      ;;
    1)
      INSTALL_DIR="${FOUND[0]}"
      ;;
    *)
      echo ""
      warn "Mehrere LibreCodeInterpreter-Installationen gefunden:"
      for i in "${!FOUND[@]}"; do
        echo -e "   ${BOLD}$((i + 1)))${RESET} ${CYAN}${FOUND[$i]}${RESET}"
      done
      [[ "${INTERACTIVE}" -eq 1 ]] \
        || die "Kein Terminal fuer die Rueckfrage verfuegbar. Bitte --dir <pfad> setzen (z.B. im Cron-Eintrag)."
      choice=""
      echo ""
      echo -ne "${BOLD}Welche soll aktualisiert werden?${RESET} [${CYAN}1${RESET}]: "
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
BACKUP_DIR="${INSTALL_DIR}/backups"
readonly BACKUP_DIR

dc() { ( cd "${INSTALL_DIR}" && ${COMPOSE_CMD} "$@" ); }

dc_run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo -e "${YELLOW}   [DRY-RUN]${RESET} (cd ${INSTALL_DIR} && ${COMPOSE_CMD} $*)"
  else
    dc "$@"
  fi
}

# -- Logging -------------------------------------------------------------------
LOG_ACTIVE=0
if [[ "${DRY_RUN}" -eq 0 ]]; then
  if ! touch "${LOG}" 2>/dev/null; then
    warn "Logdatei ${LOG} nicht beschreibbar - Ausgabe nur auf der Konsole."
  else
    exec > >(tee -a "${LOG}") 2>&1
    LOG_ACTIVE=1
  fi
fi
readonly LOG_ACTIVE

# -- Daten fuer die Zusammenfassung sammeln ------------------------------------
CONTAINERS_TOTAL=0
CONTAINERS_RUNNING=0
while IFS= read -r line; do
  [[ -n "${line}" ]] || continue
  CONTAINERS_TOTAL=$((CONTAINERS_TOTAL + 1))
  [[ "${line}" == *running* ]] && CONTAINERS_RUNNING=$((CONTAINERS_RUNNING + 1))
done < <(dc ps -a --format '{{.Service}} {{.State}}' 2>/dev/null || true)

declare -a CONFIG_ITEMS=()
for item in .env docker-compose.override.yml librechat.yaml; do
  [[ -e "${INSTALL_DIR}/${item}" ]] && CONFIG_ITEMS+=("${item}")
done

BACKUP_COUNT=0
if [[ -d "${BACKUP_DIR}" ]]; then
  BACKUP_COUNT=$(find "${BACKUP_DIR}" -maxdepth 1 -name "${BACKUP_PREFIX}_*.tar.gz" -type f 2>/dev/null | wc -l | tr -d ' ')
fi

GIT_OK=0
GIT_BRANCH=""
GIT_OLD=""
GIT_OLD_DATE=""
GIT_DIRTY=""
if [[ "${HAVE_GIT}" -eq 1 && -d "${INSTALL_DIR}/.git" ]]; then
  GIT_OK=1
  GIT_BRANCH="$(git -C "${INSTALL_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
  [[ "${GIT_BRANCH}" == "HEAD" ]] && GIT_BRANCH="main"
  GIT_OLD="$(git -C "${INSTALL_DIR}" rev-parse HEAD 2>/dev/null || true)"
  GIT_OLD_DATE="$(git -C "${INSTALL_DIR}" log -1 --format=%cd --date=short 2>/dev/null || true)"
  GIT_DIRTY="$(git -C "${INSTALL_DIR}" status --porcelain --untracked-files=no 2>/dev/null || true)"
fi

# -- 1. Zusammenfassung --------------------------------------------------------
echo ""
echo "============================================================"
echo -e "${BOLD} ZUSAMMENFASSUNG${RESET}   $(date '+%F %T')"
echo "============================================================"
printf ' %-16s %s\n' "Installation:" "${INSTALL_DIR}"
printf ' %-16s %s\n' "Compose-Datei:" "$(basename "${COMPOSE_FILE}")$( [[ -f "${INSTALL_DIR}/docker-compose.override.yml" ]] && echo " + docker-compose.override.yml" )"
if [[ "${CONTAINERS_TOTAL}" -gt 0 ]]; then
  printf ' %-16s %s\n' "Container:" "${CONTAINERS_TOTAL} (davon ${CONTAINERS_RUNNING} laufend)"
else
  printf ' %-16s %s\n' "Container:" "keine gefunden - gestoppt oder entfernt?"
fi
if [[ "${GIT_OK}" -eq 1 ]]; then
  printf ' %-16s %s\n' "Repository:" "Branch ${GIT_BRANCH}, Stand ${GIT_OLD:0:7} vom ${GIT_OLD_DATE:-unbekannt}"
elif [[ "${HAVE_GIT}" -eq 0 ]]; then
  printf ' %-16s %s\n' "Repository:" "git nicht installiert - nur Images werden aktualisiert"
else
  printf ' %-16s %s\n' "Repository:" "kein Git-Repository - nur Images werden aktualisiert"
fi
printf ' %-16s %s\n' "Konfiguration:" "${CONFIG_ITEMS[*]:-keine der erwarteten Dateien gefunden}"
printf ' %-16s %s\n' "Backups:" "${BACKUP_COUNT} vorhanden in ${BACKUP_DIR}"
[[ "${LOG_ACTIVE}" -eq 1 ]] && printf ' %-16s %s\n' "Logdatei:" "${LOG}"

echo ""
echo -e " ${BOLD}Geplante Schritte${RESET}"
echo "   1. Auf Neuerungen pruefen (Repository und Images) - ohne Eingriff"
echo "   2. Backup: ${CONFIG_ITEMS[*]:-Konfiguration}"
echo "   3. Repository per 'git merge --ff-only' aktualisieren"
echo "   4. Compose-Konfiguration pruefen und den Stack neu hochfahren"
echo "   5. Alte Backups entfernen, dangling Images aufraeumen"

if [[ -n "${GIT_DIRTY}" ]]; then
  echo ""
  warn "Lokal geaenderte, versionierte Dateien im Repository:"
  while IFS= read -r l; do [[ -n "$l" ]] && echo -e "   ${YELLOW}${l}${RESET}"; done <<<"${GIT_DIRTY}"
  warn "Schritt 3 entfaellt deshalb - es werden nur die Images aktualisiert."
  warn "Aufloesen mit: git -C ${INSTALL_DIR} checkout -- <datei>   (verwirft die Aenderung)"
fi

echo ""
echo -e " ${BOLD}Bis zur Rueckfrage wird nichts veraendert.${RESET}"

# -- 2. Auf Neuerungen pruefen -------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Pruefe auf Neuerungen${RESET}"
echo "------------------------------------------------------------"

mapfile -t IMAGES_NOW < <(dc config --images 2>/dev/null | sort -u || true)
[[ "${#IMAGES_NOW[@]}" -gt 0 ]] || die "Konnte die Image-Liste nicht aus der Compose-Config lesen. Stimmen .env und Override-Datei?"

declare -A OLD_IDS=()
for img in "${IMAGES_NOW[@]}"; do
  OLD_IDS["${img}"]="$(docker image inspect "${img}" -f '{{.Id}}' 2>/dev/null || true)"
done

GIT_NEW=""
GIT_NEW_DATE=""
GIT_CHANGED=0
if [[ "${GIT_OK}" -eq 1 && -z "${GIT_DIRTY}" ]]; then
  info "Repository (git fetch)..."
  if [[ "$(git -C "${INSTALL_DIR}" rev-parse --is-shallow-repository 2>/dev/null || echo false)" == "true" ]]; then
    run git -C "${INSTALL_DIR}" fetch --depth=1 origin "${GIT_BRANCH}"
  else
    run git -C "${INSTALL_DIR}" fetch origin "${GIT_BRANCH}"
  fi
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    GIT_NEW="$(git -C "${INSTALL_DIR}" rev-parse FETCH_HEAD 2>/dev/null || true)"
    GIT_NEW_DATE="$(git -C "${INSTALL_DIR}" log -1 --format=%cd --date=short FETCH_HEAD 2>/dev/null || true)"
    [[ -n "${GIT_NEW}" && "${GIT_NEW}" != "${GIT_OLD}" ]] && GIT_CHANGED=1
  fi
fi

info "Images (${COMPOSE_CMD} pull) - es werden nur Layer geladen..."
dc_run pull

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo "------------------------------------------------------------"
  echo -e "${YELLOW}${BOLD} DRY-RUN beendet - es wurde nichts veraendert.${RESET}"
  echo "------------------------------------------------------------"
  echo -e " Ob es Neuerungen gibt, laesst sich ohne Fetch und Pull nicht"
  echo -e " feststellen - beides wurde uebersprungen, deshalb entfaellt hier"
  echo -e " auch die Gegenueberstellung der Versionen."
  echo ""
  exit 0
fi

declare -A NEW_IDS=()
IMAGES_CHANGED=0
for img in "${IMAGES_NOW[@]}"; do
  NEW_IDS["${img}"]="$(docker image inspect "${img}" -f '{{.Id}}' 2>/dev/null || true)"
  [[ -n "${NEW_IDS[${img}]}" ]] || die "Image ${img} ist nach dem Pull nicht lokal vorhanden."
  [[ "${OLD_IDS[${img}]}" != "${NEW_IDS[${img}]}" ]] && IMAGES_CHANGED=1
done

mapfile -t IMAGES_NEXT < <(
  if [[ "${GIT_CHANGED}" -eq 1 ]]; then
    git -C "${INSTALL_DIR}" show "FETCH_HEAD:$(basename "${COMPOSE_FILE}")" 2>/dev/null \
      | sed -n 's/^[[:space:]]*image:[[:space:]]*["'"'"']\{0,1\}\([^"'"'"'[:space:]]*\)["'"'"']\{0,1\}.*/\1/p' | sort -u
  fi
)
[[ "${#IMAGES_NEXT[@]}" -gt 0 ]] || IMAGES_NEXT=("${IMAGES_NOW[@]}")

# -- 3. Aktueller und zukuenftiger Stand ---------------------------------------
component_of() {
  case "$1" in
    *librecodeinterpreter*) echo "01 LibreCodeInterpreter" ;;
    *redis*)                echo "02 Redis" ;;
    *garage*)               echo "03 Garage" ;;
    *)                      echo "20 ${1##*/}" ;;
  esac
}

tag_of() {
  local ref="$1" tail="${1##*:}"
  [[ "${ref}" == *:* && "${tail}" != */* ]] && printf '%s' "${tail}" || printf 'latest'
}

declare -A COMP_NOW=() COMP_NEXT=()
declare -a COMP_KEYS=()
for img in "${IMAGES_NOW[@]}";  do key="$(component_of "${img}")"; COMP_NOW["${key}"]="${img}";  done
for img in "${IMAGES_NEXT[@]}"; do key="$(component_of "${img}")"; COMP_NEXT["${key}"]="${img}"; done
while IFS= read -r key; do COMP_KEYS+=("${key}"); done < <(
  printf '%s\n' "${!COMP_NOW[@]}" "${!COMP_NEXT[@]}" | sort -u
)

echo ""
echo "============================================================"
echo -e "${BOLD} AKTUELLER STAND  ->  ZUKUENFTIGER STAND${RESET}"
echo "============================================================"
printf ' %-22s %-24s %-24s\n' "Komponente" "JETZT" "NACHHER"
printf ' %-22s %-24s %-24s\n' "----------------------" "------------------------" "------------------------"

for key in "${COMP_KEYS[@]}"; do
  name="${key#* }"
  img_now="${COMP_NOW[${key}]:-}"
  img_next="${COMP_NEXT[${key}]:-${img_now}}"
  [[ -n "${img_now}" ]] || img_now="${img_next}"

  if [[ "${name}" == "LibreCodeInterpreter" ]]; then
    ver_now="$(tag_of "${img_now}") (${GIT_OLD:0:7})"
    ver_next="$(tag_of "${img_next}") ($( [[ "${GIT_CHANGED}" -eq 1 ]] && echo "${GIT_NEW:0:7}" || echo "${GIT_OLD:0:7}" ))"
  else
    ver_now="$(tag_of "${img_now}")"
    ver_next="$(tag_of "${img_next}")"
    if [[ "${img_now}" == "${img_next}" && -n "${OLD_IDS[${img_now}]:-}" \
          && "${OLD_IDS[${img_now}]:-}" != "${NEW_IDS[${img_now}]:-}" ]]; then
      ver_now="${ver_now} (${OLD_IDS[${img_now}]:7:8})"
      ver_next="${ver_next} (${NEW_IDS[${img_now}]:7:8})"
    fi
  fi

  changed=0
  [[ "${ver_now}" != "${ver_next}" ]] && changed=1
  [[ "${img_now}" != "${img_next}" ]] && changed=1
  if [[ "${changed}" -eq 1 ]]; then
    printf ' %-22s %-24s %b%-24s%b %b\n' "${name}" "${ver_now}" "${GREEN}" "${ver_next}" "${RESET}" "${GREEN}<- neu${RESET}"
  else
    printf ' %-22s %-24s %-24s\n' "${name}" "${ver_now}" "${ver_next}"
  fi
done

echo ""
if [[ "${GIT_OK}" -eq 1 ]]; then
  if [[ "${GIT_CHANGED}" -eq 1 ]]; then
    echo -e " Repository:  ${GIT_OLD:0:7} (${GIT_OLD_DATE:-unbekannt})  ->  ${GREEN}${GIT_NEW:0:7} (${GIT_NEW_DATE:-unbekannt})${RESET}"
  elif [[ -n "${GIT_DIRTY}" ]]; then
    echo -e " Repository:  ${GIT_OLD:0:7} - ${YELLOW}Update uebersprungen (lokale Aenderungen)${RESET}"
  else
    echo -e " Repository:  ${GIT_OLD:0:7} (${GIT_OLD_DATE:-unbekannt}) - unveraendert"
  fi
fi

if [[ "${GIT_CHANGED}" -eq 0 && "${IMAGES_CHANGED}" -eq 0 ]]; then
  echo ""
  echo "------------------------------------------------------------"
  success "NOCHANGE: bereits aktuell - kein Backup, kein Neustart, keine Aenderung."
  echo "------------------------------------------------------------"
  echo ""
  exit 0
fi

# -- 4. Rueckfragen ------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Rueckfragen${RESET}"
echo "------------------------------------------------------------"

if [[ "${KEEP_EXPLICIT}" -eq 1 ]]; then
  info "Aufzubewahrende Backups: ${KEEP} (per --keep bzw. KEEP_BACKUPS vorgegeben)."
else
  KEEP="$(ask_number "Wie viele Backups sollen aufbewahrt werden?" "${DEFAULT_KEEP}")"
  if [[ "${INTERACTIVE}" -eq 0 || "${ASSUME_YES:-0}" == "1" ]]; then
    info "Keine Rueckfrage moeglich - es werden ${KEEP} Backups aufbewahrt (mit --keep aenderbar)."
  fi
fi
readonly KEEP

TS=$(date +%F_%H-%M-%S)
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_PREFIX}_${TS}.tar.gz"
mapfile -t DROP_BACKUPS < <(ls -1t "${BACKUP_DIR}"/${BACKUP_PREFIX}_*.tar.gz 2>/dev/null | tail -n "+${KEEP}" || true)

echo ""
echo -e " ${BOLD}Es wird jetzt:${RESET}"
if [[ "${#CONFIG_ITEMS[@]}" -gt 0 ]]; then
  echo -ne "   1. gesichert nach ${CYAN}$(basename "${BACKUP_FILE}")${RESET}: "
  echo -n "${CONFIG_ITEMS[*]}"
  echo ""
else
  echo -e "   1. ${YELLOW}kein Backup erstellt${RESET} (keine Konfiguration gefunden)"
fi
if [[ "${GIT_CHANGED}" -eq 1 ]]; then
  echo -e "   2. das Repository per ${CYAN}merge --ff-only${RESET} auf ${GIT_NEW:0:7} gebracht"
else
  echo -e "   2. das Repository nicht angefasst"
fi
echo -e "   3. die Compose-Konfiguration validiert und der Stack neu hochgefahren"
echo -e "      - kurze Downtime, je nach Host meist unter einer Minute"
if [[ "${#DROP_BACKUPS[@]}" -gt 0 ]]; then
  echo -e "   4. ${#DROP_BACKUPS[@]} alte(s) Backup(s) entfernt, aeltestes: ${CYAN}$(basename "${DROP_BACKUPS[-1]}")${RESET}"
else
  echo -e "   4. kein altes Backup entfernt (${BACKUP_COUNT} von ${KEEP} belegt)"
fi
echo -e "   5. dangling Images auf diesem Host aufgeraeumt"
echo ""
echo -e " ${BOLD}Unveraendert bleibt:${RESET} .env, docker-compose.override.yml und die"
echo -e " eventuelle librechat.yaml (stehen im Installationsverzeichnis), sowie das"
echo -e " Docker-Netzwerk mit allen anderen Stacks."

if ! ask_yesno "${BOLD}Update jetzt durchfuehren?${RESET}" "n"; then
  warn "Abgebrochen. Es wurde nichts veraendert."
  echo -e " Geladene Images und Commits liegen lokal und werden beim naechsten Lauf verwendet."
  exit 0
fi

# -- 5. Durchfuehrung ----------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Durchfuehrung${RESET}"
echo "------------------------------------------------------------"

if [[ "${#CONFIG_ITEMS[@]}" -gt 0 ]]; then
  info "Erstelle Backup..."
  mkdir -p "${BACKUP_DIR}"
  chmod 700 "${BACKUP_DIR}"
  STAGE="$(mktemp -d "${BACKUP_DIR}/.tmp-backup-XXXXXX")" || die "Konnte kein temporaeres Verzeichnis anlegen."
  trap 'rm -rf "${STAGE}"' EXIT

  mkdir -p "${STAGE}/config"
  for item in "${CONFIG_ITEMS[@]}"; do
    cp -a "${INSTALL_DIR}/${item}" "${STAGE}/config/"
  done
  success "Konfiguration gesichert: ${CONFIG_ITEMS[*]}"

  {
    echo "ERSTELLT=${TS}"
    echo "HOST=$(hostname 2>/dev/null || echo unbekannt)"
    echo "INSTALL_DIR=${INSTALL_DIR}"
    echo "GIT_COMMIT_VOR_UPDATE=${GIT_OLD:-unbekannt}"
    echo "KONFIGURATION=${CONFIG_ITEMS[*]:-keine}"
  } > "${STAGE}/manifest.txt"

  tar czf "${BACKUP_FILE}" -C "${STAGE}" .
  chmod 600 "${BACKUP_FILE}"
  rm -rf "${STAGE}"
  trap - EXIT
  success "Backup erstellt: $(basename "${BACKUP_FILE}") ($(du -h "${BACKUP_FILE}" | cut -f1))"
fi

if [[ "${GIT_CHANGED}" -eq 1 ]]; then
  info "Aktualisiere das Repository (merge --ff-only)..."
  if ! git -C "${INSTALL_DIR}" merge --ff-only FETCH_HEAD; then
    error "Fast-Forward nicht moeglich - das Repository wurde nicht veraendert."
    error "Bitte manuell pruefen: git -C ${INSTALL_DIR} status"
    die "Abbruch vor dem Neustart. Das Backup liegt unter ${BACKUP_FILE:-<keines>}."
  fi
  success "Repository auf $(git -C "${INSTALL_DIR}" rev-parse --short HEAD) gebracht."
fi

info "Validiere die Compose-Konfiguration..."
if ! dc config --quiet; then
  error "Die Compose-Konfiguration ist nach dem Update ungueltig."
  error "Haeufigste Ursache: docker-compose.override.yml verweist auf einen Service,"
  error "den es in der neuen docker-compose.yml nicht mehr gibt."
  die "Der Stack wurde NICHT neu gestartet. Bitte die Override-Datei anpassen."
fi
success "Compose-Konfiguration ist gueltig."

info "Fahre den Stack neu hoch..."
dc up -d
if [[ "${GIT_CHANGED}" -eq 1 ]]; then
  success "UPDATED: LibreCodeInterpreter (${GIT_OLD:0:7}) -> (${GIT_NEW:0:7})"
else
  success "UPDATED: Images aktualisiert, Repository unveraendert (${GIT_OLD:0:7})"
fi

echo ""
dc ps || true

mapfile -t OLD_BACKUPS < <(ls -1t "${BACKUP_DIR}"/${BACKUP_PREFIX}_*.tar.gz 2>/dev/null | tail -n "+$((KEEP + 1))" || true)
if [[ "${#OLD_BACKUPS[@]}" -gt 0 ]]; then
  echo ""
  info "Entferne ${#OLD_BACKUPS[@]} alte(s) Backup(s) (behalte die letzten ${KEEP})."
  for old in "${OLD_BACKUPS[@]}"; do rm -f "${old}"; done
fi

echo ""
info "Raeume alte (dangling) Images auf..."
docker image prune -f >/dev/null
success "Aufgeraeumt."

# -- Abschluss -----------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${GREEN}${BOLD} Update abgeschlossen.${RESET}  $(date '+%F %T')"
echo "------------------------------------------------------------"
if [[ -f "${BACKUP_FILE}" ]]; then
  echo -e " Backup: ${CYAN}${BACKUP_FILE}${RESET}"
  echo ""
  echo -e " Rollback bei Problemen:"
  echo -e "   ${CYAN}cd ${INSTALL_DIR} && ${COMPOSE_CMD} down${RESET}"
  echo -e "   ${CYAN}mkdir -p /tmp/lci-restore && tar xzf ${BACKUP_FILE} -C /tmp/lci-restore${RESET}"
  echo -e "   ${CYAN}cp /tmp/lci-restore/config/* ${INSTALL_DIR}/${RESET}"
  [[ "${GIT_CHANGED}" -eq 1 ]] && \
  echo -e "   ${CYAN}git -C ${INSTALL_DIR} checkout ${GIT_OLD:0:7}${RESET}   (alter Repository-Stand)"
  echo -e "   ${CYAN}cd ${INSTALL_DIR} && ${COMPOSE_CMD} up -d${RESET}"
  echo ""
fi
echo -e " Hinweis: Hat sich ${CYAN}.env.example${RESET} geaendert, muessen neue Variablen"
echo -e " ggf. von Hand in die ${CYAN}.env${RESET} uebernommen werden - siehe das Projekt-Changelog."
echo ""
echo -e " Mehr Tipps & Tutorials: ${CYAN}https://pc-fee.com/blog${RESET}"
echo -e " GitHub:                 ${CYAN}${LCI_GUIDE}${RESET}"
echo ""
