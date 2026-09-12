#!/usr/bin/env bash
# =============================================================================
# Nginx Proxy Manager Update Script - powered by pc-fee.com
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Aktualisiert eine mit install-npm.sh installierte NPM-Instanz:
#   1. Backup von data/ (inkl. SQLite-DB) und letsencrypt/
#   2. Behaelt nur die N neuesten Backups (Default: 5)
#   3. Zieht das aktuelle Image und erkennt auch Major-Spruenge (z.B. v14->v15)
#   4. Erstellt den Container nur bei tatsaechlich neuem Image neu
#   5. Raeumt alte (dangling) Images auf
#
# Nutzung als 1-Zeiler (von ueberall, kein vorheriger Download noetig):
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/update/update-npm.sh)"
#
# Optionen:
#   --dir <pfad>   Installationspfad fest vorgeben (ueberspringt die Erkennung)
#   --keep <n>     Anzahl aufzubewahrender Backups (Default: 5)
#   --dry-run      Zeigt nur, was passieren wuerde - aendert nichts
#   --help         Diese Hilfe anzeigen
#
# Umgebungsvariablen (fuer unbeaufsichtigten Betrieb, z.B. Cron):
#   INSTALL_DIR    wie --dir
#   KEEP_BACKUPS   wie --keep
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

# -- Optionen ------------------------------------------------------------------
DRY_RUN=0
KEEP="${KEEP_BACKUPS:-5}"
LOG="${LOG_FILE:-/var/log/npm-update.log}"

usage() {
  cat <<'USAGE'
Nginx Proxy Manager Update Script - powered by pc-fee.com

Aktualisiert eine mit install-npm.sh installierte NPM-Instanz: Backup von
data/ und letsencrypt/, Image-Pull, Neuerstellung des Containers nur bei
tatsaechlich neuem Image, Aufraeumen alter Images.

Optionen:
  --dir <pfad>   Installationspfad fest vorgeben (ueberspringt die Erkennung)
  --keep <n>     Anzahl aufzubewahrender Backups (Default: 5)
  --dry-run      Zeigt nur, was passieren wuerde - aendert nichts
  --help         Diese Hilfe anzeigen

Umgebungsvariablen: INSTALL_DIR, KEEP_BACKUPS, LOG_FILE

Beispiele:
  sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/update/update-npm.sh)"
  sudo ./update-npm.sh --dry-run
  sudo ./update-npm.sh --dir /srv/npm --keep 10
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)     INSTALL_DIR="${2:-}"; shift 2 || true ;;
    --dir=*)   INSTALL_DIR="${1#*=}"; shift ;;
    --keep)    KEEP="${2:-}"; shift 2 || true ;;
    --keep=*)  KEEP="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
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
echo -e " Backups:       ${CYAN}${BACKUP_DIR}${RESET} (die letzten ${KEEP})"
echo ""

# -- 1) Backup -----------------------------------------------------------------
TS=$(date +%F_%H-%M-%S)
BACKUP_FILE="${BACKUP_DIR}/npm_${TS}.tar.gz"

declare -a BACKUP_ITEMS=()
for item in data letsencrypt; do
  [[ -e "${INSTALL_DIR}/${item}" ]] && BACKUP_ITEMS+=("${item}")
done

if [[ "${#BACKUP_ITEMS[@]}" -eq 0 ]]; then
  warn "Weder data/ noch letsencrypt/ in ${INSTALL_DIR} gefunden - es wird kein Backup erstellt."
else
  info "Erstelle Backup von: ${BACKUP_ITEMS[*]}"
  run mkdir -p "${BACKUP_DIR}"
  # -C: relative Pfade im Archiv, unabhaengig vom Arbeitsverzeichnis.
  run tar czf "${BACKUP_FILE}" -C "${INSTALL_DIR}" "${BACKUP_ITEMS[@]}"
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    success "Backup erstellt: $(basename "${BACKUP_FILE}") ($(du -h "${BACKUP_FILE}" | cut -f1))"
  fi

  # -- 2) Rotation -------------------------------------------------------------
  mapfile -t OLD_BACKUPS < <(ls -1t "${BACKUP_DIR}"/npm_*.tar.gz 2>/dev/null | tail -n "+$((KEEP + 1))" || true)
  if [[ "${#OLD_BACKUPS[@]}" -gt 0 ]]; then
    info "Entferne ${#OLD_BACKUPS[@]} alte(s) Backup(s) (behalte die letzten ${KEEP})."
    for old in "${OLD_BACKUPS[@]}"; do run rm -f "${old}"; done
  fi
fi

# -- 3) Image-ID vor dem Pull merken -------------------------------------------
OLD_ID=$(docker image inspect "${IMAGE}" -f '{{.Id}}' 2>/dev/null || true)

# -- 4) Neues Image ziehen -----------------------------------------------------
echo ""
info "Pruefe auf ein neues Image..."
run ${COMPOSE_CMD} -f "${COMPOSE_FILE}" pull

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo -e "${YELLOW}${BOLD} DRY-RUN beendet - es wurde nichts veraendert.${RESET}"
  echo -e " Ohne ${BOLD}--dry-run${RESET} wuerde jetzt bei neuem Image ein"
  echo -e " '${COMPOSE_CMD} -f ${COMPOSE_FILE} up -d --force-recreate' folgen."
  echo ""
  exit 0
fi

NEW_ID=$(docker image inspect "${IMAGE}" -f '{{.Id}}' 2>/dev/null || true)
[[ -n "${NEW_ID}" ]] || die "Image ${IMAGE} ist nach dem Pull nicht lokal vorhanden."

# -- 5) Nur bei neuem Image sauber neu erstellen (erzwingt z.B. v14->v15) -------
if [[ "${OLD_ID}" != "${NEW_ID}" ]]; then
  info "Neues Image gefunden - Container wird neu erstellt."
  ${COMPOSE_CMD} -f "${COMPOSE_FILE}" up -d --force-recreate
  success "UPDATED: ${OLD_ID:0:19} -> ${NEW_ID:0:19}"

  info "Raeume alte (dangling) Images auf..."
  docker image prune -f >/dev/null
  success "Aufgeraeumt."
else
  success "NOCHANGE: bereits aktuell (${NEW_ID:0:19})"
fi

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
echo -e " Hardening & Tipps: ${CYAN}${NPM_GUIDE}${RESET}"
echo ""
