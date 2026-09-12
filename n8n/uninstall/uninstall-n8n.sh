#!/usr/bin/env bash
# =============================================================================
#  n8n Uninstall Script – powered by pc-fee.com
#  https://pc-fee.com | https://github.com/nephilim75/scripts
#
#  Entfernt eine mit install-n8n.sh installierte n8n-Instanz rückstandsfrei:
#  Container, das komplette Installationsverzeichnis (n8n_data mit allen
#  Workflows/Credentials/Executions, backups/, .env mit allen Secrets,
#  docker-compose.yml), optional die Docker-Images.
#
#  Das Docker-Netzwerk "shared_proxy" wird NICHT angefasst – es wird von
#  Nginx Proxy Manager und ggf. weiteren Diensten (z.B. der n8n Sandbox)
#  mitgenutzt. Eine separat installierte n8n Sandbox Service-Instanz wird
#  ebenfalls nicht angefasst (eigenständiger Stack, eigenes Uninstall-Skript).
#
#  Nutzung als 1-Zeiler:
#    bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/uninstall/uninstall-n8n.sh)
#
#  Optionen:
#    --dry-run   Zeigt nur, was entfernt würde, löscht aber nichts.
#
#  Umgebungsvariablen (für unbeaufsichtigten Betrieb):
#    INSTALL_DIR   Installationspfad (Default: /opt/n8n)
#    ASSUME_YES=1  Überspringt alle Sicherheitsabfragen (inkl. Image-Löschung)
#
#  Voraussetzungen: wie beim Installer läuft dieses Skript ohne eigenes
#  Sudo-Handling – es braucht also bereits ausreichende Rechte (z.B. root
#  oder Mitgliedschaft in der docker-Gruppe plus Schreibrechte auf
#  INSTALL_DIR), genau wie install-n8n.sh und update-n8n.sh.
#
#  Mehr Infos: https://pc-fee.com/blog
#
#  AI Transparency: Dieses Skript wurde von Claude (Anthropic) im Auftrag
#  von pc-fee.com erstellt. Es entfernt unwiderruflich Daten – bitte vor
#  dem produktiven Einsatz mit --dry-run prüfen und vorher ein Backup
#  sicherstellen.
# =============================================================================

set -euo pipefail

# ── Farben ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Konstanten ────────────────────────────────────────────────────────────────
readonly PROXY_NETWORK="shared_proxy"
readonly INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/install/install-n8n.sh"

# ── Optionen ──────────────────────────────────────────────────────────────────
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) ;;
  esac
done
readonly DRY_RUN

# ── Hilfsfunktionen ───────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[FEHLER]${RESET} $*"; }
die()     { error "$*"; exit 1; }

ask() {
  # ask <variable> <prompt> <default>
  local var="$1" prompt="$2" default="$3"
  echo ""
  echo -ne "${BOLD}${prompt}${RESET} [${CYAN}${default}${RESET}]: "
  read -r input
  eval "${var}=\"${input:-${default}}\""
}

# ask_yesno <prompt> <default: j|n> -> Rückgabewert via $? (0 = ja)
ask_yesno() {
  local prompt="$1" default="${2:-n}" input=""
  local hint="j/N"
  [[ "${default,,}" == "j" ]] && hint="J/n"
  if [[ "${ASSUME_YES:-0}" == "1" ]]; then
    info "ASSUME_YES=1 gesetzt – überspringe Abfrage: ${prompt}"
    return 0
  fi
  echo ""
  echo -ne "${BOLD}${prompt}${RESET} [${CYAN}${hint}${RESET}]: "
  read -r input
  input="${input:-${default}}"
  [[ "${input,,}" == "j" || "${input,,}" == "y" ]]
}

# run <befehl...>  – im Dry-Run nur anzeigen, sonst ausführen.
run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo -e "${YELLOW}   [DRY-RUN]${RESET} $*"
  else
    "$@"
  fi
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo -e "${CYAN}"
cat <<'EOF'
               __
 _ __  __ ___ / _|___ ___   __ ___ _ __
| '_ \/ _|___|  _/ -_) -_)_/ _/ _ \ '  \
| .__/\__|   |_| \___\___(_)__\___/_|_|_|
|_|
EOF
echo -e "${RESET}"
echo -e "${BOLD}  n8n Uninstall-Script – powered by pc-fee.com${RESET}"
echo -e "  ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo -e "  Entfernt eine mit ${BOLD}install-n8n.sh${RESET} installierte n8n-Instanz"
echo -e "  rückstandsfrei: Container, Installationsverzeichnis (inkl. aller"
echo -e "  Workflows, Credentials und der .env mit allen Secrets), optional"
echo -e "  die Docker-Images."
echo ""
echo -e "  ${YELLOW}Wird NICHT angefasst:${RESET} das Docker-Netzwerk ${BOLD}${PROXY_NETWORK}${RESET}"
echo -e "  (wird von Nginx Proxy Manager und ggf. weiteren Diensten mitgenutzt)"
echo -e "  sowie eine separat installierte n8n Sandbox."
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo -e "  ${YELLOW}${BOLD}DRY-RUN aktiv:${RESET} Es wird nichts gelöscht, nur angezeigt."
fi
echo ""
echo -e "────────────────────────────────────────────────────────────"

# ── Voraussetzungen prüfen ────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  die "Docker ist nicht installiert – ohne Docker gibt es hier nichts zu entfernen."
fi
if ! docker info &>/dev/null; then
  die "Docker-Daemon läuft nicht. Bitte starten: sudo systemctl start docker"
fi
if docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
else
  die "Docker Compose nicht gefunden."
fi

# ── Installationspfad ermitteln ───────────────────────────────────────────────
if [[ -z "${INSTALL_DIR:-}" ]]; then
  ask INSTALL_DIR "Installationspfad deiner n8n-Installation" "/opt/n8n"
fi

if [[ ! -d "${INSTALL_DIR}" ]]; then
  warn "${INSTALL_DIR} existiert nicht."
  # Trotzdem prüfen, ob verwaiste n8n-Container vorhanden sind (z.B. nach
  # manuell gelöschtem Ordner) – dann wenigstens die aufräumen.
  if docker ps -a --format '{{.Names}}' | grep -qE '^n8n$|-task-runners-1$'; then
    warn "Es existieren aber noch n8n-Container ohne zugehöriges Verzeichnis."
    warn "Diese bitte manuell prüfen/entfernen, z.B.:"
    warn "  docker ps -a | grep n8n"
  else
    success "Nichts zu tun – keine n8n-Installation und keine verwaisten Container gefunden."
  fi
  exit 0
fi

HAS_COMPOSE_FILE=false
[[ -f "${INSTALL_DIR}/docker-compose.yml" ]] && HAS_COMPOSE_FILE=true

# ── Bestandsaufnahme ──────────────────────────────────────────────────────────
echo ""
echo -e "────────────────────────────────────────────────────────────"
echo -e "${BOLD}  Bestandsaufnahme${RESET}"
echo -e "────────────────────────────────────────────────────────────"

CONTAINERS=""
if ${HAS_COMPOSE_FILE}; then
  CONTAINERS=$(cd "${INSTALL_DIR}" && { ${COMPOSE_CMD} ps -a --format '{{.Name}}' 2>/dev/null || true; })
fi
if [[ -z "${CONTAINERS}" ]]; then
  CONTAINERS=$(docker ps -a --format '{{.Names}}' | grep -E '^n8n$|-task-runners-1$' || true)
fi

if [[ -n "${CONTAINERS}" ]]; then
  info "Folgende Container werden entfernt:"
  while IFS= read -r c; do [[ -n "$c" ]] && echo -e "   • ${CYAN}${c}${RESET}"; done <<<"${CONTAINERS}"
else
  warn "Keine laufenden/gestoppten n8n-Container gefunden (evtl. schon entfernt)."
fi

echo ""
info "Folgendes Verzeichnis wird ${BOLD}komplett${RESET}${CYAN} entfernt:${RESET}"
echo -e "   • ${CYAN}${INSTALL_DIR}${RESET}"
[[ -d "${INSTALL_DIR}/n8n_data" ]] && echo -e "     ${YELLOW}└─ n8n_data/${RESET}  – ALLE Workflows, Credentials und Executions"
[[ -f "${INSTALL_DIR}/.env" ]] && echo -e "     ${YELLOW}└─ .env${RESET}       – Encryption Key & Runner Auth Token"
if [[ -d "${INSTALL_DIR}/backups" ]]; then
  backup_count=$(find "${INSTALL_DIR}/backups" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  echo -e "     ${YELLOW}└─ backups/${RESET}   – ${backup_count} vorhandene(s) Backup(s) (inkl. darin gesicherter .env-Kopien)"
fi

echo ""
warn "Das Docker-Netzwerk '${PROXY_NETWORK}' bleibt unangetastet."
if docker ps -a --format '{{.Names}}' | grep -qiE 'sandbox-api|sandbox-certs|sandbox-runner'; then
  warn "Es wurde zusätzlich eine n8n Sandbox Service-Installation auf diesem Host"
  warn "erkannt – die bleibt unangetastet (eigenständiger Stack, eigenes"
  warn "Uninstall-Skript unter n8n/sandbox/uninstall/)."
fi

# Images ermitteln (alle lokal vorhandenen Tags – über mehrere Updates können
# sich mehrere Versionen angesammelt haben, falls die Image-Bereinigung im
# Update-Skript einmal übersprungen wurde).
mapfile -t IMAGE_LINES < <(docker images --format '{{.Repository}}:{{.Tag}}	{{.ID}}' 2>/dev/null | grep -E '^n8nio/n8n:|^n8nio/runners:' || true)

if [[ "${#IMAGE_LINES[@]}" -gt 0 ]]; then
  echo ""
  info "Folgende lokal vorhandenen Images passen zu n8n (werden NUR nach"
  info "expliziter Bestätigung im nächsten Schritt gelöscht):"
  for line in "${IMAGE_LINES[@]}"; do
    name="${line%%$'\t'*}"
    id="${line##*$'\t'}"
    echo -e "   • ${CYAN}${name}${RESET} (${id:0:12})"
  done
fi

# ── Bestätigung ───────────────────────────────────────────────────────────────
echo ""
echo -e "────────────────────────────────────────────────────────────"
if ! ask_yesno "${RED}${BOLD}Wirklich ALLE n8n-Daten unwiderruflich entfernen?${RESET} Diese Aktion kann nicht rückgängig gemacht werden." "n"; then
  warn "Abgebrochen. Es wurde nichts verändert."
  exit 0
fi

REMOVE_IMAGES=false
if [[ "${#IMAGE_LINES[@]}" -gt 0 ]]; then
  if ask_yesno "Zusätzlich die oben gelisteten Images löschen?" "n"; then
    REMOVE_IMAGES=true
  fi
fi

# ── Entfernen ─────────────────────────────────────────────────────────────────
echo ""
echo -e "────────────────────────────────────────────────────────────"
echo -e "${BOLD}  Entfernen${RESET}"
echo -e "────────────────────────────────────────────────────────────"

if ${HAS_COMPOSE_FILE}; then
  info "Stoppe und entferne Container (docker compose down)..."
  (cd "${INSTALL_DIR}" && run ${COMPOSE_CMD} down --remove-orphans)
  success "Container entfernt."
else
  warn "Kein docker-compose.yml in ${INSTALL_DIR} gefunden – entferne verwaiste Container einzeln."
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    run docker rm -f "$c"
  done <<<"${CONTAINERS}"
fi

if ${REMOVE_IMAGES}; then
  info "Entferne Images..."
  for line in "${IMAGE_LINES[@]}"; do
    id="${line##*$'\t'}"
    run docker rmi "${id}" || warn "Image ${id:0:12} konnte nicht entfernt werden (evtl. noch von etwas anderem referenziert)."
  done
  success "Image-Bereinigung abgeschlossen."
else
  info "Images werden nicht entfernt (übersprungen)."
fi

info "Entferne Verzeichnis ${INSTALL_DIR}..."
run rm -rf "${INSTALL_DIR}"
success "Verzeichnis entfernt."

# ── Abschluss ─────────────────────────────────────────────────────────────────
echo ""
echo -e "────────────────────────────────────────────────────────────"
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo -e "${YELLOW}${BOLD}  DRY-RUN beendet – es wurde NICHTS gelöscht.${RESET}"
else
  echo -e "${GREEN}${BOLD}  ✓ n8n vollständig entfernt.${RESET}"
fi
echo -e "────────────────────────────────────────────────────────────"
echo ""
echo -e "  Unangetastet geblieben: Netzwerk ${CYAN}${PROXY_NETWORK}${RESET}, dein Nginx Proxy"
echo -e "  Manager sowie eine ggf. separat installierte n8n Sandbox."
echo ""
echo -e "  Vergiss nicht, den zugehörigen Proxy Host in deinem Nginx Proxy Manager"
echo -e "  zu entfernen, falls du ihn eingerichtet hattest – sonst zeigt er künftig"
echo -e "  ins Leere."
echo ""
echo -e "  Neuinstallation jederzeit möglich mit:"
echo -e "  ${CYAN}bash <(curl -fsSL ${INSTALL_SCRIPT_URL})${RESET}"
echo ""
echo -e "  Mehr Tipps & Tutorials: ${CYAN}https://pc-fee.com/blog${RESET}"
echo -e "  GitHub:                 ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
