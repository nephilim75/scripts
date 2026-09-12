#!/usr/bin/env bash
# =============================================================================
# Nginx Proxy Manager Uninstall Script - powered by pc-fee.com
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Entfernt eine mit install-npm.sh installierte NPM-Instanz rueckstandsfrei:
# Container, das Installationsverzeichnis (data/ mit SQLite-DB und allen Proxy
# Hosts, letsencrypt/ mit allen Zertifikaten, docker-compose.yml), auf Wunsch
# die Backups und die Docker-Images.
#
# Das Docker-Netzwerk "shared_proxy" wird NICHT angefasst - es wird von
# weiteren Stacks (n8n, LibreChat, ...) mitgenutzt. Diese Container laufen
# nach dem Entfernen weiter, sind aber von aussen nicht mehr erreichbar.
#
# Nutzung als 1-Zeiler (von ueberall, kein vorheriger Download noetig):
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/uninstall/uninstall-npm.sh)"
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
# Autor: Nils Weber (n8n Automation Architect, pc-fee.com)
#
# AI Transparency: Dieses Script wurde mit Unterstuetzung von KI erstellt und
# vor Veroeffentlichung geprueft. Es entfernt unwiderruflich Daten - bitte
# vorher mit --dry-run pruefen und ein Backup sicherstellen.
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
readonly DEFAULT_DIR="/opt/nginx-proxy-manager"
readonly INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/install/install-npm.sh"

# -- Optionen ------------------------------------------------------------------
DRY_RUN=0

usage() {
  cat <<'USAGE'
Nginx Proxy Manager Uninstall Script - powered by pc-fee.com

Entfernt eine mit install-npm.sh installierte NPM-Instanz: Container, das
Installationsverzeichnis (data/, letsencrypt/, docker-compose.yml), auf
Wunsch die Backups und die Docker-Images. Das Netzwerk 'shared_proxy'
bleibt unangetastet.

Optionen:
  --dir <pfad>   Installationspfad fest vorgeben (ueberspringt die Erkennung)
  --dry-run      Zeigt nur, was entfernt wuerde - loescht nichts
  --yes          Ueberspringt alle Sicherheitsabfragen (wie ASSUME_YES=1)
  --help         Diese Hilfe anzeigen

Umgebungsvariablen: INSTALL_DIR, ASSUME_YES

Beispiele:
  sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/uninstall/uninstall-npm.sh)"
  sudo ./uninstall-npm.sh --dry-run
  sudo ./uninstall-npm.sh --dir /srv/npm
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
printf '%b\n' "${BOLD} Nginx Proxy Manager Uninstall - powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo -e " Entfernt eine mit ${BOLD}install-npm.sh${RESET} installierte NPM-Instanz:"
echo -e " Container, Installationsverzeichnis (${BOLD}data/${RESET} mit allen Proxy Hosts,"
echo -e " ${BOLD}letsencrypt/${RESET} mit allen Zertifikaten), auf Wunsch Backups und Images."
echo ""
echo -e " ${YELLOW}Wird NICHT angefasst:${RESET} das Docker-Netzwerk ${BOLD}${PROXY_NETWORK}${RESET} und"
echo -e " die Container anderer Stacks (n8n, LibreChat, ...)."
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo -e " ${YELLOW}${BOLD}DRY-RUN aktiv:${RESET} es wird nichts geloescht, nur angezeigt."
fi
echo "------------------------------------------------------------"

# -- Root-Check ----------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  die "Bitte als root oder mit sudo ausfuehren."
fi

# Siehe install-npm.sh: in ein garantiert existierendes Verzeichnis wechseln,
# damit spaetere Aufrufe nicht an einer geloeschten CWD scheitern.
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
# Identische Erkennung wie im Update-Script: Container-Label -> Volume-Quelle
# -> Standardpfad. Ein Verzeichnis gilt als NPM-Installation, wenn es eine
# Compose-Datei mit nginx-proxy-manager-Image enthaelt.
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

  while IFS= read -r cid; do
    [[ -n "${cid}" ]] || continue
    d=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "${cid}" 2>/dev/null || true)
    [[ -n "${d}" && "${d}" == /* ]] && raw+=("${d}")
    d=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "${cid}" 2>/dev/null || true)
    [[ -n "${d}" && "${d}" == /* ]] && raw+=("$(dirname "${d}")")
  done < <(docker ps -a --format '{{.ID}} {{.Image}}' | awk '/nginx-proxy-manager/ {print $1}')

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

# Verwaiste Container (Verzeichnis bereits von Hand geloescht) einsammeln.
mapfile -t NPM_CONTAINERS < <(docker ps -a --format '{{.ID}} {{.Names}} {{.Image}}' | awk '/nginx-proxy-manager/ {print $2}')

if [[ -n "${INSTALL_DIR:-}" ]]; then
  [[ -d "${INSTALL_DIR}" ]] || die "Angegebener Pfad existiert nicht: ${INSTALL_DIR}"
  info "Installationspfad (vorgegeben): ${INSTALL_DIR}"
else
  mapfile -t FOUND < <(detect_dirs)
  case "${#FOUND[@]}" in
    0)
      if [[ "${#NPM_CONTAINERS[@]}" -gt 0 ]]; then
        warn "Kein Installationsverzeichnis gefunden, aber es existieren noch NPM-Container:"
        for c in "${NPM_CONTAINERS[@]}"; do echo -e "   - ${CYAN}${c}${RESET}"; done
        if ask_yesno "${BOLD}Diese verwaisten Container entfernen?${RESET}" "n"; then
          for c in "${NPM_CONTAINERS[@]}"; do run docker rm -f "${c}"; done
          success "Verwaiste Container entfernt."
        else
          warn "Abgebrochen. Es wurde nichts veraendert."
        fi
        exit 0
      fi
      success "Nichts zu tun - keine NPM-Installation und keine Container gefunden."
      exit 0
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
readonly INSTALL_DIR

COMPOSE_FILE=""
COMPOSE_FILE="$(compose_file_of "${INSTALL_DIR}" || true)"
readonly COMPOSE_FILE

# -- Bestandsaufnahme ----------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Bestandsaufnahme${RESET}"
echo "------------------------------------------------------------"

CONTAINERS=""
if [[ -n "${COMPOSE_FILE}" ]]; then
  CONTAINERS=$(${COMPOSE_CMD} -f "${COMPOSE_FILE}" ps -a --format '{{.Name}}' 2>/dev/null || true)
fi
if [[ -z "${CONTAINERS}" && "${#NPM_CONTAINERS[@]}" -gt 0 ]]; then
  CONTAINERS=$(printf '%s\n' "${NPM_CONTAINERS[@]}")
fi

if [[ -n "${CONTAINERS}" ]]; then
  info "Folgende Container werden entfernt:"
  while IFS= read -r c; do [[ -n "$c" ]] && echo -e "   - ${CYAN}${c}${RESET}"; done <<<"${CONTAINERS}"
else
  warn "Keine laufenden/gestoppten NPM-Container gefunden (evtl. schon entfernt)."
fi

echo ""
info "Folgendes Verzeichnis wird entfernt: ${BOLD}${INSTALL_DIR}${RESET}"
[[ -d "${INSTALL_DIR}/data" ]] && \
  echo -e "     ${YELLOW}+- data/${RESET}        - SQLite-DB, ALLE Proxy Hosts, Zugangsdaten, Access Lists"
[[ -d "${INSTALL_DIR}/letsencrypt" ]] && \
  echo -e "     ${YELLOW}+- letsencrypt/${RESET} - ALLE ausgestellten Zertifikate und Account-Keys"
[[ -n "${COMPOSE_FILE}" ]] && \
  echo -e "     ${YELLOW}+- $(basename "${COMPOSE_FILE}")${RESET}"

BACKUP_COUNT=0
BACKUP_SIZE="0"
if [[ -d "${INSTALL_DIR}/backups" ]]; then
  BACKUP_COUNT=$(find "${INSTALL_DIR}/backups" -maxdepth 1 -name 'npm_*.tar.gz' -type f 2>/dev/null | wc -l | tr -d ' ')
  BACKUP_SIZE=$(du -sh "${INSTALL_DIR}/backups" 2>/dev/null | cut -f1)
  echo -e "     ${YELLOW}+- backups/${RESET}     - ${BACKUP_COUNT} Backup(s), ${BACKUP_SIZE} (separate Abfrage)"
fi

# Andere Container am shared_proxy-Netz: die verlieren ihren Reverse Proxy.
OTHERS=""
if docker network inspect "${PROXY_NETWORK}" &>/dev/null; then
  OTHERS=$(docker network inspect "${PROXY_NETWORK}" \
    --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' 2>/dev/null \
    | grep -v '^$' | grep -viE 'nginx-proxy-manager|npm' || true)
fi
if [[ -n "${OTHERS}" ]]; then
  echo ""
  warn "Diese Container haengen ebenfalls am Netzwerk '${PROXY_NETWORK}':"
  while IFS= read -r c; do [[ -n "$c" ]] && echo -e "   - ${CYAN}${c}${RESET}"; done <<<"${OTHERS}"
  warn "Sie laufen weiter, sind ohne NPM aber nicht mehr von aussen erreichbar."
fi

# Images ermitteln (ueber mehrere Updates koennen sich mehrere Tags ansammeln).
mapfile -t IMAGE_LINES < <(docker images --format '{{.Repository}}:{{.Tag}}	{{.ID}}' 2>/dev/null | grep -i 'nginx-proxy-manager' || true)
if [[ "${#IMAGE_LINES[@]}" -gt 0 ]]; then
  echo ""
  info "Lokal vorhandene NPM-Images (werden nur nach expliziter Bestaetigung geloescht):"
  for line in "${IMAGE_LINES[@]}"; do
    name="${line%%$'\t'*}"
    id="${line##*$'\t'}"
    echo -e "   - ${CYAN}${name}${RESET} (${id:0:12})"
  done
fi

# -- Bestaetigung --------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
if ! ask_yesno "${RED}${BOLD}Wirklich Container und ${INSTALL_DIR} unwiderruflich entfernen?${RESET}" "n"; then
  warn "Abgebrochen. Es wurde nichts veraendert."
  exit 0
fi

REMOVE_BACKUPS=false
KEEP_DIR=""
if [[ "${BACKUP_COUNT}" -gt 0 ]]; then
  if ask_yesno "Auch die ${BACKUP_COUNT} Backup(s) (${BACKUP_SIZE}) in backups/ loeschen?" "n"; then
    REMOVE_BACKUPS=true
  else
    KEEP_DIR="$(dirname "${INSTALL_DIR}")/npm-backups-$(date +%F_%H-%M-%S)"
    info "Backups werden vor dem Loeschen nach ${KEEP_DIR} verschoben."
  fi
fi

REMOVE_IMAGES=false
if [[ "${#IMAGE_LINES[@]}" -gt 0 ]]; then
  if ask_yesno "Zusaetzlich die oben gelisteten Images loeschen?" "n"; then
    REMOVE_IMAGES=true
  fi
fi

# -- Entfernen -----------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Entfernen${RESET}"
echo "------------------------------------------------------------"

if [[ -n "${COMPOSE_FILE}" ]]; then
  info "Stoppe und entferne Container (compose down)..."
  run ${COMPOSE_CMD} -f "${COMPOSE_FILE}" down --remove-orphans
  success "Container entfernt."
elif [[ -n "${CONTAINERS}" ]]; then
  warn "Keine Compose-Datei gefunden - entferne Container einzeln."
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    run docker rm -f "$c"
  done <<<"${CONTAINERS}"
  success "Container entfernt."
fi

if [[ -n "${KEEP_DIR}" ]]; then
  info "Sichere Backups nach ${KEEP_DIR}..."
  run mv "${INSTALL_DIR}/backups" "${KEEP_DIR}"
  success "Backups gesichert."
elif ${REMOVE_BACKUPS}; then
  info "Backups werden zusammen mit dem Verzeichnis geloescht."
fi

if ${REMOVE_IMAGES}; then
  info "Entferne Images..."
  for line in "${IMAGE_LINES[@]}"; do
    id="${line##*$'\t'}"
    run docker rmi "${id}" || warn "Image ${id:0:12} konnte nicht entfernt werden (evtl. noch referenziert)."
  done
  success "Image-Bereinigung abgeschlossen."
else
  info "Images bleiben erhalten (uebersprungen)."
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
  echo -e "${GREEN}${BOLD} Nginx Proxy Manager vollstaendig entfernt.${RESET}"
fi
echo "------------------------------------------------------------"
echo ""
[[ -n "${KEEP_DIR}" ]] && echo -e " Aufbewahrte Backups: ${CYAN}${KEEP_DIR}${RESET}" && echo ""
echo -e " Unangetastet geblieben: Netzwerk ${CYAN}${PROXY_NETWORK}${RESET} und alle Container"
echo -e " anderer Stacks. Diese sind ohne Reverse Proxy nicht mehr von aussen"
echo -e " erreichbar - entweder neuen Proxy aufsetzen oder Ports direkt binden."
echo ""

# Uebrig gebliebene Reste, die dieses Script bewusst nicht anfasst.
if crontab -l 2>/dev/null | grep -q 'update-npm'; then
  warn "In der root-Crontab steht noch ein Eintrag fuer update-npm.sh."
  warn "Bitte manuell entfernen: crontab -e"
  echo ""
fi
if [[ -f /var/log/npm-update.log ]]; then
  info "Das Update-Log /var/log/npm-update.log bleibt erhalten."
  echo ""
fi

echo -e " Neuinstallation jederzeit moeglich mit:"
echo -e " ${CYAN}sudo bash -c \"\$(curl -fsSL ${INSTALL_SCRIPT_URL})\"${RESET}"
echo ""
echo -e " Mehr Tipps & Tutorials: ${CYAN}https://pc-fee.com/blog${RESET}"
echo -e " GitHub:                 ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
