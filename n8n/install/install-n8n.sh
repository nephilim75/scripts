#!/usr/bin/env bash
# =============================================================================
#  n8n Install Script – powered by pc-fee.com
#  https://pc-fee.com | https://github.com/nephilim75/scripts
#
#  Installiert n8n + Task Runner hinter einem Nginx Proxy Manager
#  via Docker Compose (SQLite, external runner, shared_proxy-Netzwerk).
#
#  Voraussetzungen:
#    - Docker ist installiert und läuft
#    - Das Docker-Netzwerk "shared_proxy" existiert bereits
#    - Nginx Proxy Manager läuft und ist im shared_proxy-Netzwerk
#
#  Mehr Infos: https://pc-fee.com/blog
# =============================================================================

set -euo pipefail

# ── Farben ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

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

ask_nodefault() {
  # ask_nodefault <variable> <prompt>
  local var="$1" prompt="$2" input=""
  while [[ -z "$input" ]]; do
    echo ""
    echo -ne "${BOLD}${prompt}${RESET}: "
    read -r input
    [[ -z "$input" ]] && warn "Eingabe darf nicht leer sein."
  done
  eval "${var}=\"${input}\""
}

generate_token() {
  # Erzeugt einen sicheren 48-Zeichen-Token
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48 || true
  echo ""
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
echo -e "${BOLD}  n8n Installations-Script – powered by pc-fee.com${RESET}"
echo -e "  ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo -e "  Dieses Script installiert n8n + Task Runner hinter einem"
echo -e "  Nginx Proxy Manager via Docker Compose."
echo ""
echo -e "  ${YELLOW}Voraussetzungen:${RESET}"
echo -e "   • Docker ist installiert und läuft"
echo -e "   • Das Docker-Netzwerk ${BOLD}shared_proxy${RESET} existiert"
echo -e "   • Nginx Proxy Manager läuft im shared_proxy-Netzwerk"
echo ""
echo -e "────────────────────────────────────────────────────────────"
echo ""

# ── Voraussetzungen prüfen ────────────────────────────────────────────────────
info "Prüfe Voraussetzungen..."

# Docker vorhanden?
if ! command -v docker &>/dev/null; then
  die "Docker ist nicht installiert.\n\n       📖 Anleitung auf pc-fee.com:\n       https://pc-fee.com/2026/05/03/docker-compose/\n\n       Danach dieses Script erneut starten."
fi
DOCKER_VERSION=$(docker --version 2>&1) || true
success "Docker gefunden: ${DOCKER_VERSION}"

# Docker läuft?
if ! docker info &>/dev/null; then
  die "Docker-Daemon läuft nicht. Bitte starten: sudo systemctl start docker"
fi
success "Docker-Daemon läuft."

# Docker Compose vorhanden? (Plugin oder standalone)
if docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
else
  die "Docker Compose nicht gefunden.\n\n       📖 Anleitung auf pc-fee.com:\n       https://pc-fee.com/2026/05/03/docker-compose/\n\n       Danach dieses Script erneut starten."
fi
success "Docker Compose gefunden: $($COMPOSE_CMD version --short 2>/dev/null || $COMPOSE_CMD version)"

# NPM läuft?
if ! docker ps --format '{{.Image}}' | grep -q 'nginx-proxy-manager'; then
  die "Nginx Proxy Manager läuft nicht.\n\n       📖 Anleitung auf pc-fee.com:\n       https://pc-fee.com/2026/05/03/nginx-proxy-manager/\n\n       Bitte zuerst NPM installieren und starten, danach dieses Script erneut ausführen."
fi
success "Nginx Proxy Manager läuft."

# shared_proxy-Netzwerk vorhanden?
if ! docker network inspect shared_proxy &>/dev/null; then
  echo ""
  warn "Das Docker-Netzwerk 'shared_proxy' existiert nicht."
  echo -e "  Soll es jetzt erstellt werden? (Nginx Proxy Manager muss danach"
  echo -e "  ebenfalls in dieses Netzwerk eingebunden werden.)"
  echo ""
  echo -ne "  ${BOLD}Netzwerk jetzt erstellen?${RESET} [${CYAN}j${RESET}/n]: "
  read -r create_net
  if [[ "${create_net,,}" != "n" ]]; then
    docker network create shared_proxy
    success "Netzwerk 'shared_proxy' erstellt."
    warn "Vergiss nicht, deinen Nginx Proxy Manager ebenfalls in dieses Netzwerk einzubinden!"
  else
    die "Netzwerk 'shared_proxy' fehlt. Installation abgebrochen.\n\n       📖 Anleitung Nginx Proxy Manager auf pc-fee.com:\n       https://pc-fee.com/2026/05/03/nginx-proxy-manager/\n\n       Das Netzwerk wird beim NPM-Setup automatisch angelegt."
  fi
else
  success "Docker-Netzwerk 'shared_proxy' gefunden."
fi

echo ""
echo -e "────────────────────────────────────────────────────────────"
echo -e "${BOLD}  Konfiguration${RESET}"
echo -e "────────────────────────────────────────────────────────────"
echo ""

# ── Aktuelle n8n-Version ermitteln ────────────────────────────────────────────
info "Ermittle aktuelle n8n-Version von Docker Hub..."
LATEST_N8N_VERSION=""

if command -v curl &>/dev/null; then
  LATEST_N8N_VERSION=$(
    curl -fsSL "https://registry.hub.docker.com/v2/repositories/n8nio/n8n/tags?page_size=10&ordering=last_updated" \
    2>/dev/null \
    | grep -oP '"name":\s*"\K[0-9]+\.[0-9]+\.[0-9]+' \
    | head -1
  ) || true
elif command -v wget &>/dev/null; then
  LATEST_N8N_VERSION=$(
    wget -qO- "https://registry.hub.docker.com/v2/repositories/n8nio/n8n/tags?page_size=10&ordering=last_updated" \
    2>/dev/null \
    | grep -oP '"name":\s*"\K[0-9]+\.[0-9]+\.[0-9]+' \
    | head -1
  ) || true
fi

if [[ -n "$LATEST_N8N_VERSION" ]]; then
  success "Aktuelle n8n-Version ermittelt: ${LATEST_N8N_VERSION}"
  info    "Runner-Image (n8nio/runners) nutzt dasselbe Tag – bleibt automatisch synchron."
  N8N_VERSION_DEFAULT="$LATEST_N8N_VERSION"
else
  warn "Version konnte nicht automatisch ermittelt werden (kein Internet oder API-Fehler)."
  warn "Fallback-Version wird als Default verwendet."
  N8N_VERSION_DEFAULT="2.22.2"
fi

# ── Bestehende Installation prüfen ────────────────────────────────────────────
# Ziel: Niemals „drüber installieren“, weil sonst N8N_ENCRYPTION_KEY kollidiert und n8n nicht mehr startet.

EXISTING_INSTALL=false
EXISTING_REASON=""

# 1) Installationspfad aus Default (noch bevor User-Input kommt)
#    Wir prüfen hier bewusst nur /opt/n8n, weil der User den Pfad erst später setzt.
if [[ -f "/opt/n8n/.env" ]] || [[ -f "/opt/n8n/docker-compose.yml" ]] || [[ -d "/opt/n8n/n8n_data" ]]; then
  EXISTING_INSTALL=true
  EXISTING_REASON="/opt/n8n vorhanden (.env/docker-compose.yml/n8n_data)"
fi

# 2) Container/Compose-Projekt-Indikatoren
if docker ps -a --format '{{.Names}}' | grep -qE '^n8n$|^n8n-task-runners-1$'; then
  EXISTING_INSTALL=true
  EXISTING_REASON="n8n Container existiert (n8n / n8n-task-runners-1)"
fi

# 3) Image-Indikator (failsafe)
if docker ps -a --format '{{.Image}}' | grep -qE '^n8nio/n8n:|^n8nio/runners:'; then
  EXISTING_INSTALL=true
  EXISTING_REASON="n8nio/n8n oder n8nio/runners Container existiert"
fi

if [[ "$EXISTING_INSTALL" == "true" ]]; then
  echo ""
  echo -e "────────────────────────────────────────────────────────────"
  warn "Bestehende n8n-Installation erkannt (${EXISTING_REASON})."
  echo ""
  echo -e "  ${RED}${BOLD}Abbruch:${RESET} Dieses Install-Script installiert NICHT über eine bestehende Installation."
  echo -e "  Grund: Ein neuer ${BOLD}N8N_ENCRYPTION_KEY${RESET} würde zu einem Key-Mismatch führen"
  echo -e "  (n8n startet dann nicht / Credentials werden unbrauchbar)."
  echo ""
  echo -e "  ${BOLD}Was du jetzt tun kannst:${RESET}"
  echo -e "   1) ${BOLD}Upgrade/Restart${RESET} der bestehenden Installation:"
  echo -e "      - in den bestehenden Ordner wechseln (meist /opt/n8n)"
  echo -e "      - Version im docker-compose.yml anpassen"
  echo -e "      - ${BOLD}docker compose up -d${RESET}"
  echo -e ""
  echo -e "   2) ${BOLD}Komplett neu installieren${RESET} (Daten weg):"
  echo -e "      - ${BOLD}cd /opt/n8n && docker compose down -v${RESET}"
  echo -e "      - ${BOLD}rm -rf /opt/n8n${RESET}"
  echo -e "      - Script erneut starten"
  echo ""
  die "Installation abgebrochen, um Datenverlust/Key-Mismatch zu vermeiden."
fi

# ── Benutzereingaben ──────────────────────────────────────────────────────────

# Domain
ask_nodefault N8N_DOMAIN "Deine n8n-Domain (z.B. n8n.meinedomain.de)"

# Installationspfad
ask INSTALL_DIR "Installationspfad" "/opt/n8n"

# n8n-Version (Default = automatisch ermittelt oder Fallback)
ask N8N_VERSION "n8n-Version" "${N8N_VERSION_DEFAULT}"

# Timezone
ask TIMEZONE "Zeitzone" "Europe/Berlin"

# Encryption Key (optional, wird sonst generiert)
echo ""
info "Ein Encryption Key schützt deine gespeicherten Credentials in n8n."
echo ""
echo -ne "${BOLD}Eigenen Encryption Key eingeben?${RESET} (leer lassen = automatisch generieren) [${CYAN}leer${RESET}]: "
read -r user_enc_key
if [[ -n "$user_enc_key" ]]; then
  N8N_ENCRYPTION_KEY="$user_enc_key"
else
  N8N_ENCRYPTION_KEY=$(generate_token)
  info "Encryption Key automatisch generiert."
fi

# Runner Auth Token (immer generiert, kein User-Input nötig)
N8N_RUNNERS_AUTH_TOKEN=$(generate_token)

echo ""
echo -e "────────────────────────────────────────────────────────────"
echo -e "${BOLD}  Zusammenfassung${RESET}"
echo -e "────────────────────────────────────────────────────────────"
echo ""
echo -e "  Domain:           ${CYAN}${N8N_DOMAIN}${RESET}"
echo -e "  Installationspfad:${CYAN} ${INSTALL_DIR}${RESET}"
echo -e "  n8n-Version:      ${CYAN}${N8N_VERSION}${RESET}"
echo -e "  Runner-Version:   ${CYAN}${N8N_VERSION}${RESET} (synchron)"
echo -e "  Zeitzone:         ${CYAN}${TIMEZONE}${RESET}"
echo -e "  Encryption Key:   ${CYAN}[gesetzt]${RESET}"
echo -e "  Runner Token:     ${CYAN}[automatisch generiert]${RESET}"
echo ""
echo -ne "${BOLD}Alles korrekt? Installation starten?${RESET} [${CYAN}j${RESET}/n]: "
read -r confirm
if [[ "${confirm,,}" == "n" ]]; then
  warn "Installation abgebrochen. Starte das Script erneut."
  exit 0
fi

echo ""
echo -e "────────────────────────────────────────────────────────────"
echo -e "${BOLD}  Installation${RESET}"
echo -e "────────────────────────────────────────────────────────────"
echo ""

# ── Verzeichnisse anlegen ─────────────────────────────────────────────────────
info "Erstelle Verzeichnisse unter ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}/n8n_data"
mkdir -p "${INSTALL_DIR}/backups"
chown -R 1000:1000 "${INSTALL_DIR}/n8n_data"
echo "${N8N_VERSION}" > "${INSTALL_DIR}/current_version"
success "Verzeichnisse erstellt, Version ${N8N_VERSION} in current_version geschrieben."

# ── .env schreiben ────────────────────────────────────────────────────────────
info "Schreibe .env..."
cat > "${INSTALL_DIR}/.env" <<EOF
# n8n Umgebungsvariablen – generiert von pc-fee.com Install-Script
# Mehr Infos: https://pc-fee.com/blog

N8N_RUNNERS_AUTH_TOKEN=${N8N_RUNNERS_AUTH_TOKEN}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
EOF
chmod 600 "${INSTALL_DIR}/.env"
success ".env geschrieben (Berechtigungen: 600)."

# ── docker-compose.yml schreiben ──────────────────────────────────────────────
info "Schreibe docker-compose.yml..."
cat > "${INSTALL_DIR}/docker-compose.yml" <<EOF
# docker-compose.yml – generiert von pc-fee.com Install-Script
# n8n ${N8N_VERSION} + Task Runner hinter Nginx Proxy Manager
# Mehr Infos: https://pc-fee.com/blog

services:
  n8n:
    image: n8nio/n8n:${N8N_VERSION}
    container_name: n8n
    restart: unless-stopped
    expose:
      - "5678"
    environment:
      - GENERIC_TIMEZONE=${TIMEZONE}
      - N8N_HOST=${N8N_DOMAIN}
      - N8N_PORT=5678
      - WEBHOOK_URL=https://${N8N_DOMAIN}/
      - N8N_RUNNERS_MODE=external
      - N8N_RUNNERS_BROKER_ENABLED=true
      - N8N_RUNNERS_BROKER_PORT=5679
      - N8N_RUNNERS_BROKER_LISTEN_ADDRESS=0.0.0.0
      - N8N_RUNNERS_AUTH_TOKEN=\${N8N_RUNNERS_AUTH_TOKEN}
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      - N8N_NATIVE_PYTHON_RUNNER=true
      - N8N_PROXY_HOPS=1
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=168
      - EXECUTIONS_DATA_PRUNE_MAX_COUNT=1000
      - N8N_RESTRICT_FILE_ACCESS_TO=/opt/current_version
    volumes:
      - ./n8n_data:/home/node/.n8n
      - ./current_version:/opt/current_version
    networks:
      - shared_proxy

  task-runners:
    image: n8nio/runners:${N8N_VERSION}
    restart: unless-stopped
    environment:
      - N8N_RUNNERS_TASK_BROKER_URI=http://n8n:5679
      - N8N_RUNNERS_AUTH_TOKEN=\${N8N_RUNNERS_AUTH_TOKEN}
    depends_on:
      - n8n
    networks:
      - shared_proxy

networks:
  shared_proxy:
    external: true
EOF
success "docker-compose.yml geschrieben."

# ── Stack starten ─────────────────────────────────────────────────────────────
info "Starte n8n Stack..."
cd "${INSTALL_DIR}"
$COMPOSE_CMD up -d

echo ""
echo -e "────────────────────────────────────────────────────────────"
echo -e "${GREEN}${BOLD}  ✓ Installation abgeschlossen!${RESET}"
echo -e "────────────────────────────────────────────────────────────"
echo ""
echo -e "  ${BOLD}Nächste Schritte:${RESET}"
echo -e ""
echo -e "  1. Richte in deinem ${BOLD}Nginx Proxy Manager${RESET} einen neuen"
echo -e "     Proxy Host ein:"
echo -e "     • Domain:  ${CYAN}${N8N_DOMAIN}${RESET}"
echo -e "     • Forward: ${CYAN}http://n8n:5678${RESET}"
echo -e "     • SSL:     Let's Encrypt aktivieren"
echo -e "     • Websockets aktivieren (unter 'Advanced')"
echo -e ""
echo -e "  2. Öffne n8n im Browser:"
echo -e "     ${CYAN}https://${N8N_DOMAIN}${RESET}"
echo -e ""
echo -e "  3. Lege deinen Admin-Account an."
echo -e ""
echo -e "  ${YELLOW}Wichtig:${RESET} Bewahre deine .env sicher auf:"
echo -e "  ${CYAN}${INSTALL_DIR}/.env${RESET}"
echo -e ""
echo -e "  Mehr Tipps & Tutorials: ${CYAN}https://pc-fee.com/blog${RESET}"
echo -e "  GitHub:                 ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
