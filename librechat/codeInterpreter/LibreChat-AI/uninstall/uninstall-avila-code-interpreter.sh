#!/usr/bin/env bash
# =============================================================================
# avila-code-interpreter Uninstall Script - powered by pc-fee.com
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Macht die Installation aus install-avila-code-interpreter.sh vollstaendig
# rueckgaengig: die acht Container (avila-api, avila-service-worker,
# avila-egress-gateway, avila-tool-call-server, avila-sandbox-runner,
# avila-file-server, avila-redis, avila-minio), die Docker-Volumes des
# Projekts, das Installationsverzeichnis (geklontes Repository, .env mit allen
# Secrets, docker-compose.override.yml, nsjail-fix/, data/pkgs/ mit den
# Laufzeitumgebungen) und auf Wunsch die Backups, die lokal gebauten Images
# sowie die vom Installer angelegte Swap-Datei.
#
# WICHTIG - was dieses Script grundsaetzlich NICHT anfasst:
#   * LibreChat selbst. Die Eintraege LIBRECHAT_CODE_BASEURL= und CODEAPI_* in
#     LibreChats .env werden nur gemeldet; das Auskommentieren ist eine eigene,
#     ausdrueckliche Rueckfrage (Standard: nein).
#   * das Docker-Netzwerk "shared_proxy" - es wird von weiteren Stacks
#     (LibreChat, n8n, SearXNG, Nginx Proxy Manager, ...) mitgenutzt.
#   * den Proxy Host im Nginx Proxy Manager und den DNS-A-Record. Beides muss
#     von Hand entfernt werden, das Script nennt es am Ende.
#   * jedes Verzeichnis ausserhalb der erkannten Installation.
#
# Nutzung als 1-Zeiler (von ueberall, kein vorheriger Download noetig):
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/uninstall/uninstall-avila-code-interpreter.sh)"
#
# Optionen:
#   --dir <pfad>   Installationspfad fest vorgeben (ueberspringt die Erkennung)
#   --dry-run      Zeigt nur, was entfernt wuerde - loescht nichts
#   --yes          Ueberspringt alle Sicherheitsabfragen (wie ASSUME_YES=1)
#   --help         Diese Hilfe anzeigen
#
# Umgebungsvariablen (fuer unbeaufsichtigten Betrieb):
#   INSTALL_DIR    wie --dir
#   ASSUME_YES=1   wie --yes (entfernt dann auch Backups und Images ungefragt,
#                  kommentiert aber weiterhin NICHTS in LibreChats .env aus)
#
# Voraussetzungen: root (bzw. sudo), Docker + Docker Compose.
#
# AI Transparency: Dieses Script wurde mit Unterstuetzung von KI erstellt und
# vor Veroeffentlichung geprueft. Es entfernt unwiderruflich Daten - darunter
# die .env mit allen Secrets und dem Manifest-Schluesselpaar sowie, falls noch
# vorhanden, die Datei librechat-jwt-block.txt mit dem privaten JWT-Schluessel.
# Bitte vorher mit --dry-run pruefen.
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
readonly PROXY_NETWORK="shared_proxy"
readonly DEFAULT_DIR="/opt/avila-code-interpreter"
# Marker der eigenen Installation: die docker-compose.override.yml wird
# ausschliesslich vom Installer geschrieben und benennt den API-Container.
readonly MARKER_FILE="docker-compose.override.yml"
readonly MARKER_STRING="container_name: avila-api"
readonly API_CONTAINER="avila-api"
readonly PKG_INIT_IMAGE="avila-package-init"
# Vom Installer optional angelegt (Schritt 3) - inklusive fstab-Eintrag.
readonly SWAP_FILE="/swapfile-avila-code-interpreter"
readonly LIBRECHAT_IMAGE_MARKER="danny-avila/librechat"
readonly LIBRECHAT_DEFAULT_DIR="/opt/librechat"
readonly INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/install/install-avila-code-interpreter.sh"
# Container-Namen aus der Override-Datei des Installers. Dienen als Rueckfall,
# wenn das Installationsverzeichnis bereits von Hand geloescht wurde.
readonly EXPECTED_CONTAINERS=(
  avila-api avila-service-worker avila-egress-gateway avila-tool-call-server
  avila-sandbox-runner avila-file-server avila-redis avila-minio
)

# -- Optionen ------------------------------------------------------------------
DRY_RUN=0

usage() {
  cat <<'USAGE'
avila-code-interpreter Uninstall Script - powered by pc-fee.com

Entfernt eine mit install-avila-code-interpreter.sh installierte Instanz des
LibreChat Code Interpreters: Container, Docker-Volumes, das Installations-
verzeichnis (Repository, .env mit allen Secrets, Override, nsjail-fix/,
data/pkgs/), auf Wunsch Backups, lokal gebaute Images und die vom Installer
angelegte Swap-Datei.

Nicht angetastet werden LibreChat selbst, das Netzwerk 'shared_proxy', der
Proxy Host im Nginx Proxy Manager und jedes Verzeichnis ausserhalb der
Installation. LibreChats .env wird nur nach eigener Rueckfrage angepasst.

Optionen:
  --dir <pfad>   Installationspfad fest vorgeben (ueberspringt die Erkennung)
  --dry-run      Zeigt nur, was entfernt wuerde - loescht nichts
  --yes          Ueberspringt alle Sicherheitsabfragen (wie ASSUME_YES=1)
  --help         Diese Hilfe anzeigen

Umgebungsvariablen: INSTALL_DIR, ASSUME_YES

Beispiele:
  sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/uninstall/uninstall-avila-code-interpreter.sh)"
  sudo ./uninstall-avila-code-interpreter.sh --dry-run
  sudo ./uninstall-avila-code-interpreter.sh --dir /srv/code-interpreter
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)     INSTALL_DIR="${2:-}"; shift 2 || true ;;
    --dir=*)   INSTALL_DIR="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y)  ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         echo "Unbekannte Option: $1 (siehe --help)" >&2; exit 1 ;;
  esac
done
readonly DRY_RUN

# -- Eingabequelle -------------------------------------------------------------
# Wird das Script per 'curl ... | bash' gestartet, liegt auf stdin der Script-
# Text selbst - ein 'read' wuerde ihn verschlucken. Deshalb immer vom Terminal
# lesen. Ohne Terminal wird nichts geloescht, ausser ASSUME_YES=1 ist gesetzt.
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
    warn "Ohne Bestaetigung wird nichts entfernt (ASSUME_YES=1 setzen, falls gewollt)."
    return 1
  fi
  echo ""
  echo -ne "${BOLD}${prompt}${RESET} [${CYAN}${hint}${RESET}]: "
  read -r input <"${TTY}" || true
  input="${input:-${default}}"
  [[ "${input,,}" == "j" || "${input,,}" == "y" ]]
}

# ask_yesno_strict - wie ask_yesno, aber ohne ASSUME_YES-Abkuerzung. Fuer
# Eingriffe ausserhalb der eigenen Installation (LibreChats .env): ein
# unbeaufsichtigter Lauf soll dort niemals etwas aendern.
ask_yesno_strict() {
  local prompt="$1" input=""
  if [[ "${INTERACTIVE}" -eq 0 ]]; then
    warn "Kein Terminal verfuegbar - uebersprungen (keine Aenderung): ${prompt}"
    return 1
  fi
  echo ""
  echo -ne "${BOLD}${prompt}${RESET} [${CYAN}j/N${RESET}]: "
  read -r input <"${TTY}" || true
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
printf '%b\n' "${BOLD} Code Interpreter Uninstall - powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo -e " Macht die Installation aus ${BOLD}install-avila-code-interpreter.sh${RESET}"
echo -e " rueckgaengig: Container, ${BOLD}Docker-Volumes${RESET} und das Installations-"
echo -e " verzeichnis mit Repository, ${BOLD}.env${RESET} (Secrets, Manifest-Schluessel),"
echo -e " nsjail-fix/ und den Laufzeitumgebungen unter data/pkgs/."
echo ""
echo -e " ${YELLOW}Wird NICHT angefasst:${RESET} ${BOLD}LibreChat selbst${RESET}, das Docker-Netzwerk"
echo -e " ${BOLD}${PROXY_NETWORK}${RESET}, der Proxy Host im Nginx Proxy Manager und jedes"
echo -e " Verzeichnis ausserhalb der Installation."
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo -e " ${YELLOW}${BOLD}DRY-RUN aktiv:${RESET} es wird nichts geloescht, nur angezeigt."
fi
echo "------------------------------------------------------------"

# -- Root-Check ----------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  die "Bitte als root oder mit sudo ausfuehren."
fi

# In ein garantiert existierendes Verzeichnis wechseln, damit spaetere Aufrufe
# nicht an einer geloeschten CWD scheitern.
cd / 2>/dev/null || die "Konnte nicht nach / wechseln."

# -- Voraussetzungen pruefen ---------------------------------------------------
command -v docker &>/dev/null || die "Docker ist nicht installiert - hier gibt es nichts zu entfernen."
docker info &>/dev/null || die "Docker-Daemon laeuft nicht. Bitte starten: systemctl start docker"

if docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
else
  die "Docker Compose nicht gefunden."
fi
readonly COMPOSE_CMD

# -- Installationspfad ermitteln -----------------------------------------------
is_install_dir() {
  local d="$1"
  [[ -f "${d}/${MARKER_FILE}" ]] && grep -q "${MARKER_STRING}" "${d}/${MARKER_FILE}" 2>/dev/null
}

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

  while IFS= read -r cid; do
    [[ -n "${cid}" ]] || continue
    d=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "${cid}" 2>/dev/null || true)
    [[ -n "${d}" && "${d}" == /* ]] && raw+=("${d}")
  done < <(docker ps -a --format '{{.ID}} {{.Names}}' | awk -v n="${API_CONTAINER}" '$2==n {print $1}')

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

# Verwaiste Container einsammeln (Verzeichnis bereits von Hand geloescht).
# Bewusst ein Abgleich gegen die feste Namensliste statt 'grep ^avila-':
# so werden fremde Container mit aehnlichem Namen nicht mitgerissen.
ALL_CONTAINER_NAMES="$(docker ps -a --format '{{.Names}}' 2>/dev/null || true)"
declare -a ORPHAN_CONTAINERS=()
for c in "${EXPECTED_CONTAINERS[@]}"; do
  grep -qxF "${c}" <<<"${ALL_CONTAINER_NAMES}" && ORPHAN_CONTAINERS+=("${c}")
done

if [[ -n "${INSTALL_DIR:-}" ]]; then
  [[ -d "${INSTALL_DIR}" ]] || die "Angegebener Pfad existiert nicht: ${INSTALL_DIR}"
  info "Installationspfad (vorgegeben): ${INSTALL_DIR}"
  is_install_dir "${INSTALL_DIR}" \
    || warn "In ${INSTALL_DIR} fehlt die ${MARKER_FILE} mit '${MARKER_STRING}' - bitte die Bestandsaufnahme unten besonders genau lesen."
else
  mapfile -t FOUND < <(detect_dirs)
  case "${#FOUND[@]}" in
    0)
      if [[ "${#ORPHAN_CONTAINERS[@]}" -gt 0 ]]; then
        warn "Kein Installationsverzeichnis gefunden, aber es existieren noch Container:"
        for c in "${ORPHAN_CONTAINERS[@]}"; do echo -e "   - ${CYAN}${c}${RESET}"; done
        if ask_yesno "${BOLD}Diese verwaisten Container entfernen?${RESET}" "n"; then
          for c in "${ORPHAN_CONTAINERS[@]}"; do run docker rm -f "${c}"; done
          success "Verwaiste Container entfernt."
          warn "Etwaige Docker-Volumes dieses Stacks bleiben bestehen - sie lassen sich"
          warn "mit 'docker volume ls' pruefen und mit 'docker volume rm <name>' entfernen."
        else
          warn "Abgebrochen. Es wurde nichts veraendert."
        fi
        exit 0
      fi
      success "Nichts zu tun - keine Code-Interpreter-Installation und keine Container gefunden."
      exit 0
      ;;
    1)
      INSTALL_DIR="${FOUND[0]}"
      info "Installation erkannt: ${INSTALL_DIR}"
      ;;
    *)
      echo ""
      warn "Mehrere Installationen gefunden:"
      for i in "${!FOUND[@]}"; do
        echo -e "   ${BOLD}$((i + 1)))${RESET} ${CYAN}${FOUND[$i]}${RESET}"
      done
      [[ "${INTERACTIVE}" -eq 1 ]] \
        || die "Kein Terminal fuer die Rueckfrage verfuegbar. Bitte --dir <pfad> setzen."
      choice=""
      echo ""
      echo -ne "${BOLD}Welche soll entfernt werden?${RESET} [${CYAN}1${RESET}]: "
      read -r choice <"${TTY}" || true
      choice="${choice:-1}"
      { [[ "${choice}" =~ ^[0-9]+$ ]] && [[ "${choice}" -ge 1 ]] && [[ "${choice}" -le "${#FOUND[@]}" ]]; } \
        || die "Ungueltige Auswahl: ${choice}"
      INSTALL_DIR="${FOUND[$((choice - 1))]}"
      ;;
  esac
fi

# Sicherheitsnetz gegen ein 'rm -rf' an der falschen Stelle: ein per --dir oder
# INSTALL_DIR uebergebener Pfad kann alles sein. Deshalb ausdruecklich pruefen,
# dass es sich um ein echtes Unterverzeichnis handelt und nicht um /, /opt,
# /srv oder ein Home-Verzeichnis.
INSTALL_DIR="$(cd "${INSTALL_DIR}" && pwd -P)" || die "Installationspfad nicht lesbar: ${INSTALL_DIR}"
case "${INSTALL_DIR}" in
  /|/opt|/srv|/usr|/var|/home|/root|/etc|/tmp|/mnt|/media)
    die "Verweigert: ${INSTALL_DIR} ist ein Systemverzeichnis und wird nicht geloescht." ;;
esac
[[ "$(awk -F/ '{print NF-1}' <<<"${INSTALL_DIR}")" -ge 2 ]] \
  || die "Verweigert: ${INSTALL_DIR} liegt zu weit oben im Dateisystem."
readonly INSTALL_DIR

COMPOSE_FILE=""
COMPOSE_FILE="$(compose_file_of "${INSTALL_DIR}" || true)"
readonly COMPOSE_FILE

# Compose aus dem Installationsverzeichnis heraus aufrufen, damit Override und
# .env automatisch gezogen werden - sonst kennt 'down' die Netzwerke nicht.
dc() { ( cd "${INSTALL_DIR}" && ${COMPOSE_CMD} "$@" ); }
dc_run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo -e "${YELLOW}   [DRY-RUN]${RESET} (cd ${INSTALL_DIR} && ${COMPOSE_CMD} $*)"
  else
    dc "$@"
  fi
}

# -- Bestandsaufnahme ----------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Bestandsaufnahme${RESET}"
echo "------------------------------------------------------------"

CONTAINERS=""
if [[ -n "${COMPOSE_FILE}" ]]; then
  CONTAINERS=$(dc ps -a --format '{{.Name}}' 2>/dev/null || true)
fi
if [[ -z "${CONTAINERS}" && "${#ORPHAN_CONTAINERS[@]}" -gt 0 ]]; then
  CONTAINERS=$(printf '%s\n' "${ORPHAN_CONTAINERS[@]}")
fi

if [[ -n "${CONTAINERS}" ]]; then
  info "Folgende Container werden entfernt:"
  while IFS= read -r c; do [[ -n "$c" ]] && echo -e "   - ${CYAN}${c}${RESET}"; done <<<"${CONTAINERS}"
else
  warn "Keine laufenden/gestoppten Container dieses Stacks gefunden (evtl. schon entfernt)."
fi

# Named Volumes des Projekts. Ueber das Label com.docker.compose.project sind
# sie sicher zuzuordnen, ohne fremde Volumes mit aehnlichem Namen zu treffen.
PROJECT_NAME="$(dc config --format json 2>/dev/null | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)"
[[ -n "${PROJECT_NAME}" ]] || PROJECT_NAME="$(basename "${INSTALL_DIR}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"
mapfile -t PROJECT_VOLUMES < <(
  docker volume ls --filter "label=com.docker.compose.project=${PROJECT_NAME}" --format '{{.Name}}' 2>/dev/null || true
)
if [[ "${#PROJECT_VOLUMES[@]}" -gt 0 ]]; then
  echo ""
  warn "Diese Docker-Volumes des Projekts '${PROJECT_NAME}' werden mit entfernt (compose down -v):"
  for v in "${PROJECT_VOLUMES[@]}"; do
    vpath="$(docker volume inspect "${v}" -f '{{.Mountpoint}}' 2>/dev/null || true)"
    vsize=""
    [[ -n "${vpath}" && -d "${vpath}" ]] && vsize="$(du -sh "${vpath}" 2>/dev/null | cut -f1)"
    echo -e "   - ${CYAN}${v}${RESET}${vsize:+ (${vsize})}"
  done
  echo -e "     ${YELLOW}Enthalten die Objektablage (MinIO) und die Job-Queue (Redis) -${RESET}"
  echo -e "     ${YELLOW}also die Dateien aus Code-Ausfuehrungen, keine Chats.${RESET}"
fi

echo ""
info "Folgendes Verzeichnis wird entfernt: ${BOLD}${INSTALL_DIR}${RESET}"

dirsize() { du -sh "${INSTALL_DIR}/$1" 2>/dev/null | cut -f1; }
item() { printf '     %b+- %-29s%b%b\n' "$1" "$2" "${RESET}" "$3"; }

[[ -f "${INSTALL_DIR}/.env" ]] && \
  item "${RED}" ".env" "- ${BOLD}Secrets, Manifest-Schluesselpaar, JWT-Public-Key${RESET}"
[[ -f "${INSTALL_DIR}/librechat-jwt-block.txt" ]] && \
  item "${RED}" "librechat-jwt-block.txt" "- ${BOLD}privater JWT-Signierschluessel${RESET}"
[[ -f "${INSTALL_DIR}/${MARKER_FILE}" ]] && \
  item "${YELLOW}" "${MARKER_FILE}" "- Container-Namen, geschlossene Host-Ports"
[[ -d "${INSTALL_DIR}/nsjail-fix" ]] && \
  item "${YELLOW}" "nsjail-fix/" "- gepatchter Sandbox-Starter + Healthcheck"
[[ -d "${INSTALL_DIR}/data/pkgs" ]] && \
  item "${YELLOW}" "data/pkgs/" "- Laufzeiten python/node/bun/bash ($(dirsize data/pkgs))"
if [[ -d "${INSTALL_DIR}/data" ]]; then
  item "${YELLOW}" "data/" "- Arbeitsdaten der Sandbox ($(dirsize data))"
fi
[[ -d "${INSTALL_DIR}/.git" ]] && \
  item "${YELLOW}" ".git/" "- geklontes code-interpreter-Repository ($(dirsize .git))"

BACKUP_COUNT=0
BACKUP_SIZE="0"
if [[ -d "${INSTALL_DIR}/backups" ]]; then
  BACKUP_COUNT=$(find "${INSTALL_DIR}/backups" -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.tgz' \) 2>/dev/null | wc -l | tr -d ' ')
  BACKUP_SIZE=$(du -sh "${INSTALL_DIR}/backups" 2>/dev/null | cut -f1)
  item "${YELLOW}" "backups/" "- ${BACKUP_COUNT} Backup(s), ${BACKUP_SIZE} (separate Abfrage)"
fi

# Andere Container am shared_proxy-Netz: die laufen unveraendert weiter, werden
# hier aber genannt, damit klar ist, was auf dem Host bestehen bleibt.
OTHERS=""
if docker network inspect "${PROXY_NETWORK}" &>/dev/null; then
  OTHERS=$(docker network inspect "${PROXY_NETWORK}" \
    --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' 2>/dev/null \
    | grep -v '^$' | grep -v '^avila-' || true)
fi
if [[ -n "${OTHERS}" ]]; then
  echo ""
  warn "Diese Container haengen ebenfalls am Netzwerk '${PROXY_NETWORK}':"
  while IFS= read -r c; do [[ -n "$c" ]] && echo -e "   - ${CYAN}${c}${RESET}"; done <<<"${OTHERS}"
  warn "Sie laufen unveraendert weiter - dieses Script ruehrt das Netzwerk nicht an."
fi

# -- LibreChat-Seite ermitteln (nur melden) ------------------------------------
# Der Interpreter ist eine Erweiterung: in LibreChats .env stehen
# LIBRECHAT_CODE_BASEURL und die CODEAPI_-Werte. Bleiben sie stehen, zeigt
# LibreChat den Code Interpreter weiter an und jede Ausfuehrung scheitert.
LIBRECHAT_DIR=""
LIBRECHAT_ENV=""
LIBRECHAT_LINES=""
LIBRECHAT_BASEURL=""
while IFS= read -r cid; do
  [[ -n "${cid}" ]] || continue
  d=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "${cid}" 2>/dev/null || true)
  [[ -n "${d}" && -f "${d}/.env" ]] && { LIBRECHAT_DIR="${d}"; break; }
done < <(docker ps -a --format '{{.ID}} {{.Image}}' | awk -v img="${LIBRECHAT_IMAGE_MARKER}" 'index($2, img) {print $1}')
[[ -z "${LIBRECHAT_DIR}" && -f "${LIBRECHAT_DEFAULT_DIR}/.env" ]] && LIBRECHAT_DIR="${LIBRECHAT_DEFAULT_DIR}"

if [[ -n "${LIBRECHAT_DIR}" ]]; then
  LIBRECHAT_ENV="${LIBRECHAT_DIR}/.env"
  LIBRECHAT_LINES="$(grep -nE '^[[:space:]]*(LIBRECHAT_CODE_BASEURL=|CODEAPI_)' "${LIBRECHAT_ENV}" 2>/dev/null || true)"
  LIBRECHAT_BASEURL="$(grep -E '^[[:space:]]*LIBRECHAT_CODE_BASEURL=' "${LIBRECHAT_ENV}" 2>/dev/null | tail -n 1 | cut -d= -f2- || true)"
fi

if [[ -n "${LIBRECHAT_LINES}" ]]; then
  echo ""
  warn "In LibreChats .env (${LIBRECHAT_ENV}) verweisen noch aktive Zeilen auf diesen Dienst:"
  while IFS= read -r l; do
    [[ -n "$l" ]] || continue
    # Private Schluessel nicht ins Log schreiben - nur den Namen zeigen.
    case "${l}" in
      *CODEAPI_JWT_PRIVATE_JWK_JSON=*) echo -e "   ${YELLOW}${l%%=*}=<privater Schluessel, hier nicht ausgegeben>${RESET}" ;;
      *) echo -e "   ${YELLOW}${l}${RESET}" ;;
    esac
  done <<<"${LIBRECHAT_LINES}"
  warn "Solange sie dort stehen, versucht LibreChat weiter, Code auszufuehren -"
  warn "und meldet Fehler, weil der Dienst dann nicht mehr existiert."
fi

# -- Images ermitteln ----------------------------------------------------------
# Lokal gebaute Images haben keinen RepoDigest - so lassen sie sich von den aus
# einer Registry gezogenen Basis-Images (redis, minio) unterscheiden, ohne die
# Compose-Datei zu interpretieren. Die Trennung ist wichtig: Basis-Images
# koennen von anderen Stacks mitbenutzt werden.
declare -a LOCAL_IMAGES=() BASE_IMAGES=()
if [[ -n "${COMPOSE_FILE}" ]]; then
  while IFS= read -r img; do
    [[ -n "${img}" ]] || continue
    docker image inspect "${img}" >/dev/null 2>&1 || continue
    if [[ "$(docker image inspect "${img}" -f '{{len .RepoDigests}}' 2>/dev/null || echo 0)" == "0" ]]; then
      LOCAL_IMAGES+=("${img}")
    else
      BASE_IMAGES+=("${img}")
    fi
  done < <(dc config --images 2>/dev/null | sort -u || true)
fi
# Vom Installer im NsJail-Modus gebaut und ausserhalb der Compose-Datei
# gestartet - taucht in 'config --images' deshalb nicht auf.
if docker image inspect "${PKG_INIT_IMAGE}" >/dev/null 2>&1; then
  LOCAL_IMAGES+=("${PKG_INIT_IMAGE}")
fi

if [[ "${#LOCAL_IMAGES[@]}" -gt 0 || "${#BASE_IMAGES[@]}" -gt 0 ]]; then
  echo ""
  info "Lokal vorhandene Images dieses Stacks (werden nur nach expliziter Bestaetigung geloescht):"
  for img in ${LOCAL_IMAGES[@]+"${LOCAL_IMAGES[@]}"}; do
    echo -e "   - ${CYAN}${img}${RESET} (aus dem Quellcode gebaut, $(docker image inspect "${img}" -f '{{.Size}}' 2>/dev/null | awk '{printf "%.1f GB", $1/1024/1024/1024}'))"
  done
  for img in ${BASE_IMAGES[@]+"${BASE_IMAGES[@]}"}; do
    echo -e "   - ${YELLOW}${img}${RESET} (Basis-Image, moeglicherweise von anderen Stacks mitgenutzt)"
  done
fi

# -- Swap-Datei des Installers -------------------------------------------------
SWAP_ACTIVE=0
SWAP_PRESENT=0
if [[ -f "${SWAP_FILE}" ]]; then
  SWAP_PRESENT=1
  swapon --show=NAME --noheadings 2>/dev/null | grep -qxF "${SWAP_FILE}" && SWAP_ACTIVE=1
  echo ""
  warn "Vom Installer angelegte Swap-Datei gefunden: ${SWAP_FILE}"
  echo -e "   Groesse: ${CYAN}$(du -h "${SWAP_FILE}" 2>/dev/null | cut -f1)${RESET}, aktiv: ${CYAN}$( ((SWAP_ACTIVE)) && echo ja || echo nein )${RESET}"
  warn "Sie wurde nur als Sicherheitsnetz fuer den Image-Build angelegt - kann"
  warn "inzwischen aber von anderen Diensten mitgenutzt werden. Eigene Abfrage."
fi

# -- Bestaetigung --------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${RED}${BOLD} Achtung: Secrets, Schluessel und die Sandbox-Laufzeiten sind danach weg.${RESET}"
echo -e " Eine Neuinstallation erzeugt neue Schluessel - LibreChats .env muss"
echo -e " dann ohnehin neu befuellt werden."
if ! ask_yesno "${RED}${BOLD}Wirklich Container, Volumes und ${INSTALL_DIR} unwiderruflich entfernen?${RESET}" "n"; then
  warn "Abgebrochen. Es wurde nichts veraendert."
  exit 0
fi

REMOVE_BACKUPS=false
KEEP_DIR=""
if [[ "${BACKUP_COUNT}" -gt 0 ]]; then
  if ask_yesno "Auch die ${BACKUP_COUNT} Backup(s) (${BACKUP_SIZE}) in backups/ loeschen? Sie enthalten alte .env-Staende mit Secrets." "n"; then
    REMOVE_BACKUPS=true
  else
    KEEP_DIR="$(dirname "${INSTALL_DIR}")/$(basename "${INSTALL_DIR}")-backups-$(date +%F_%H-%M-%S)"
    info "Backups werden vor dem Loeschen nach ${KEEP_DIR} verschoben."
  fi
fi

REMOVE_LOCAL_IMAGES=false
if [[ "${#LOCAL_IMAGES[@]}" -gt 0 ]]; then
  echo ""
  info "Hinweis: Diese Images sind lokal aus dem Quellcode gebaut. Nach dem"
  info "Loeschen dauert eine Neuinstallation wieder 10-30+ Minuten."
  if ask_yesno "Die selbst gebauten Images loeschen (${#LOCAL_IMAGES[@]} Stueck)?" "n"; then
    REMOVE_LOCAL_IMAGES=true
  fi
fi

REMOVE_BASE_IMAGES=false
if [[ "${#BASE_IMAGES[@]}" -gt 0 ]]; then
  if ask_yesno "Auch die Basis-Images (redis, minio, ...) loeschen? Andere Stacks koennen sie nutzen." "n"; then
    REMOVE_BASE_IMAGES=true
  fi
fi

REMOVE_SWAP=false
if [[ "${SWAP_PRESENT}" -eq 1 ]]; then
  if ask_yesno "Die Swap-Datei ${SWAP_FILE} abschalten, loeschen und den fstab-Eintrag entfernen?" "n"; then
    REMOVE_SWAP=true
  fi
fi

# Eingriff ausserhalb der eigenen Installation: bewusst ohne ASSUME_YES und mit
# Standard "nein". Geaendert werden nur die Zeilen dieses Dienstes, und vorher
# wird eine Sicherung angelegt.
CLEAN_LIBRECHAT=false
if [[ -n "${LIBRECHAT_LINES}" ]]; then
  echo ""
  warn "Optionaler Eingriff in ${BOLD}fremdes${RESET} Verzeichnis: ${LIBRECHAT_ENV}"
  info "Es wuerden ausschliesslich die Zeilen LIBRECHAT_CODE_BASEURL= und CODEAPI_*"
  info "auskommentiert (mit '#' davor), nach einer datierten Sicherung der Datei."
  if ask_yesno_strict "In LibreChats .env die Eintraege dieses Dienstes auskommentieren?"; then
    CLEAN_LIBRECHAT=true
  else
    info "LibreChats .env bleibt unveraendert - Hinweis folgt am Ende."
  fi
fi

# -- Entfernen -----------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Entfernen${RESET}"
echo "------------------------------------------------------------"

CONTAINERS_REMOVED=0
if [[ -n "${COMPOSE_FILE}" ]]; then
  info "Stoppe und entferne Container samt Volumes (compose down -v)..."
  if dc_run down -v --remove-orphans; then
    success "Container und Volumes entfernt."
    CONTAINERS_REMOVED=1
  else
    warn "'compose down -v' ist fehlgeschlagen (fehlende .env-Variablen?) - entferne die Container einzeln."
  fi
fi
if [[ "${CONTAINERS_REMOVED}" -eq 0 && -n "${CONTAINERS}" ]]; then
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    run docker rm -f "$c"
  done <<<"${CONTAINERS}"
  success "Container entfernt."
fi

# Falls 'down -v' ein Volume nicht erwischt hat (z.B. weil es aus einem
# frueheren Projektnamen stammt), gezielt nachraeumen - ausschliesslich
# Volumes mit dem Projekt-Label dieser Installation.
for v in ${PROJECT_VOLUMES[@]+"${PROJECT_VOLUMES[@]}"}; do
  if docker volume inspect "${v}" >/dev/null 2>&1; then
    info "Entferne uebrig gebliebenes Volume ${v}..."
    run docker volume rm "${v}" || warn "Volume ${v} konnte nicht entfernt werden (noch in Benutzung?)."
  fi
done

if [[ -n "${KEEP_DIR}" ]]; then
  info "Sichere Backups nach ${KEEP_DIR}..."
  run mv "${INSTALL_DIR}/backups" "${KEEP_DIR}"
  success "Backups gesichert."
elif ${REMOVE_BACKUPS}; then
  info "Backups werden zusammen mit dem Verzeichnis geloescht."
fi

if ${REMOVE_LOCAL_IMAGES}; then
  info "Entferne die selbst gebauten Images..."
  for img in "${LOCAL_IMAGES[@]}"; do
    run docker rmi "${img}" || warn "Image ${img} konnte nicht entfernt werden (evtl. noch referenziert)."
  done
fi
if ${REMOVE_BASE_IMAGES}; then
  info "Entferne die Basis-Images..."
  for img in "${BASE_IMAGES[@]}"; do
    run docker rmi "${img}" || warn "Image ${img} konnte nicht entfernt werden (evtl. noch referenziert)."
  done
fi
if ! ${REMOVE_LOCAL_IMAGES} && ! ${REMOVE_BASE_IMAGES}; then
  info "Images bleiben erhalten (uebersprungen)."
else
  success "Image-Bereinigung abgeschlossen."
fi

# Die Laufzeitumgebungen unter data/pkgs gehoeren root und liegen teils
# schreibgeschuetzt vor (Ergebnis des package-init-Containers). 'rm -rf'
# kommt damit zurecht, der Hinweis erklaert nur die Dauer.
info "Entferne Verzeichnis ${INSTALL_DIR} (data/pkgs kann einen Moment dauern)..."
run rm -rf "${INSTALL_DIR}"
success "Verzeichnis entfernt."

if ${REMOVE_SWAP}; then
  info "Entferne die Swap-Datei ${SWAP_FILE}..."
  if [[ "${SWAP_ACTIVE}" -eq 1 ]]; then
    run swapoff "${SWAP_FILE}" || warn "swapoff fehlgeschlagen - Datei bleibt bestehen."
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo -e "${YELLOW}   [DRY-RUN]${RESET} sed -i '\\#^${SWAP_FILE} #d' /etc/fstab"
  else
    # Nur die genau passende Zeile entfernen, fremde Swap-Eintraege bleiben.
    sed -i "\\#^${SWAP_FILE} #d" /etc/fstab 2>/dev/null || warn "fstab-Eintrag konnte nicht entfernt werden - bitte pruefen: /etc/fstab"
  fi
  run rm -f "${SWAP_FILE}"
  success "Swap-Datei entfernt und fstab bereinigt."
fi

if ${CLEAN_LIBRECHAT}; then
  LC_BACKUP="${LIBRECHAT_ENV}.vor-code-interpreter-entfernung-$(date +%Y%m%d-%H%M%S)"
  info "Sichere ${LIBRECHAT_ENV} nach $(basename "${LC_BACKUP}")..."
  run cp -a "${LIBRECHAT_ENV}" "${LC_BACKUP}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo -e "${YELLOW}   [DRY-RUN]${RESET} sed -i -E 's~^(LIBRECHAT_CODE_BASEURL=|CODEAPI_)~#&~' ${LIBRECHAT_ENV}"
  else
    sed -i -E 's~^(LIBRECHAT_CODE_BASEURL=|CODEAPI_)~#&~' "${LIBRECHAT_ENV}" \
      || warn "Konnte ${LIBRECHAT_ENV} nicht anpassen - bitte von Hand pruefen."
  fi
  success "Eintraege in LibreChats .env auskommentiert (Sicherung: $(basename "${LC_BACKUP}"))."
fi

# -- Abschluss -----------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo -e "${YELLOW}${BOLD} DRY-RUN beendet - es wurde NICHTS geloescht.${RESET}"
else
  echo -e "${GREEN}${BOLD} Code Interpreter vollstaendig entfernt.${RESET}"
fi
echo "------------------------------------------------------------"
echo ""
[[ -n "${KEEP_DIR}" ]] && { echo -e " Aufbewahrte Backups: ${CYAN}${KEEP_DIR}${RESET}"; echo -e " ${YELLOW}Sie enthalten alte .env-Staende mit Secrets - sicher aufbewahren oder loeschen.${RESET}"; echo ""; }
echo -e " Unangetastet geblieben: Netzwerk ${CYAN}${PROXY_NETWORK}${RESET}, LibreChat und alle"
echo -e " Container anderer Stacks (Nginx Proxy Manager, n8n, SearXNG, ...)."
echo ""

if ${CLEAN_LIBRECHAT}; then
  printf '%b\n' "${YELLOW}${BOLD} >>> Letzter Schritt auf der LibreChat-Seite <<<${RESET}"
  echo ""
  echo -e " Die .env wurde angepasst, LibreChat liest sie aber nur beim Start neu."
  echo -e " Ein reines 'docker restart' genuegt ${BOLD}nicht${RESET}:"
  echo ""
  echo -e "   ${CYAN}docker stop LibreChat && docker start LibreChat${RESET}"
  echo ""
elif [[ -n "${LIBRECHAT_LINES}" ]]; then
  printf '%b\n' "${YELLOW}${BOLD} >>> Offener Schritt auf der LibreChat-Seite <<<${RESET}"
  echo ""
  echo -e " In ${CYAN}${LIBRECHAT_ENV}${RESET} stehen weiterhin Zeilen fuer diesen Dienst"
  echo -e " (LIBRECHAT_CODE_BASEURL= und CODEAPI_*). LibreChat zeigt den Code"
  echo -e " Interpreter deshalb weiter an, jede Ausfuehrung schlaegt aber fehl."
  echo ""
  echo -e " Zeilen entfernen oder auskommentieren, danach LibreChat stoppen und"
  echo -e " starten (ein reines 'docker restart' liest die .env NICHT neu):"
  echo ""
  echo -e "   ${CYAN}docker stop LibreChat && docker start LibreChat${RESET}"
  echo ""
fi

if [[ -n "${LIBRECHAT_BASEURL}" && "${LIBRECHAT_BASEURL}" == https://* ]]; then
  DOMAIN_HINT="${LIBRECHAT_BASEURL#https://}"
  DOMAIN_HINT="${DOMAIN_HINT%%/*}"
  echo -e " Der Dienst war offenbar ueber die Domain ${CYAN}${DOMAIN_HINT}${RESET} erreichbar."
  echo -e " Bitte im Nginx Proxy Manager den zugehoerigen Proxy Host (und eine"
  echo -e " etwaige Access List) entfernen - ebenso den DNS-A-Record beim"
  echo -e " Domain-Provider. Das Zertifikat kann dort gleich mit weg."
else
  echo -e " Falls im Nginx Proxy Manager noch ein Proxy Host auf ${CYAN}avila-api:3112${RESET}"
  echo -e " zeigt, bitte dort manuell entfernen - ebenso den DNS-A-Record beim"
  echo -e " Domain-Provider und eine etwaige Access List."
fi
echo ""

if ! ${REMOVE_LOCAL_IMAGES}; then
  echo -e " Die selbst gebauten Images sind noch vorhanden - eine Neuinstallation"
  echo -e " wird dadurch deutlich schneller. Spaeter aufraeumen mit:"
  echo -e "   ${CYAN}docker image ls${RESET}   und   ${CYAN}docker image prune -a${RESET}"
  echo ""
fi
echo -e " Der Docker-Build-Cache dieses Stacks kann mehrere GB belegen und wird"
echo -e " hier bewusst nicht angefasst (er ist hostweit geteilt). Groesse pruefen"
echo -e " und bei Bedarf freigeben:"
echo -e "   ${CYAN}docker system df${RESET}   und   ${CYAN}docker builder prune${RESET}"
echo ""

if crontab -l 2>/dev/null | grep -q 'update-avila-code-interpreter'; then
  warn "In der root-Crontab steht noch ein Eintrag fuer update-avila-code-interpreter.sh."
  warn "Bitte manuell entfernen: crontab -e"
  echo ""
fi
if [[ -f /var/log/avila-code-interpreter-update.log ]]; then
  info "Das Update-Log /var/log/avila-code-interpreter-update.log bleibt erhalten."
  echo ""
fi

echo -e " Neuinstallation jederzeit moeglich mit:"
echo -e " ${CYAN}sudo bash -c \"\$(curl -fsSL ${INSTALL_SCRIPT_URL})\"${RESET}"
echo ""
echo -e " Mehr Tipps & Tutorials: ${CYAN}https://pc-fee.com/blog${RESET}"
echo -e " GitHub:                 ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
