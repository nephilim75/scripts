#!/usr/bin/env bash
# =============================================================================
# avila-code-interpreter Update Script - powered by pc-fee.com
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Aktualisiert eine mit install-avila-code-interpreter.sh installierte Instanz
# des LibreChat Code Interpreters (Fork LibreChat-AI/code-interpreter).
#
# Ablauf auf dem Bildschirm:
#   1. Zusammenfassung - wo liegt die Installation, in welchem Modus laeuft sie
#   2. Pruefung auf Neuerungen (git fetch + compose pull); der laufende Stack
#      bleibt dabei unberuehrt
#   3. Aktueller Stand und zukuenftiger Stand je Komponente
#   4. Rueckfragen (Backup-Rotation, Laufzeitumgebungen), dann die Bestaetigung
#   5. Durchfuehrung: Backup, merge --ff-only, NsJail-Patch neu erzeugen,
#      Compose-Validierung, compose build, Stack hochfahren, aufraeumen
#
# Besonderheit gegenueber dem LibreChat-Update: dieser Stack zieht KEIN
# fertiges Image aus einer Registry, sondern baut seine Images lokal aus dem
# Quellcode. Ein Update bedeutet deshalb immer einen Neubau (10-30+ Minuten)
# und braucht entsprechend Plattenplatz.
#
# Ohne Bestaetigung wird nichts veraendert. Fuer Cron: --yes bzw. ASSUME_YES=1.
#
# Nutzung als 1-Zeiler (von ueberall, kein vorheriger Download noetig):
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/update/update-avila-code-interpreter.sh)"
#
# Optionen:
#   --dir <pfad>   Installationspfad fest vorgeben (ueberspringt die Erkennung)
#   --keep <n>     Anzahl aufzubewahrender Backups - ohne Angabe wird gefragt
#   --force-build  Auch ohne neuen Quellstand neu bauen und neu starten
#   --pull         Beim Bauen auch die Basis-Images der Dockerfiles erneuern
#   --no-cache     Ohne Docker-Build-Cache bauen (dauert deutlich laenger)
#   --pkgs         Laufzeitumgebungen (data/pkgs) neu erzeugen - nur NsJail
#   --no-pkgs      Laufzeitumgebungen nie neu erzeugen - nur NsJail
#   --dry-run      Zeigt nur, was passieren wuerde - aendert nichts
#   --yes          Ueberspringt die Rueckfragen (wie ASSUME_YES=1, fuer Cron)
#   --help         Diese Hilfe anzeigen
#
# Umgebungsvariablen (fuer unbeaufsichtigten Betrieb, z.B. Cron):
#   INSTALL_DIR    wie --dir
#   KEEP_BACKUPS   wie --keep
#   ASSUME_YES=1   wie --yes
#   LOG_FILE       Logdatei (Default: /var/log/avila-code-interpreter-update.log)
#
# Der Installationspfad wird automatisch ermittelt (Container-Label des
# avila-api-Containers -> Marker-Datei docker-compose.override.yml ->
# /opt/avila-code-interpreter). Nur bei mehreren Treffern wird gefragt.
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
readonly GUIDE_URL="https://github.com/nephilim75/scripts/tree/main/librechat/codeInterpreter"
readonly DEFAULT_DIR="/opt/avila-code-interpreter"
# Marker der eigenen Installation: die docker-compose.override.yml wird
# ausschliesslich vom Installer geschrieben und benennt den API-Container.
# Ein Grep auf "code-interpreter" waere zu unscharf - der Ordnername ist frei
# waehlbar und fremde Stacks tragen aehnliche Namen.
readonly MARKER_FILE="docker-compose.override.yml"
readonly MARKER_STRING="container_name: avila-api"
readonly API_CONTAINER="avila-api"
readonly PKG_INIT_IMAGE="avila-package-init"
readonly BACKUP_PREFIX="avila-code-interpreter"
readonly DEFAULT_KEEP=5
# Reihenfolge wie im Installer: Abhaengigkeiten zuerst.
readonly SERVICES=(redis minio tool_call_server egress_gateway sandbox-runner file_server api service-worker)
# Plattenbedarf fuer den Neubau. Alte und neue Images liegen waehrend des
# Builds parallel vor, deshalb deutlich mehr als die reine Image-Groesse.
readonly MIN_FREE_MB=10000
readonly MIN_FREE_PKGS_MB=5000

# -- Optionen ------------------------------------------------------------------
DRY_RUN=0
FORCE_BUILD=0
BUILD_PULL=0
BUILD_NO_CACHE=0
PKGS_MODE="auto"   # auto | always | never
KEEP=""
KEEP_EXPLICIT=0
LOG="${LOG_FILE:-/var/log/avila-code-interpreter-update.log}"

if [[ -n "${KEEP_BACKUPS:-}" ]]; then
  KEEP="${KEEP_BACKUPS}"
  KEEP_EXPLICIT=1
fi

usage() {
  cat <<'USAGE'
avila-code-interpreter Update Script - powered by pc-fee.com

Aktualisiert eine mit install-avila-code-interpreter.sh installierte Instanz
des LibreChat Code Interpreters. Zeigt erst eine Zusammenfassung, danach den
aktuellen und den zukuenftigen Stand je Komponente, und fragt dann nach -
vorher wird nichts veraendert.

Die Images dieses Stacks werden lokal aus dem Quellcode gebaut. Ein Update
bedeutet deshalb immer einen Neubau (10-30+ Minuten).

Optionen:
  --dir <pfad>   Installationspfad fest vorgeben (ueberspringt die Erkennung)
  --keep <n>     Anzahl aufzubewahrender Backups - ohne Angabe wird gefragt
  --force-build  Auch ohne neuen Quellstand neu bauen und neu starten
  --pull         Beim Bauen auch die Basis-Images der Dockerfiles erneuern
  --no-cache     Ohne Docker-Build-Cache bauen (dauert deutlich laenger)
  --pkgs         Laufzeitumgebungen (data/pkgs) neu erzeugen - nur NsJail
  --no-pkgs      Laufzeitumgebungen nie neu erzeugen - nur NsJail
  --dry-run      Zeigt nur, was passieren wuerde - aendert nichts
  --yes          Ueberspringt die Rueckfragen (wie ASSUME_YES=1, fuer Cron)
  --help         Diese Hilfe anzeigen

Umgebungsvariablen: INSTALL_DIR, KEEP_BACKUPS, ASSUME_YES, LOG_FILE

Beispiele:
  sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/update/update-avila-code-interpreter.sh)"
  sudo ./update-avila-code-interpreter.sh --dry-run
  sudo ./update-avila-code-interpreter.sh --dir /srv/code-interpreter --keep 10
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)          INSTALL_DIR="${2:-}"; shift 2 || true ;;
    --dir=*)        INSTALL_DIR="${1#*=}"; shift ;;
    --keep)         KEEP="${2:-}"; KEEP_EXPLICIT=1; shift 2 || true ;;
    --keep=*)       KEEP="${1#*=}"; KEEP_EXPLICIT=1; shift ;;
    --force-build)  FORCE_BUILD=1; shift ;;
    --pull)         BUILD_PULL=1; shift ;;
    --no-cache)     BUILD_NO_CACHE=1; shift ;;
    --pkgs)         PKGS_MODE="always"; shift ;;
    --no-pkgs)      PKGS_MODE="never"; shift ;;
    --dry-run)      DRY_RUN=1; shift ;;
    --yes|-y)       ASSUME_YES=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              echo "Unbekannte Option: $1 (siehe --help)" >&2; exit 1 ;;
  esac
done
readonly DRY_RUN FORCE_BUILD BUILD_PULL BUILD_NO_CACHE PKGS_MODE KEEP_EXPLICIT

# Ein ausdruecklich gesetzter Wert wird sofort geprueft - ein Tippfehler im
# Cron-Eintrag soll nicht erst nach dem Backup auffallen.
if [[ "${KEEP_EXPLICIT}" -eq 1 ]]; then
  if ! [[ "${KEEP}" =~ ^[0-9]+$ ]] || [[ "${KEEP}" -lt 1 ]]; then
    echo "--keep erwartet eine positive Ganzzahl (erhalten: '${KEEP}')." >&2
    exit 1
  fi
fi

# -- Eingabequelle -------------------------------------------------------------
# Wird das Script per 'curl ... | bash' gestartet, liegt auf stdin der Script-
# Text selbst - ein 'read' wuerde ihn verschlucken. Deshalb immer vom Terminal
# lesen. Ohne Terminal (z.B. Cron) wird nie gefragt, sondern abgebrochen.
# Achtung: '[[ -r /dev/tty ]]' prueft nur die Rechtebits und ist auch dann wahr,
# wenn es gar kein steuerndes Terminal gibt. Deshalb wirklich oeffnen.
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

# ask_number <prompt> <default> -> gibt die Zahl auf stdout aus.
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

# run <befehl...> - im Dry-Run nur anzeigen, sonst ausfuehren.
run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo -e "${YELLOW}   [DRY-RUN]${RESET} $*"
  else
    "$@"
  fi
}

# -- Banner --------------------------------------------------------------------
# 'clear' scheitert ohne brauchbares TERM (z.B. im Cron) - das darf das Script
# nicht abbrechen, deshalb der Fallback.
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
printf '%b\n' "${BOLD} Code Interpreter Update - powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo -e " Aktualisiert den LibreChat Code Interpreter (MicroVM/NsJail, Egress-"
echo -e " Gateway, signierte Manifeste) hinter dem Nginx Proxy Manager."
echo -e " ${YELLOW}Die Images werden lokal gebaut${RESET} - rechne mit 10-30+ Minuten."
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo -e " ${YELLOW}${BOLD}DRY-RUN aktiv:${RESET} es wird nichts veraendert, nur angezeigt."
fi
echo "------------------------------------------------------------"

# -- Root-Check ----------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  die "Bitte als root oder mit sudo ausfuehren."
fi

# In ein garantiert existierendes Verzeichnis wechseln. Wurde die CWD der
# aufrufenden Shell zwischenzeitlich geloescht, scheitern spaetere Aufrufe
# sonst mit 'getcwd: cannot access parent directories'.
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
# Ein Verzeichnis gilt als Installation dieses Stacks, wenn dort die vom
# Installer geschriebene Override-Datei mit dem avila-api-Container liegt.
is_install_dir() {
  local d="$1"
  [[ -f "${d}/${MARKER_FILE}" ]] && grep -q "${MARKER_STRING}" "${d}/${MARKER_FILE}" 2>/dev/null
}

# Compose-Datei des Repositorys. Der Fork liefert docker-compose.yaml (nicht
# .yml) - beide Varianten werden geprueft, damit ein Umbenennen upstream nicht
# sofort zum Abbruch fuehrt.
compose_file_of() {
  local d="$1" f
  for f in docker-compose.yaml docker-compose.yml compose.yaml compose.yml; do
    [[ -f "${d}/${f}" ]] && { echo "${d}/${f}"; return 0; }
  done
  return 1
}

detect_dirs() {
  local -a raw=() out=()
  local cid d existing seen

  # 1. Laufender/gestoppter API-Container: Compose-Working-Dir aus dem Label.
  while IFS= read -r cid; do
    [[ -n "${cid}" ]] || continue
    d=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "${cid}" 2>/dev/null || true)
    [[ -n "${d}" && "${d}" == /* ]] && raw+=("${d}")
  done < <(docker ps -a --format '{{.ID}} {{.Names}}' | awk -v n="${API_CONTAINER}" '$2==n {print $1}')

  # 2. Standardpfad des Installers.
  raw+=("${DEFAULT_DIR}")

  for d in "${raw[@]}"; do
    is_install_dir "${d}" || continue
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
  is_install_dir "${INSTALL_DIR}" \
    || die "In ${INSTALL_DIR} liegt keine ${MARKER_FILE} mit '${MARKER_STRING}'.\n  Das sieht nicht nach einer Installation von install-avila-code-interpreter.sh aus."
else
  mapfile -t FOUND < <(detect_dirs)
  case "${#FOUND[@]}" in
    0)
      die "Keine Code-Interpreter-Installation gefunden.\n  Erwartet wurde eine ${MARKER_FILE} mit '${MARKER_STRING}',\n  z.B. unter ${DEFAULT_DIR}.\n  Pfad ggf. direkt angeben: --dir /pfad/zur/installation"
      ;;
    1)
      INSTALL_DIR="${FOUND[0]}"
      ;;
    *)
      echo ""
      warn "Mehrere Installationen gefunden:"
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
INSTALL_DIR="$(cd "${INSTALL_DIR}" && pwd -P)" || die "Installationspfad nicht lesbar."
readonly INSTALL_DIR

COMPOSE_FILE="$(compose_file_of "${INSTALL_DIR}")" \
  || die "Keine Compose-Datei in ${INSTALL_DIR} gefunden - unvollstaendige Installation?"
readonly COMPOSE_FILE
BACKUP_DIR="${INSTALL_DIR}/backups"
readonly BACKUP_DIR

# Compose immer aus dem Installationsverzeichnis heraus aufrufen: nur so zieht
# Docker Compose die docker-compose.override.yml (Container-Namen, geschlossene
# Ports, shared_proxy) und die .env automatisch mit. Ein blosses
# '-f docker-compose.yaml' wuerde das Override ignorieren und beim 'up' die
# Host-Ports wieder oeffnen.
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

# -- Betriebsmodus aus der .env lesen ------------------------------------------
# KVM_ENABLED=false bedeutet NsJail-only. Nur dann existieren der gepatchte
# Sandbox-Starter unter nsjail-fix/ und die Laufzeitumgebungen unter data/pkgs.
NSJAIL_MODE=0
JWT_MODE="unbekannt"
if [[ -f "${INSTALL_DIR}/.env" ]]; then
  grep -qE '^KVM_ENABLED=false[[:space:]]*$' "${INSTALL_DIR}/.env" && NSJAIL_MODE=1
  if grep -qE '^CODEAPI_AUTH_PROVIDER=librechat-jwt[[:space:]]*$' "${INSTALL_DIR}/.env"; then
    JWT_MODE="JWT (EdDSA)"
  elif grep -qE '^CODEAPI_AUTH_PROVIDER=none[[:space:]]*$' "${INSTALL_DIR}/.env"; then
    JWT_MODE="keine (offener Zugriff im Docker-Netz)"
  fi
else
  warn "In ${INSTALL_DIR} fehlt die .env - der Stack kann so nicht starten."
fi
readonly NSJAIL_MODE

# -- Daten fuer die Zusammenfassung sammeln ------------------------------------
CONTAINERS_TOTAL=0
CONTAINERS_RUNNING=0
while IFS= read -r line; do
  [[ -n "${line}" ]] || continue
  CONTAINERS_TOTAL=$((CONTAINERS_TOTAL + 1))
  [[ "${line}" == *running* ]] && CONTAINERS_RUNNING=$((CONTAINERS_RUNNING + 1))
done < <(dc ps -a --format '{{.Service}} {{.State}}' 2>/dev/null || true)

# Gesichert wird alles, was der Installer selbst erzeugt hat und was bei einem
# Verlust nicht wiederherstellbar ist: Secrets und Schluessel (.env), die
# Override-Datei sowie die gepatchten Sandbox-Skripte. data/pkgs bleibt aussen
# vor - mehrere GB, jederzeit neu baubar.
declare -a CONFIG_ITEMS=()
for item in .env "${MARKER_FILE}" nsjail-fix librechat-jwt-block.txt; do
  [[ -e "${INSTALL_DIR}/${item}" ]] && CONFIG_ITEMS+=("${item}")
done

BACKUP_COUNT=0
if [[ -d "${BACKUP_DIR}" ]]; then
  BACKUP_COUNT=$(find "${BACKUP_DIR}" -maxdepth 1 -name "${BACKUP_PREFIX}_*.tar.gz" -type f 2>/dev/null | wc -l | tr -d ' ')
fi

# Git-Stand. Der Installer legt die Installation als flachen Clone an (--depth=1),
# deshalb spaeter '--depth=1' beim Fetch - sonst wuerde aus dem flachen Clone
# still ein vollstaendiger und der Plattenbedarf vervielfacht sich.
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

# Plattenplatz dort messen, wo Docker seine Images ablegt - nicht auf "/".
DOCKER_ROOT="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
[[ -d "${DOCKER_ROOT}" ]] || DOCKER_ROOT="/var/lib/docker"
[[ -d "${DOCKER_ROOT}" ]] || DOCKER_ROOT="/"
FREE_MB="$(df -Pm "${DOCKER_ROOT}" | awk 'NR==2{print $4}')"

# -- 1. Zusammenfassung --------------------------------------------------------
echo ""
echo "============================================================"
echo -e "${BOLD} ZUSAMMENFASSUNG${RESET}   $(date '+%F %T')"
echo "============================================================"
printf ' %-18s %s\n' "Installation:" "${INSTALL_DIR}"
printf ' %-18s %s\n' "Compose-Datei:" "$(basename "${COMPOSE_FILE}") + ${MARKER_FILE}"
if [[ "${CONTAINERS_TOTAL}" -gt 0 ]]; then
  printf ' %-18s %s\n' "Container:" "${CONTAINERS_TOTAL} (davon ${CONTAINERS_RUNNING} laufend)"
else
  printf ' %-18s %s\n' "Container:" "keine gefunden - gestoppt oder entfernt?"
fi
printf ' %-18s %s\n' "Isolation:" "$( [[ "${NSJAIL_MODE}" -eq 1 ]] && echo "NsJail-only (KVM_ENABLED=false)" || echo "MicroVM (KVM_ENABLED=true)" )"
printf ' %-18s %s\n' "Authentifizierung:" "${JWT_MODE}"
if [[ "${GIT_OK}" -eq 1 ]]; then
  printf ' %-18s %s\n' "Quellcode:" "Branch ${GIT_BRANCH}, Stand ${GIT_OLD:0:7} vom ${GIT_OLD_DATE:-unbekannt}"
elif [[ "${HAVE_GIT}" -eq 0 ]]; then
  printf ' %-18s %s\n' "Quellcode:" "git nicht installiert - kein Quell-Update moeglich"
else
  printf ' %-18s %s\n' "Quellcode:" "kein Git-Repository - kein Quell-Update moeglich"
fi
printf ' %-18s %s\n' "Sicherung von:" "${CONFIG_ITEMS[*]:-keine der erwarteten Dateien gefunden}"
printf ' %-18s %s\n' "Backups:" "${BACKUP_COUNT} vorhanden in ${BACKUP_DIR}"
printf ' %-18s %s\n' "Plattenplatz:" "${FREE_MB} MB frei auf ${DOCKER_ROOT}"
[[ "${LOG_ACTIVE}" -eq 1 ]] && printf ' %-18s %s\n' "Logdatei:" "${LOG}"

# Schritte durchzaehlen statt feste Nummern: einzelne Schritte entfallen je
# nach Modus, eine Luecke in der Numerierung wuerde nur verunsichern.
STEP_NO=0
step() { STEP_NO=$((STEP_NO + 1)); echo -e "   ${STEP_NO}. $*"; }

echo ""
echo -e " ${BOLD}Geplante Schritte${RESET}"
step "Auf Neuerungen pruefen (Quellcode und Basis-Images) - ohne Eingriff"
step "Backup der Konfiguration (Secrets, Schluessel, Override, NsJail-Fix)"
step "Quellcode per 'git merge --ff-only' aktualisieren"
[[ "${NSJAIL_MODE}" -eq 1 ]] && \
step "Gepatchten NsJail-Sandbox-Starter aus dem neuen Quellstand erzeugen"
step "Compose-Konfiguration pruefen, Images bauen, Stack hochfahren"
step "Alte Backups entfernen, dangling Images aufraeumen"

if [[ -n "${GIT_DIRTY}" ]]; then
  echo ""
  warn "Lokal geaenderte, versionierte Dateien im Repository:"
  while IFS= read -r l; do [[ -n "$l" ]] && echo -e "   ${YELLOW}${l}${RESET}"; done <<<"${GIT_DIRTY}"
  warn "Das Quell-Update entfaellt deshalb - es wird nur neu gebaut/gestartet."
  warn "Aufloesen mit: git -C ${INSTALL_DIR} checkout -- <datei>   (verwirft die Aenderung)"
fi

echo ""
echo -e " ${BOLD}Bis zur Rueckfrage wird nichts veraendert.${RESET}"

# -- 2. Auf Neuerungen pruefen -------------------------------------------------
# Beides veraendert den laufenden Stack nicht: der Fetch schreibt nur in .git/,
# der Pull laedt hoechstens Image-Layer.
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Pruefe auf Neuerungen${RESET}"
echo "------------------------------------------------------------"

mapfile -t IMAGES_NOW < <(dc config --images 2>/dev/null | sort -u || true)
[[ "${#IMAGES_NOW[@]}" -gt 0 ]] || die "Konnte die Image-Liste nicht aus der Compose-Config lesen. Stimmen .env und Override-Datei?"

# Lokal gebaute Images haben keinen RepoDigest - so lassen sie sich von den
# aus einer Registry gezogenen Basis-Images (redis, minio) unterscheiden,
# ohne die Compose-Datei zu interpretieren.
is_local_build() {
  local n
  n="$(docker image inspect "$1" -f '{{len .RepoDigests}}' 2>/dev/null || echo 0)"
  [[ "${n}" == "0" ]]
}

declare -A OLD_IDS=()
declare -A IS_LOCAL=()
for img in "${IMAGES_NOW[@]}"; do
  OLD_IDS["${img}"]="$(docker image inspect "${img}" -f '{{.Id}}' 2>/dev/null || true)"
  if [[ -z "${OLD_IDS[${img}]}" ]]; then
    IS_LOCAL["${img}"]=1   # noch nie gebaut -> zaehlt als lokal zu bauen
  elif is_local_build "${img}"; then
    IS_LOCAL["${img}"]=1
  else
    IS_LOCAL["${img}"]=0
  fi
done

GIT_NEW=""
GIT_NEW_DATE=""
GIT_CHANGED=0
CHANGED_FILES=""
if [[ "${GIT_OK}" -eq 1 && -z "${GIT_DIRTY}" ]]; then
  info "Quellcode (git fetch)..."
  if [[ "$(git -C "${INSTALL_DIR}" rev-parse --is-shallow-repository 2>/dev/null || echo false)" == "true" ]]; then
    run git -C "${INSTALL_DIR}" fetch --depth=1 origin "${GIT_BRANCH}"
  else
    run git -C "${INSTALL_DIR}" fetch origin "${GIT_BRANCH}"
  fi
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    GIT_NEW="$(git -C "${INSTALL_DIR}" rev-parse FETCH_HEAD 2>/dev/null || true)"
    GIT_NEW_DATE="$(git -C "${INSTALL_DIR}" log -1 --format=%cd --date=short FETCH_HEAD 2>/dev/null || true)"
    if [[ -n "${GIT_NEW}" && "${GIT_NEW}" != "${GIT_OLD}" ]]; then
      GIT_CHANGED=1
      # Bei flachen Clones fehlt der gemeinsame Vorfahre; ein Vergleich der
      # beiden Baeume funktioniert trotzdem, weil beide Commits lokal liegen.
      CHANGED_FILES="$(git -C "${INSTALL_DIR}" diff --name-only "${GIT_OLD}" "${GIT_NEW}" 2>/dev/null || true)"
    fi
  fi
fi

info "Basis-Images (${COMPOSE_CMD} pull) - lokal gebaute Images werden dabei uebersprungen..."
# --ignore-pull-failures: fuer die selbst gebauten Images existiert kein
# Registry-Eintrag, der Fehlschlag ist hier erwartbar und harmlos.
dc_run pull --ignore-pull-failures || warn "Der Pull meldete Fehler - lokal gebaute Images bleiben unveraendert."

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo "------------------------------------------------------------"
  echo -e "${YELLOW}${BOLD} DRY-RUN beendet - es wurde nichts veraendert.${RESET}"
  echo "------------------------------------------------------------"
  echo " Ob es Neuerungen gibt, laesst sich ohne Fetch und Pull nicht"
  echo " feststellen - beides wurde uebersprungen, deshalb entfaellt hier"
  echo " auch die Gegenueberstellung der Versionen."
  echo ""
  exit 0
fi

declare -A NEW_IDS=()
IMAGES_CHANGED=0
for img in "${IMAGES_NOW[@]}"; do
  NEW_IDS["${img}"]="$(docker image inspect "${img}" -f '{{.Id}}' 2>/dev/null || true)"
  if [[ "${IS_LOCAL[${img}]}" == "0" ]]; then
    [[ -n "${NEW_IDS[${img}]}" ]] || die "Basis-Image ${img} ist nach dem Pull nicht lokal vorhanden."
    [[ "${OLD_IDS[${img}]}" != "${NEW_IDS[${img}]}" ]] && IMAGES_CHANGED=1
  fi
done

# -- NsJail-Patch gegen den neuen Quellstand pruefen ---------------------------
# Der Installer spielt drei Fixes fuer docker/start-direct-sandbox.sh per
# schreibgeschuetztem Volume ein (fehlender ROOTFS-Export, Symlink-Bind-Falle
# bei /usr/sbin, Bash-Pfad-Cache). Aendert upstream dieses Skript, muss die
# lokale Kopie neu erzeugt werden - sonst startet die Sandbox mit einem
# veralteten Starter. Geprueft wird bewusst VOR jeder Aenderung, gegen
# FETCH_HEAD: schlaegt der Patch fehl, bricht das Script ab, ohne den
# laufenden Stack angefasst zu haben.
readonly SANDBOX_SRC="docker/start-direct-sandbox.sh"
readonly SANDBOX_COPY="nsjail-fix/start-direct-sandbox.sh"

patch_sandbox() {
  local src="$1" dst="$2"
  sed \
    -e '/mount -o bind,ro "\$ROOTFS\/usr\/sbin"/i\    rm -f /usr/sbin \&\& mkdir -p /usr/sbin' \
    -e '/mount -o bind,ro "\$ROOTFS\/usr\/sbin"/a\    hash -r' \
    -e '/^export SANDBOX_ROOTFS="\$ROOTFS"$/a\export ROOTFS="$ROOTFS"' \
    "${src}" >"${dst}"
}

verify_sandbox_patch() {
  local f="$1"
  grep -q '^    rm -f /usr/sbin && mkdir -p /usr/sbin$' "${f}" \
    && grep -q '^    hash -r$' "${f}" \
    && grep -q '^export ROOTFS="\$ROOTFS"$' "${f}"
}

SANDBOX_PATCH_NEEDED=0
if [[ "${NSJAIL_MODE}" -eq 1 && "${GIT_CHANGED}" -eq 1 ]]; then
  if [[ -n "${CHANGED_FILES}" ]] && grep -qx "${SANDBOX_SRC}" <<<"${CHANGED_FILES}"; then
    info "Upstream hat ${SANDBOX_SRC} geaendert - pruefe, ob die drei NsJail-Fixes noch greifen..."
    PATCH_TMP="$(mktemp -d)" || die "Konnte kein temporaeres Verzeichnis anlegen."
    trap 'rm -rf "${PATCH_TMP}"' EXIT
    if ! git -C "${INSTALL_DIR}" show "FETCH_HEAD:${SANDBOX_SRC}" >"${PATCH_TMP}/upstream.sh" 2>/dev/null; then
      die "Konnte ${SANDBOX_SRC} aus dem neuen Stand nicht lesen - Abbruch, nichts veraendert."
    fi
    patch_sandbox "${PATCH_TMP}/upstream.sh" "${PATCH_TMP}/patched.sh"
    if verify_sandbox_patch "${PATCH_TMP}/patched.sh"; then
      SANDBOX_PATCH_NEEDED=1
      success "Die Fixes lassen sich auf den neuen Stand anwenden."
    else
      echo ""
      error "Die drei NsJail-Fixes passen nicht mehr auf das neue ${SANDBOX_SRC}."
      error "Moegliche Ursachen: upstream hat die Fehler selbst behoben oder das"
      error "Skript grundlegend umgebaut. Ein blindes Weiterlaufen wuerde den"
      error "Sandbox-Starter mit einer veralteten Kopie ueberdecken."
      echo ""
      echo -e " Naechste Schritte:"
      echo -e "   1. Aenderung ansehen:"
      echo -e "      ${CYAN}git -C ${INSTALL_DIR} diff ${GIT_OLD:0:7} FETCH_HEAD -- ${SANDBOX_SRC}${RESET}"
      echo -e "   2. Sind die Fehler behoben, den Volume-Mount fuer"
      echo -e "      ${CYAN}${SANDBOX_COPY}${RESET} aus ${MARKER_FILE} entfernen"
      echo -e "      (oder den Installer auf einem frischen Pfad neu laufen lassen)."
      echo ""
      die "Abbruch vor jeder Aenderung - der laufende Stack ist unberuehrt."
    fi
    rm -rf "${PATCH_TMP}"
    trap - EXIT
  else
    info "${SANDBOX_SRC} ist upstream unveraendert - die gepatchte Kopie bleibt gueltig."
  fi
fi

# Aenderungen am Erzeuger der Laufzeitumgebungen erkennen: nur dann ist ein
# Neubau von data/pkgs wirklich noetig (mehrere Minuten, ~3 GB).
PKGS_RECOMMENDED=0
if [[ "${NSJAIL_MODE}" -eq 1 && "${GIT_CHANGED}" -eq 1 && -n "${CHANGED_FILES}" ]]; then
  if grep -qE '^docker/Dockerfile\.package-init$|^docker/packages/' <<<"${CHANGED_FILES}"; then
    PKGS_RECOMMENDED=1
  fi
fi

# -- 3. Aktueller und zukuenftiger Stand ---------------------------------------
tag_of() {
  local ref="$1" tail="${1##*:}"
  [[ "${ref}" == *:* && "${tail}" != */* ]] && printf '%s' "${tail}" || printf 'latest'
}

echo ""
echo "============================================================"
echo -e "${BOLD} AKTUELLER STAND  ->  ZUKUENFTIGER STAND${RESET}"
echo "============================================================"
printf ' %-26s %-22s %-22s\n' "Komponente" "JETZT" "NACHHER"
printf ' %-26s %-22s %-22s\n' "--------------------------" "----------------------" "----------------------"

if [[ "${GIT_OK}" -eq 1 ]]; then
  if [[ "${GIT_CHANGED}" -eq 1 ]]; then
    printf ' %-26s %-22s %b%-22s%b %b\n' "Quellcode (${GIT_BRANCH})" \
      "${GIT_OLD:0:7} ${GIT_OLD_DATE:-}" "${GREEN}" "${GIT_NEW:0:7} ${GIT_NEW_DATE:-}" "${RESET}" "${GREEN}<- neu${RESET}"
  else
    printf ' %-26s %-22s %-22s\n' "Quellcode (${GIT_BRANCH})" "${GIT_OLD:0:7} ${GIT_OLD_DATE:-}" "unveraendert"
  fi
fi

for img in "${IMAGES_NOW[@]}"; do
  name="${img##*/}"; name="${name%%:*}"
  if [[ "${IS_LOCAL[${img}]}" == "1" ]]; then
    now="${OLD_IDS[${img}]:7:10}"
    [[ -n "${now}" ]] || now="nicht gebaut"
    if [[ "${GIT_CHANGED}" -eq 1 || "${FORCE_BUILD}" -eq 1 || -z "${OLD_IDS[${img}]}" ]]; then
      printf ' %-26s %-22s %b%-22s%b %b\n' "${name} (lokal gebaut)" "${now}" "${GREEN}" "wird neu gebaut" "${RESET}" "${GREEN}<- neu${RESET}"
    else
      printf ' %-26s %-22s %-22s\n' "${name} (lokal gebaut)" "${now}" "unveraendert"
    fi
  else
    now="$(tag_of "${img}") (${OLD_IDS[${img}]:7:8})"
    next="$(tag_of "${img}") (${NEW_IDS[${img}]:7:8})"
    if [[ "${OLD_IDS[${img}]}" != "${NEW_IDS[${img}]}" ]]; then
      printf ' %-26s %-22s %b%-22s%b %b\n' "${name} (Registry)" "${now}" "${GREEN}" "${next}" "${RESET}" "${GREEN}<- neu${RESET}"
    else
      printf ' %-26s %-22s %-22s\n' "${name} (Registry)" "${now}" "unveraendert"
    fi
  fi
done

if [[ "${NSJAIL_MODE}" -eq 1 ]]; then
  echo ""
  if [[ "${SANDBOX_PATCH_NEEDED}" -eq 1 ]]; then
    echo -e " NsJail-Fix:  ${YELLOW}wird aus dem neuen Quellstand neu erzeugt${RESET}"
  else
    echo -e " NsJail-Fix:  unveraendert (${SANDBOX_COPY})"
  fi
  if [[ "${PKGS_RECOMMENDED}" -eq 1 ]]; then
    echo -e " data/pkgs:   ${YELLOW}Erzeuger upstream geaendert - Neubau empfohlen${RESET}"
  else
    echo -e " data/pkgs:   unveraendert (Neubau nicht erforderlich)"
  fi
fi

# -- Nichts Neues: hier ist Schluss, ohne irgendetwas anzufassen ---------------
if [[ "${GIT_CHANGED}" -eq 0 && "${IMAGES_CHANGED}" -eq 0 && "${FORCE_BUILD}" -eq 0 ]]; then
  echo ""
  echo "------------------------------------------------------------"
  success "NOCHANGE: bereits aktuell - kein Backup, kein Neubau, keine Aenderung."
  echo "------------------------------------------------------------"
  echo -e " Trotzdem neu bauen (z.B. fuer neue Basis-Images oder nach einer"
  echo -e " Aenderung an der .env): ${CYAN}--force-build${RESET}, bei Bedarf mit ${CYAN}--pull${RESET}."
  echo ""
  exit 0
fi

# -- 4. Rueckfragen ------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Rueckfragen${RESET}"
echo "------------------------------------------------------------"

REQUIRED_FREE_MB="${MIN_FREE_MB}"
DO_PKGS=0
if [[ "${NSJAIL_MODE}" -eq 1 ]]; then
  case "${PKGS_MODE}" in
    always) DO_PKGS=1; info "Laufzeitumgebungen werden neu erzeugt (--pkgs)." ;;
    never)  DO_PKGS=0; info "Laufzeitumgebungen bleiben unveraendert (--no-pkgs)." ;;
    auto)
      if [[ "${PKGS_RECOMMENDED}" -eq 1 ]]; then
        warn "Upstream hat den Erzeuger der Laufzeitumgebungen geaendert."
        warn "Ohne Neubau laufen Python/Node/Bun/Bash weiter in der alten Fassung."
        ask_yesno "Laufzeitumgebungen unter data/pkgs neu erzeugen (dauert einige Minuten)?" "j" && DO_PKGS=1
      else
        info "Laufzeitumgebungen bleiben unveraendert - kein Anlass fuer einen Neubau."
      fi
      ;;
  esac
  [[ "${DO_PKGS}" -eq 1 ]] && REQUIRED_FREE_MB=$((MIN_FREE_MB + MIN_FREE_PKGS_MB))
fi
readonly DO_PKGS

if (( FREE_MB < REQUIRED_FREE_MB )); then
  error "Nur ${FREE_MB} MB frei auf ${DOCKER_ROOT}, benoetigt werden etwa ${REQUIRED_FREE_MB} MB."
  die "Der Neubau wuerde vermutlich mitten drin abbrechen. Bitte zuerst Platz schaffen (z.B. 'docker image prune -a')."
fi

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
STEP_NO=0
if [[ "${#CONFIG_ITEMS[@]}" -gt 0 ]]; then
  step "gesichert nach ${CYAN}$(basename "${BACKUP_FILE}")${RESET}: ${CONFIG_ITEMS[*]}"
else
  step "${YELLOW}kein Backup erstellt${RESET} (keine Konfigurationsdateien gefunden)"
fi
if [[ "${GIT_CHANGED}" -eq 1 ]]; then
  step "der Quellcode per ${CYAN}merge --ff-only${RESET} auf ${GIT_NEW:0:7} gebracht"
else
  step "der Quellcode nicht angefasst"
fi
[[ "${SANDBOX_PATCH_NEEDED}" -eq 1 ]] && \
step "${CYAN}${SANDBOX_COPY}${RESET} aus dem neuen Quellstand neu erzeugt"
step "die Compose-Konfiguration validiert und ${CYAN}${COMPOSE_CMD} build${RESET} ausgefuehrt"
echo -e "      ${YELLOW}- das kann 10-30+ Minuten dauern, der Stack laeuft dabei weiter${RESET}"
[[ "${DO_PKGS}" -eq 1 ]] && \
step "${CYAN}data/pkgs${RESET} neu erzeugt (Python wird aus dem Quellcode kompiliert)"
step "der Stack neu hochgefahren - kurze Downtime, meist unter einer Minute"
if [[ "${#DROP_BACKUPS[@]}" -gt 0 ]]; then
  step "${#DROP_BACKUPS[@]} alte(s) Backup(s) entfernt, aeltestes: ${CYAN}$(basename "${DROP_BACKUPS[-1]}")${RESET}"
else
  step "kein altes Backup entfernt (${BACKUP_COUNT} von ${KEEP} belegt)"
fi
echo ""
echo -e " ${BOLD}Unveraendert bleibt:${RESET} .env mit allen Secrets und Schluesseln, die"
echo -e " Override-Datei mit den geschlossenen Host-Ports, das Docker-Netzwerk"
echo -e " ${CYAN}shared_proxy${RESET} samt aller anderen Stacks - und die LibreChat-Seite:"
echo -e " weder .env noch Proxy Host in NPM werden angefasst."

if ! ask_yesno "${BOLD}Update jetzt durchfuehren?${RESET}" "n"; then
  warn "Abgebrochen. Es wurde nichts veraendert."
  echo -e " Geladene Layer und Commits liegen lokal und werden beim naechsten Lauf verwendet."
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

  {
    echo "ERSTELLT=${TS}"
    echo "HOST=$(hostname 2>/dev/null || echo unbekannt)"
    echo "INSTALL_DIR=${INSTALL_DIR}"
    echo "GIT_COMMIT_VOR_UPDATE=${GIT_OLD:-unbekannt}"
    echo "GIT_BRANCH=${GIT_BRANCH:-unbekannt}"
    echo "ISOLATION=$( [[ "${NSJAIL_MODE}" -eq 1 ]] && echo nsjail || echo microvm )"
    echo "KONFIGURATION=${CONFIG_ITEMS[*]}"
    echo "HINWEIS=data/pkgs und die Session-Daten in Redis/MinIO sind NICHT enthalten"
  } > "${STAGE}/manifest.txt"

  # -C: relative Pfade im Archiv, unabhaengig vom Arbeitsverzeichnis.
  tar czf "${BACKUP_FILE}" -C "${STAGE}" .
  # Das Archiv enthaelt die .env mit allen Secrets und - bei nicht
  # uebertragenem JWT-Block - den privaten Signierschluessel.
  chmod 600 "${BACKUP_FILE}"
  rm -rf "${STAGE}"
  trap - EXIT
  success "Backup erstellt: $(basename "${BACKUP_FILE}") ($(du -h "${BACKUP_FILE}" | cut -f1))"
fi

if [[ "${GIT_CHANGED}" -eq 1 ]]; then
  info "Aktualisiere den Quellcode (merge --ff-only)..."
  # --ff-only statt 'git pull': schlaegt sauber fehl, statt bei lokalen Commits
  # einen Merge-Commit oder Konflikte im Installationsverzeichnis zu erzeugen.
  if ! git -C "${INSTALL_DIR}" merge --ff-only FETCH_HEAD; then
    error "Fast-Forward nicht moeglich - der Quellcode wurde nicht veraendert."
    error "Bitte manuell pruefen: git -C ${INSTALL_DIR} status"
    die "Abbruch vor dem Neubau. Das Backup liegt unter ${BACKUP_FILE:-<keines>}."
  fi
  success "Quellcode auf $(git -C "${INSTALL_DIR}" rev-parse --short HEAD) gebracht."
fi

if [[ "${SANDBOX_PATCH_NEEDED}" -eq 1 ]]; then
  info "Erzeuge ${SANDBOX_COPY} aus dem neuen Quellstand..."
  cp -a "${INSTALL_DIR}/${SANDBOX_COPY}" "${INSTALL_DIR}/${SANDBOX_COPY}.vor-${TS}" 2>/dev/null || true
  patch_sandbox "${INSTALL_DIR}/${SANDBOX_SRC}" "${INSTALL_DIR}/${SANDBOX_COPY}.neu"
  if ! verify_sandbox_patch "${INSTALL_DIR}/${SANDBOX_COPY}.neu"; then
    rm -f "${INSTALL_DIR}/${SANDBOX_COPY}.neu"
    die "Patch fuer ${SANDBOX_SRC} liess sich nach dem Merge nicht anwenden - alte Kopie bleibt aktiv, Stack nicht neu gestartet."
  fi
  mv "${INSTALL_DIR}/${SANDBOX_COPY}.neu" "${INSTALL_DIR}/${SANDBOX_COPY}"
  chmod +x "${INSTALL_DIR}/${SANDBOX_COPY}"
  success "NsJail-Fix neu erzeugt (Vorgaenger: $(basename "${SANDBOX_COPY}").vor-${TS})."
fi

info "Validiere die Compose-Konfiguration..."
# Nach einem Quell-Update kann sich die Basis-Compose-Datei geaendert haben
# (neue oder umbenannte Services). Passt das Override nicht mehr dazu, faellt
# das hier auf - vor dem Build, nicht mittendrin.
if ! dc config --quiet; then
  error "Die Compose-Konfiguration ist nach dem Update ungueltig."
  error "Haeufigste Ursache: ${MARKER_FILE} verweist auf einen Service, den es"
  error "in der neuen $(basename "${COMPOSE_FILE}") nicht mehr gibt."
  if [[ "${GIT_CHANGED}" -eq 1 ]]; then
    warn "Setze den Quellcode auf ${GIT_OLD:0:7} zurueck, damit der Stack weiterlaeuft..."
    if git -C "${INSTALL_DIR}" reset --hard "${GIT_OLD}" >/dev/null 2>&1; then
      success "Quellcode zurueckgesetzt - der laufende Stack bleibt unveraendert."
    else
      error "Ruecksetzen fehlgeschlagen. Bitte manuell: git -C ${INSTALL_DIR} reset --hard ${GIT_OLD:0:7}"
    fi
  fi
  die "Der Stack wurde NICHT neu gebaut oder gestartet. Bitte die Override-Datei anpassen."
fi
success "Compose-Konfiguration ist gueltig."

declare -a BUILD_ARGS=()
[[ "${BUILD_PULL}" -eq 1 ]] && BUILD_ARGS+=(--pull)
[[ "${BUILD_NO_CACHE}" -eq 1 ]] && BUILD_ARGS+=(--no-cache)
info "Baue die Images neu - das dauert, bitte nicht abbrechen..."
if ! dc build ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}; then
  error "Der Build ist fehlgeschlagen. Der alte Stack laeuft unveraendert weiter."
  echo -e " Haeufige Ursachen: kein Plattenplatz mehr, kein Netz zur Registry,"
  echo -e " oder eine Aenderung im Quellcode. Log: ${CYAN}${LOG}${RESET}"
  if [[ "${GIT_CHANGED}" -eq 1 ]]; then
    echo -e " Quellstand zuruecknehmen: ${CYAN}git -C ${INSTALL_DIR} reset --hard ${GIT_OLD:0:7}${RESET}"
  fi
  die "Abbruch nach dem Build - es wurde kein Container neu gestartet."
fi
success "Images gebaut."

if [[ "${DO_PKGS}" -eq 1 ]]; then
  info "Erzeuge die Laufzeitumgebungen neu (Python wird kompiliert)..."
  mkdir -p "${INSTALL_DIR}/data/pkgs"
  ( cd "${INSTALL_DIR}" && docker build -f docker/Dockerfile.package-init -t "${PKG_INIT_IMAGE}" . ) \
    || die "Image fuer die Laufzeitumgebungen konnte nicht gebaut werden - Stack nicht neu gestartet."
  docker run --rm -v "${INSTALL_DIR}/data/pkgs:/pkgs" "${PKG_INIT_IMAGE}" \
    || die "Laufzeitumgebungen konnten nicht erzeugt werden - Stack nicht neu gestartet."
  # Gegenpruefung: fehlt eine der vier Laufzeiten, scheitert spaeter JEDE
  # Codeausfuehrung mit "<runtime> is unknown" - das faellt sonst erst beim
  # ersten echten Nutzer-Aufruf auf.
  for runtime in python node bun bash; do
    [[ -e "${INSTALL_DIR}/data/pkgs/${runtime}" ]] \
      || die "Laufzeitumgebung '${runtime}' fehlt unter ${INSTALL_DIR}/data/pkgs - Abbruch."
  done
  success "Laufzeitumgebungen bereit: python, node, bun, bash."
fi

info "Fahre den Stack neu hoch..."
dc up -d

# -- Auf Bereitschaft warten ---------------------------------------------------
# Reihenfolge wie im Installer. sandbox-runner braucht im NsJail-Modus am
# laengsten, deshalb grosszuegiges Zeitfenster.
wait_ready() {
  local service="$1" cid state health
  for _ in {1..80}; do
    cid="$(dc ps -q "${service}" 2>/dev/null || true)"
    if [[ -n "${cid}" ]]; then
      state="$(docker inspect --format '{{.State.Status}}' "${cid}" 2>/dev/null || true)"
      health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${cid}" 2>/dev/null || true)"
      if [[ "${health}" == "healthy" || ( "${health}" == "none" && "${state}" == "running" ) ]]; then
        success "${service} ist bereit (${state}, health=${health})."
        return 0
      fi
      [[ "${state}" == "exited" || "${state}" == "dead" ]] && break
    fi
    sleep 3
  done
  return 1
}

FAILED_SERVICES=()
for svc in "${SERVICES[@]}"; do
  wait_ready "${svc}" || FAILED_SERVICES+=("${svc}")
done

if [[ "${#FAILED_SERVICES[@]}" -gt 0 ]]; then
  echo ""
  dc ps || true
  for svc in "${FAILED_SERVICES[@]}"; do
    echo ""
    warn "Logs von ${svc}:"
    dc logs --tail=40 "${svc}" || true
  done
  echo ""
  error "Diese Services wurden nicht bereit: ${FAILED_SERVICES[*]}"
  echo -e " Das Backup liegt unter ${CYAN}${BACKUP_FILE:-<keines>}${RESET}."
  echo -e " Rollback: ${CYAN}cd ${INSTALL_DIR} && ${COMPOSE_CMD} down${RESET}, dann"
  [[ "${GIT_CHANGED}" -eq 1 ]] && \
  echo -e "           ${CYAN}git -C ${INSTALL_DIR} reset --hard ${GIT_OLD:0:7}${RESET}, dann"
  echo -e "           ${CYAN}cd ${INSTALL_DIR} && ${COMPOSE_CMD} build && ${COMPOSE_CMD} up -d${RESET}"
  die "Update unvollstaendig."
fi

if [[ "${GIT_CHANGED}" -eq 1 ]]; then
  success "UPDATED: Quellcode ${GIT_OLD:0:7} -> ${GIT_NEW:0:7}, Images neu gebaut."
else
  success "UPDATED: Images neu gebaut, Quellcode unveraendert (${GIT_OLD:0:7})."
fi

echo ""
dc ps || true

# -- Sicherheits-Check: kein Port oeffentlich ----------------------------------
# Gleiche Pruefung wie im Installer: ein Upstream-Update kann neue Services mit
# 'ports:' mitbringen, die das Override nicht kennt und die dann doch am Host
# haengen.
echo ""
PUBLIC_PORT_FOUND=0
while IFS= read -r cname; do
  [[ -n "${cname}" ]] || continue
  if docker port "${cname}" 2>/dev/null | grep -q '0\.0\.0\.0\|\[::\]'; then
    warn "Container ${cname} hat einen oeffentlich gebundenen Port - bitte pruefen: docker port ${cname}"
    warn "Abhilfe: den Service in ${MARKER_FILE} mit 'ports: !reset []' ergaenzen."
    PUBLIC_PORT_FOUND=1
  fi
done < <(dc ps -a --format '{{.Name}}' 2>/dev/null || true)
(( PUBLIC_PORT_FOUND == 0 )) && success "Kein Container hat einen oeffentlich gebundenen Port."

# Rotation erst jetzt - das frische Backup zaehlt mit.
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
info "Der Build-Cache bleibt bewusst erhalten - er beschleunigt den naechsten"
info "Lauf erheblich. Bei Platzmangel: docker builder prune"

# -- Hinweis auf neue .env-Variablen -------------------------------------------
# Nach einem Quell-Update kann die Beispiel-Konfiguration neue Schalter
# kennen, die in der bestehenden .env fehlen. Fehlende Werte fallen sonst erst
# im Betrieb auf - deshalb hier nur melden, nie automatisch eintragen.
if [[ "${GIT_CHANGED}" -eq 1 && -f "${INSTALL_DIR}/.env.example" && -f "${INSTALL_DIR}/.env" ]]; then
  # Bewusst ueber echte Dateien statt Process Substitution: 'comm' muss die
  # beiden Listen selbst oeffnen, und /dev/fd ist nicht auf jedem System da.
  KEYS_EXAMPLE="$(mktemp)"; KEYS_ENV="$(mktemp)"
  grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "${INSTALL_DIR}/.env.example" | tr -d '=' | sort -u >"${KEYS_EXAMPLE}"
  grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "${INSTALL_DIR}/.env" | tr -d '=' | sort -u >"${KEYS_ENV}"
  mapfile -t MISSING_KEYS < <(comm -23 "${KEYS_EXAMPLE}" "${KEYS_ENV}")
  rm -f "${KEYS_EXAMPLE}" "${KEYS_ENV}"
  if [[ "${#MISSING_KEYS[@]}" -gt 0 ]]; then
    echo ""
    warn "Die neue .env.example kennt ${#MISSING_KEYS[@]} Variable(n), die in deiner .env fehlen:"
    for k in "${MISSING_KEYS[@]}"; do echo -e "   - ${CYAN}${k}${RESET}"; done
    warn "Sie werden bewusst NICHT automatisch gesetzt. Meist greifen die"
    warn "Standardwerte; im Zweifel in der .env.example nachlesen und von Hand"
    warn "uebernehmen, danach: cd ${INSTALL_DIR} && ${COMPOSE_CMD} up -d"
  fi
fi

# -- Abschluss -----------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${GREEN}${BOLD} Update abgeschlossen.${RESET}  $(date '+%F %T')"
echo "------------------------------------------------------------"
echo ""
if [[ "${NSJAIL_MODE}" -eq 1 ]]; then
  warn "Isolation: NsJail-only-Modus (teilt sich den Host-Kernel, laut Projekt-Doku"
  warn "geeignet fuer lokale Tests, nicht fuer produktive Systeme mit unbekannten Nutzern)."
else
  success "Isolation: MicroVM-Modus (voll gehaertet)."
fi
echo ""
echo -e " LibreChat selbst wurde ${BOLD}nicht${RESET} angefasst: weder .env noch Proxy Host."
echo -e " Ein Neustart von LibreChat ist nur noetig, wenn du dort Werte aenderst -"
echo -e " und dann als echtes Stop+Start, ein 'docker restart' liest die .env NICHT neu:"
echo -e "   ${CYAN}docker stop LibreChat && docker start LibreChat${RESET}"
echo ""
if [[ -f "${BACKUP_FILE:-/nonexistent}" ]]; then
  echo -e " Backup: ${CYAN}${BACKUP_FILE}${RESET}"
  echo ""
  echo -e " Rollback bei Problemen:"
  echo -e "   ${CYAN}cd ${INSTALL_DIR} && ${COMPOSE_CMD} down${RESET}"
  echo -e "   ${CYAN}mkdir -p /tmp/ci-restore && tar xzf ${BACKUP_FILE} -C /tmp/ci-restore${RESET}"
  echo -e "   ${CYAN}cp -a /tmp/ci-restore/config/. ${INSTALL_DIR}/${RESET}"
  [[ "${GIT_CHANGED}" -eq 1 ]] && \
  echo -e "   ${CYAN}git -C ${INSTALL_DIR} reset --hard ${GIT_OLD:0:7}${RESET}   (alter Quellstand)"
  echo -e "   ${CYAN}cd ${INSTALL_DIR} && ${COMPOSE_CMD} build && ${COMPOSE_CMD} up -d${RESET}"
  echo ""
fi
echo -e " Wichtige Befehle:"
echo -e "   Logs:   ${CYAN}cd ${INSTALL_DIR} && ${COMPOSE_CMD} logs -f${RESET}"
echo -e "   Status: ${CYAN}cd ${INSTALL_DIR} && ${COMPOSE_CMD} ps${RESET}"
echo ""
echo -e " Mehr Tipps & Tutorials: ${CYAN}https://pc-fee.com/blog${RESET}"
echo -e " GitHub:                 ${CYAN}${GUIDE_URL}${RESET}"
echo ""
