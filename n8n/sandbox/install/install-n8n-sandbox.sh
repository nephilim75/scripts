#!/usr/bin/env bash
# =============================================================================
#  n8n Sandbox Install Script – powered by pc-fee.com
#  https://pc-fee.com | https://github.com/nephilim75/scripts
#
#  Installiert den n8n Sandbox Service (isolierte Code-Ausführung, siehe
#  https://github.com/n8n-io/n8n-sandbox-service) via Docker Compose im
#  "shared_proxy"-Netzwerk – hinter einem Nginx Proxy Manager (NPM), ohne
#  öffentlich gebundene Ports. Der gesamte Traffic läuft ausschließlich
#  über den NPM.
#
#  Funktioniert unabhängig davon, ob auf diesem Host bereits n8n selbst
#  läuft oder nicht – die Sandbox ist ein eigenständiger Stack.
#
#  Voraussetzungen:
#    - Docker + Docker Compose Plugin sind installiert und laufen
#    - Das Docker-Netzwerk "shared_proxy" existiert (oder wird erstellt)
#    - Nginx Proxy Manager läuft im shared_proxy-Netzwerk
#
#  Nutzung als 1-Zeiler:
#    bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/install/install-n8n-sandbox.sh)
#
#  Das Script erkennt selbst, ob es als root läuft. Falls nicht, wird jeder
#  privilegierte Befehl automatisch mit sudo ausgeführt – kein "sudo" vor
#  dem Einzeiler nötig (und wegen sudo's Filedescriptor-Handling bei
#  Process-Substitution auch nicht empfehlenswert: "sudo bash <(curl ...)"
#  schlägt auf den meisten Systemen mit "/dev/fd/NN: No such file or
#  directory" fehl, weil sudo standardmäßig alle Filedescriptoren ab 3
#  schließt, bevor es den Befehl ausführt).
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
readonly SANDBOX_GUIDE="https://github.com/n8n-io/n8n-sandbox-service"
readonly NPM_GUIDE="https://pc-fee.com/2026/05/03/nginx-proxy-manager/"
readonly DOCKER_COMPOSE_GUIDE="https://pc-fee.com/2026/05/03/docker-compose/"

# ── Eingabequelle ─────────────────────────────────────────────────────────────
# Wird das Script per 'bash <(curl ...)' oder 'curl ... | bash' gestartet,
# kann stdin belegt sein (beim Pipe-Aufruf sogar vom Script-Text selbst).
# Deshalb IMMER vom Terminal lesen, wenn eins vorhanden ist.
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
# Nutzt einen evtl. bereits per Umgebungsvariable gesetzten Wert als Default,
# damit das Script auch unbeaufsichtigt (z.B. in Automationen) laufen kann:
#   SANDBOX_DOMAIN=sandbox.example.com bash <(curl ...)
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

# ask_nodefault <variable> <prompt>
ask_nodefault() {
  local var="$1" prompt="$2" input=""
  local preset="${!var:-}"
  if [[ -n "$preset" ]]; then
    printf -v "${var}" '%s' "${preset}"
    return 0
  fi
  while [[ -z "$input" ]]; do
    echo ""
    echo -ne "${BOLD}${prompt}${RESET}: "
    if [[ "${INTERACTIVE}" -eq 1 ]]; then
      read -r input <"${TTY}" || true
    else
      die "Keine Eingabe moeglich (kein Terminal) und '${var}' wurde nicht per Umgebungsvariable gesetzt."
    fi
    [[ -z "$input" ]] && warn "Eingabe darf nicht leer sein."
  done
  printf -v "${var}" '%s' "${input}"
}

# ask_yesno <prompt> <default: j|n> -> Rueckgabewert via $? (0 = ja)
ask_yesno() {
  local prompt="$1" default="${2:-j}" input=""
  local hint="J/n"
  [[ "${default,,}" == "n" ]] && hint="j/N"
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

generate_token() {
  # Erzeugt einen sicheren 48-Zeichen alphanumerischen Token (bewusst ohne
  # Sonderzeichen, damit er in .env / YAML nie Quoting-Probleme verursacht).
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48 || true
  echo ""
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
echo -e "${BOLD}  n8n Sandbox Service – Installations-Script – powered by pc-fee.com${RESET}"
echo -e "  ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo -e "  Dieses Script installiert den ${BOLD}n8n Sandbox Service${RESET} (isolierte"
echo -e "  Code-Ausführung, ${CYAN}${SANDBOX_GUIDE}${RESET}) via Docker"
echo -e "  Compose – hinter einem Nginx Proxy Manager, ohne öffentlich"
echo -e "  gebundene Ports. Der Traffic läuft ausschließlich über den NPM."
echo ""
echo -e "  ${YELLOW}Voraussetzungen:${RESET}"
echo -e "   • Docker + Docker Compose Plugin sind installiert und laufen"
echo -e "   • Das Docker-Netzwerk ${BOLD}shared_proxy${RESET} existiert (oder wird erstellt)"
echo -e "   • Nginx Proxy Manager läuft im shared_proxy-Netzwerk"
echo -e "   • Ob auf diesem Host bereits n8n läuft, ist egal – beides ist ok"
echo ""
echo -e "────────────────────────────────────────────────────────────"

# ── root/sudo ─────────────────────────────────────────────────────────────────
# Läuft bereits als root: SUDO bleibt leer. Sonst wird jeder privilegierte
# Befehl im weiteren Verlauf mit ${SUDO} ausgeführt statt das ganze Script
# unter 'sudo' zu erzwingen – so funktioniert auch 'bash <(curl -fsSL ...)'
# ohne vorangestelltes sudo (siehe Kommentar am Scriptanfang).
SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "Bitte als root ausführen oder sudo installieren."
  SUDO="sudo"
fi

# Unbedingt in ein garantiert existierendes Verzeichnis wechseln, siehe
# ausführlicher Kommentar dazu im NPM-Install-Script dieses Repos.
cd / 2>/dev/null || die "Konnte nicht nach / wechseln."

# ── Voraussetzungen prüfen ────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Voraussetzungen${RESET}"
echo -e "────────────────────────────────────────────────────────────"
info "Prüfe Voraussetzungen..."

# Docker vorhanden?
if ! command -v docker &>/dev/null; then
  die "Docker ist nicht installiert.\n\n       📖 Anleitung auf pc-fee.com:\n       ${DOCKER_COMPOSE_GUIDE}\n\n       Danach dieses Script erneut starten."
fi
success "Docker gefunden: $(docker --version 2>&1)"

# Docker-Daemon läuft?
if ! ${SUDO} docker info &>/dev/null; then
  die "Docker-Daemon läuft nicht. Bitte starten: sudo systemctl start docker"
fi
success "Docker-Daemon läuft."

# Docker Compose vorhanden? (Plugin oder standalone)
if ${SUDO} docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="${SUDO} docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="${SUDO} docker-compose"
else
  die "Docker Compose nicht gefunden.\n\n       📖 Anleitung auf pc-fee.com:\n       ${DOCKER_COMPOSE_GUIDE}"
fi
success "Docker Compose gefunden: $($COMPOSE_CMD version --short 2>/dev/null || $COMPOSE_CMD version)"

# NPM läuft?
if ! ${SUDO} docker ps --format '{{.Image}}' | grep -qi 'nginx-proxy-manager'; then
  die "Nginx Proxy Manager läuft nicht.\n\n       Dieser Stack bindet bewusst keine öffentlichen Ports – der\n       gesamte Traffic muss über einen laufenden NPM geroutet werden.\n\n       📖 Anleitung auf pc-fee.com:\n       ${NPM_GUIDE}\n\n       Bitte zuerst NPM installieren und starten, danach dieses Script erneut ausführen."
fi
success "Nginx Proxy Manager läuft."

# shared_proxy-Netzwerk vorhanden?
if ! ${SUDO} docker network inspect "${PROXY_NETWORK}" &>/dev/null; then
  echo ""
  warn "Das Docker-Netzwerk '${PROXY_NETWORK}' existiert nicht."
  echo -e "  Soll es jetzt erstellt werden? (Nginx Proxy Manager muss ebenfalls"
  echo -e "  in dieses Netzwerk eingebunden sein, sonst kann er die Sandbox"
  echo -e "  nicht erreichen.)"
  if ask_yesno "Netzwerk '${PROXY_NETWORK}' jetzt erstellen?" "j"; then
    ${SUDO} docker network create "${PROXY_NETWORK}"
    success "Netzwerk '${PROXY_NETWORK}' erstellt."
    warn "Vergiss nicht, deinen Nginx Proxy Manager ebenfalls in dieses Netzwerk einzubinden!"
  else
    die "Netzwerk '${PROXY_NETWORK}' fehlt. Installation abgebrochen."
  fi
else
  success "Docker-Netzwerk '${PROXY_NETWORK}' gefunden."
fi

# Informativ: läuft auf diesem Host bereits n8n? (kein Blocker – die Sandbox
# ist ein eigenständiger Stack und läuft unabhängig von n8n auf demselben
# oder einem anderen Host.)
if ${SUDO} docker ps -a --format '{{.Names}} {{.Image}}' | grep -qiE '(^|[^a-z0-9])n8n([^a-z0-9]|$)|n8nio/n8n'; then
  info "n8n wurde auf diesem Host erkannt – kein Problem, die Sandbox läuft unabhängig davon."
else
  info "Kein n8n auf diesem Host gefunden – auch kein Problem. Die Sandbox kann z.B."
  info "für eine n8n-Instanz auf einem anderen Host betrieben werden, die über den"
  info "Nginx Proxy Manager erreichbar ist."
fi

# ── Bestehende Sandbox-Installation prüfen ────────────────────────────────────
# Ziel: Niemals „drüber installieren“ – ein Re-Bootstrap der mTLS-Zertifikate
# und neu generierte Secrets würden eine laufende Installation zerstören.
EXISTING_INSTALL=false
EXISTING_REASON=""

if ${SUDO} docker ps -a --format '{{.Names}} {{.Image}}' | grep -qiE 'sandbox-api|sandbox-certs|sandbox-runner|n8n-sandbox-service'; then
  EXISTING_INSTALL=true
  EXISTING_REASON="Container der Sandbox existiert bereits (sandbox-api/-certs/-runner)"
fi

echo ""
echo -e "────────────────────────────────────────────────────────────"
echo -e "${BOLD}  Konfiguration${RESET}"
echo -e "────────────────────────────────────────────────────────────"

# Installationspfad (wird auch für die Prüfung auf bestehende Dateien benötigt)
ask INSTALL_DIR "Installationspfad" "/opt/n8n-sandbox"

if [[ -f "${INSTALL_DIR}/.env" ]] || [[ -f "${INSTALL_DIR}/docker-compose.yml" ]]; then
  EXISTING_INSTALL=true
  EXISTING_REASON="${EXISTING_REASON:+${EXISTING_REASON}; }${INSTALL_DIR} enthält bereits .env/docker-compose.yml"
fi

if [[ "${EXISTING_INSTALL}" == "true" ]]; then
  echo ""
  echo -e "────────────────────────────────────────────────────────────"
  warn "Bestehende n8n-Sandbox-Installation erkannt (${EXISTING_REASON})."
  echo ""
  echo -e "  ${RED}${BOLD}Abbruch:${RESET} Dieses Install-Script installiert NICHT über eine"
  echo -e "  bestehende Installation. Grund: Neu generierte API-Keys/Tokens und ein"
  echo -e "  Re-Bootstrap der mTLS-Zertifikate würden bereits registrierte Runner"
  echo -e "  und laufende Sandboxes unbrauchbar machen."
  echo ""
  echo -e "  ${BOLD}Was du jetzt tun kannst:${RESET}"
  echo -e "   1) ${BOLD}Update/Restart${RESET} der bestehenden Installation:"
  echo -e "      - cd ${INSTALL_DIR} && ${COMPOSE_CMD} pull && ${COMPOSE_CMD} up -d"
  echo -e ""
  echo -e "   2) ${BOLD}Komplett neu installieren${RESET} (Secrets/Zertifikate gehen verloren):"
  echo -e "      - cd ${INSTALL_DIR} && ${COMPOSE_CMD} down -v"
  echo -e "      - ${SUDO} rm -rf ${INSTALL_DIR}"
  echo -e "      - Script erneut starten"
  echo ""
  die "Installation abgebrochen, um eine laufende Installation nicht zu zerstören."
fi

# Domain (nur zur Doku/für die NPM-Einrichtung – wird von keinem Container
# direkt ausgewertet, da das Routing komplett beim NPM liegt)
ask_nodefault SANDBOX_DOMAIN "Domain für den Sandbox-API-Zugriff über NPM (z.B. sandbox.meinedomain.de)"

# Image-Tag (Default: latest, wie im offiziellen Setup)
ask SANDBOX_IMAGE_TAG "Image-Tag für die Sandbox-Images" "latest"

# Secrets werden immer automatisch generiert – kein User-Input nötig, damit
# nie ein schwaches/wiederverwendetes Secret in der Sandbox landet.
SANDBOX_API_KEYS=$(generate_token)
SANDBOX_API_RUNNER_REGISTRATION_TOKEN=$(generate_token)
SANDBOX_API_RUNNER_API_KEY=$(generate_token)

echo ""
echo -e "────────────────────────────────────────────────────────────"
echo -e "${BOLD}  Zusammenfassung${RESET}"
echo -e "────────────────────────────────────────────────────────────"
echo -e "  Installationspfad: ${CYAN}${INSTALL_DIR}${RESET}"
echo -e "  Domain (für NPM):  ${CYAN}${SANDBOX_DOMAIN}${RESET}"
echo -e "  Image-Tag:         ${CYAN}${SANDBOX_IMAGE_TAG}${RESET}"
echo -e "  Netzwerk:          ${CYAN}${PROXY_NETWORK}${RESET} (kein Port wird öffentlich gebunden)"
echo -e "  Runner:            ${CYAN}1${RESET} (sandbox-runner-1, privileged Docker-in-Docker)"
echo -e "  API-Keys/Tokens:   ${CYAN}[automatisch generiert]${RESET}"
echo ""

if ! ask_yesno "Alles korrekt? Installation starten?" "j"; then
  warn "Installation abgebrochen. Starte das Script erneut."
  exit 0
fi

# ── Installation ──────────────────────────────────────────────────────────────
echo ""
echo -e "────────────────────────────────────────────────────────────"
echo -e "${BOLD}  Installation${RESET}"
echo -e "────────────────────────────────────────────────────────────"

info "Erstelle Verzeichnis ${INSTALL_DIR}..."
${SUDO} mkdir -p "${INSTALL_DIR}"
success "Verzeichnis erstellt."

info "Schreibe .env..."
${SUDO} tee "${INSTALL_DIR}/.env" >/dev/null <<EOF
# n8n Sandbox Service – Umgebungsvariablen – generiert von pc-fee.com Install-Script
# Mehr Infos: https://pc-fee.com/blog
# Env-Referenz: https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/configuration.md
#
# ACHTUNG: Diese Datei enthält Secrets. Nicht committen! (Berechtigungen: 600)
#
# Domain, unter der die Sandbox-API über den Nginx Proxy Manager erreichbar
# ist (nur zur Doku, wird von keinem Container ausgewertet):
# SANDBOX_DOMAIN=${SANDBOX_DOMAIN}

SANDBOX_IMAGE_TAG=${SANDBOX_IMAGE_TAG}
SANDBOX_API_KEYS=${SANDBOX_API_KEYS}
SANDBOX_API_RUNNER_REGISTRATION_TOKEN=${SANDBOX_API_RUNNER_REGISTRATION_TOKEN}
SANDBOX_API_RUNNER_API_KEY=${SANDBOX_API_RUNNER_API_KEY}
EOF
${SUDO} chmod 600 "${INSTALL_DIR}/.env"
success ".env geschrieben (Berechtigungen: 600)."

info "Schreibe docker-compose.yml..."
${SUDO} tee "${INSTALL_DIR}/docker-compose.yml" >/dev/null <<'EOF'
# docker-compose.yml – generiert von pc-fee.com Install-Script
# n8n Sandbox Service hinter Nginx Proxy Manager, keine öffentlichen Ports
# Referenz: https://github.com/n8n-io/n8n-sandbox-service
# Mehr Infos: https://pc-fee.com/blog
#
# Hinweis: restart: unless-stopped wurde bewusst ergänzt (Best Practice,
# siehe offizielles Compose-Beispiel des n8n-sandbox-service-Repos), damit
# der Stack einen Host-Reboot übersteht.

volumes:
  sandbox-tls:

services:
  sandbox-certs:
    image: ghcr.io/n8n-io/n8n-sandbox-service-api:${SANDBOX_IMAGE_TAG}
    user: '0:0'
    entrypoint: ['sh', '-c']
    command:
      - >
        bootstrap-mtls.sh --out-dir /tls --api-san sandbox-api
        --control-san-prefix sandbox-runner &&
        chown -R sandbox-api:sandbox-api /tls/api
    environment:
      NUM_RUNNERS: '1'
    volumes:
      - sandbox-tls:/tls
    networks:
      - shared_proxy

  sandbox-api:
    image: ghcr.io/n8n-io/n8n-sandbox-service-api:${SANDBOX_IMAGE_TAG}
    restart: unless-stopped
    depends_on:
      sandbox-certs:
        condition: service_completed_successfully
    environment:
      SANDBOX_API_KEYS: ${SANDBOX_API_KEYS}
      SANDBOX_API_RUNNER_REGISTRATION_TOKEN: ${SANDBOX_API_RUNNER_REGISTRATION_TOKEN}
      SANDBOX_API_RUNNER_API_KEY: ${SANDBOX_API_RUNNER_API_KEY}
      SANDBOX_API_GRPC_TLS_CERT_FILE: /tls/api/grpc-server.crt
      SANDBOX_API_GRPC_TLS_KEY_FILE: /tls/api/grpc-server.key
      SANDBOX_API_GRPC_TLS_CLIENT_CA_FILE: /tls/api/ca.crt
      SANDBOX_API_RUNNER_CONTROL_GRPC_TLS_CA_FILE: /tls/api/ca.crt
      SANDBOX_API_RUNNER_CONTROL_GRPC_TLS_CERT_FILE: /tls/api/control-grpc-api-client.crt
      SANDBOX_API_RUNNER_CONTROL_GRPC_TLS_KEY_FILE: /tls/api/control-grpc-api-client.key
      SANDBOX_API_RUNNER_CONTROL_GRPC_TLS_SERVER_NAME: sandbox-runner-1
    volumes:
      - sandbox-tls:/tls:ro
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/healthz"]
      interval: 5s
      timeout: 3s
      retries: 5
      start_period: 10s
    networks:
      - shared_proxy

  sandbox-runner-1:
    image: ghcr.io/n8n-io/n8n-sandbox-service-runner-dind:${SANDBOX_IMAGE_TAG}
    privileged: true
    restart: unless-stopped
    depends_on:
      sandbox-api:
        condition: service_healthy
    environment:
      SANDBOX_RUNNER_API_KEYS: ${SANDBOX_API_RUNNER_API_KEY}
      SANDBOX_RUNNER_REGISTRATION_TOKEN: ${SANDBOX_API_RUNNER_REGISTRATION_TOKEN}
      SANDBOX_RUNNER_API_GRPC_ADDR: sandbox-api:9090
      SANDBOX_RUNNER_HTTP_BASE_URL: http://sandbox-runner-1:8080
      SANDBOX_RUNNER_CONTROL_GRPC_LISTEN_ADDR: ':9091'
      SANDBOX_RUNNER_CONTROL_GRPC_ADVERTISE_ADDR: sandbox-runner-1:9091
      SANDBOX_RUNNER_ID: runner-1
      SANDBOX_RUNNER_DOCKER_SANDBOX_IMAGE: ghcr.io/n8n-io/n8n-sandbox-service-sandbox:${SANDBOX_IMAGE_TAG}
      SANDBOX_RUNNER_REGISTRATION_GRPC_CA_FILE: /tls/runner/ca.crt
      SANDBOX_RUNNER_REGISTRATION_GRPC_CERT_FILE: /tls/runner/grpc-client.crt
      SANDBOX_RUNNER_REGISTRATION_GRPC_KEY_FILE: /tls/runner/grpc-client.key
      SANDBOX_RUNNER_REGISTRATION_GRPC_SERVER_NAME: sandbox-api
      SANDBOX_RUNNER_CONTROL_GRPC_TLS_CERT_FILE: /tls/runner/control-grpc-server.crt
      SANDBOX_RUNNER_CONTROL_GRPC_TLS_KEY_FILE: /tls/runner/control-grpc-server.key
      SANDBOX_RUNNER_CONTROL_GRPC_TLS_CLIENT_CA_FILE: /tls/runner/ca.crt
    volumes:
      - sandbox-tls:/tls:ro
    networks:
      - shared_proxy

networks:
  shared_proxy:
    external: true
EOF
success "docker-compose.yml geschrieben."

info "Lade Images (${SANDBOX_IMAGE_TAG})..."
cd "${INSTALL_DIR}"
$COMPOSE_CMD pull
success "Images geladen."

info "Starte n8n-Sandbox-Stack..."
$COMPOSE_CMD up -d
success "Stack gestartet."

# ── Auf gesunde API warten ────────────────────────────────────────────────────
info "Warte auf Health Check der Sandbox-API (max. 60s)..."
API_CID=""
HEALTHY=false
for _ in $(seq 1 30); do
  API_CID=$($COMPOSE_CMD ps -q sandbox-api 2>/dev/null || true)
  if [[ -n "${API_CID}" ]]; then
    status=$(${SUDO} docker inspect -f '{{.State.Health.Status}}' "${API_CID}" 2>/dev/null || echo "unknown")
    if [[ "${status}" == "healthy" ]]; then
      HEALTHY=true
      break
    fi
  fi
  sleep 2
done

if [[ "${HEALTHY}" == "true" ]]; then
  success "Sandbox-API ist healthy."
else
  warn "Sandbox-API meldet noch keinen 'healthy'-Status. Das kann beim ersten"
  warn "Start etwas dauern (Image-Pull für den Runner, mTLS-Bootstrap). Prüfe ggf.:"
  warn "  cd ${INSTALL_DIR} && ${COMPOSE_CMD} logs -f"
fi

# ── Abschluss ─────────────────────────────────────────────────────────────────
echo ""
echo -e "────────────────────────────────────────────────────────────"
echo -e "${GREEN}${BOLD}  ✓ Installation abgeschlossen!${RESET}"
echo -e "────────────────────────────────────────────────────────────"
echo ""
echo -e "  ${BOLD}Nächste Schritte:${RESET}"
echo ""
echo -e "  1. Richte in deinem ${BOLD}Nginx Proxy Manager${RESET} einen neuen"
echo -e "     Proxy Host ein:"
echo -e "     ${BOLD}Reiter Details${RESET}:"
echo -e "     • Domain:  ${CYAN}${SANDBOX_DOMAIN}${RESET}"
echo -e "     • Forward Hostname: ${CYAN}sandbox-api${RESET}"
echo -e "     • Forward Port:     ${CYAN}8080${RESET}"
echo -e "     • Websockets aktivieren"
echo -e "     • Block Common Exploits aktivieren"
echo -e "     ${BOLD}Reiter SSL${RESET}:"
echo -e "     • SSL Certificate: Request a new Certificate with Let's Encrypt"
echo -e "     • Force SSL aktivieren"
echo -e "     • HTTP/2 Support aktivieren"
echo -e "     • HSTS Enabled aktivieren"
echo ""
echo -e "  2. Health Check testen (nach DNS + NPM-Einrichtung):"
echo -e "     ${CYAN}curl https://${SANDBOX_DOMAIN}/healthz${RESET}"
echo ""
echo -e "  3. Trage diesen Key dort ein, wo deine n8n-Instanz die Sandbox-Anbindung"
echo -e "     konfiguriert (Details dazu weiter unten):"
echo -e "     ${BOLD}SANDBOX_API_KEYS:${RESET} ${CYAN}${SANDBOX_API_KEYS}${RESET}"
echo ""
echo -e "  ${YELLOW}Sicherheitshinweis:${RESET} SANDBOX_API_KEYS ist ein Admin-Key mit vollem"
echo -e "  Zugriff auf alle Sandboxes und Tenant-Verwaltung. Sobald die Domain über"
echo -e "  NPM öffentlich erreichbar ist, sichert nur dieser Key (bzw. mTLS zwischen"
echo -e "  API/Runner) den Zugriff ab. Erwäge zusätzlich eine NPM-Access-List (IP-"
echo -e "  Allowlist), wenn die Sandbox nicht von überall erreichbar sein muss."
echo ""
echo -e "  ${YELLOW}Wichtig:${RESET} Bewahre deine .env sicher auf (enthält alle Secrets):"
echo -e "  ${CYAN}${INSTALL_DIR}/.env${RESET}"
echo ""
echo -e "  4. Diese Sandbox wird von n8n ausschließlich für den ${BOLD}AI Assistant${RESET}"
echo -e "     (n8n Assistant) genutzt, NICHT für Code-Nodes. In deiner n8n-Instanz"
echo -e "     (als Env-Vars, ab n8n 2.x) setzen:"
echo -e "     ${CYAN}N8N_INSTANCE_AI_SANDBOX_ENABLED=true${RESET}"
echo -e "     ${CYAN}N8N_INSTANCE_AI_SANDBOX_PROVIDER=n8n-sandbox${RESET}"
echo -e "     ${CYAN}N8N_SANDBOX_SERVICE_URL=http://sandbox-api:8080${RESET}  (falls n8n"
echo -e "       ebenfalls im ${BOLD}shared_proxy${RESET}-Netzwerk läuft – sonst die"
echo -e "       öffentliche NPM-Domain aus Schritt 1 verwenden)"
echo -e "     ${CYAN}N8N_SANDBOX_SERVICE_API_KEY=${SANDBOX_API_KEYS}${RESET}"
echo -e "     Details/aktueller Stand: ${CYAN}${SANDBOX_GUIDE}${RESET}"
echo ""
echo -e "  ${YELLOW}Hinweis:${RESET} n8n selbst beschreibt diesen manuellen/self-hosted"
echo -e "  Sandbox-Weg als für lokale Entwicklung/Tests geeignet; für Produktiv-"
echo -e "  betrieb empfiehlt n8n offiziell eine Daytona-basierte Sandbox. Für den"
echo -e "  Eigenbetrieb (wie hier) ist das kein Blocker, aber wissenswert."
echo ""
echo -e "  5. Sandbox unabhängig von n8n direkt testen (prüft API+mTLS+Runner+"
echo -e "     echte Code-Ausführung, ganz ohne n8n):"
echo -e "     ${CYAN}docker run --rm --network ${PROXY_NETWORK} curlimages/curl -s -X POST \\"
echo -e "       http://sandbox-api:8080/sandboxes -H \"X-Api-Key: ${SANDBOX_API_KEYS}\"${RESET}"
echo -e "     liefert eine Sandbox-ID zurück; damit dann z.B."
echo -e "     ${CYAN}.../sandboxes/<ID>/executions${RESET} mit"
echo -e "     ${CYAN}-d '{\"command\":\"echo hallo\",\"timeout_ms\":10000}'${RESET} aufrufen."
echo -e "     Volles API-Referenz: ${CYAN}${SANDBOX_GUIDE}/blob/main/docs/API.md${RESET}"
echo ""
echo -e "  Mehr Tipps & Tutorials: ${CYAN}https://pc-fee.com/blog${RESET}"
echo -e "  GitHub:                 ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
