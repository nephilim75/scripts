```bash
#!/usr/bin/env bash
# =============================================================================
#  LibreChat Install Script – powered by pc-fee.com
#  https://pc-fee.com | https://github.com/nephilim75/scripts
#
#  Installiert LibreChat (api + admin-panel) mit MongoDB und Meilisearch
#  hinter einem Nginx Proxy Manager via Docker Compose.
#
#  Voraussetzungen:
#    - Docker ist installiert und läuft
#    - Das Docker-Netzwerk "shared_proxy" existiert bereits
#    - Nginx Proxy Manager läuft im shared_proxy-Netzwerk
#    - Je eine Domain fuer Chat und Admin-Panel zeigt auf den Server
#
#  Mehr Infos: https://pc-fee.com/blog
# =============================================================================
#
#  AI Transparency: Dieses Script wurde mit Unterstuetzung von KI erstellt
#  (Nils Weber, KI-Assistent bei pc-fee.com) und vor Veroeffentlichung geprueft.
#  Nutzung auf eigene Gefahr. Backups sind Pflicht.
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
info()    { echo -e "$${CYAN}[INFO]$${RESET}  $*"; }
success() { echo -e "$${GREEN}[OK]$${RESET}    $*"; }
warn()    { echo -e "$${YELLOW}[WARN]$${RESET}  $*"; }
error()   { echo -e "$${RED}[FEHLER]$${RESET} $*"; }
die()     { error "$*"; exit 1; }

ask() {
  local var="\$1" prompt="\$2" default="\$3"
  local input
  echo ""
  echo -ne "$${BOLD}$${prompt}$${RESET} [$${CYAN}$${default}$${RESET}]: "
  read -r input
  eval "$${var}=\"$${input:-${default}}\""
}

ask_validated() {
  local var="\$1" prompt="\$2" default="\$3" validator="\$4"
  local input=""
  while true; do
    echo ""
    echo -ne "$${BOLD}$${prompt}$${RESET} [$${CYAN}$${default}$${RESET}]: "
    read -r input
    input="$${input:-$${default}}"
    if "$${validator}" "$${input}"; then
      break
    else
      warn "Eingabe ungueltig: ${prompt}"
    fi
  done
  eval "$${var}=\"$${input}\""
}

ask_password() {
  local var="\$1" prompt="\$2" minlen="${3:-12}"
  local input="" input2=""
  while true; do
    echo ""
    echo -ne "$${BOLD}$${prompt}${RESET}: "
    read -rs input
    echo ""
    if [[ $${#input} -lt $$minlen ]]; then
      warn "Passwort muss mindestens ${minlen} Zeichen lang sein."
      continue
    fi
    echo -ne "$${BOLD}$${prompt} (Wiederholung)${RESET}: "
    read -rs input2
    echo ""
    if [[ "$$input" != "$$input2" ]]; then
      warn "Passwoerter stimmen nicht ueberein."
      continue
    fi
    break
  done
  eval "$${var}=\"$${input}\""
}

is_email() {
  [[ "\$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

is_domain() {
  [[ "\$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

is_path_abs() {
  [[ "\$1" =~ ^/[A-Za-z0-9._/-]+$ ]]
}

is_network_name() {
  [[ "\$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]
}

generate_token() {
  local n="${1:-64}"
  tr -dc 'A-Fa-f0-9' </dev/urandom | head -c "$n" || true
  echo ""
}

wait_for_healthy() {
  local name="\$1" max="${2:-60}"
  local elapsed=0
  while (( elapsed < max )); do
    local status
    status="$$($${SUDO} docker inspect --format '{{.State.Health.Status}}' "${name}" 2>/dev/null || echo 'starting')"
    case "${status}" in
      healthy) return 0 ;;
      unhealthy) return 1 ;;
    esac
    sleep 2
    elapsed=$(( elapsed + 2 ))
  done
  return 1
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
echo -e "$${BOLD}  LibreChat Installations-Script – powered by pc-fee.com$${RESET}"
echo -e "  $${CYAN}https://pc-fee.com$${RESET} | $${CYAN}https://github.com/nephilim75/scripts$${RESET}"
echo ""
echo -e "  Dieses Script installiert LibreChat (api + admin-panel) mit"
echo -e "  MongoDB und Meilisearch hinter einem Nginx Proxy Manager."
echo ""
echo -e "  $${YELLOW}Voraussetzungen:$${RESET}"
echo -e "   • Docker ist installiert und läuft"
echo -e "   • Das Docker-Netzwerk $${BOLD}shared_proxy$${RESET} existiert"
echo -e "   • Nginx Proxy Manager läuft im shared_proxy-Netzwerk"
echo -e "   • Je eine Domain für Chat und Admin-Panel zeigt auf den Server"
echo ""
echo -e "────────────────────────────────────────────────────────────"
echo ""

# ── SUDO-Helfer ───────────────────────────────────────────────────────────────
SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo &>/dev/null; then
    SUDO="sudo"
  else
    die "Bitte als root oder mit sudo ausfuehren."
  fi
fi

# ── Konstanten (Images, Defaults) ─────────────────────────────────────────────
IMAGE_API="registry.librechat.ai/danny-avila/librechat:dev-latest"
IMAGE_ADMIN="registry.librechat.ai/clickhouse/librechat-admin-panel:latest"
IMAGE_MONGO="mongo:8.0.20"
IMAGE_MEILI="getmeili/meilisearch:v1.35.1"

DEFAULT_INSTALL_DIR="/opt/librechat"
DEFAULT_NETWORK="shared_proxy"

# ── Schritt 0: Voraussetzungen + Konflikt-Erkennung ───────────────────────────
echo ""
echo -e "$${BOLD} Schritt 0: Voraussetzungen + Konflikt-Erkennung$${RESET}"
echo -e "------------------------------------------------------------"

info "Pruefe Voraussetzungen..."

if [[ "${EUID}" -eq 0 ]]; then
  success "Skript laeuft als root."
else
  success "Skript laeuft mit sudo."
fi

if ! command -v docker &>/dev/null; then
  die "Docker ist nicht installiert.

  Anleitung auf pc-fee.com:
  https://pc-fee.com/2026/05/03/docker-compose/

  Danach dieses Script erneut starten."
fi
success "Docker gefunden: $(docker --version 2>&1)"

if ! docker info &>/dev/null; then
  die "Docker-Daemon laeuft nicht. Bitte starten: sudo systemctl start docker"
fi
success "Docker-Daemon laeuft."

if docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
  warn "docker-compose (Standalone) gefunden - Plugin v2 wird empfohlen."
else
  die "Docker Compose nicht gefunden.

  Anleitung auf pc-fee.com:
  https://pc-fee.com/2026/05/03/docker-compose/"
fi
success "Docker Compose gefunden: ${COMPOSE_CMD}"

command -v curl &>/dev/null || die "curl ist nicht installiert (apt install curl)."
success "curl gefunden."

if ! docker ps --format '{{.Image}}' | grep -q 'nginx-proxy-manager'; then
  die "Nginx Proxy Manager laeuft nicht.

  Anleitung auf pc-fee.com:
  https://pc-fee.com/2026/05/03/nginx-proxy-manager/

  Bitte zuerst NPM installieren und starten, danach dieses Script erneut ausfuehren."
fi
success "Nginx Proxy Manager laeuft."

echo ""
info "Pruefe auf bestehende LibreChat-Installation..."
CONFLICT_FOUND=0

EXISTING_CONTAINERS="$(docker ps -a --format '{{.Names}}' 2>/dev/null \
  | grep -E '^(librechat|librechat-api|librechat-admin|librechat-mongo|librechat-meili)$' || true)"
if [[ -n "${EXISTING_CONTAINERS}" ]]; then
  error "Bestehende LibreChat-Container gefunden:"
  echo "${EXISTING_CONTAINERS}" | sed 's/^/    /'
  echo "    Aufloesung: docker rm -f <name>"
  CONFLICT_FOUND=1
fi

EXISTING_IMAGES="$(docker ps -a --format '{{.Names}} {{.Image}}' 2>/dev/null \
  | grep -E 'registry\.librechat\.ai/.*librechat|registry\.librechat\.ai/.*admin-panel' || true)"
if [[ -n "${EXISTING_IMAGES}" ]]; then
  error "Container mit LibreChat-Images gefunden:"
  echo "${EXISTING_IMAGES}" | sed 's/^/    /'
  echo "    Aufloesung: docker rm -f <name>"
  CONFLICT_FOUND=1
fi

EXISTING_VOLUMES="$(docker volume ls --format '{{.Name}}' 2>/dev/null \
  | grep -E '^(librechat|librechat_mongo|librechat_meili)' || true)"
if [[ -n "${EXISTING_VOLUMES}" ]]; then
  error "Bestehende LibreChat-Volumes gefunden:"
  echo "${EXISTING_VOLUMES}" | sed 's/^/    /'
  echo "    Aufloesung: docker volume rm <name>   (loescht Daten!)"
  CONFLICT_FOUND=1
fi

for port in 3080 3000 27017 7700; do
  if ss -tln 2>/dev/null | grep -qE ":${port}\s"; then
    OWNER="$$(ss -tlnp 2>/dev/null | grep -E ":$${port}\s" | head -1 || true)"
    error "Port $${port} ist bereits belegt: $${OWNER}"
    echo "    Aufloesung: Prozess auf Port ${port} stoppen."
    CONFLICT_FOUND=1
  fi
done

if [[ "${CONFLICT_FOUND}" -ne 0 ]]; then
  die "Konflikte gefunden. Schutzregel: keine bestehende Installation ueberschreiben.

  Wenn du LibreChat komplett neu aufsetzen willst, entferne die oben genannten
  Container/Volumes/Ports zuerst manuell. Bestaehende Daten gehen dabei verloren."
fi
success "Keine Konflikte gefunden."

# ── Schritt 1: Interaktive Eingaben ───────────────────────────────────────────
echo ""
echo -e "$${BOLD} Schritt 1: Konfiguration$${RESET}"
echo -e "------------------------------------------------------------"

info "Bitte beantworte die folgenden Fragen."

ask_validated INSTALL_DIR "Installationspfad" "${DEFAULT_INSTALL_DIR}" is_path_abs
INSTALL_DIR="${INSTALL_DIR%/}"

ask_validated NETWORK_NAME "Docker-Netzwerk (vom NPM-Installer)" "${DEFAULT_NETWORK}" is_network_name

if ! docker network inspect "${NETWORK_NAME}" &>/dev/null; then
  echo ""
  warn "Das Docker-Netzwerk '${NETWORK_NAME}' existiert nicht."
  echo -ne "  $${BOLD}Jetzt erstellen?$${RESET} [$${CYAN}j$${RESET}/n]: "
  read -r create_net
  if [[ "${create_net,,}" != "n" ]]; then
    docker network create "${NETWORK_NAME}"
    success "Netzwerk '${NETWORK_NAME}' erstellt."
    warn "Vergiss nicht, deinen Nginx Proxy Manager ebenfalls in dieses Netzwerk einzubinden!"
  else
    die "Netzwerk '${NETWORK_NAME}' fehlt. Installation abgebrochen.

  Anleitung Nginx Proxy Manager auf pc-fee.com:
  https://pc-fee.com/2026/05/03/nginx-proxy-manager/"
  fi
else
  success "Docker-Netzwerk '${NETWORK_NAME}' gefunden."
fi

ask_validated CHAT_DOMAIN "Chat-Domain (z.B. chat.deinedomain.de)" "" is_domain
ask_validated ADMIN_DOMAIN "Admin-Panel-Domain (z.B. chat-admin.deinedomain.de)" "" is_domain

if [[ "$${CHAT_DOMAIN}" == "$${ADMIN_DOMAIN}" ]]; then
  die "Chat-Domain und Admin-Domain muessen verschieden sein."
fi

ask_validated ADMIN_EMAIL "Admin-E-Mail" "" is_email

DEFAULT_ADMIN_USERNAME="${ADMIN_EMAIL%%@*}"
ask ADMIN_USERNAME "Admin-Username" "${DEFAULT_ADMIN_USERNAME}"
ask ADMIN_NAME "Admin-Anzeigename" "${ADMIN_USERNAME}"
ask_password ADMIN_PASS "Admin-Passwort (mind. 12 Zeichen)" 12

echo ""
info "Ein JWT-Secret schuetzt Login-Tokens (Refresh-Token, Access-Token)."
echo ""
echo -ne "$${BOLD}Eigenes JWT-Secret eingeben?$${RESET} [$${CYAN}leer = generieren$${RESET}]: "
read -r jwt_in
if [[ -n "${jwt_in}" ]]; then
  if [[ ${#jwt_in} -lt 32 ]]; then
    warn "Eigenes JWT-Secret wird akzeptiert, aber mind. 32 Zeichen empfohlen."
  fi
  JWT_SECRET="${jwt_in}"
else
  JWT_SECRET="$(generate_token 64)"
  success "JWT-Secret automatisch generiert (64 hex Zeichen)."
fi

echo ""
echo -e "────────────────────────────────────────────────────────────"
echo -e "$${BOLD} Zusammenfassung$${RESET}"
echo -e "────────────────────────────────────────────────────────────"
echo ""
echo -e "  Installationspfad:   $${CYAN}$${INSTALL_DIR}${RESET}"
echo -e "  Docker-Netzwerk:     $${CYAN}$${NETWORK_NAME}${RESET}"
echo -e "  Chat-Domain:         $${CYAN}$${CHAT_DOMAIN}${RESET}"
echo -e "  Admin-Domain:        $${CYAN}$${ADMIN_DOMAIN}${RESET}"
echo -e "  Admin-E-Mail:        $${CYAN}$${ADMIN_EMAIL}${RESET}"
echo -e "  Admin-Username:      $${CYAN}$${ADMIN_USERNAME}${RESET}"
echo -e "  Admin-Anzeigename:   $${CYAN}$${ADMIN_NAME}${RESET}"
echo -e "  Admin-Passwort:      $${CYAN}[gesetzt]$${RESET}"
echo -e "  JWT-Secret:          $${CYAN}[gesetzt]$${RESET}"
echo ""
echo -ne "$${BOLD}Alles korrekt? Installation starten?$${RESET} [$${CYAN}j$${RESET}/n]: "
read -r confirm
if [[ "${confirm,,}" == "n" ]]; then
  warn "Installation abgebrochen. Starte das Script erneut."
  exit 0
fi

# ── Schritt 2: Tokens + Dateien schreiben ─────────────────────────────────────
echo ""
echo -e "$${BOLD} Schritt 2: Konfiguration schreiben$${RESET}"
echo -e "------------------------------------------------------------"

CREDS_KEY="$(generate_token 64)"
CREDS_IV="$(generate_token 32)"
MEILI_MASTER_KEY="$(generate_token 32)"
success "Secrets generiert (CREDS_KEY, CREDS_IV, MEILI_MASTER_KEY)."

info "Erstelle Verzeichnisse unter ${INSTALL_DIR}..."
$${SUDO} mkdir -p "$${INSTALL_DIR}/data/mongo"
$${SUDO} mkdir -p "$${INSTALL_DIR}/data/meili"
success "Verzeichnisse erstellt."

$${SUDO} tee "$${INSTALL_DIR}/current_version" >/dev/null <<EOF
api=${IMAGE_API}
admin=${IMAGE_ADMIN}
mongo=${IMAGE_MONGO}
meili=${IMAGE_MEILI}
installed=$(date -u +%FT%TZ)
EOF

info "Schreibe .env..."
$${SUDO} tee "$${INSTALL_DIR}/.env" >/dev/null <<EOF
# LibreChat Umgebungsvariablen – generiert von pc-fee.com Install-Script
# Mehr Infos: https://pc-fee.com/blog

# --- Allgemein ---
HOST=https://${CHAT_DOMAIN}
ALLOW_REGISTRATION=false
ALLOW_EMAIL_LOGIN=true
ALLOW_PASSWORD_RESET=false

# --- Admin ---
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_USERNAME=${ADMIN_USERNAME}

# --- Tokens (generiert) ---
JWT_SECRET=${JWT_SECRET}
CREDS_KEY=${CREDS_KEY}
CREDS_IV=${CREDS_IV}
MEILI_MASTER_KEY=${MEILI_MASTER_KEY}

# --- MongoDB ---
MONGO_URI=mongodb://mongodb:27017/librechat

# --- Meilisearch ---
MEILI_URL=http://meilisearch:7700
MEILI_NO_ANALYTICS=true
EOF
$${SUDO} chmod 600 "$${INSTALL_DIR}/.env"
success ".env geschrieben (Berechtigungen: 600)."

info "Schreibe librechat.yaml..."
$${SUDO} tee "$${INSTALL_DIR}/librechat.yaml" >/dev/null <<EOF
# librechat.yaml – generiert von pc-fee.com Install-Script
# Provider-Endpoints hier manuell ergaenzen (Format siehe librechat.ai Docs).
# Mehr Infos: https://pc-fee.com/blog

version: 1.0.0
cache: true

interface:
  customWelcome: "Willkommen bei deinem Chat"

endpoints: {}

registration:
  disable: true

search:
  endpoint: "http://meilisearch:7700"
  apiKey: "\${MEILI_MASTER_KEY}"
EOF
$${SUDO} chmod 644 "$${INSTALL_DIR}/librechat.yaml"
success "librechat.yaml geschrieben."

info "Schreibe docker-compose.yml..."
$${SUDO} tee "$${INSTALL_DIR}/docker-compose.yml" >/dev/null <<EOF
# docker-compose.yml – generiert von pc-fee.com Install-Script
# LibreChat + MongoDB + Meilisearch hinter Nginx Proxy Manager.
# Mehr Infos: https://pc-fee.com/blog

services:
  mongodb:
    image: ${IMAGE_MONGO}
    container_name: librechat-mongo
    restart: unless-stopped
    expose:
      - "27017"
    volumes:
      - ${INSTALL_DIR}/data/mongo:/data/db
    networks:
      - librechat_internal
    healthcheck:
      test: ["CMD", "mongosh", "--quiet", "--eval", "db.adminCommand('ping').ok"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

  meilisearch:
    image: ${IMAGE_MEILI}
    container_name: librechat-meili
    restart: unless-stopped
    expose:
      - "7700"
    environment:
      - MEILI_MASTER_KEY=\${MEILI_MASTER_KEY}
      - MEILI_NO_ANALYTICS=true
    volumes:
      - ${INSTALL_DIR}/data/meili:/meili_data
    networks:
      - librechat_internal
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:7700/health"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 20s

  api:
    image: ${IMAGE_API}
    container_name: librechat-api
    restart: unless-stopped
    expose:
      - "3080"
    env_file:
      - ${INSTALL_DIR}/.env
    depends_on:
      mongodb:
        condition: service_healthy
      meilisearch:
        condition: service_healthy
    volumes:
      - type: bind
        source: ${INSTALL_DIR}/librechat.yaml
        target: /app/librechat.yaml
        read_only: true
    networks:
      - ${NETWORK_NAME}
      - librechat_internal
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:3080/api/health"]
      interval: 15s
      timeout: 5s
      retries: 10
      start_period: 60s

  admin-panel:
    image: ${IMAGE_ADMIN}
    container_name: librechat-admin
    restart: unless-stopped
    expose:
      - "3000"
    env_file:
      - ${INSTALL_DIR}/.env
    networks:
      - ${NETWORK_NAME}

networks:
  ${NETWORK_NAME}:
    external: true
  librechat_internal:
    driver: bridge
EOF
$${SUDO} chmod 644 "$${INSTALL_DIR}/docker-compose.yml"
success "docker-compose.yml geschrieben."

# ── Schritt 3: Stack hochfahren + Admin-Seed ───────────────────────────────────
echo ""
echo -e "$${BOLD} Schritt 3: Stack starten + Admin-Seed$${RESET}"
echo -e "------------------------------------------------------------"

cd "${INSTALL_DIR}"

info "Starte mongodb und meilisearch..."
$${SUDO} $${COMPOSE_CMD} up -d mongodb meilisearch

info "Warte auf mongodb (max. 60s)..."
if wait_for_healthy librechat-mongo 60; then
  success "mongodb ist healthy."
else
  die "mongodb wurde nicht healthy. Pruefe mit: ${COMPOSE_CMD} logs mongodb"
fi

info "Warte auf meilisearch (max. 60s)..."
if wait_for_healthy librechat-meili 60; then
  success "meilisearch ist healthy."
else
  die "meilisearch wurde nicht healthy. Pruefe mit: ${COMPOSE_CMD} logs meilisearch"
fi

info "Starte api und admin-panel..."
$${SUDO} $${COMPOSE_CMD} up -d api admin-panel

info "Warte auf api (max. 90s)..."
if wait_for_healthy librechat-api 90; then
  success "api ist healthy."
else
  warn "api wurde nicht innerhalb von 90s healthy. Pruefe mit: ${COMPOSE_CMD} logs api"
  warn "Versuche trotzdem den Admin-Seed..."
fi

echo ""
info "Lege Admin-User '${ADMIN_USERNAME}' an..."

# Workaround fuer LibreChat-Image-Bug: npm run create-user aus /app/config
# aufrufen, nicht aus /app/api (sonst MODULE_NOT_FOUND).
SEED_INPUT="${ADMIN_EMAIL}
${ADMIN_USERNAME}
${ADMIN_NAME}
${ADMIN_PASS}
${ADMIN_PASS}
y
"
SEED_OUTPUT="$$(printf '%s' "$${SEED_INPUT}" \
  | $${SUDO} $${COMPOSE_CMD} exec -T api sh -c 'cd /app/config && npm run create-user' 2>&1 || true)"

if echo "${SEED_OUTPUT}" | grep -qiE 'already exists|user exists|duplicate'; then
  warn "Admin-User '${ADMIN_USERNAME}' existiert bereits - ueberspringe Seed."
elif echo "${SEED_OUTPUT}" | grep -qiE 'error|fehler|MODULE_NOT_FOUND'; then
  error "Admin-Seed fehlgeschlagen:"
  echo "${SEED_OUTPUT}" | sed 's/^/    /'
  echo ""
  warn "Du kannst es manuell versuchen:"
  echo "    cd $${INSTALL_DIR} && $${COMPOSE_CMD} exec api sh -c 'cd /app/config && npm run create-user'"
else
  success "Admin-User '${ADMIN_USERNAME}' angelegt."
fi

info "Starte api neu (Seed-Aktivierung)..."
$${SUDO} $${COMPOSE_CMD} restart api >/dev/null
success "api neugestartet."

# ── Schritt 4: Health-Checks + NPM-Proxy-Host-Hinweise ────────────────────────
echo ""
echo -e "$${BOLD} Schritt 4: Status + naechste Schritte$${RESET}"
echo -e "------------------------------------------------------------"

info "Aktueller Container-Status:"
$${SUDO} $${COMPOSE_CMD} ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'

echo ""
echo -e "$${BOLD}============================================================$${RESET}"
echo -e "$${GREEN}$${BOLD}  Installation abgeschlossen!${RESET}"
echo -e "$${BOLD}============================================================$${RESET}"
echo ""
echo -e "  $${BOLD}Naechste Schritte:$${RESET}"
echo ""
echo -e "  1. Richte in deinem $${BOLD}Nginx Proxy Manager$${RESET} zwei Proxy Hosts ein:"
echo ""
echo -e "     $${BOLD}Host 1 - Chat:$${RESET}"
echo -e "       Domain:        $${CYAN}$${CHAT_DOMAIN}${RESET}"
echo -e "       Scheme:        http"
echo -e "       Forward Host:  $${CYAN}librechat-api$${RESET}"
echo -e "       Forward Port:  $${CYAN}3080$${RESET}"
echo -e "       Websockets:    AN"
echo -e "       SSL:           Let's Encrypt"
echo ""
echo -e "     $${BOLD}Host 2 - Admin-Panel:$${RESET}"
echo -e "       Domain:        $${CYAN}$${ADMIN_DOMAIN}${RESET}"
echo -e "       Scheme:        http"
echo -e "       Forward Host:  $${CYAN}librechat-admin$${RESET}"
echo -e "       Forward Port:  $${CYAN}3000$${RESET}"
echo -e "       Websockets:    AN"
echo -e "       SSL:           Let's Encrypt"
echo ""
echo -e "  2. Erster Login:"
echo -e "     Browser -> $${CYAN}https://$${CHAT_DOMAIN}${RESET}"
echo -e "     Login mit: $${CYAN}$${ADMIN_EMAIL}${RESET}  /  <dein Passwort>"
echo ""
echo -e "  3. LLM-Provider in ${INSTALL_DIR}/librechat.yaml eintragen."
echo -e "     Danach: cd $${INSTALL_DIR} && sudo $${COMPOSE_CMD} restart api"
echo ""
echo -e "  $${YELLOW}Wichtig:$${RESET} Bewahre deine .env sicher auf:"
echo -e "  $${CYAN}$${INSTALL_DIR}/.env${RESET} (Berechtigungen: 600)"
echo ""
echo -e "$${BOLD}============================================================$${RESET}"
echo -e "$${BOLD} Befehle zur Wiederholung / Kontrolle$${RESET}"
echo -e "$${BOLD}============================================================$${RESET}"
echo ""
echo -e "  Stack neustarten:        cd $${INSTALL_DIR} && sudo $${COMPOSE_CMD} restart"
echo -e "  Logs ansehen:            cd $${INSTALL_DIR} && sudo $${COMPOSE_CMD} logs -f"
echo -e "  Status pruefen:          cd $${INSTALL_DIR} && sudo $${COMPOSE_CMD} ps"
echo -e "  Auf Updates prüfen:      cd $${INSTALL_DIR} && sudo $${COMPOSE_CMD} pull"
echo ""
echo -e "  Mehr Tipps & Tutorials:  $${CYAN}https://pc-fee.com/blog$${RESET}"
echo -e "  GitHub:                  $${CYAN}https://github.com/nephilim75/scripts$${RESET}"
echo ""
```
