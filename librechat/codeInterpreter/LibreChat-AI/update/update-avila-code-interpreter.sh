#!/usr/bin/env bash
# =============================================================================
# avila-code-interpreter Update Script - powered by pc-fee.com
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Aktualisiert eine mit install-avila-code-interpreter.sh installierte Instanz
# des LibreChat Code Interpreters - im Ablauf wie das n8n-Update-Script.
#
# Ablauf auf dem Bildschirm:
#   1. Zusammenfassung - wo liegt die Installation, welche Version laeuft
#   2. Version waehlen - installierte und neueste Version nebeneinander, dann
#      "Auf welche Version updaten? [neueste]". Jede veroeffentlichte Version
#      mit fertigen Images ist waehlbar, auch eine aeltere (Rueckstufung).
#   3. Pruefung auf Neuerungen (Zielversion holen, Basis-Images pruefen); der
#      laufende Stack bleibt dabei unberuehrt
#   4. Aktueller Stand und zukuenftiger Stand je Komponente
#   5. Rueckfragen (Laufzeitumgebungen, Backup-Rotation), dann die Bestaetigung
#   6. Durchfuehrung: Backup, Rollback-Stand sichern, Version umstellen,
#      Compose-Validierung, Images laden, Stack hochfahren, Health Check
#   7. Schlaegt etwas fehl: automatisches Rollback auf den vorherigen Stand
#
# Versionen: Installiert wird ausschliesslich eine veroeffentlichte Version
# (Tag wie v1.10.4) mit den fertigen Images der Entwickler von ghcr.io - nie
# der Entwicklungsstand "main". Ohne Terminal (Cron) bzw. mit --yes geht es
# ohne Rueckfrage auf die neueste Version; --version legt eine bestimmte fest.
#
# Ohne Bestaetigung wird nichts veraendert. Fuer Cron: --yes bzw. ASSUME_YES=1.
#
# Nutzung als 1-Zeiler (von ueberall, kein vorheriger Download noetig):
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/update/update-avila-code-interpreter.sh)"
#
# Optionen:
#   --dir <pfad>     Installationspfad fest vorgeben (ueberspringt die Erkennung)
#   --version <v>    Zielversion vorgeben statt Abfrage (z.B. v1.10.4)
#   --keep <n>       Anzahl aufzubewahrender Backups - ohne Angabe wird gefragt
#   --force          Auch ohne Neuerung neu laden und neu starten
#   --pkgs           Laufzeitumgebungen (data/pkgs) neu erzeugen - nur NsJail
#   --no-pkgs        Laufzeitumgebungen nie neu erzeugen - nur NsJail
#   --dry-run        Zeigt nur, was passieren wuerde - aendert nichts
#   --yes            Ueberspringt die Rueckfragen (wie ASSUME_YES=1, fuer Cron)
#   --help           Diese Hilfe anzeigen
#
# Umgebungsvariablen (fuer unbeaufsichtigten Betrieb, z.B. Cron):
#   INSTALL_DIR      wie --dir
#   CODEAPI_VERSION  wie --version
#   KEEP_BACKUPS     wie --keep
#   ASSUME_YES=1     wie --yes
#   LOG_FILE         Logdatei (Default: /var/log/avila-code-interpreter-update.log)
#
# Der Installationspfad wird automatisch ermittelt (Container-Label des
# avila-api-Containers -> /opt/avila-code-interpreter). Nur bei mehreren
# Treffern wird gefragt.
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
readonly GUIDE_URL="https://github.com/nephilim75/scripts/tree/main/librechat/codeInterpreter/LibreChat-AI"
readonly TAGS_URL="https://github.com/LibreChat-AI/code-interpreter/tags"
readonly DEFAULT_DIR="/opt/avila-code-interpreter"
# Marker der eigenen Installation: die docker-compose.override.yml schreibt
# ausschliesslich der Installer; sie benennt den API-Container und verweist
# auf die fertigen Images.
readonly MARKER_FILE="docker-compose.override.yml"
readonly MARKER_STRING="container_name: avila-api"
readonly IMAGE_MARKER="ghcr.io/librechat-ai/code-interpreter-"
readonly API_CONTAINER="avila-api"
readonly PKG_INIT_IMAGE="avila-package-init"
readonly BACKUP_PREFIX="avila-code-interpreter"
readonly DEFAULT_KEEP=5
# Tag, unter dem die laufenden Basis-Images (redis, minio) vor dem Update
# gesichert werden - ihr Tag kann sich beim Laden aendern.
readonly ROLLBACK_TAG="avila-rollback"
# Reihenfolge wie im Installer: Abhaengigkeiten zuerst.
readonly SERVICES=(redis minio tool_call_server egress_gateway sandbox-runner file_server api service-worker)
# Platzbedarf: neue Images (komprimiert rund 0,9 GB, dazu entpackt) neben den
# alten, die fuer ein Rollback bis zum Erfolg liegen bleiben.
readonly MIN_FREE_MB=4000
# Beim Neubau von data/pkgs bleiben die alten Laufzeitumgebungen (~3 GB) fuer
# ein Rollback liegen, dazu kommen die neuen (~3 GB) und das Init-Image.
readonly MIN_FREE_PKGS_MB=8000

# -- Optionen ------------------------------------------------------------------
DRY_RUN=0
FORCE=0
PKGS_MODE="auto"   # auto | always | never
KEEP=""
KEEP_EXPLICIT=0
TARGET_VERSION="${CODEAPI_VERSION:-}"
LOG="${LOG_FILE:-/var/log/avila-code-interpreter-update.log}"

if [[ -n "${KEEP_BACKUPS:-}" ]]; then
  KEEP="${KEEP_BACKUPS}"
  KEEP_EXPLICIT=1
fi

usage() {
  cat <<'USAGE'
avila-code-interpreter Update Script - powered by pc-fee.com

Aktualisiert eine mit install-avila-code-interpreter.sh installierte Instanz
des LibreChat Code Interpreters. Wie beim n8n-Update wird nach der Zielversion
gefragt (Vorschlag: neueste veroeffentlichte Version mit fertigen Images).
Vor der Bestaetigung wird nichts veraendert; schlaegt das Update fehl, wird
automatisch auf den vorherigen Stand zurueckgerollt.

Optionen:
  --dir <pfad>     Installationspfad fest vorgeben (ueberspringt die Erkennung)
  --version <v>    Zielversion vorgeben statt Abfrage (z.B. v1.10.4)
  --keep <n>       Anzahl aufzubewahrender Backups - ohne Angabe wird gefragt
  --force          Auch ohne Neuerung neu laden und neu starten
  --pkgs           Laufzeitumgebungen (data/pkgs) neu erzeugen - nur NsJail
  --no-pkgs        Laufzeitumgebungen nie neu erzeugen - nur NsJail
  --dry-run        Zeigt nur, was passieren wuerde - aendert nichts
  --yes            Ueberspringt die Rueckfragen (wie ASSUME_YES=1, fuer Cron)
  --help           Diese Hilfe anzeigen

Umgebungsvariablen: INSTALL_DIR, CODEAPI_VERSION, KEEP_BACKUPS, ASSUME_YES, LOG_FILE

Beispiele:
  sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/update/update-avila-code-interpreter.sh)"
  sudo ./update-avila-code-interpreter.sh --dry-run
  sudo ./update-avila-code-interpreter.sh --version v1.10.3
  sudo ./update-avila-code-interpreter.sh --yes --keep 5      (Cron)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)          INSTALL_DIR="${2:-}"; shift 2 || true ;;
    --dir=*)        INSTALL_DIR="${1#*=}"; shift ;;
    --version)      TARGET_VERSION="${2:-}"; shift 2 || true ;;
    --version=*)    TARGET_VERSION="${1#*=}"; shift ;;
    --keep)         KEEP="${2:-}"; KEEP_EXPLICIT=1; shift 2 || true ;;
    --keep=*)       KEEP="${1#*=}"; KEEP_EXPLICIT=1; shift ;;
    --force)        FORCE=1; shift ;;
    --pkgs)         PKGS_MODE="always"; shift ;;
    --no-pkgs)      PKGS_MODE="never"; shift ;;
    --dry-run)      DRY_RUN=1; shift ;;
    --yes|-y)       ASSUME_YES=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              echo "Unbekannte Option: $1 (siehe --help)" >&2; exit 1 ;;
  esac
done
# FORCE bleibt veraenderbar: "Trotzdem fortfahren?" setzt es spaeter.
readonly DRY_RUN PKGS_MODE KEEP_EXPLICIT

# "1.10.4" ohne fuehrendes v ebenfalls akzeptieren.
normalize_version() { local v="$1"; [[ "${v}" =~ ^[0-9] ]] && v="v${v}"; printf '%s' "${v}"; }
is_version_format() { [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]]; }

# Ausdruecklich gesetzte Werte sofort pruefen - ein Tippfehler im Cron-Eintrag
# soll nicht erst nach dem Backup auffallen.
if [[ "${KEEP_EXPLICIT}" -eq 1 ]]; then
  if ! [[ "${KEEP}" =~ ^[0-9]+$ ]] || [[ "${KEEP}" -lt 1 ]]; then
    echo "--keep erwartet eine positive Ganzzahl (erhalten: '${KEEP}')." >&2
    exit 1
  fi
fi
if [[ -n "${TARGET_VERSION}" ]]; then
  TARGET_VERSION="$(normalize_version "${TARGET_VERSION}")"
  if ! is_version_format "${TARGET_VERSION}"; then
    echo "--version erwartet eine Versionsnummer wie v1.10.4 (erhalten: '${TARGET_VERSION}')." >&2
    exit 1
  fi
fi

# -- Eingabequelle -------------------------------------------------------------
# Wird das Script per 'curl ... | bash' gestartet, liegt auf stdin der Script-
# Text selbst - ein 'read' wuerde ihn verschlucken. Deshalb immer vom Terminal
# lesen. Ohne Terminal (z.B. Cron) wird nie gefragt.
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

# ask_text <prompt> <default> -> gibt die Eingabe (oder den Default) aus.
ask_text() {
  local prompt="$1" default="$2" input=""
  if [[ "${INTERACTIVE}" -eq 0 || "${ASSUME_YES:-0}" == "1" ]]; then
    printf '%s' "${default}"
    return 0
  fi
  echo "" >&2
  echo -ne "${BOLD}${prompt}${RESET} [${CYAN}${default}${RESET}]: " >&2
  read -r input <"${TTY}" || true
  printf '%s' "${input:-${default}}"
}

# run <befehl...> - im Dry-Run nur anzeigen, sonst ausfuehren.
run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo -e "${YELLOW}   [DRY-RUN]${RESET} $*"
  else
    "$@"
  fi
}

# version_lt A B -> wahr, wenn A aelter als B ist.
version_lt() {
  [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" == "$1" ]]
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
echo -e " Aktualisiert den LibreChat Code Interpreter (LibreChat-AI) auf eine"
echo -e " neue Version - mit Backup, Health Check und automatischem Rollback."
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo -e " ${YELLOW}${BOLD}DRY-RUN aktiv:${RESET} es wird nichts veraendert, nur angezeigt."
fi
echo "------------------------------------------------------------"

# -- Root-Check ----------------------------------------------------------------
[[ "${EUID}" -eq 0 ]] || die "Bitte als root oder mit sudo ausfuehren."

# In ein garantiert existierendes Verzeichnis wechseln. Wurde die CWD der
# aufrufenden Shell zwischenzeitlich geloescht, scheitern spaetere Aufrufe
# sonst mit 'getcwd: cannot access parent directories'.
cd / 2>/dev/null || die "Konnte nicht nach / wechseln."

# -- Voraussetzungen pruefen ---------------------------------------------------
command -v docker &>/dev/null || die "Docker ist nicht installiert."
docker info &>/dev/null || die "Docker-Daemon laeuft nicht. Bitte starten: systemctl start docker"
docker compose version &>/dev/null || die "Docker Compose Plugin nicht gefunden."
readonly COMPOSE_CMD="docker compose"
command -v git &>/dev/null || die "'git' nicht gefunden - wird fuer den Versionswechsel gebraucht."
command -v tar &>/dev/null || die "'tar' nicht gefunden - wird fuer das Backup gebraucht."

# -- Installationspfad ermitteln -----------------------------------------------
is_install_dir() {
  local d="$1"
  [[ -f "${d}/${MARKER_FILE}" ]] && grep -q "${MARKER_STRING}" "${d}/${MARKER_FILE}" 2>/dev/null
}

detect_dirs() {
  local -a raw=() out=()
  local cid d existing seen
  # 1. API-Container (laufend oder gestoppt): Compose-Working-Dir aus dem Label.
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
      die "Keine Code-Interpreter-Installation gefunden.\n  Erwartet wurde eine ${MARKER_FILE} mit '${MARKER_STRING}',\n  z.B. unter ${DEFAULT_DIR}. Pfad ggf. direkt angeben: --dir /pfad/zur/installation"
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
readonly ENV_FILE="${INSTALL_DIR}/.env"
readonly BACKUP_DIR="${INSTALL_DIR}/backups"

# Diese Fassung arbeitet ausschliesslich mit fertigen Images. Installationen
# frueherer Installer-Fassungen (lokal gebaut) werden nicht umgestellt.
if ! grep -q "${IMAGE_MARKER}" "${INSTALL_DIR}/${MARKER_FILE}" || ! grep -q '^CODEAPI_IMAGE_TAG=' "${ENV_FILE}" 2>/dev/null; then
  error "${INSTALL_DIR} stammt von einer frueheren Fassung des Installers"
  error "(Images lokal gebaut). Diese Fassung des Update-Scripts stellt solche"
  error "Installationen nicht um."
  echo -e " Bitte entfernen und neu installieren:"
  echo -e "   ${CYAN}uninstall-avila-code-interpreter.sh${RESET}, danach ${CYAN}install-avila-code-interpreter.sh${RESET}"
  echo -e "   (${GUIDE_URL})"
  die "Abbruch - es wurde nichts veraendert."
fi
[[ -d "${INSTALL_DIR}/.git" ]] || die "In ${INSTALL_DIR} fehlt das Repository (.git) - unvollstaendige Installation?"

# Compose immer aus dem Installationsverzeichnis heraus aufrufen: nur so zieht
# Docker Compose die Override-Datei (Images, Namen, geschlossene Ports,
# shared_proxy) und die .env automatisch mit.
dc() { ( cd "${INSTALL_DIR}" && ${COMPOSE_CMD} "$@" ); }
dc_run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo -e "${YELLOW}   [DRY-RUN]${RESET} (cd ${INSTALL_DIR} && ${COMPOSE_CMD} $*)"
  else
    dc "$@"
  fi
}
env_get() { grep -E "^$1=" "${ENV_FILE}" 2>/dev/null | tail -n1 | cut -d= -f2- || true; }

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

# -- Stand der Installation lesen ----------------------------------------------
NSJAIL_MODE=0
grep -qE '^KVM_ENABLED=false[[:space:]]*$' "${ENV_FILE}" && NSJAIL_MODE=1
readonly NSJAIL_MODE
JWT_MODE="unbekannt"
case "$(env_get CODEAPI_AUTH_PROVIDER)" in
  librechat-jwt) JWT_MODE="JWT (EdDSA)" ;;
  none)          JWT_MODE="keine (offener Zugriff im Docker-Netz)" ;;
esac

CURRENT_TAG="$(env_get CODEAPI_IMAGE_TAG)"
CURRENT_VERSION="$(env_get CODEAPI_VERSION)"
GIT_OLD="$(git -C "${INSTALL_DIR}" rev-parse HEAD 2>/dev/null || true)"
[[ -n "${CURRENT_VERSION}" ]] || CURRENT_VERSION="$(git -C "${INSTALL_DIR}" describe --tags --exact-match HEAD 2>/dev/null || echo unbekannt)"
readonly CURRENT_TAG CURRENT_VERSION GIT_OLD
GIT_DIRTY="$(git -C "${INSTALL_DIR}" status --porcelain --untracked-files=no 2>/dev/null || true)"

# Welche fertigen Images diese Installation nutzt (Sandbox-Variante je nach
# Modus) - direkt aus der Override-Datei des Installers gelesen.
mapfile -t STACK_IMAGES < <(grep -oE "${IMAGE_MARKER}[a-z-]+" "${INSTALL_DIR}/${MARKER_FILE}" | sed "s#${IMAGE_MARKER}##" | sort -u)
[[ "${#STACK_IMAGES[@]}" -gt 0 ]] || die "Keine fertigen Images in ${MARKER_FILE} gefunden."

CONTAINERS_TOTAL=0
CONTAINERS_RUNNING=0
while IFS= read -r line; do
  [[ -n "${line}" ]] || continue
  CONTAINERS_TOTAL=$((CONTAINERS_TOTAL + 1))
  [[ "${line}" == *running* ]] && CONTAINERS_RUNNING=$((CONTAINERS_RUNNING + 1))
done < <(dc ps -a --format '{{.Service}} {{.State}}' 2>/dev/null || true)

# Gesichert wird, was der Installer erzeugt hat und nicht wiederherstellbar
# ist: Secrets und Schluessel (.env), die Override-Datei, der Healthcheck.
# data/pkgs bleibt aussen vor - mehrere GB, jederzeit neu erzeugbar.
declare -a CONFIG_ITEMS=()
for item in .env "${MARKER_FILE}" nsjail-fix librechat-jwt-block.txt; do
  [[ -e "${INSTALL_DIR}/${item}" ]] && CONFIG_ITEMS+=("${item}")
done
BACKUP_COUNT=0
if [[ -d "${BACKUP_DIR}" ]]; then
  BACKUP_COUNT=$(find "${BACKUP_DIR}" -maxdepth 1 -name "${BACKUP_PREFIX}_*.tar.gz" -type f 2>/dev/null | wc -l | tr -d ' ')
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
printf ' %-18s %s\n' "Version:" "${CURRENT_VERSION} (Images ${CURRENT_TAG:0:11})"
if [[ "${CONTAINERS_TOTAL}" -gt 0 ]]; then
  printf ' %-18s %s\n' "Container:" "${CONTAINERS_TOTAL} (davon ${CONTAINERS_RUNNING} laufend)"
else
  printf ' %-18s %s\n' "Container:" "keine gefunden - gestoppt oder entfernt?"
fi
printf ' %-18s %s\n' "Isolation:" "$( [[ "${NSJAIL_MODE}" -eq 1 ]] && echo "NsJail-only (KVM_ENABLED=false)" || echo "MicroVM (KVM_ENABLED=true)" )"
printf ' %-18s %s\n' "Authentifizierung:" "${JWT_MODE}"
printf ' %-18s %s\n' "Sicherung von:" "${CONFIG_ITEMS[*]:-keine der erwarteten Dateien gefunden}"
printf ' %-18s %s\n' "Backups:" "${BACKUP_COUNT} vorhanden in ${BACKUP_DIR}"
printf ' %-18s %s\n' "Plattenplatz:" "${FREE_MB} MB frei auf ${DOCKER_ROOT}"
[[ "${LOG_ACTIVE}" -eq 1 ]] && printf ' %-18s %s\n' "Logdatei:" "${LOG}"

if [[ -n "${GIT_DIRTY}" ]]; then
  echo ""
  warn "Im Repository wurden versionierte Dateien von Hand geaendert:"
  while IFS= read -r l; do [[ -n "$l" ]] && echo -e "   ${YELLOW}${l}${RESET}"; done <<<"${GIT_DIRTY}"
  echo -e " Ein Versionswechsel wuerde diese Aenderungen verwerfen oder scheitern."
  echo -e " Zuruecksetzen mit: ${CYAN}git -C ${INSTALL_DIR} checkout -- .${RESET}"
  die "Abbruch - es wurde nichts veraendert."
fi

# Schritte durchzaehlen statt feste Nummern: einzelne Schritte entfallen je
# nach Modus, eine Luecke in der Numerierung wuerde nur verunsichern.
STEP_NO=0
step() { STEP_NO=$((STEP_NO + 1)); echo -e "   ${STEP_NO}. $*"; }

echo ""
echo -e " ${BOLD}Geplante Schritte${RESET}"
step "Zielversion waehlen (Vorschlag: neueste mit fertigen Images)"
step "Auf Neuerungen pruefen - ohne Eingriff"
step "Backup der Konfiguration (Secrets, Schluessel, Override)"
step "Version umstellen, Images laden, Stack neu starten, Health Check"
step "Bei einem Fehler: automatisches Rollback auf ${CURRENT_VERSION}"
step "Alte Images und Backups aufraeumen"
echo ""
echo -e " ${BOLD}Bis zur Rueckfrage wird nichts veraendert.${RESET}"

# -- 2. Version waehlen --------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Version waehlen${RESET}"
echo "------------------------------------------------------------"

# Alle Versionen samt Commit mit einem Aufruf holen (ls-remote liest nur). Bei
# annotierten Tags zeigt der Eintrag mit "^{}" auf den eigentlichen Commit.
declare -A TAG_COMMIT=()
while read -r sha ref; do
  [[ -n "${ref:-}" ]] || continue
  ref="${ref#refs/tags/}"
  if [[ "${ref}" == *'^{}' ]]; then
    TAG_COMMIT["${ref%'^{}'}"]="${sha}"
  elif [[ -z "${TAG_COMMIT[${ref}]:-}" ]]; then
    TAG_COMMIT["${ref}"]="${sha}"
  fi
done < <(git -C "${INSTALL_DIR}" ls-remote --tags origin 'v*' 2>/dev/null || true)
[[ "${#TAG_COMMIT[@]}" -gt 0 ]] || die "Die Versionen sind nicht abrufbar (GitHub erreichbar?). Es wurde nichts veraendert."

# Gibt es zu dieser Version alle fertigen Images dieser Installation?
# 'docker manifest inspect' liest nur, es wird nichts heruntergeladen.
images_available() {
  local sha="${TAG_COMMIT[$1]:-}" img
  [[ -n "${sha}" ]] || return 1
  for img in "${STACK_IMAGES[@]}"; do
    docker manifest inspect "${IMAGE_MARKER}${img}:sha-${sha}" >/dev/null 2>&1 || return 1
  done
}

# Neueste stabile Version (vX.Y.Z, keine -rcN) mit vollstaendigen Images. Zu
# einer brandneuen Version erscheinen die Images womoeglich mit Verzoegerung -
# dann ist die vorige die neueste verfuegbare.
LATEST_VERSION=""
while read -r v; do
  [[ -n "${v}" ]] || continue
  if images_available "${v}"; then LATEST_VERSION="${v}"; break; fi
done < <(printf '%s\n' "${!TAG_COMMIT[@]}" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -Vr | head -n 10)
if [[ -z "${LATEST_VERSION}" && -z "${TARGET_VERSION}" ]]; then
  die "Keine Version mit fertigen Images ermittelbar (ghcr.io erreichbar?).\n  Es wurde nichts veraendert. Eine bestimmte Version laesst sich mit --version vorgeben."
fi
printf ' %-30s %b\n' "Aktuell installierte Version:" "${BOLD}${CURRENT_VERSION}${RESET}"
printf ' %-30s %b\n' "Neueste verfuegbare Version:" "${BOLD}${LATEST_VERSION:-unbekannt}${RESET}"

target_ok() {
  [[ -n "${TAG_COMMIT[$1]:-}" ]] || { warn "Version '$1' gibt es nicht. Verfuegbare Versionen: ${TAGS_URL}"; return 1; }
  images_available "$1" || { warn "Zu $1 gibt es keine vollstaendigen fertigen Images (erst ab v1.10.0)."; return 1; }
}

if [[ -n "${TARGET_VERSION}" ]]; then
  # Per --version / CODEAPI_VERSION vorgegeben.
  target_ok "${TARGET_VERSION}" || die "Es wurde nichts veraendert."
  info "Zielversion per --version vorgegeben: ${TARGET_VERSION}"
elif [[ "${INTERACTIVE}" -eq 0 || "${ASSUME_YES:-0}" == "1" || "${DRY_RUN}" -eq 1 ]]; then
  TARGET_VERSION="${LATEST_VERSION}"
  info "Ohne Rueckfrage: Ziel ist die neueste Version ${TARGET_VERSION}."
else
  if [[ "${CURRENT_VERSION}" == "${LATEST_VERSION}" && "${FORCE}" -eq 0 ]]; then
    echo ""
    warn "Du bist bereits auf der neuesten Version (${LATEST_VERSION})."
    if ! ask_yesno "Trotzdem fortfahren (neu laden und neu starten)?" "n"; then
      info "Abgebrochen. Es wurde nichts veraendert."
      exit 0
    fi
    FORCE=1
  fi
  while :; do
    TARGET_VERSION="$(normalize_version "$(ask_text "Auf welche Version updaten?" "${LATEST_VERSION}")")"
    target_ok "${TARGET_VERSION}" && break
  done
fi
readonly TARGET_VERSION
readonly TARGET_TAG="sha-${TAG_COMMIT[${TARGET_VERSION}]}"
if [[ "${CURRENT_VERSION}" =~ ^v ]] && version_lt "${TARGET_VERSION}" "${CURRENT_VERSION}"; then
  warn "Rueckstufung: ${CURRENT_VERSION} -> ${TARGET_VERSION} (aeltere Version)."
fi
success "Zielversion: ${TARGET_VERSION}"
VERSION_CHANGED=0
[[ "${TARGET_TAG}" != "${CURRENT_TAG}" ]] && VERSION_CHANGED=1
readonly VERSION_CHANGED

# -- 3. Auf Neuerungen pruefen -------------------------------------------------
# Veraendert den laufenden Stack nicht: der Fetch schreibt nur in .git/, der
# Pull laedt hoechstens Image-Layer der Basis-Images.
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Pruefe auf Neuerungen${RESET}"
echo "------------------------------------------------------------"

GIT_NEW=""
GIT_NEW_DATE=""
CHANGED_FILES=""
if [[ "${VERSION_CHANGED}" -eq 1 ]]; then
  info "Hole die Konfiguration der Version ${TARGET_VERSION} (git fetch)..."
  # Genau dieser eine Tag, ohne Verlauf - nicht der Branch "main".
  run git -C "${INSTALL_DIR}" fetch -q --no-tags --depth=1 origin "+refs/tags/${TARGET_VERSION}:refs/tags/${TARGET_VERSION}" \
    || die "Version ${TARGET_VERSION} konnte nicht geladen werden (GitHub erreichbar?). Es wurde nichts veraendert."
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    GIT_NEW="$(git -C "${INSTALL_DIR}" rev-parse "refs/tags/${TARGET_VERSION}^{commit}" 2>/dev/null || true)"
    [[ -n "${GIT_NEW}" ]] || die "Version ${TARGET_VERSION} wurde geladen, ist aber lokal nicht aufloesbar. Es wurde nichts veraendert."
    GIT_NEW_DATE="$(git -C "${INSTALL_DIR}" log -1 --format=%cd --date=short "${GIT_NEW}" 2>/dev/null || true)"
    # Bei flachen Clones fehlt der gemeinsame Vorfahre; ein Vergleich der
    # beiden Baeume funktioniert trotzdem, weil beide Commits lokal liegen.
    CHANGED_FILES="$(git -C "${INSTALL_DIR}" diff --name-only "${GIT_OLD}" "${GIT_NEW}" 2>/dev/null || true)"
  fi
fi

# Basis-Images (redis, minio) kommen von Docker Hub bzw. quay.io und koennen
# sich auch ohne Versionswechsel aendern. Ihre jetzigen Image-IDs werden
# gemerkt - fuer die Anzeige und fuer ein Rollback.
mapfile -t BASE_IMAGES < <(dc config --images 2>/dev/null | grep -v "^${IMAGE_MARKER}" | sort -u || true)
declare -A OLD_IDS=() NEW_IDS=()
for img in ${BASE_IMAGES[@]+"${BASE_IMAGES[@]}"}; do
  OLD_IDS["${img}"]="$(docker image inspect "${img}" -f '{{.Id}}' 2>/dev/null || true)"
done
info "Basis-Images (redis, minio) pruefen..."
for img in ${BASE_IMAGES[@]+"${BASE_IMAGES[@]}"}; do
  run docker pull -q "${img}" >/dev/null || warn "Basis-Image ${img} konnte nicht geprueft werden."
done

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo "------------------------------------------------------------"
  echo -e "${YELLOW}${BOLD} DRY-RUN beendet - es wurde nichts veraendert.${RESET}"
  echo "------------------------------------------------------------"
  echo -e " Installiert: ${BOLD}${CURRENT_VERSION}${RESET}   Ziel: ${BOLD}${TARGET_VERSION}${RESET}"
  [[ "${VERSION_CHANGED}" -eq 0 ]] && echo -e " Die Zielversion ist bereits installiert."
  echo ""
  exit 0
fi

BASE_CHANGED=0
for img in ${BASE_IMAGES[@]+"${BASE_IMAGES[@]}"}; do
  NEW_IDS["${img}"]="$(docker image inspect "${img}" -f '{{.Id}}' 2>/dev/null || true)"
  [[ "${OLD_IDS[${img}]}" != "${NEW_IDS[${img}]}" ]] && BASE_CHANGED=1
done

# Aenderungen am Erzeuger der Laufzeitumgebungen erkennen - alles, was
# docker/Dockerfile.package-init in sein Image kopiert. Nur dann ist ein
# Neubau von data/pkgs (mehrere Minuten, ~3 GB) wirklich noetig.
PKGS_RECOMMENDED=0
if [[ "${NSJAIL_MODE}" -eq 1 && -n "${CHANGED_FILES}" ]]; then
  if grep -qE '^docker/Dockerfile\.package-init$|^docker/package-init\.sh$|^docker/apt-install\.sh$|^docker/python-runtime/|^javascript-packages\.txt$' <<<"${CHANGED_FILES}"; then
    PKGS_RECOMMENDED=1
  fi
fi

# -- 4. Aktueller und zukuenftiger Stand ---------------------------------------
echo ""
echo "============================================================"
echo -e "${BOLD} AKTUELLER STAND  ->  ZUKUENFTIGER STAND${RESET}"
echo "============================================================"
printf ' %-24s %-24s %-24s\n' "Komponente" "JETZT" "NACHHER"
printf ' %-24s %-24s %-24s\n' "------------------------" "------------------------" "------------------------"
neu() { printf ' %-24s %-24s %b%-24s%b %b\n' "$1" "$2" "${GREEN}" "$3" "${RESET}" "${GREEN}<- neu${RESET}"; }
gleich() { printf ' %-24s %-24s %-24s\n' "$1" "$2" "unveraendert"; }

if [[ "${VERSION_CHANGED}" -eq 1 ]]; then
  neu "Code Interpreter" "${CURRENT_VERSION}" "${TARGET_VERSION} (${GIT_NEW_DATE})"
  for img in "${STACK_IMAGES[@]}"; do
    neu "${img}" "${CURRENT_TAG:0:11}" "${TARGET_TAG:0:11}"
  done
else
  gleich "Code Interpreter" "${CURRENT_VERSION}"
  for img in "${STACK_IMAGES[@]}"; do
    gleich "${img}" "${CURRENT_TAG:0:11}"
  done
fi
for img in ${BASE_IMAGES[@]+"${BASE_IMAGES[@]}"}; do
  name="${img##*/}"; name="${name%%:*}"
  if [[ "${OLD_IDS[${img}]}" != "${NEW_IDS[${img}]}" ]]; then
    neu "${name}" "${OLD_IDS[${img}]:7:12}" "${NEW_IDS[${img}]:7:12}"
  else
    gleich "${name}" "${OLD_IDS[${img}]:7:12}"
  fi
done

if [[ -n "${LATEST_VERSION}" ]] && version_lt "${TARGET_VERSION}" "${LATEST_VERSION}"; then
  echo ""
  info "Hinweis: Neuer als ${TARGET_VERSION} ist bereits ${LATEST_VERSION}."
fi
if [[ "${NSJAIL_MODE}" -eq 1 ]]; then
  echo ""
  if [[ "${PKGS_RECOMMENDED}" -eq 1 ]]; then
    echo -e " data/pkgs:   ${YELLOW}Erzeuger upstream geaendert - Neubau empfohlen${RESET}"
  else
    echo -e " data/pkgs:   unveraendert (Neubau nicht erforderlich)"
  fi
fi

# -- Nichts Neues: hier ist Schluss, ohne irgendetwas anzufassen ---------------
if [[ "${VERSION_CHANGED}" -eq 0 && "${BASE_CHANGED}" -eq 0 && "${FORCE}" -eq 0 && "${PKGS_MODE}" != "always" ]]; then
  echo ""
  echo "------------------------------------------------------------"
  success "NOCHANGE: bereits aktuell - kein Backup, kein Neustart, keine Aenderung."
  echo "------------------------------------------------------------"
  echo -e " Trotzdem neu laden und neu starten: ${CYAN}--force${RESET}"
  echo ""
  exit 0
fi

# -- 5. Rueckfragen ------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Rueckfragen${RESET}"
echo "------------------------------------------------------------"

REQUIRED_FREE_MB="${MIN_FREE_MB}"
DO_PKGS=0
if [[ "${NSJAIL_MODE}" -eq 1 ]]; then
  case "${PKGS_MODE}" in
    always) DO_PKGS=1; info "Laufzeitumgebungen werden neu erzeugt (--pkgs)." ;;
    never)  info "Laufzeitumgebungen bleiben unveraendert (--no-pkgs)." ;;
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
  die "Bitte zuerst Platz schaffen - es wurde nichts veraendert."
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
readonly TS
# Wie beim n8n-Update steht die Version vor dem Update im Namen des Backups.
readonly BACKUP_FILE="${BACKUP_DIR}/${BACKUP_PREFIX}_${CURRENT_VERSION}_${TS}.tar.gz"
mapfile -t DROP_BACKUPS < <(ls -1t "${BACKUP_DIR}"/${BACKUP_PREFIX}_*.tar.gz 2>/dev/null | tail -n "+${KEEP}" || true)

echo ""
echo -e " ${BOLD}Es wird jetzt:${RESET}"
STEP_NO=0
step "gesichert nach ${CYAN}$(basename "${BACKUP_FILE}")${RESET}: ${CONFIG_ITEMS[*]}"
if [[ "${VERSION_CHANGED}" -eq 1 ]]; then
  step "von ${CURRENT_VERSION} auf ${CYAN}${TARGET_VERSION}${RESET} umgestellt (Konfiguration + Images)"
else
  step "die Version ${CURRENT_VERSION} beibehalten"
fi
step "die Images geladen - der Stack laeuft dabei weiter"
[[ "${DO_PKGS}" -eq 1 ]] && \
step "${CYAN}data/pkgs${RESET} neu erzeugt (Python wird kompiliert, 10-20 Minuten)"
step "der Stack neu gestartet - kurze Downtime, meist unter einer Minute"
step "bei einem Fehler automatisch auf ${CURRENT_VERSION} zurueckgerollt"
if [[ "${#DROP_BACKUPS[@]}" -gt 0 ]]; then
  step "${#DROP_BACKUPS[@]} alte(s) Backup(s) entfernt, aeltestes: ${CYAN}$(basename "${DROP_BACKUPS[-1]}")${RESET}"
else
  step "kein altes Backup entfernt (${BACKUP_COUNT} von ${KEEP} belegt)"
fi
echo ""
echo -e " ${BOLD}Unveraendert bleibt:${RESET} alle Secrets und Schluessel, die geschlossenen"
echo -e " Host-Ports, das Docker-Netzwerk ${CYAN}shared_proxy${RESET} samt aller anderen Stacks"
echo -e " - und die LibreChat-Seite: weder .env noch Proxy Host werden angefasst."

if ! ask_yesno "${BOLD}Update jetzt durchfuehren?${RESET}" "n"; then
  warn "Abgebrochen. Es wurde nichts veraendert."
  exit 0
fi

# -- 6. Durchfuehrung ----------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Durchfuehrung${RESET}"
echo "------------------------------------------------------------"

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
  echo "VERSION_VOR_UPDATE=${CURRENT_VERSION}"
  echo "IMAGES_VOR_UPDATE=${CURRENT_TAG}"
  echo "GIT_COMMIT_VOR_UPDATE=${GIT_OLD}"
  echo "ZIELVERSION=${TARGET_VERSION}"
  echo "ISOLATION=$( [[ "${NSJAIL_MODE}" -eq 1 ]] && echo nsjail || echo microvm )"
  echo "KONFIGURATION=${CONFIG_ITEMS[*]}"
  echo "HINWEIS=data/pkgs und die Session-Daten in Redis/MinIO sind NICHT enthalten"
} > "${STAGE}/manifest.txt"
tar czf "${BACKUP_FILE}" -C "${STAGE}" .
# Das Archiv enthaelt die .env mit allen Secrets.
chmod 600 "${BACKUP_FILE}"
rm -rf "${STAGE}"
trap - EXIT
success "Backup erstellt: $(basename "${BACKUP_FILE}") ($(du -h "${BACKUP_FILE}" | cut -f1))"

# -- Rollback-Vorbereitung -----------------------------------------------------
# Wie beim n8n-Update wird bei einem Fehler automatisch zurueckgerollt. Die
# alten Images der Dienste bleiben unter ihrem sha-Tag liegen, bis das Update
# erfolgreich war; die Basis-Images werden ueber ihre ID gesichert, weil ihr
# Tag beim Laden auf eine neue Fassung wandern kann.
SRC_SWITCHED=0      # Quellcode auf die Zielversion umgestellt
ENV_CHANGED=0       # .env auf die Zielversion umgestellt
STACK_RESTARTED=0   # Container mit dem neuen Stand gestartet
PKGS_MOVED=0        # alte data/pkgs zur Seite gelegt
ROLLBACK_IMAGES=()  # Basis-Images mit gesichertem Rollback-Tag
readonly PKGS_ROLLBACK_DIR="${INSTALL_DIR}/data/pkgs.rollback-${TS}"

rollback_ref() {
  local img="$1" repo="$1"
  [[ "${img##*/}" == *:* ]] && repo="${img%:*}"
  printf '%s:%s' "${repo}" "${ROLLBACK_TAG}"
}

# Wartet, bis ein Service laeuft bzw. "healthy" meldet. sandbox-runner braucht
# im NsJail-Modus am laengsten, deshalb grosszuegiges Zeitfenster.
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

drop_rollback_tags() {
  local img
  for img in ${ROLLBACK_IMAGES[@]+"${ROLLBACK_IMAGES[@]}"}; do
    docker rmi "$(rollback_ref "${img}")" >/dev/null 2>&1 || true
  done
}

# rollback <grund> <neustart: 0|1>
# Setzt Konfiguration, Quellcode, Basis-Images und data/pkgs auf den Stand vor
# dem Update zurueck. Mit Neustart (nur wenn der neue Stand schon lief) wird
# die vorherige Version direkt wieder gestartet - ihre Images liegen noch vor.
rollback() {
  local reason="$1" restart="$2" img ok=1
  trap - ERR
  set +e
  echo ""
  echo "------------------------------------------------------------"
  error "${reason}"
  warn "Starte automatisches Rollback auf ${CURRENT_VERSION}..."
  echo "------------------------------------------------------------"
  if [[ "${ENV_CHANGED}" -eq 1 ]]; then
    if cp -a "${ENV_FILE}.vor-${TS}" "${ENV_FILE}"; then
      success ".env zurueck auf ${CURRENT_VERSION}."
    else
      error ".env konnte nicht zurueckgesetzt werden - Vorher-Stand: .env.vor-${TS}"
    fi
  fi
  if [[ "${SRC_SWITCHED}" -eq 1 ]]; then
    if git -C "${INSTALL_DIR}" -c advice.detachedHead=false checkout -q --detach "${GIT_OLD}" >/dev/null 2>&1; then
      success "Konfiguration (Repository) zurueck auf ${CURRENT_VERSION}."
    else
      error "Repository konnte nicht zurueckgesetzt werden: git -C ${INSTALL_DIR} checkout --detach ${GIT_OLD:0:7}"
    fi
  fi
  for img in ${ROLLBACK_IMAGES[@]+"${ROLLBACK_IMAGES[@]}"}; do
    docker tag "$(rollback_ref "${img}")" "${img}" || error "Basis-Image ${img} konnte nicht zurueckgesetzt werden."
  done
  if [[ "${PKGS_MOVED}" -eq 1 ]]; then
    if rm -rf "${INSTALL_DIR}/data/pkgs" && mv "${PKGS_ROLLBACK_DIR}" "${INSTALL_DIR}/data/pkgs"; then
      success "Laufzeitumgebungen (data/pkgs) zurueck auf den alten Stand."
    else
      error "data/pkgs konnte nicht zurueckgesetzt werden - alter Stand: ${PKGS_ROLLBACK_DIR}"
    fi
  fi
  if [[ "${restart}" -eq 1 ]]; then
    info "Starte ${CURRENT_VERSION} neu (die Images liegen noch vor)..."
    dc up -d
    for svc in "${SERVICES[@]}"; do
      wait_ready "${svc}" || ok=0
    done
  fi
  if [[ "${ok}" -eq 1 ]]; then
    drop_rollback_tags
    # Die Images der fehlgeschlagenen Version belegen nur Platz.
    if [[ "${VERSION_CHANGED}" -eq 1 ]]; then
      for img in "${STACK_IMAGES[@]}"; do
        docker rmi "${IMAGE_MARKER}${img}:${TARGET_TAG}" >/dev/null 2>&1 || true
      done
    fi
  fi
  echo ""
  if [[ "${ok}" -eq 1 && "${restart}" -eq 1 ]]; then
    error "ROLLBACK: Update auf ${TARGET_VERSION} fehlgeschlagen, ${CURRENT_VERSION} laeuft wieder."
  elif [[ "${ok}" -eq 1 ]]; then
    error "ROLLBACK: Update auf ${TARGET_VERSION} fehlgeschlagen, ${CURRENT_VERSION} laeuft unveraendert weiter."
  else
    error "ROLLBACK unvollstaendig: ${CURRENT_VERSION} kam nicht vollstaendig hoch."
    echo -e " Bitte pruefen: ${CYAN}cd ${INSTALL_DIR} && ${COMPOSE_CMD} ps${RESET} und ${CYAN}${COMPOSE_CMD} logs${RESET}"
  fi
  echo -e " Backup der Konfiguration: ${CYAN}${BACKUP_FILE}${RESET}"
  [[ "${LOG_ACTIVE}" -eq 1 ]] && echo -e " Log: ${CYAN}${LOG}${RESET}"
  exit 1
}
# Unerwartete Fehler (set -e) loesen ebenfalls ein Rollback aus, statt das
# Script mitten im Umbau stehen zu lassen.
trap 'rollback "Unerwarteter Fehler in Zeile ${LINENO}." "${STACK_RESTARTED}"' ERR

for img in ${BASE_IMAGES[@]+"${BASE_IMAGES[@]}"}; do
  [[ -n "${OLD_IDS[${img}]}" ]] || continue
  docker tag "${OLD_IDS[${img}]}" "$(rollback_ref "${img}")" && ROLLBACK_IMAGES+=("${img}")
done

if [[ "${VERSION_CHANGED}" -eq 1 ]]; then
  info "Stelle auf Version ${TARGET_VERSION} um..."
  # checkout --detach statt merge/pull: eine Version ist kein Branch, auf dem
  # weiterentwickelt wird. Funktioniert auch fuer eine Rueckstufung.
  git -C "${INSTALL_DIR}" -c advice.detachedHead=false checkout -q --detach "${GIT_NEW}" \
    || rollback "Wechsel der Konfiguration auf ${TARGET_VERSION} nicht moeglich (git checkout)." 0
  SRC_SWITCHED=1
  # Version und Image-Tag in der .env umstellen - wie beim n8n-Update die
  # Version in der Compose-Datei. Eine Kopie bleibt fuer das Rollback liegen.
  cp -a "${ENV_FILE}" "${ENV_FILE}.vor-${TS}"
  chmod 600 "${ENV_FILE}.vor-${TS}"
  ENV_CHANGED=1
  sed -i -e "s|^CODEAPI_IMAGE_TAG=.*|CODEAPI_IMAGE_TAG=${TARGET_TAG}|" \
         -e "s|^CODEAPI_VERSION=.*|CODEAPI_VERSION=${TARGET_VERSION}|" "${ENV_FILE}"
  grep -q "^CODEAPI_VERSION=" "${ENV_FILE}" || echo "CODEAPI_VERSION=${TARGET_VERSION}" >>"${ENV_FILE}"
  [[ "$(env_get CODEAPI_IMAGE_TAG)" == "${TARGET_TAG}" ]] \
    || rollback "CODEAPI_IMAGE_TAG konnte in der .env nicht umgestellt werden." 0
  success "Version ${TARGET_VERSION} eingestellt (Images ${TARGET_TAG:0:11})."
fi

info "Validiere die Compose-Konfiguration..."
# Nach einem Versionswechsel kann sich die Basis-Compose-Datei geaendert haben
# (neue oder umbenannte Services). Passt die Override-Datei nicht mehr dazu,
# faellt das hier auf - bevor irgendein Container angefasst wird.
dc config --quiet \
  || rollback "Die Compose-Konfiguration passt nicht zu ${TARGET_VERSION} (haeufigste Ursache: ein Service der Override-Datei existiert in der neuen docker-compose.yaml nicht mehr)." 0
success "Compose-Konfiguration ist gueltig."

info "Lade die Images..."
dc pull || rollback "Die Images konnten nicht geladen werden (Netz zu ghcr.io / Docker Hub?)." 0
success "Images geladen."

if [[ "${DO_PKGS}" -eq 1 ]]; then
  info "Erzeuge die Laufzeitumgebungen neu (Python wird kompiliert)..."
  # Alte Laufzeitumgebungen fuer ein Rollback aufheben statt ueberschreiben -
  # die vorherige Version laeuft womoeglich nicht mit den neuen.
  if [[ -d "${INSTALL_DIR}/data/pkgs" ]]; then
    mv "${INSTALL_DIR}/data/pkgs" "${PKGS_ROLLBACK_DIR}"
    PKGS_MOVED=1
  fi
  mkdir -p "${INSTALL_DIR}/data/pkgs"
  ( cd "${INSTALL_DIR}" && docker build -f docker/Dockerfile.package-init -t "${PKG_INIT_IMAGE}" . ) \
    || rollback "Image fuer die Laufzeitumgebungen konnte nicht gebaut werden." 0
  docker run --rm -v "${INSTALL_DIR}/data/pkgs:/pkgs" "${PKG_INIT_IMAGE}" \
    || rollback "Laufzeitumgebungen konnten nicht erzeugt werden." 0
  # Fehlt eine der vier Laufzeiten, scheitert spaeter JEDE Codeausfuehrung mit
  # "<runtime> is unknown" - das faellt sonst erst beim ersten Nutzer auf.
  for runtime in python node bun bash; do
    [[ -e "${INSTALL_DIR}/data/pkgs/${runtime}" ]] \
      || rollback "Laufzeitumgebung '${runtime}' fehlt unter ${INSTALL_DIR}/data/pkgs." 0
  done
  success "Laufzeitumgebungen bereit: python, node, bun, bash."
fi

info "Starte den Stack neu..."
STACK_RESTARTED=1
dc up -d

# -- Health Check --------------------------------------------------------------
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
  rollback "Diese Services wurden mit ${TARGET_VERSION} nicht bereit: ${FAILED_SERVICES[*]}" 1
fi
trap - ERR

# -- Aufraeumen ----------------------------------------------------------------
# Erst jetzt, da der neue Stand nachweislich laeuft.
drop_rollback_tags
[[ "${PKGS_MOVED}" -eq 1 ]] && rm -rf "${PKGS_ROLLBACK_DIR}"
rm -f "${ENV_FILE}.vor-${TS}"

if [[ "${VERSION_CHANGED}" -eq 1 ]]; then
  success "UPDATED: ${CURRENT_VERSION} -> ${TARGET_VERSION}."
  # Die Images der vorherigen Version werden nicht mehr gebraucht (wie beim
  # n8n-Update). Zurueck geht es jederzeit mit --version - dann werden sie
  # neu geladen.
  info "Entferne die Images der vorherigen Version (${CURRENT_TAG:0:11})..."
  for img in "${STACK_IMAGES[@]}"; do
    docker rmi "${IMAGE_MARKER}${img}:${CURRENT_TAG}" >/dev/null 2>&1 || true
  done
else
  success "UPDATED: ${CURRENT_VERSION} neu geladen und neu gestartet."
fi

echo ""
dc ps || true

# Sicherheits-Check wie im Installer: eine neue Version kann Services mit
# 'ports:' mitbringen, die die Override-Datei nicht kennt.
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
  info "Entferne ${#OLD_BACKUPS[@]} alte(s) Backup(s) (behalte die letzten ${KEEP})."
  for old in "${OLD_BACKUPS[@]}"; do rm -f "${old}"; done
fi
docker image prune -f >/dev/null
success "Aufgeraeumt."

# -- Abschluss -----------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${GREEN}${BOLD} Update abgeschlossen.${RESET}  $(date '+%F %T')"
echo "------------------------------------------------------------"
echo ""
if [[ "${NSJAIL_MODE}" -eq 1 ]]; then
  warn "Isolation: NsJail-only-Modus (teilt sich den Host-Kernel, laut Projekt-Doku"
  warn "geeignet fuer Tests, nicht fuer produktive Systeme mit unbekannten Nutzern)."
else
  success "Isolation: MicroVM-Modus."
fi
echo ""
echo -e " LibreChat wurde ${BOLD}nicht${RESET} angefasst und muss nicht neu gestartet werden."
echo ""
echo -e " Backup: ${CYAN}${BACKUP_FILE}${RESET}"
if [[ "${VERSION_CHANGED}" -eq 1 && "${CURRENT_VERSION}" =~ ^v ]]; then
  echo ""
  echo -e " Zurueck zur vorherigen Version, falls spaeter Probleme auftauchen:"
  echo -e "   ${CYAN}update-avila-code-interpreter.sh --version ${CURRENT_VERSION}${RESET}"
fi
echo ""
echo -e " Wichtige Befehle:"
echo -e "   Logs:   ${CYAN}cd ${INSTALL_DIR} && ${COMPOSE_CMD} logs -f${RESET}"
echo -e "   Status: ${CYAN}cd ${INSTALL_DIR} && ${COMPOSE_CMD} ps${RESET}"
echo ""
echo -e " Mehr Tipps & Tutorials: ${CYAN}https://pc-fee.com/blog${RESET}"
echo -e " GitHub:                 ${CYAN}${GUIDE_URL}${RESET}"
echo ""
