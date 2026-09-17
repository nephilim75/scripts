#!/usr/bin/env bash
# =============================================================================
# Nginx Proxy Manager Update Script - powered by pc-fee.com
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Aktualisiert eine mit install-npm.sh installierte NPM-Instanz:
#   1. Bestandsaufnahme: Installation, Container, aktuelles Image, Datenmengen
#   2. Ermittelt die Zielversion:
#      - feste Version (z.B. ':2.15.1', Standard von install-npm.sh): neueste
#        stabile Version auf Docker Hub oder die per --version vorgegebene
#      - gleitender Tag (z.B. ':latest'): neues Image unter demselben Tag
#   3. Laedt das Image (laufender Container bleibt unberuehrt)
#   4. Zeigt Zusammenfassung JETZT -> NACHHER und fragt nach Bestaetigung
#   5. Erst danach: Backup von data/ (inkl. SQLite-DB), letsencrypt/ und der
#      Compose-Datei, dann ggf. neue Version in die Compose-Datei eintragen
#   6. Erstellt den Container neu (erzwingt auch Major-Spruenge, z.B. v14->v15);
#      startet er nicht, wird die alte Compose-Datei wiederhergestellt
#   7. Behaelt nur die N neuesten Backups (Default: 5), raeumt alte Images auf
#
# Ohne Bestaetigung wird nichts veraendert. Fuer Cron: --yes bzw. ASSUME_YES=1.
#
# Nutzung als 1-Zeiler (von ueberall, kein vorheriger Download noetig):
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/update/update-npm.sh)"
#
# Optionen:
#   --dir <pfad>   Installationspfad fest vorgeben (ueberspringt die Erkennung)
#   --version <v>  Zielversion fest vorgeben (z.B. 2.15.1 oder latest)
#   --keep <n>     Anzahl aufzubewahrender Backups (Default: 5)
#   --dry-run      Zeigt nur, was passieren wuerde - aendert nichts
#   --yes          Ueberspringt die Bestaetigung (wie ASSUME_YES=1, fuer Cron)
#   --help         Diese Hilfe anzeigen
#
# Umgebungsvariablen (fuer unbeaufsichtigten Betrieb, z.B. Cron):
#   INSTALL_DIR    wie --dir
#   NPM_VERSION    wie --version
#   KEEP_BACKUPS   wie --keep
#   ASSUME_YES=1   wie --yes
#   LOG_FILE       Logdatei (Default: /var/log/npm-update.log)
#
# Der Installationspfad wird automatisch ermittelt (Container-Label ->
# Volume-Quelle -> /opt/nginx-proxy-manager). Nur wenn mehrere Installationen
# gefunden werden, fragt das Script nach.
#
# Voraussetzungen: root (bzw. sudo), Docker + Docker Compose.
#
# Autor: Nils Weber (n8n Automation Architect, pc-fee.com)
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
readonly NPM_GUIDE="https://pc-fee.com/2026/05/03/nginx-proxy-manager/"
readonly DEFAULT_DIR="/opt/nginx-proxy-manager"
readonly DEFAULT_IMAGE="jc21/nginx-proxy-manager:latest"
readonly HUB_REPO="jc21/nginx-proxy-manager"
readonly HUB_TAGS_URL="https://hub.docker.com/v2/repositories/${HUB_REPO}/tags?page_size=100&ordering=last_updated"

# -- Optionen ------------------------------------------------------------------
DRY_RUN=0
TARGET_VERSION="${NPM_VERSION:-}"
KEEP="${KEEP_BACKUPS:-5}"
LOG="${LOG_FILE:-/var/log/npm-update.log}"

usage() {
  cat <<'USAGE'
Nginx Proxy Manager Update Script - powered by pc-fee.com

Aktualisiert eine mit install-npm.sh installierte NPM-Instanz: Backup von
data/, letsencrypt/ und Compose-Datei, Image-Pull, Neuerstellung des
Containers nur bei tatsaechlich neuer Version, Aufraeumen alter Images.

Bei fester Version (z.B. ':2.15.1') wird die neueste stabile Version von
Docker Hub ermittelt und nach Bestaetigung in die Compose-Datei eingetragen.

Optionen:
  --dir <pfad>   Installationspfad fest vorgeben (ueberspringt die Erkennung)
  --version <v>  Zielversion fest vorgeben (z.B. 2.15.1 oder latest)
  --keep <n>     Anzahl aufzubewahrender Backups (Default: 5)
  --dry-run      Zeigt nur, was passieren wuerde - aendert nichts
  --yes          Ueberspringt die Bestaetigung (wie ASSUME_YES=1, fuer Cron)
  --help         Diese Hilfe anzeigen

Das Script zeigt erst eine Zusammenfassung (JETZT -> NACHHER) und fragt nach,
bevor Backup und Container-Neuerstellung starten.

Umgebungsvariablen: INSTALL_DIR, NPM_VERSION, KEEP_BACKUPS, ASSUME_YES, LOG_FILE

Beispiele:
  sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/update/update-npm.sh)"
  sudo ./update-npm.sh --dry-run
  sudo ./update-npm.sh --dir /srv/npm --keep 10
  sudo ./update-npm.sh --version 2.15.1
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)     INSTALL_DIR="${2:-}"; shift 2 || true ;;
    --dir=*)   INSTALL_DIR="${1#*=}"; shift ;;
    --version) TARGET_VERSION="${2:-}"; shift 2 || true ;;
    --version=*) TARGET_VERSION="${1#*=}"; shift ;;
    --keep)    KEEP="${2:-}"; shift 2 || true ;;
    --keep=*)  KEEP="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y)  ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         echo "Unbekannte Option: $1 (siehe --help)" >&2; exit 1 ;;
  esac
done
readonly DRY_RUN

if ! [[ "${KEEP}" =~ ^[0-9]+$ ]] || [[ "${KEEP}" -lt 1 ]]; then
  echo "--keep erwartet eine positive Ganzzahl (erhalten: '${KEEP}')." >&2
  exit 1
fi
readonly KEEP

if [[ -n "${TARGET_VERSION}" ]] && ! [[ "${TARGET_VERSION}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
  echo "--version erwartet einen gueltigen Image-Tag (erhalten: '${TARGET_VERSION}')." >&2
  exit 1
fi

# -- Eingabequelle -------------------------------------------------------------
# Wird das Script per 'curl ... | bash' gestartet, liegt auf stdin der Script-
# Text selbst - ein 'read' wuerde ihn verschlucken. Deshalb immer vom Terminal
# lesen. Ohne Terminal (z.B. Cron) wird nie gefragt, sondern abgebrochen.
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

# run <befehl...> - im Dry-Run nur anzeigen, sonst ausfuehren.
run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo -e "${YELLOW}   [DRY-RUN]${RESET} $*"
  else
    "$@"
  fi
}

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
printf '%b\n' "${BOLD} Nginx Proxy Manager Update - powered by pc-fee.com${RESET}"
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

# Unbedingt in ein garantiert existierendes Verzeichnis wechseln. Wurde die CWD
# der aufrufenden Shell zwischenzeitlich geloescht, scheitern spaetere Aufrufe
# sonst mit 'getcwd: cannot access parent directories'. Das Script arbeitet
# ausschliesslich mit absoluten Pfaden.
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

# -- Installationspfad ermitteln -----------------------------------------------
# Ein Verzeichnis gilt als NPM-Installation, wenn es eine Compose-Datei enthaelt,
# die auf ein nginx-proxy-manager-Image verweist.
compose_file_of() {
  local d="$1" f
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    if [[ -f "${d}/${f}" ]] && grep -qi 'nginx-proxy-manager' "${d}/${f}"; then
      echo "${d}/${f}"
      return 0
    fi
  done
  return 1
}

detect_dirs() {
  local -a raw=() out=()
  local cid d existing seen

  # 1. Container mit NPM-Image: Compose-Working-Dir aus dem Label lesen.
  while IFS= read -r cid; do
    [[ -n "${cid}" ]] || continue
    d=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "${cid}" 2>/dev/null || true)
    [[ -n "${d}" && "${d}" == /* ]] && raw+=("${d}")
    # 2. Fallback: Quelle des /data-Mounts - eine Ebene hoeher liegt die Installation.
    d=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "${cid}" 2>/dev/null || true)
    [[ -n "${d}" && "${d}" == /* ]] && raw+=("$(dirname "${d}")")
  done < <(docker ps -a --format '{{.ID}} {{.Image}}' | awk '/nginx-proxy-manager/ {print $1}')

  # 3. Standardpfad des Installers.
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
    || die "In ${INSTALL_DIR} liegt keine Compose-Datei mit einem nginx-proxy-manager-Image."
  info "Installationspfad (vorgegeben): ${INSTALL_DIR}"
else
  mapfile -t FOUND < <(detect_dirs)
  case "${#FOUND[@]}" in
    0)
      die "Keine NPM-Installation gefunden.\n  Erwartet wurde eine Compose-Datei mit nginx-proxy-manager-Image,\n  z.B. unter ${DEFAULT_DIR}.\n  Pfad ggf. direkt angeben: --dir /pfad/zur/installation"
      ;;
    1)
      INSTALL_DIR="${FOUND[0]}"
      info "Installation erkannt: ${INSTALL_DIR}"
      ;;
    *)
      echo ""
      warn "Mehrere NPM-Installationen gefunden:"
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

# Image-Referenz aus der Compose-Datei lesen statt fest zu verdrahten - so
# funktioniert das Script auch bei gepinnten Tags (z.B. ':2.11.3').
IMAGE=$(sed -n "s/^[[:space:]]*image:[[:space:]]*[\"']\{0,1\}\([^\"'[:space:]]*nginx-proxy-manager[^\"'[:space:]]*\)[\"']\{0,1\}.*/\1/p" "${COMPOSE_FILE}" | head -n 1)
IMAGE="${IMAGE:-${DEFAULT_IMAGE}}"
readonly IMAGE

# Repository und Tag trennen (ein ':' im letzten Pfadteil ist der Tag).
if [[ "${IMAGE##*/}" == *:* ]]; then
  IMAGE_REPO="${IMAGE%:*}"
  CUR_TAG="${IMAGE##*:}"
else
  IMAGE_REPO="${IMAGE}"
  CUR_TAG="latest"
fi
readonly IMAGE_REPO CUR_TAG

is_semver() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

# Neueste stabile Version (x.y.z) von Docker Hub - nur lesend.
latest_hub_version() {
  command -v curl &>/dev/null || return 1
  curl -fsSL --max-time 20 "${HUB_TAGS_URL}" 2>/dev/null \
    | grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+"' \
    | sed -E 's/.*"([^"]+)"$/\1/' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V | tail -n 1
}

# Ist $1 eine hoehere Version als $2?
version_gt() {
  [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" == "$1" ]]
}

# -- Zielversion bestimmen -----------------------------------------------------
if [[ -n "${TARGET_VERSION}" ]]; then
  TARGET_TAG="${TARGET_VERSION}"
elif is_semver "${CUR_TAG}"; then
  # Feste Version: ein Pull desselben Tags bringt nie etwas Neues. Deshalb die
  # neueste stabile Version auf Docker Hub nachschlagen.
  if [[ "${IMAGE_REPO#docker.io/}" != "${HUB_REPO}" ]]; then
    die "Image ${IMAGE} stammt nicht von Docker Hub (${HUB_REPO}).\n  Zielversion bitte direkt angeben: --version <tag>"
  fi
  info "Feste Version ${CUR_TAG} erkannt - frage neueste Version bei Docker Hub ab..."
  TARGET_TAG="$(latest_hub_version || true)"
  [[ -n "${TARGET_TAG}" ]] \
    || die "Docker Hub nicht erreichbar oder keine Version gefunden.\n  Zielversion bitte direkt angeben: --version <tag>"
else
  TARGET_TAG="${CUR_TAG}"
fi
readonly TARGET_TAG
NEW_IMAGE="${IMAGE_REPO}:${TARGET_TAG}"
readonly NEW_IMAGE

VERSION_CHANGE=0
[[ "${NEW_IMAGE}" != "${IMAGE}" ]] && VERSION_CHANGE=1
readonly VERSION_CHANGE

# -- Logging -------------------------------------------------------------------
# Ab hier alles zusaetzlich in die Logdatei schreiben (wichtig fuer Cron-Laeufe).
if [[ "${DRY_RUN}" -eq 0 ]]; then
  if ! touch "${LOG}" 2>/dev/null; then
    warn "Logdatei ${LOG} nicht beschreibbar - Ausgabe nur auf der Konsole."
  else
    exec > >(tee -a "${LOG}") 2>&1
  fi
fi

echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Update${RESET}  $(date '+%F %T')"
echo "------------------------------------------------------------"
echo -e " Installation:  ${CYAN}${INSTALL_DIR}${RESET}"
echo -e " Compose-Datei: ${CYAN}${COMPOSE_FILE}${RESET}"
echo -e " Image:         ${CYAN}${IMAGE}${RESET}"
if [[ "${VERSION_CHANGE}" -eq 1 ]]; then
  echo -e " Zielversion:   ${GREEN}${NEW_IMAGE}${RESET}"
fi
echo -e " Backups:       ${CYAN}${BACKUP_DIR}${RESET} (die letzten ${KEEP})"
echo ""

# -- Bestandsaufnahme ----------------------------------------------------------
echo "------------------------------------------------------------"
echo -e "${BOLD} Bestandsaufnahme${RESET}"
echo "------------------------------------------------------------"

CONTAINERS=$(${COMPOSE_CMD} -f "${COMPOSE_FILE}" ps -a --format '{{.Name}} ({{.State}})' 2>/dev/null || true)
if [[ -n "${CONTAINERS}" ]]; then
  info "Container:"
  while IFS= read -r c; do [[ -n "$c" ]] && echo -e "   - ${CYAN}${c}${RESET}"; done <<<"${CONTAINERS}"
else
  warn "Kein Container zu dieser Compose-Datei gefunden (gestoppt oder entfernt?)."
fi

OLD_ID=$(docker image inspect "${IMAGE}" -f '{{.Id}}' 2>/dev/null || true)
OLD_CREATED=$(docker image inspect "${IMAGE}" -f '{{.Created}}' 2>/dev/null | cut -c1-10 || true)
if [[ -n "${OLD_ID}" ]]; then
  info "Aktuelles Image: ${OLD_ID:0:19} (Stand ${OLD_CREATED:-unbekannt})"
else
  warn "Image ${IMAGE} ist lokal noch nicht vorhanden - es wird erstmalig geladen."
fi

# Feste Version, die bereits die neueste ist: nichts zu tun.
if [[ "${VERSION_CHANGE}" -eq 0 && -n "${OLD_ID}" ]] && is_semver "${CUR_TAG}"; then
  echo ""
  echo "------------------------------------------------------------"
  success "NOCHANGE: ${IMAGE} ist die aktuelle Version."
  echo "------------------------------------------------------------"
  echo -e " Kein Download, kein Backup, kein Neustart."
  echo ""
  exit 0
fi

# Aeltere Zielversion: Datenbank-Migrationen lassen sich nicht zurueckdrehen.
if is_semver "${CUR_TAG}" && is_semver "${TARGET_TAG}" && version_gt "${CUR_TAG}" "${TARGET_TAG}"; then
  echo ""
  warn "Zielversion ${TARGET_TAG} ist AELTER als die installierte ${CUR_TAG}."
  warn "Ein Downgrade kann an bereits migrierten Datenbanken scheitern."
  warn "Sicherer Weg zurueck: ein Backup von vor dem Update einspielen (siehe README)."
  if [[ "${ASSUME_YES:-0}" == "1" ]]; then
    die "Downgrade wird mit --yes nicht automatisch ausgefuehrt."
  fi
  ask_yesno "Trotzdem auf ${TARGET_TAG} wechseln?" "n" || { warn "Abgebrochen. Es wurde nichts veraendert."; exit 0; }
fi

declare -a BACKUP_ITEMS=()
for item in data letsencrypt "$(basename "${COMPOSE_FILE}")"; do
  [[ -e "${INSTALL_DIR}/${item}" ]] && BACKUP_ITEMS+=("${item}")
done
if [[ "${#BACKUP_ITEMS[@]}" -gt 0 ]]; then
  info "Zu sichernde Daten:"
  for item in "${BACKUP_ITEMS[@]}"; do
    echo -e "   - ${CYAN}${item}/${RESET} ($(du -sh "${INSTALL_DIR}/${item}" 2>/dev/null | cut -f1))"
  done
else
  warn "Weder data/ noch letsencrypt/ gefunden - es kann kein Backup erstellt werden."
fi

BACKUP_COUNT=0
if [[ -d "${BACKUP_DIR}" ]]; then
  BACKUP_COUNT=$(find "${BACKUP_DIR}" -maxdepth 1 -name 'npm_*.tar.gz' -type f 2>/dev/null | wc -l | tr -d ' ')
fi
info "Vorhandene Backups: ${BACKUP_COUNT} in ${BACKUP_DIR} (es werden ${KEEP} behalten)"

# -- Auf neues Image pruefen ---------------------------------------------------
# Der Pull laedt hoechstens Layer herunter - der laufende Container wird dabei
# nicht angefasst. Alles, was den Dienst tatsaechlich veraendert, passiert erst
# nach der Bestaetigung weiter unten.
echo ""
info "Lade Image ${NEW_IMAGE}..."
info "Es wird nur geladen - der laufende Container bleibt dabei unberuehrt."
run docker pull "${NEW_IMAGE}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo "------------------------------------------------------------"
  echo -e "${YELLOW}${BOLD} DRY-RUN beendet - es wurde nichts veraendert.${RESET}"
  echo "------------------------------------------------------------"
  if [[ "${VERSION_CHANGE}" -eq 1 ]]; then
    echo -e " Versionswechsel ${CYAN}${IMAGE}${RESET} -> ${GREEN}${NEW_IMAGE}${RESET}."
    echo -e " Nach einer Rueckfrage wuerde folgen:"
  else
    echo -e " Ob ein neues Image vorliegt, laesst sich ohne Download nicht"
    echo -e " feststellen - der Pull wurde uebersprungen. Bei neuem Image wuerde"
    echo -e " nach einer Rueckfrage folgen:"
  fi
  echo -e "   1. Backup nach ${CYAN}${BACKUP_DIR}/npm_<zeitstempel>.tar.gz${RESET}"
  [[ "${VERSION_CHANGE}" -eq 1 ]] && \
    echo -e "   2. Image-Zeile in ${CYAN}$(basename "${COMPOSE_FILE}")${RESET} auf ${NEW_IMAGE} setzen"
  echo -e "   3. ${CYAN}${COMPOSE_CMD} -f ${COMPOSE_FILE} up -d --force-recreate${RESET}"
  echo -e "   4. Backups ueber ${KEEP} hinaus entfernen, alte Images aufraeumen"
  echo ""
  exit 0
fi

NEW_ID=$(docker image inspect "${NEW_IMAGE}" -f '{{.Id}}' 2>/dev/null || true)
NEW_CREATED=$(docker image inspect "${NEW_IMAGE}" -f '{{.Created}}' 2>/dev/null | cut -c1-10 || true)
[[ -n "${NEW_ID}" ]] || die "Image ${NEW_IMAGE} ist nach dem Pull nicht lokal vorhanden."

# -- Kein neues Image: hier ist Schluss, ohne irgendetwas anzufassen ------------
if [[ "${VERSION_CHANGE}" -eq 0 && "${OLD_ID}" == "${NEW_ID}" ]]; then
  echo ""
  echo "------------------------------------------------------------"
  success "NOCHANGE: bereits aktuell (${NEW_ID:0:19}, Stand ${NEW_CREATED:-unbekannt})"
  echo "------------------------------------------------------------"
  echo -e " Kein Backup, kein Neustart, keine Aenderung am Container."
  echo ""
  exit 0
fi

# -- Zusammenfassung -----------------------------------------------------------
TS=$(date +%F_%H-%M-%S)
BACKUP_FILE="${BACKUP_DIR}/npm_${TS}.tar.gz"

mapfile -t DROP_BACKUPS < <(ls -1t "${BACKUP_DIR}"/npm_*.tar.gz 2>/dev/null | tail -n "+${KEEP}" || true)

echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Zusammenfassung${RESET}"
echo "------------------------------------------------------------"
echo -e " Installation:  ${CYAN}${INSTALL_DIR}${RESET}"
echo ""
echo -e " ${BOLD}JETZT${RESET}      ${IMAGE}  ${OLD_ID:0:19}  (Stand ${OLD_CREATED:-unbekannt})"
echo -e " ${BOLD}NACHHER${RESET}    ${GREEN}${NEW_IMAGE}${RESET}  ${GREEN}${NEW_ID:0:19}${RESET}  (Stand ${NEW_CREATED:-unbekannt})  ${GREEN}<- neu${RESET}"
echo ""
echo -e " ${BOLD}Es wird:${RESET}"
if [[ "${#BACKUP_ITEMS[@]}" -gt 0 ]]; then
  echo -e "   1. ${BACKUP_ITEMS[*]} gesichert nach ${CYAN}$(basename "${BACKUP_FILE}")${RESET}"
else
  echo -e "   1. ${YELLOW}kein Backup erstellt${RESET} (weder data/ noch letsencrypt/ vorhanden)"
fi
if [[ "${VERSION_CHANGE}" -eq 1 ]]; then
  echo -e "   2. in ${CYAN}$(basename "${COMPOSE_FILE}")${RESET} die Image-Zeile auf ${NEW_IMAGE} gesetzt"
  echo -e "      und der Container neu erstellt - kurze Downtime, meist 10-30 Sekunden"
else
  echo -e "   2. der Container neu erstellt - kurze Downtime, meist 10-30 Sekunden"
fi
if [[ "${#DROP_BACKUPS[@]}" -gt 0 ]]; then
  echo -e "   3. ${#DROP_BACKUPS[@]} alte(s) Backup(s) entfernt, aeltestes: ${CYAN}$(basename "${DROP_BACKUPS[-1]}")${RESET}"
else
  echo -e "   3. kein altes Backup entfernt (${BACKUP_COUNT} von ${KEEP} belegt)"
fi
if [[ "${VERSION_CHANGE}" -eq 1 ]]; then
  echo -e "   4. das alte Image ${IMAGE} und dangling Images aufgeraeumt"
else
  echo -e "   4. dangling Images auf diesem Host aufgeraeumt"
fi
echo ""
echo -e " ${BOLD}Unveraendert bleibt:${RESET}"
if [[ "${VERSION_CHANGE}" -eq 1 ]]; then
  echo -e "   - ${CYAN}$(basename "${COMPOSE_FILE}")${RESET} bis auf die Image-Zeile, inkl. Portfreigaben und Hardening"
else
  echo -e "   - ${CYAN}$(basename "${COMPOSE_FILE}")${RESET} inkl. Portfreigaben und Hardening"
fi
echo -e "   - deine Proxy Hosts, Zertifikate und Zugangsdaten in data/ und letsencrypt/"
echo -e "   - das Docker-Netzwerk und alle anderen Stacks darauf"
echo ""

# -- Bestaetigung --------------------------------------------------------------
echo "------------------------------------------------------------"
if ! ask_yesno "${BOLD}Update jetzt durchfuehren?${RESET}" "n"; then
  warn "Abgebrochen. Es wurde nichts veraendert."
  echo -e " Das geladene Image bleibt lokal liegen und wird beim naechsten Lauf verwendet."
  exit 0
fi

# -- Durchfuehrung -------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Durchfuehrung${RESET}"
echo "------------------------------------------------------------"

if [[ "${#BACKUP_ITEMS[@]}" -gt 0 ]]; then
  info "Erstelle Backup von: ${BACKUP_ITEMS[*]}"
  mkdir -p "${BACKUP_DIR}"
  # -C: relative Pfade im Archiv, unabhaengig vom Arbeitsverzeichnis.
  tar czf "${BACKUP_FILE}" -C "${INSTALL_DIR}" "${BACKUP_ITEMS[@]}"
  success "Backup erstellt: $(basename "${BACKUP_FILE}") ($(du -h "${BACKUP_FILE}" | cut -f1))"
fi

COMPOSE_BAK=""
if [[ "${VERSION_CHANGE}" -eq 1 ]]; then
  COMPOSE_BAK="$(mktemp "${COMPOSE_FILE}.pre-update.XXXXXX")"
  cp -p "${COMPOSE_FILE}" "${COMPOSE_BAK}"
  info "Setze Image in $(basename "${COMPOSE_FILE}") auf ${NEW_IMAGE}..."
  # Nur die image:-Zeile mit exakt dem alten Wert ersetzen (Sonderzeichen maskiert).
  OLD_RE="$(printf '%s' "${IMAGE}" | sed 's/[][\\/.^$*|]/\\&/g')"
  NEW_RE="$(printf '%s' "${NEW_IMAGE}" | sed 's/[\\/&|]/\\&/g')"
  sed -i -E "s|^([[:space:]]*image:[[:space:]]*[\"']?)${OLD_RE}([\"']?[[:space:]]*)$|\\1${NEW_RE}\\2|" "${COMPOSE_FILE}"
  grep -qF "${NEW_IMAGE}" "${COMPOSE_FILE}" || {
    mv -f "${COMPOSE_BAK}" "${COMPOSE_FILE}"
    die "Image-Zeile konnte nicht angepasst werden. Compose-Datei unveraendert."
  }
fi

info "Erstelle Container neu..."
if ! ${COMPOSE_CMD} -f "${COMPOSE_FILE}" up -d --force-recreate; then
  error "Container konnte mit ${NEW_IMAGE} nicht gestartet werden."
  if [[ -n "${COMPOSE_BAK}" ]]; then
    warn "Stelle die vorherige Compose-Datei (${IMAGE}) wieder her..."
    mv -f "${COMPOSE_BAK}" "${COMPOSE_FILE}"
    ${COMPOSE_CMD} -f "${COMPOSE_FILE}" up -d --force-recreate || true
  fi
  die "Update fehlgeschlagen. Backup: ${BACKUP_FILE:-keins}"
fi
[[ -n "${COMPOSE_BAK}" ]] && rm -f "${COMPOSE_BAK}"
success "UPDATED: ${IMAGE} (${OLD_ID:0:19}) -> ${NEW_IMAGE} (${NEW_ID:0:19})"

# Rotation erst jetzt - das frische Backup zaehlt mit.
mapfile -t OLD_BACKUPS < <(ls -1t "${BACKUP_DIR}"/npm_*.tar.gz 2>/dev/null | tail -n "+$((KEEP + 1))" || true)
if [[ "${#OLD_BACKUPS[@]}" -gt 0 ]]; then
  info "Entferne ${#OLD_BACKUPS[@]} alte(s) Backup(s) (behalte die letzten ${KEEP})."
  for old in "${OLD_BACKUPS[@]}"; do rm -f "${old}"; done
fi

info "Raeume alte Images auf..."
if [[ "${VERSION_CHANGE}" -eq 1 ]]; then
  docker image rm "${IMAGE}" >/dev/null 2>&1 \
    || warn "Altes Image ${IMAGE} konnte nicht entfernt werden (noch in Benutzung?)."
fi
docker image prune -f >/dev/null
success "Aufgeraeumt."

# -- Abschluss -----------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${GREEN}${BOLD} Update abgeschlossen.${RESET}  $(date '+%F %T')"
echo "------------------------------------------------------------"
if [[ "${#BACKUP_ITEMS[@]}" -gt 0 ]]; then
  echo -e " Rollback bei Problemen:"
  echo -e "   ${CYAN}${COMPOSE_CMD} -f ${COMPOSE_FILE} down${RESET}"
  echo -e "   ${CYAN}tar xzf ${BACKUP_FILE} -C ${INSTALL_DIR}${RESET}"
  echo -e "   ${CYAN}${COMPOSE_CMD} -f ${COMPOSE_FILE} up -d${RESET}"
  echo ""
fi
if [[ "${VERSION_CHANGE}" -eq 1 ]]; then
  echo -e " Die Compose-Datei ist im Backup enthalten - der Rollback stellt also"
  echo -e " auch die vorherige Version (${IMAGE}) wieder her."
  echo ""
fi
echo -e " Hardening & Tipps: ${CYAN}${NPM_GUIDE}${RESET}"
echo ""
