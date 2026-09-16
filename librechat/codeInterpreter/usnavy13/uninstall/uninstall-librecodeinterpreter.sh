#!/usr/bin/env bash
# =============================================================================
# LibreCodeInterpreter Uninstall Script - powered by pc-fee.com
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Macht die Installation aus install-librecodeinterpreter.sh vollstaendig
# rueckgaengig: Container (api, redis, garage), die zugehoerigen Docker-Volumes,
# das Installationsverzeichnis (Repository, .env, docker-compose.override.yml,
# librechat.yaml, logs/), auf Wunsch die Backups und die Docker-Images.
#
# WICHTIG - was dieses Script grundsaetzlich NICHT anfasst:
#   * jedes Verzeichnis ausserhalb der erkannten LibreCodeInterpreter-
#     Installation. Andere Komponenten (LibreChat unter /opt/librechat,
#     avila-code-interpreter unter /opt/avila-code-interpreter) werden nur
#     erkannt und gemeldet.
#   * das Docker-Netzwerk "shared_proxy" - es wird von weiteren Stacks
#     (Nginx Proxy Manager, n8n, SearXNG, LibreChat, ...) mitgenutzt.
#
# Nutzung als 1-Zeiler (von ueberall, kein vorheriger Download noetig):
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/usnavy13/uninstall/uninstall-librecodeinterpreter.sh)"
#
# Optionen:
#   --dir <pfad>   Installationspfad fest vorgeben (ueberspringt die Erkennung)
#   --dry-run      Zeigt nur, was entfernt wuerde - loescht nichts
#   --yes          Ueberspringt alle Sicherheitsabfragen (wie ASSUME_YES=1)
#   --help         Diese Hilfe anzeigen
#
# Umgebungsvariablen (fuer unbeaufsichtigten Betrieb):
#   INSTALL_DIR    wie --dir
#   ASSUME_YES=1   wie --yes (loescht dann auch Backups und Images ungefragt)
#
# Voraussetzungen: root (bzw. sudo), Docker + Docker Compose.
#
# AI Transparency: Dieses Script wurde mit Unterstuetzung von KI erstellt und
# vor Veroeffentlichung geprueft. Es entfernt unwiderruflich Daten - inklusive
# aller API-Keys und hochgeladener Dateien. Bitte vorher mit --dry-run pruefen
# und ein Backup sicherstellen.
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
readonly DEFAULT_DIR="/opt/LibreCodeInterpreter"
readonly IMAGE_MARKER="usnavy13/LibreCodeInterpreter"
readonly INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/usnavy13/install/install-librecodeinterpreter.sh"
# Verzeichnisse zusaetzlicher Komponenten. Werden ausschliesslich gemeldet -
# dieses Script loescht nichts ausserhalb der LibreCodeInterpreter-Installation.
readonly EXTRA_DIRS=(
  "/opt/librechat:LibreChat (Hauptinstallation)"
  "/opt/avila-code-interpreter:Code Interpreter (LibreChat-AI/avila)"
)

# -- Optionen ------------------------------------------------------------------
DRY_RUN=0

usage() {
  cat <<'USAGE'
LibreCodeInterpreter Uninstall Script - powered by pc-fee.com

Entfernt eine mit install-librecodeinterpreter.sh installierte Instanz:
Container, Docker-Volumes, das Installationsverzeichnis (Repository, .env,
docker-compose.override.yml, logs/), auf Wunsch die Backups und die Docker-Images.

Nicht angetastet werden das Netzwerk 'shared_proxy' und jedes Verzeichnis
ausserhalb der Installation - LibreChat und /opt/avila-code-interpreter werden
nur gemeldet.

Optionen:
  --dir <pfad>   Installationspfad fest vorgeben (ueberspringt die Erkennung)
  --dry-run      Zeigt nur, was entfernt wuerde - loescht nichts
  --yes          Ueberspringt alle Sicherheitsabfragen (wie ASSUME_YES=1)
  --help         Diese Hilfe anzeigen

Umgebungsvariablen: INSTALL_DIR, ASSUME_YES

Beispiele:
  sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/usnavy13/uninstall/uninstall-librecodeinterpreter.sh)"
  sudo ./uninstall-librecodeinterpreter.sh --dry-run
  sudo ./uninstall-librecodeinterpreter.sh --dir /srv/LibreCodeInterpreter
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
    warn "Ohne Bestaetigung wird nichts entfernt (ASSUME_YES=1 setzen, falls gewollt)."
    return 1
  fi
  echo ""
  echo -ne "${BOLD}${prompt}${RESET} [${CYAN}${hint}${RESET}]: "
  read -r input <"${TTY}" || true
  input="${input:-${default}}"
  [[ "${input,,}" == "j" || "${input,,}" == "y" ]]
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
printf '%b\n' "${BOLD} LibreCodeInterpreter Uninstall - powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo -e " Macht die Installation aus ${BOLD}install-librecodeinterpreter.sh${RESET} rueckgaengig:"
echo -e " Container, ${BOLD}Docker-Volumes${RESET} und das Installationsverzeichnis mit"
echo -e " Repository, ${BOLD}.env${RESET}, docker-compose.override.yml und Logs."
echo ""
echo -e " ${YELLOW}Wird NICHT angefasst:${RESET} das Docker-Netzwerk ${BOLD}${PROXY_NETWORK}${RESET}, die"
echo -e " Container anderer Stacks und ${BOLD}jedes Verzeichnis ausserhalb${RESET} der"
echo -e " Installation (LibreChat, avila-code-interpreter werden nur gemeldet)."
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo -e " ${YELLOW}${BOLD}DRY-RUN aktiv:${RESET} es wird nichts geloescht, nur angezeigt."
fi
echo "------------------------------------------------------------"

# -- Root-Check ----------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  die "Bitte als root oder mit sudo ausfuehren."
fi

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

mapfile -t LCI_CONTAINERS < <(
  docker ps -a --format '{{.ID}} {{.Names}} {{.Image}}' \
    | awk -v a="${IMAGE_MARKER}" 'index($3, a) {print $2}'
)

if [[ -n "${INSTALL_DIR:-}" ]]; then
  [[ -d "${INSTALL_DIR}" ]] || die "Angegebener Pfad existiert nicht: ${INSTALL_DIR}"
  info "Installationspfad (vorgegeben): ${INSTALL_DIR}"
else
  mapfile -t FOUND < <(detect_dirs)
  case "${#FOUND[@]}" in
    0)
      if [[ "${#LCI_CONTAINERS[@]}" -gt 0 ]]; then
        warn "Kein Installationsverzeichnis gefunden, aber es existieren noch LibreCodeInterpreter-Container:"
        for c in "${LCI_CONTAINERS[@]}"; do echo -e "   - ${CYAN}${c}${RESET}"; done
        if ask_yesno "${BOLD}Diese verwaisten Container entfernen?${RESET}" "n"; then
          for c in "${LCI_CONTAINERS[@]}"; do run docker rm -f "${c}"; done
          success "Verwaiste Container entfernt."
          warn "Etwaige Docker-Volumes dieses Stacks bleiben bestehen - sie lassen sich"
          warn "mit 'docker volume ls' pruefen und mit 'docker volume rm <name>' entfernen."
        else
          warn "Abgebrochen. Es wurde nichts veraendert."
        fi
        exit 0
      fi
      success "Nichts zu tun - keine LibreCodeInterpreter-Installation und keine Container gefunden."
      exit 0
      ;;
    1)
      INSTALL_DIR="${FOUND[0]}"
      info "Installation erkannt: ${INSTALL_DIR}"
      ;;
    *)
      echo ""
      warn "Mehrere LibreCodeInterpreter-Installationen gefunden:"
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
if [[ -z "${CONTAINERS}" && "${#LCI_CONTAINERS[@]}" -gt 0 ]]; then
  CONTAINERS=$(printf '%s\n' "${LCI_CONTAINERS[@]}")
fi

if [[ -n "${CONTAINERS}" ]]; then
  info "Folgende Container werden entfernt:"
  while IFS= read -r c; do [[ -n "$c" ]] && echo -e "   - ${CYAN}${c}${RESET}"; done <<<"${CONTAINERS}"
else
  warn "Keine laufenden/gestoppten LibreCodeInterpreter-Container gefunden (evtl. schon entfernt)."
fi

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
fi

echo ""
info "Folgendes Verzeichnis wird entfernt: ${BOLD}${INSTALL_DIR}${RESET}"

dirsize() { du -sh "${INSTALL_DIR}/$1" 2>/dev/null | cut -f1; }
item() { printf '     %b+- %-29s%b%b\n' "$1" "$2" "${RESET}" "$3"; }

[[ -f "${INSTALL_DIR}/.env" ]] && \
  item "${YELLOW}" ".env" "- Schluessel, Secrets, MASTER_API_KEY"
[[ -f "${INSTALL_DIR}/docker-compose.override.yml" ]] && \
  item "${YELLOW}" "docker-compose.override.yml" "- NPM-Netzwerk, geschlossene Host-Ports"
[[ -f "${INSTALL_DIR}/librechat.yaml" ]] && \
  item "${YELLOW}" "librechat.yaml" "- zusaetzliche Konfiguration"
[[ -d "${INSTALL_DIR}/logs" ]] && \
  item "${YELLOW}" "logs/" "- Anwendungslogs ($(dirsize logs))"
[[ -d "${INSTALL_DIR}/.git" ]] && \
  item "${YELLOW}" ".git/" "- geklontes LibreCodeInterpreter-Repository"

BACKUP_COUNT=0
BACKUP_SIZE="0"
if [[ -d "${INSTALL_DIR}/backups" ]]; then
  BACKUP_COUNT=$(find "${INSTALL_DIR}/backups" -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.tgz' \) 2>/dev/null | wc -l | tr -d ' ')
  BACKUP_SIZE=$(du -sh "${INSTALL_DIR}/backups" 2>/dev/null | cut -f1)
  item "${YELLOW}" "backups/" "- ${BACKUP_COUNT} Backup(s), ${BACKUP_SIZE} (separate Abfrage)"
fi

OTHERS=""
if docker network inspect "${PROXY_NETWORK}" &>/dev/null; then
  OTHERS=$(docker network inspect "${PROXY_NETWORK}" \
    --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' 2>/dev/null \
    | grep -v '^$' | grep -viE 'librecodeinterpreter|code-interpreter' || true)
fi
if [[ -n "${OTHERS}" ]]; then
  echo ""
  warn "Diese Container haengen ebenfalls am Netzwerk '${PROXY_NETWORK}':"
  while IFS= read -r c; do [[ -n "$c" ]] && echo -e "   - ${CYAN}${c}${RESET}"; done <<<"${OTHERS}"
  warn "Sie laufen unveraendert weiter - dieses Script ruehrt das Netzwerk nicht an."
fi

declare -a EXTRAS_FOUND=()
for entry in "${EXTRA_DIRS[@]}"; do
  d="${entry%%:*}"
  label="${entry#*:}"
  [[ "${d}" == "${INSTALL_DIR}" ]] && continue
  [[ -d "${d}" ]] && EXTRAS_FOUND+=("${d} - ${label}")
done

if [[ "${#EXTRAS_FOUND[@]}" -gt 0 ]]; then
  echo ""
  warn "Zusaetzliche Komponenten gefunden - ${BOLD}diese bleiben unangetastet${RESET}:"
  for e in ${EXTRAS_FOUND[@]+"${EXTRAS_FOUND[@]}"}; do
    echo -e "   - ${CYAN}${e}${RESET}"
  done
  warn "Sie wurden von eigenen Scripten installiert und muessen dort entfernt werden."
fi

declare -a LCI_IMAGES=() SHARED_IMAGES=()
if [[ -n "${COMPOSE_FILE}" ]]; then
  while IFS= read -r img; do
    [[ -n "${img}" ]] || continue
    docker image inspect "${img}" >/dev/null 2>&1 || continue
    if [[ "${img}" == *"${IMAGE_MARKER}"* ]]; then
      LCI_IMAGES+=("${img}")
    else
      SHARED_IMAGES+=("${img}")
    fi
  done < <(dc config --images 2>/dev/null | sort -u || true)
fi

if [[ "${#LCI_IMAGES[@]}" -gt 0 || "${#SHARED_IMAGES[@]}" -gt 0 ]]; then
  echo ""
  info "Lokal vorhandene Images dieses Stacks (werden nur nach expliziter Bestaetigung geloescht):"
  for img in ${LCI_IMAGES[@]+"${LCI_IMAGES[@]}"}; do
    echo -e "   - ${CYAN}${img}${RESET} (LibreCodeInterpreter-eigen)"
  done
  for img in ${SHARED_IMAGES[@]+"${SHARED_IMAGES[@]}"}; do
    echo -e "   - ${YELLOW}${img}${RESET} (Basis-Image, moeglicherweise von anderen Stacks mitgenutzt)"
  done
fi

# -- Bestaetigung --------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${RED}${BOLD} Achtung: API-Keys und hochgeladene Dateien sind danach weg.${RESET}"
if ! ask_yesno "${RED}${BOLD}Wirklich Container, Volumes und ${INSTALL_DIR} unwiderruflich entfernen?${RESET}" "n"; then
  warn "Abgebrochen. Es wurde nichts veraendert."
  exit 0
fi

REMOVE_BACKUPS=false
KEEP_DIR=""
if [[ "${BACKUP_COUNT}" -gt 0 ]]; then
  if ask_yesno "Auch die ${BACKUP_COUNT} Backup(s) (${BACKUP_SIZE}) in backups/ loeschen?" "n"; then
    REMOVE_BACKUPS=true
  else
    KEEP_DIR="$(dirname "${INSTALL_DIR}")/librecodeinterpreter-backups-$(date +%F_%H-%M-%S)"
    info "Backups werden vor dem Loeschen nach ${KEEP_DIR} verschoben."
  fi
fi

REMOVE_LCI_IMAGES=false
if [[ "${#LCI_IMAGES[@]}" -gt 0 ]]; then
  if ask_yesno "Die LibreCodeInterpreter-eigenen Images loeschen (${#LCI_IMAGES[@]} Stueck)?" "n"; then
    REMOVE_LCI_IMAGES=true
  fi
fi

REMOVE_SHARED_IMAGES=false
if [[ "${#SHARED_IMAGES[@]}" -gt 0 ]]; then
  if ask_yesno "Auch die Basis-Images (redis, garage, ...) loeschen? Andere Stacks koennen sie nutzen." "n"; then
    REMOVE_SHARED_IMAGES=true
  fi
fi

# -- Entfernen -----------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Entfernen${RESET}"
echo "------------------------------------------------------------"

if [[ -n "${COMPOSE_FILE}" ]]; then
  info "Stoppe und entferne Container samt Volumes (compose down -v)..."
  dc_run down -v --remove-orphans
  success "Container und Volumes entfernt."
elif [[ -n "${CONTAINERS}" ]]; then
  warn "Keine Compose-Datei gefunden - entferne Container einzeln."
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    run docker rm -f "$c"
  done <<<"${CONTAINERS}"
  success "Container entfernt."
fi

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

if ${REMOVE_LCI_IMAGES}; then
  info "Entferne LibreCodeInterpreter-eigene Images..."
  for img in "${LCI_IMAGES[@]}"; do
    run docker rmi "${img}" || warn "Image ${img} konnte nicht entfernt werden (evtl. noch referenziert)."
  done
fi
if ${REMOVE_SHARED_IMAGES}; then
  info "Entferne Basis-Images..."
  for img in "${SHARED_IMAGES[@]}"; do
    run docker rmi "${img}" || warn "Image ${img} konnte nicht entfernt werden (evtl. noch referenziert)."
  done
fi
if ! ${REMOVE_LCI_IMAGES} && ! ${REMOVE_SHARED_IMAGES}; then
  info "Images bleiben erhalten (uebersprungen)."
else
  success "Image-Bereinigung abgeschlossen."
fi

info "Entferne Verzeichnis ${INSTALL_DIR}..."
run rm -rf "${INSTALL_DIR}"
success "Verzeichnis entfernt."

# -- Abschluss -----------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo -e "${YELLOW}${BOLD} DRY-RUN beendet - es wurde NICHTS geloescht.${RESET}"
else
  echo -e "${GREEN}${BOLD} LibreCodeInterpreter vollstaendig entfernt.${RESET}"
fi
echo "------------------------------------------------------------"
echo ""
[[ -n "${KEEP_DIR}" ]] && echo -e " Aufbewahrte Backups: ${CYAN}${KEEP_DIR}${RESET}" && echo ""
echo -e " Unangetastet geblieben: Netzwerk ${CYAN}${PROXY_NETWORK}${RESET} und alle Container"
echo -e " anderer Stacks (Nginx Proxy Manager, n8n, SearXNG, LibreChat, ...)."
echo ""

if [[ "${#EXTRAS_FOUND[@]}" -gt 0 ]]; then
  warn "Diese Komponenten bestehen weiterhin und muessen separat entfernt werden:"
  for e in ${EXTRAS_FOUND[@]+"${EXTRAS_FOUND[@]}"}; do
    echo -e "   - ${CYAN}${e}${RESET}"
  done
  echo -e "   Anleitung: ${CYAN}https://github.com/nephilim75/scripts/tree/main/librechat${RESET}"
  echo ""
fi

if crontab -l 2>/dev/null | grep -q 'update-librecodeinterpreter'; then
  warn "In der root-Crontab steht noch ein Eintrag fuer update-librecodeinterpreter.sh."
  warn "Bitte manuell entfernen: crontab -e"
  echo ""
fi
if [[ -f /var/log/librecodeinterpreter-update.log ]]; then
  info "Das Update-Log /var/log/librecodeinterpreter-update.log bleibt erhalten."
  echo ""
fi

echo -e " Falls im Nginx Proxy Manager noch ein Proxy Host fuer die Code-Interpreter-"
echo -e " Domain existiert, bitte dort manuell entfernen - ebenso den zugehoerigen"
echo -e " DNS-A-Record beim Domain-Provider."
echo ""
echo -e " Neuinstallation jederzeit moeglich mit:"
echo -e " ${CYAN}sudo bash -c \"\$(curl -fsSL ${INSTALL_SCRIPT_URL})\"${RESET}"
echo ""
echo -e " Mehr Tipps & Tutorials: ${CYAN}https://pc-fee.com/blog${RESET}"
echo -e " GitHub:                 ${CYAN}${LCI_GUIDE:-https://github.com/nephilim75/scripts/tree/main/librechat/codeInterpreter/usnavy13}${RESET}"
echo ""
