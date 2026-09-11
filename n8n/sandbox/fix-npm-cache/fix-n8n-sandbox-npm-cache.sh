#!/usr/bin/env bash
# =============================================================================
#  n8n Sandbox – npm-Cache-Fix – powered by pc-fee.com
#  https://pc-fee.com | https://github.com/nephilim75/scripts
#
#  Behebt einen Fehler im offiziellen Sandbox-Image von n8n, durch den die
#  Sandbox-Einrichtung fehlschlaegt:
#
#      Sandbox workspace setup failed during install-dependencies:
#      npm error code ETARGET
#      No matching version found for @n8n/workflow-sdk@<version>
#
#  Ursache: Im Image ist ein npm-Cache vom Build-Zeitpunkt eingebacken. Der
#  Setup-Lauf installiert mit "--prefer-offline" und loest die Version deshalb
#  gegen diesen Cache auf statt gegen die Registry. Jede SDK-Version, die nach
#  dem Build-Datum des Images veroeffentlicht wurde, ist damit unsichtbar.
#  Verlangt n8n eine solche Version, schlaegt die Einrichtung fehl.
#  Details: https://github.com/n8n-io/n8n-sandbox-service/issues/178
#
#  Dieses Script untersucht zuerst, ob das Problem ueberhaupt vorliegt, und
#  wird nur dann aktiv. Der Fix baut das Sandbox-Image lokal neu – auf Basis
#  des offiziellen Images, mit geleertem npm-Cache – und legt es unter
#  demselben Namen ab, den der Runner verwendet.
#
#  WICHTIG: Der Fix ist lokal und ueberlebt kein Update des Sandbox-Stacks.
#  Nach jedem "docker compose pull" ist wieder das Originalimage aktiv – dann
#  dieses Script erneut ausfuehren.
#
#  Nutzung als 1-Zeiler:
#    bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/fix-npm-cache/fix-n8n-sandbox-npm-cache.sh)
#
#  Optionen:
#    --check-only    Nur untersuchen, nie etwas veraendern
#    --dry-run       Alle Schritte anzeigen, nichts ausfuehren
#    --force         Fix auch anwenden, wenn keine Auffaelligkeit gefunden wurde
#    -h | --help     Diese Hilfe anzeigen
#
#  Vorbelegbare Umgebungsvariablen:
#    INSTALL_DIR     Installationsverzeichnis (Default: /opt/n8n-sandbox)
#    ASSUME_YES=1    Rueckfragen ueberspringen (fuer Automatisierung)
#
#  Das Script erkennt selbst, ob es als root laeuft. Falls nicht, wird jeder
#  privilegierte Befehl automatisch mit sudo ausgefuehrt – kein "sudo" vor dem
#  Einzeiler noetig (und wegen sudo's Filedescriptor-Handling bei
#  Process-Substitution auch nicht empfehlenswert).
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
readonly DEFAULT_INSTALL_DIR="/opt/n8n-sandbox"
readonly RUNNER_SERVICE="sandbox-runner-1"
readonly SDK_PACKAGE="@n8n/workflow-sdk"
readonly SANDBOX_IMAGE_FALLBACK="ghcr.io/n8n-io/n8n-sandbox-service-sandbox"
readonly FIX_LABEL="com.pc-fee.n8n-sandbox.npm-cache-fix"
readonly UPSTREAM_ISSUE="https://github.com/n8n-io/n8n-sandbox-service/issues/178"
readonly INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/install/install-n8n-sandbox.sh"

# ── Flags ─────────────────────────────────────────────────────────────────────
DRY_RUN=0
CHECK_ONLY=0
FORCE=0

usage() {
  sed -n '2,45p' "$0" | sed 's/^#\{1,\} \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=1 ;;
    --check-only) CHECK_ONLY=1 ;;
    --force)      FORCE=1 ;;
    -h|--help)    usage ;;
    *)            echo "Unbekannte Option: $1 (siehe --help)" >&2; exit 1 ;;
  esac
  shift
done
readonly DRY_RUN CHECK_ONLY FORCE

# run <befehl...> – fuehrt den Befehl aus oder zeigt ihn nur an (--dry-run)
run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${RESET} $*"
  else
    "$@"
  fi
}

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

# ask <variable> <prompt> <default>
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
ask_yesno() {
  local prompt="$1" default="${2:-j}" input=""
  local hint="J/n"
  [[ "${default,,}" == "n" ]] && hint="j/N"
  if [[ "${ASSUME_YES:-0}" == "1" ]]; then
    echo ""
    echo -e "${BOLD}${prompt}${RESET}: ${CYAN}ja${RESET} (ASSUME_YES=1)"
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

# max_version – liest Versionen von stdin und gibt die hoechste zurueck
max_version() {
  grep -o '"[0-9][^"]*"' | tr -d '"' | sort -V | tail -n1
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
echo -e "${BOLD}  n8n Sandbox – npm-Cache-Fix – powered by pc-fee.com${RESET}"
echo -e "  ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo -e "  Dieses Script prüft, ob das Sandbox-Image einen ${BOLD}veralteten"
echo -e "  npm-Cache${RESET} mitbringt, der die Sandbox-Einrichtung mit"
echo -e "  ${BOLD}ETARGET${RESET} scheitern lässt – und behebt das nur, wenn es"
echo -e "  tatsächlich vorliegt."
echo ""
echo -e "  Upstream-Bug: ${CYAN}${UPSTREAM_ISSUE}${RESET}"
[[ "${DRY_RUN}"    -eq 1 ]] && echo -e "  ${YELLOW}Modus: DRY-RUN – es wird nichts verändert.${RESET}"
[[ "${CHECK_ONLY}" -eq 1 ]] && echo -e "  ${YELLOW}Modus: CHECK-ONLY – es wird nur untersucht.${RESET}"
echo ""
echo -e "────────────────────────────────────────────────────────────"

# ── root/sudo ─────────────────────────────────────────────────────────────────
SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "Bitte als root ausführen oder sudo installieren."
  SUDO="sudo"
fi

if [[ -n "${SUDO}" ]]; then
  DOCKER=(sudo docker)
else
  DOCKER=(docker)
fi

cd / 2>/dev/null || die "Konnte nicht nach / wechseln."

# ── Voraussetzungen ───────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Voraussetzungen${RESET}"
echo -e "────────────────────────────────────────────────────────────"

command -v docker &>/dev/null || die "Docker ist nicht installiert."
success "Docker gefunden: $(docker --version 2>&1)"

"${DOCKER[@]}" info &>/dev/null || die "Docker-Daemon läuft nicht. Bitte starten: sudo systemctl start docker"
success "Docker-Daemon läuft."

ask INSTALL_DIR "Installationsverzeichnis der Sandbox" "${DEFAULT_INSTALL_DIR}"
[[ -d "${INSTALL_DIR}" ]] || die "Verzeichnis '${INSTALL_DIR}' existiert nicht.\n\n       Keine Sandbox-Installation gefunden. Installation mit:\n       bash <(curl -fsSL ${INSTALL_SCRIPT_URL})"
success "Installationsverzeichnis: ${INSTALL_DIR}"

# ── Runner-Container finden ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Bestandsaufnahme${RESET}"
echo -e "────────────────────────────────────────────────────────────"

RUNNER=""
if [[ -f "${INSTALL_DIR}/docker-compose.yml" ]]; then
  RUNNER="$("${DOCKER[@]}" compose -f "${INSTALL_DIR}/docker-compose.yml" \
            --project-directory "${INSTALL_DIR}" ps -q "${RUNNER_SERVICE}" 2>/dev/null | head -n1 || true)"
fi
if [[ -z "${RUNNER}" ]]; then
  RUNNER="$("${DOCKER[@]}" ps --format '{{.Names}}' 2>/dev/null | grep -m1 -- "${RUNNER_SERVICE}" || true)"
fi
[[ -n "${RUNNER}" ]] || die "Runner-Container (${RUNNER_SERVICE}) läuft nicht.\n\n       Bitte den Sandbox-Stack starten und das Script erneut ausführen:\n       cd ${INSTALL_DIR} && ${SUDO} docker compose up -d"
success "Runner-Container: ${RUNNER}"

# Inneren Docker-Daemon (Docker-in-Docker) erreichbar?
"${DOCKER[@]}" exec "${RUNNER}" docker version --format '{{.Server.Version}}' &>/dev/null \
  || die "Der innere Docker-Daemon im Runner antwortet nicht.\n\n       Der Runner ist vermutlich noch am Hochfahren – bitte eine\n       Minute warten und das Script erneut ausführen."
success "Innerer Docker-Daemon erreichbar."

# ── Sandbox-Image ermitteln ───────────────────────────────────────────────────
SANDBOX_IMAGE="$("${DOCKER[@]}" inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "${RUNNER}" 2>/dev/null \
                 | grep -m1 '^SANDBOX_RUNNER_DOCKER_SANDBOX_IMAGE=' | cut -d= -f2- || true)"

if [[ -z "${SANDBOX_IMAGE}" ]]; then
  TAG=""
  if [[ -r "${INSTALL_DIR}/.env" ]]; then
    TAG="$("${DOCKER[@]}" run --rm -v "${INSTALL_DIR}/.env:/env:ro" busybox \
           sh -c "grep -m1 '^SANDBOX_IMAGE_TAG=' /env | cut -d= -f2-" 2>/dev/null || true)"
  fi
  [[ -n "${TAG}" ]] || TAG="latest"
  SANDBOX_IMAGE="${SANDBOX_IMAGE_FALLBACK}:${TAG}"
  warn "Image-Name nicht aus dem Runner lesbar – nutze Rückfall: ${SANDBOX_IMAGE}"
fi
readonly SANDBOX_IMAGE
success "Sandbox-Image: ${SANDBOX_IMAGE}"

"${DOCKER[@]}" exec "${RUNNER}" docker image inspect "${SANDBOX_IMAGE}" &>/dev/null \
  || die "Das Image '${SANDBOX_IMAGE}' liegt nicht im inneren Docker des Runners.\n\n       Bitte zuerst eine Sandbox starten (oder den Stack neu starten),\n       damit das Image gezogen wird."

# Bereits gefixt?
ALREADY="$("${DOCKER[@]}" exec "${RUNNER}" docker image inspect \
           -f "{{index .Config.Labels \"${FIX_LABEL}\"}}" "${SANDBOX_IMAGE}" 2>/dev/null || true)"
if [[ -n "${ALREADY}" && "${ALREADY}" != "<no value>" ]]; then
  info "Dieses Image trägt bereits den Fix (angewendet: ${ALREADY})."
else
  info "Dieses Image trägt den Fix noch nicht."
fi

# ── Untersuchung ──────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Untersuchung${RESET}"
echo -e "────────────────────────────────────────────────────────────"
info "Vergleiche, welche ${SDK_PACKAGE}-Versionen das Image online bzw."
info "aus seinem eingebauten npm-Cache sieht..."

sdk_versions() {
  # $1 = --prefer-online | --prefer-offline
  "${DOCKER[@]}" exec "${RUNNER}" docker run --rm -u user "${SANDBOX_IMAGE}" \
    npm view "$1" "${SDK_PACKAGE}" versions --json 2>/dev/null || true
}

ONLINE_MAX="$(sdk_versions --prefer-online | max_version || true)"
[[ -n "${ONLINE_MAX}" ]] || die "Konnte die Versionsliste nicht von der Registry laden.\n\n       Prüfe die Netzwerkverbindung des Runners:\n       ${SUDO} docker exec ${RUNNER} wget -qO- https://registry.npmjs.org/ >/dev/null && echo ok"
success "Neueste Version laut Registry:     ${ONLINE_MAX}"

OFFLINE_MAX="$(sdk_versions --prefer-offline | max_version || true)"
if [[ -z "${OFFLINE_MAX}" ]]; then
  info "Aus dem Cache ist keine Versionsliste lesbar – kein veralteter Cache."
  OFFLINE_MAX="${ONLINE_MAX}"
else
  success "Neueste Version laut Image-Cache:  ${OFFLINE_MAX}"
fi

PROBLEM=0
if [[ "${OFFLINE_MAX}" != "${ONLINE_MAX}" ]]; then
  PROBLEM=1
fi

echo ""
if [[ "${PROBLEM}" -eq 1 ]]; then
  error "Problem bestätigt: Der eingebaute npm-Cache ist veraltet."
  echo ""
  echo -e "  Das Image kennt höchstens ${BOLD}${OFFLINE_MAX}${RESET}, veröffentlicht ist"
  echo -e "  bereits ${BOLD}${ONLINE_MAX}${RESET}. Verlangt n8n eine neuere Version als"
  echo -e "  ${BOLD}${OFFLINE_MAX}${RESET}, scheitert die Sandbox-Einrichtung mit ETARGET."
else
  success "Kein Problem gefunden: Der Cache im Image ist aktuell (${OFFLINE_MAX})."
  echo ""
  echo -e "  Scheitert deine Sandbox trotzdem, liegt die Ursache woanders."
  echo -e "  Der komplette npm-Fehler steht im Log des Sandbox-Containers:"
  echo -e "  ${CYAN}${SUDO} docker exec ${RUNNER} docker ps${RESET}"
fi

if [[ "${CHECK_ONLY}" -eq 1 ]]; then
  echo ""
  info "CHECK-ONLY: Es wurde nichts verändert."
  exit 0
fi

if [[ "${PROBLEM}" -eq 0 && "${FORCE}" -eq 0 ]]; then
  echo ""
  info "Es gibt nichts zu tun. (Mit --force ließe sich der Fix trotzdem anwenden.)"
  exit 0
fi

[[ "${PROBLEM}" -eq 0 ]] && warn "--force: Der Fix wird trotz unauffälliger Prüfung angewendet."

# ── Fix ───────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Fix${RESET}"
echo -e "────────────────────────────────────────────────────────────"
echo ""
echo -e "  Der Fix baut ${BOLD}${SANDBOX_IMAGE}${RESET} lokal neu:"
echo -e "   • Basis ist das unveränderte offizielle Image (wird frisch gezogen)"
echo -e "   • darin wird der npm-Cache geleert"
echo -e "   • das Ergebnis ersetzt den Image-Namen im inneren Docker des Runners"
echo ""
echo -e "  ${YELLOW}Nicht angetastet werden:${RESET} n8n selbst, deine Workflows,"
echo -e "  Credentials, das shared_proxy-Netzwerk und der Sandbox-Stack."
echo ""
echo -e "  ${YELLOW}Der Fix ist lokal${RESET} und geht beim nächsten Update des"
echo -e "  Sandbox-Stacks verloren – danach dieses Script erneut ausführen."

if ! ask_yesno "Fix jetzt anwenden?" "j"; then
  echo ""
  info "Abgebrochen – es wurde nichts verändert."
  exit 0
fi

echo ""
info "Ziehe das offizielle Basis-Image frisch (macht den Lauf wiederholbar)..."
if ! run "${DOCKER[@]}" exec "${RUNNER}" docker pull "${SANDBOX_IMAGE}"; then
  warn "Pull fehlgeschlagen – es wird das lokal vorhandene Image als Basis genutzt."
fi

info "Baue das Image mit geleertem npm-Cache..."
FIX_STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo -e "  ${YELLOW}[DRY-RUN]${RESET} ${SUDO} docker exec -i ${RUNNER} docker build -t ${SANDBOX_IMAGE} - <<EOF"
  echo -e "  ${YELLOW}[DRY-RUN]${RESET}   FROM ${SANDBOX_IMAGE}"
  echo -e "  ${YELLOW}[DRY-RUN]${RESET}   USER user"
  echo -e "  ${YELLOW}[DRY-RUN]${RESET}   RUN npm cache clean --force"
  echo -e "  ${YELLOW}[DRY-RUN]${RESET}   LABEL ${FIX_LABEL}=\"${FIX_STAMP}\""
  echo -e "  ${YELLOW}[DRY-RUN]${RESET} EOF"
else
  "${DOCKER[@]}" exec -i "${RUNNER}" docker build -t "${SANDBOX_IMAGE}" - <<EOF || die "Der Image-Build ist fehlgeschlagen."
FROM ${SANDBOX_IMAGE}
USER user
RUN npm cache clean --force
LABEL ${FIX_LABEL}="${FIX_STAMP}"
EOF
  success "Image gebaut."
fi

# ── Gegenprobe ────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Gegenprobe${RESET}"
echo -e "────────────────────────────────────────────────────────────"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  info "DRY-RUN: Gegenprobe übersprungen."
else
  info "Prüfe erneut, welche Version das Image aus seinem Cache sieht..."
  VERIFY_MAX="$(sdk_versions --prefer-offline | max_version || true)"
  if [[ -z "${VERIFY_MAX}" || "${VERIFY_MAX}" == "${ONLINE_MAX}" ]]; then
    success "Der Cache blockiert nicht mehr – ${ONLINE_MAX} ist jetzt auflösbar."
  else
    die "Die Gegenprobe schlug fehl: Image sieht weiterhin nur ${VERIFY_MAX}.\n\n       Bitte den Runner neu starten und das Script erneut ausführen:\n       cd ${INSTALL_DIR} && ${SUDO} docker compose restart ${RUNNER_SERVICE}"
  fi
fi

# ── Abschluss ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Fertig${RESET}"
echo -e "────────────────────────────────────────────────────────────"
echo ""
echo -e "  ${GREEN}Der Fix ist aktiv.${RESET} Neue Sandboxen starten jetzt aus dem"
echo -e "  bereinigten Image."
echo ""
echo -e "  ${BOLD}Zu beachten:${RESET}"
echo -e "   • Bereits laufende Sandbox-Container nutzen noch das alte Image."
echo -e "     Sie verschwinden von selbst – oder sofort mit einem Neustart:"
echo -e "     ${CYAN}cd ${INSTALL_DIR} && ${SUDO} docker compose restart ${RUNNER_SERVICE}${RESET}"
echo -e "   • Im n8n-Assistenten eine ${BOLD}neue Unterhaltung${RESET} öffnen – alte"
echo -e "     Unterhaltungen halten den Fehlerzustand fest."
echo -e "   • Nach jedem Update des Sandbox-Stacks ist wieder das Originalimage"
echo -e "     aktiv. Dann dieses Script erneut ausführen."
echo -e "   • Das ursprüngliche Image bleibt namenlos auf der Platte liegen und"
echo -e "     wird bei einem ${CYAN}docker image prune${RESET} entfernt – das ist unkritisch."
echo ""
echo -e "  Sobald n8n den Bug behebt, wird dieses Script überflüssig:"
echo -e "  ${CYAN}${UPSTREAM_ISSUE}${RESET}"
echo ""
