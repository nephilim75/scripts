#!/usr/bin/env bash
# =============================================================================
#  n8n Sandbox Uninstall Script – powered by pc-fee.com
#  https://pc-fee.com | https://github.com/nephilim75/scripts
#
#  Entfernt eine mit install-n8n-sandbox.sh installierte n8n-Sandbox
#  rückstandsfrei: Container, das Docker-Volume mit den mTLS-Zertifikaten,
#  optional die Docker-Images, sowie das komplette Installationsverzeichnis
#  (inkl. .env mit allen Secrets).
#
#  Das Docker-Netzwerk "shared_proxy" wird NICHT angefasst – es wird von
#  anderen Diensten (Nginx Proxy Manager, ggf. n8n selbst) mitgenutzt.
#
#  Nutzung als 1-Zeiler:
#    bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/uninstall/uninstall-n8n-sandbox.sh)
#
#  Optionen:
#    --dry-run   Zeigt nur, was entfernt würde, löscht aber nichts.
#
#  Umgebungsvariablen (für unbeaufsichtigten Betrieb):
#    INSTALL_DIR   Installationspfad (Default: /opt/n8n-sandbox)
#    ASSUME_YES=1  Überspringt alle Sicherheitsabfragen (inkl. Image-Löschung)
#
#  Das Script erkennt selbst, ob es als root läuft; falls nicht, wird jeder
#  privilegierte Befehl automatisch mit sudo ausgeführt (siehe
#  install-n8n-sandbox.sh für den Hintergrund dazu).
#
#  Mehr Infos: https://pc-fee.com/blog
#
#  AI Transparency: Dieses Script wurde von Claude (Anthropic) im Auftrag
#  von pc-fee.com erstellt und vor Veroeffentlichung geprueft. Nutzung auf
#  eigene Gefahr. Backups sind Pflicht.
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
readonly INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/install/install-n8n-sandbox.sh"

# ── Optionen ──────────────────────────────────────────────────────────────────
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) ;;
  esac
done
readonly DRY_RUN

# ── Eingabequelle ─────────────────────────────────────────────────────────────
# Siehe install-n8n-sandbox.sh: IMMER vom Terminal lesen, falls vorhanden,
# damit Prompts auch bei 'bash <(curl ...)' / 'curl ... | bash' funktionieren.
if { exec 3<>/dev/tty; } 2>/dev/null; then
  exec 3<&-
  TTY=/dev/tty
  INTERACTIVE=1
else
  TTY=/dev/null
  INTERACTIVE=0
fi
readonly TTY INTERACTIVE

# ── Hilfsfunktionen ───────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[FEHLER]${RESET} $*"; }
die()     { error "$*"; exit 1; }

ask() {
  local var="$1" prompt="$2" default="$3" input=""
  local preset="${!var:-}"
  [[ -n "$preset" ]] && default="$preset"
  echo ""
  if [[ "${INTERACTIVE}" -eq 1 ]]; then
    echo -ne "${BOLD}${prompt}${RESET} [${CYAN}${default}${RESET}]: "
    read -r input <"${TTY}" || true
  else
    echo -e "${BOLD}${prompt}${RESET}: ${CYAN}${default}${RESET} (Vorgabe, kein Terminal)"
  fi
  printf -v "${var}" '%s' "${input:-${default}}"
}

# ask_yesno <prompt> <default: j|n> -> Rueckgabewert via $? (0 = ja)
# Bei ASSUME_YES=1 oder --dry-run wird nie geloescht, ohne dass hier "ja"
# beantwortet wurde – im Dry-Run wird trotzdem "ja" simuliert, damit man
# sieht, was passieren WÜRDE, ohne dass tatsächlich etwas ausgeführt wird
# (die eigentlichen Löschbefehle laufen ohnehin durch run(), siehe unten).
ask_yesno() {
  local prompt="$1" default="${2:-n}" input=""
  local hint="j/N"
  [[ "${default,,}" == "j" ]] && hint="J/n"
  if [[ "${ASSUME_YES:-0}" == "1" ]]; then
    info "ASSUME_YES=1 gesetzt – überspringe Abfrage: ${prompt}"
    return 0
  fi
  echo ""
  if [[ "${INTERACTIVE}" -eq 1 ]]; then
    echo -ne "${BOLD}${prompt}${RESET} [${CYAN}${hint}${RESET}]: "
    read -r input <"${TTY}" || true
  else
    input="${default}"
    echo -e "${BOLD}${prompt}${RESET}: ${CYAN}${default}${RESET} (Vorgabe, kein Terminal)"
  fi
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
cat <<'LOGO'
               __
 _ __  __ ___ / _|___ ___   __ ___ _ __
| '_ \/ _|___|  _/ -_) -_)_/ _/ _ \ '  \
| .__/\__|   |_| \___\___(_)__\___/_|_|_|
|_|
LOGO
echo -e "${RESET}"
echo -e "${BOLD}  n8n Sandbox Service – Deinstallations-Script – powered by pc-fee.com${RESET}"
echo -e "  ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo -e "  Entfernt eine mit ${BOLD}install-n8n-sandbox.sh${RESET} installierte n8n-Sandbox"
echo -e "  rückstandsfrei: Container, das TLS-Volume, optional die Images sowie"
echo -e "  das komplette Installationsverzeichnis (inkl. .env mit den Secrets)."
echo ""
echo -e "  ${YELLOW}Wird NICHT angefasst:${RESET} das Docker-Netzwerk ${BOLD}${PROXY_NETWORK}${RESET}"
echo -e "  (wird von NPM und ggf. weiteren Diensten mitgenutzt) sowie n8n selbst."
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo -e "  ${YELLOW}${BOLD}DRY-RUN aktiv:${RESET} Es wird nichts gelöscht, nur angezeigt."
fi
echo ""
echo -e "────────────────────────────────────────────────────────────"

# ── root/sudo ─────────────────────────────────────────────────────────────────
SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "Bitte als root ausführen oder sudo installieren."
  SUDO="sudo"
fi

cd / 2>/dev/null || die "Konnte nicht nach / wechseln."

# ── Voraussetzungen ───────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  die "Docker ist nicht installiert – ohne Docker gibt es hier nichts zu entfernen."
fi
if ! ${SUDO} docker info &>/dev/null; then
  die "Docker-Daemon läuft nicht. Bitte starten: sudo systemctl start docker"
fi
if ${SUDO} docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="${SUDO} docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="${SUDO} docker-compose"
else
  die "Docker Compose nicht gefunden."
fi

# ── Installationspfad ─────────────────────────────────────────────────────────
ask INSTALL_DIR "Installationspfad der n8n Sandbox" "/opt/n8n-sandbox"

if [[ ! -d "${INSTALL_DIR}" ]]; then
  warn "${INSTALL_DIR} existiert nicht."
  # Trotzdem prüfen, ob verwaiste Sandbox-Container vorhanden sind (z.B. nach
  # manuell gelöschtem Ordner) – dann wenigstens die aufräumen.
  if ${SUDO} docker ps -a --format '{{.Names}}' | grep -qiE 'sandbox-api|sandbox-certs|sandbox-runner'; then
    warn "Es existieren aber noch Sandbox-Container ohne zugehöriges Verzeichnis."
    warn "Diese bitte manuell prüfen/entfernen, z.B.:"
    warn "  ${SUDO} docker ps -a | grep sandbox"
  else
    success "Nichts zu tun – keine Sandbox-Installation und keine verwaisten Container gefunden."
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
  CONTAINERS=$(${SUDO} docker ps -a --format '{{.Names}}' | grep -iE 'sandbox-api|sandbox-certs|sandbox-runner' || true)
fi

if [[ -n "${CONTAINERS}" ]]; then
  info "Folgende Container werden entfernt:"
  while IFS= read -r c; do [[ -n "$c" ]] && echo -e "   • ${CYAN}${c}${RESET}"; done <<<"${CONTAINERS}"
else
  warn "Keine laufenden/gestoppten Sandbox-Container gefunden (evtl. schon entfernt)."
fi

VOLUMES=""
if ${HAS_COMPOSE_FILE}; then
  VOLUMES=$(cd "${INSTALL_DIR}" && { ${COMPOSE_CMD} config --volumes 2>/dev/null || true; })
fi
if [[ -n "${VOLUMES}" ]]; then
  info "Folgendes Docker-Volume wird entfernt (enthält die mTLS-Zertifikate):"
  while IFS= read -r v; do [[ -n "$v" ]] && echo -e "   • ${CYAN}${v}${RESET}"; done <<<"${VOLUMES}"
fi

info "Folgendes Verzeichnis wird entfernt (inkl. .env mit allen Secrets):"
echo -e "   • ${CYAN}${INSTALL_DIR}${RESET}"

echo ""
warn "Das Docker-Netzwerk '${PROXY_NETWORK}' bleibt unangetastet."
warn "n8n selbst (falls auf diesem Host installiert) bleibt unangetastet."

# Images ermitteln (nur die vom Host aus sichtbaren: -api und -runner-dind;
# das -sandbox-Image läuft im inneren Docker-in-Docker des Runners und ist
# vom Host aus gar nicht sichtbar – es verschwindet automatisch mit dem
# Runner-Container).
mapfile -t IMAGE_LINES < <(${SUDO} docker images --format '{{.Repository}}:{{.Tag}}	{{.ID}}' 2>/dev/null | grep -i 'n8n-sandbox-service' || true)

if [[ "${#IMAGE_LINES[@]}" -gt 0 ]]; then
  echo ""
  info "Folgende lokal vorhandenen Images passen zur Sandbox (werden NUR nach"
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
if ! ask_yesno "${RED}${BOLD}Wirklich entfernen?${RESET} Diese Aktion kann nicht rückgängig gemacht werden." "n"; then
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
  info "Stoppe Container und entferne Volume (docker compose down -v)..."
  (cd "${INSTALL_DIR}" && run ${COMPOSE_CMD} down -v --remove-orphans)
  success "Container und Volume entfernt."
else
  warn "Kein docker-compose.yml in ${INSTALL_DIR} gefunden – entferne verwaiste Container einzeln."
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    run ${SUDO} docker rm -f "$c"
  done <<<"${CONTAINERS}"
fi

if ${REMOVE_IMAGES}; then
  info "Entferne Images..."
  for line in "${IMAGE_LINES[@]}"; do
    id="${line##*$'\t'}"
    run ${SUDO} docker rmi "${id}" || warn "Image ${id:0:12} konnte nicht entfernt werden (evtl. noch von etwas anderem referenziert)."
  done
  success "Image-Bereinigung abgeschlossen."
else
  info "Images werden nicht entfernt (übersprungen)."
fi

info "Entferne Verzeichnis ${INSTALL_DIR}..."
run ${SUDO} rm -rf "${INSTALL_DIR}"
success "Verzeichnis entfernt."

# ── Abschluss ─────────────────────────────────────────────────────────────────
echo ""
echo -e "────────────────────────────────────────────────────────────"
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo -e "${YELLOW}${BOLD}  DRY-RUN beendet – es wurde NICHTS gelöscht.${RESET}"
else
  echo -e "${GREEN}${BOLD}  ✓ n8n Sandbox vollständig entfernt.${RESET}"
fi
echo -e "────────────────────────────────────────────────────────────"
echo ""
echo -e "  Unangetastet geblieben: Netzwerk ${CYAN}${PROXY_NETWORK}${RESET}, dein Nginx Proxy"
echo -e "  Manager sowie eine ggf. auf diesem Host laufende n8n-Installation."
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
