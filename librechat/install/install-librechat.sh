#!/usr/bin/env bash
# =============================================================================
# LibreChat Docker Installer
# - folgt dem offiziellen Docker-Setup: https://www.librechat.ai/de/docs/local/docker
# - kein Port wird an den Host gebunden, Zugriff ausschliesslich ueber ein
#   bestehendes externes Docker-Netzwerk eines Nginx Proxy Managers (NPM)
# - Admin-User wird per CLI angelegt, Weboberflaechen-Registrierung bleibt aus
#
# -----------------------------------------------------------------------------
# AI-Transparenzhinweis:
# Dieses Skript wurde unter Einsatz von KI-Modellen (Claude Sonnet 5, Anthropic;
# MiniMax3, MiniMax) recherchiert, erstellt und iterativ ueberarbeitet.
# Alle technischen Aussagen wurden gegen die offizielle LibreChat-Dokumentation
# und den LibreChat-Quellcode geprueft. Vor produktivem Einsatz eigenverant-
# wortlich pruefen.
# -----------------------------------------------------------------------------
# =============================================================================
set -Eeuo pipefail
trap 'rc=$?; echo "[FEHLER] Abbruch in Zeile ${LINENO} (Exit ${rc})." >&2; exit ${rc}' ERR

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { printf '%b\n' "${CYAN}[INFO]${RESET}  $*"; }
success() { printf '%b\n' "${GREEN}[OK]${RESET}    $*"; }
warn()    { printf '%b\n' "${YELLOW}[WARN]${RESET}  $*"; }
error()   { printf '%b\n' "${RED}[FEHLER]${RESET} $*"; }
die()     { error "$*"; exit 1; }

readonly LIBRECHAT_REPO="https://github.com/danny-avila/LibreChat.git"
readonly LIBRECHAT_BRANCH="${LIBRECHAT_BRANCH:-main}"
readonly DEFAULT_INSTALL_DIR="/opt/librechat"
readonly DEFAULT_NPM_NETWORK="shared_proxy"
readonly DOCKER_COMPOSE_GUIDE="https://pc-fee.com/2026/05/03/docker-compose/"
readonly NPM_GUIDE="https://pc-fee.com/2026/05/03/nginx-proxy-manager/"

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "Bitte als root ausfuehren oder sudo installieren."
  SUDO="sudo"
fi

# -----------------------------------------------------------------------------
# Banner
# -----------------------------------------------------------------------------
clear
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
printf '%b\n' "${BOLD} LibreChat Docker Installer – powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo "Installiert LibreChat (inkl. Admin-Panel) hinter einem Nginx Proxy"
echo "Manager via Docker Compose. Kein Port wird an den Host gebunden."
echo "------------------------------------------------------------"

# -----------------------------------------------------------------------------
# Schritt 0: Voraussetzungen pruefen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 0: Voraussetzungen${RESET}"
echo "------------------------------------------------------------"

if command -v git >/dev/null 2>&1; then
  success "git gefunden: $(git --version)"
else
  warn "git ist nicht installiert, wird nachinstalliert."
  command -v apt-get >/dev/null 2>&1 || die "apt-get nicht gefunden (nur Debian 12/13 unterstuetzt)."
  ${SUDO} apt-get install -y git || die "git-Installation fehlgeschlagen."
  command -v git >/dev/null 2>&1 || die "git konnte nicht installiert werden."
  success "git wurde installiert: $(git --version)"
fi

if command -v docker >/dev/null 2>&1; then
  success "Docker gefunden: $(docker --version)"
else
  die "Docker ist nicht installiert. Anleitung: ${DOCKER_COMPOSE_GUIDE}"
fi

if ${SUDO} docker info >/dev/null 2>&1; then
  success "Docker-Daemon laeuft."
else
  die "Docker-Daemon laeuft nicht oder ist nicht erreichbar. Anleitung: ${DOCKER_COMPOSE_GUIDE}"
fi

if ${SUDO} docker compose version >/dev/null 2>&1; then
  success "Docker Compose Plugin gefunden: $(${SUDO} docker compose version --short 2>/dev/null || ${SUDO} docker compose version)"
  COMPOSE_CMD="${SUDO} docker compose"
else
  die "Docker Compose Plugin nicht gefunden. Anleitung: ${DOCKER_COMPOSE_GUIDE}"
fi

if ${SUDO} docker ps --format '{{.Image}}' | grep -qi 'nginx-proxy-manager'; then
  success "Nginx Proxy Manager Container laeuft."
else
  die "Kein laufender Nginx Proxy Manager Container gefunden. Anleitung: ${NPM_GUIDE}"
fi

if ${SUDO} docker network inspect "${DEFAULT_NPM_NETWORK}" >/dev/null 2>&1; then
  success "Docker-Netzwerk '${DEFAULT_NPM_NETWORK}' gefunden."
else
  die "Docker-Netzwerk '${DEFAULT_NPM_NETWORK}' existiert nicht. Anleitung: ${NPM_GUIDE}"
fi

# Bestehende LibreChat-Installation erkennen (Image-Indikator).
# Ein Substring-Filter auf "librechat" allein ist zu unscharf, daher gezielt
# auf die offiziellen Image-Namen pruefen.
EXISTING_IMAGES="$(${SUDO} docker ps -a --format '{{.Names}}\t{{.Image}}' \
  | grep -Ei 'danny-avila/librechat|clickhouse/librechat-admin-panel' || true)"
if [[ -n "${EXISTING_IMAGES}" ]]; then
  error "Es existieren bereits Container einer LibreChat-Installation:"
  echo "${EXISTING_IMAGES}" | sed 's/^/    /'
  echo ""
  echo "  Zum Entfernen der alten Installation (manuell, NICHT durch dieses Skript):"
  echo "    1. cd <altes-installationsverzeichnis>"
  echo "    2. docker compose down -v   (stoppt Container, entfernt zugehoerige Volumes)"
  echo "    3. docker image rm <image>  (fuer jedes oben gelistete Image)"
  die "Abbruch, um eine bestehende Installation nicht versehentlich zu ueberschreiben."
fi

# Installationsverzeichnis pruefen: der tatsaechliche Pfad wird erst in
# Schritt 1 abgefragt, daher hier bewusst nur der Default-Pfad als
# Vorab-Pruefung. Der tatsaechlich gewaehlte Pfad wird nach der Eingabe
# erneut und verbindlich geprueft.
if [[ -e "${DEFAULT_INSTALL_DIR}" ]]; then
  die "Standard-Installationsverzeichnis ${DEFAULT_INSTALL_DIR} existiert bereits. Bitte pruefen/entfernen oder im naechsten Schritt einen anderen Pfad angeben."
fi
success "Kein Standard-Installationsverzeichnis vorgefunden."

# -----------------------------------------------------------------------------
# Schritt 1: Konfiguration abfragen
# -----------------------------------------------------------------------------
is_domain() { [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; }
is_email()  { [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; }
canon_dir() { local d="${1:-}"; d="${d/#\~/$HOME}"; printf '%s' "${d%/}"; }
rand_hex()  { local n="${1:-64}"; openssl rand -hex "$(( (n + 1) / 2 ))" | cut -c1-"${n}"; }
detect_public_ipv4() {
  local ip
  ip="$(curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  [[ -z "${ip}" ]] && ip="$(curl -fsS4 --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  printf '%s' "${ip}"
}

printf '%b\n' "\n${BOLD}Schritt 1: Konfiguration${RESET}"
echo "------------------------------------------------------------"
read -rp "Installationspfad [${DEFAULT_INSTALL_DIR}]: " INSTALL_DIR
INSTALL_DIR="$(canon_dir "${INSTALL_DIR:-${DEFAULT_INSTALL_DIR}}")"
[[ ! -e "${INSTALL_DIR}" ]] || die "${INSTALL_DIR} existiert bereits. Abbruch, um eine bestehende Installation nicht zu ueberschreiben. Bitte pruefen/entfernen oder einen anderen Pfad waehlen."
read -rp "Docker-Netzwerk des Nginx Proxy Managers [${DEFAULT_NPM_NETWORK}]: " NPM_NETWORK
NPM_NETWORK="${NPM_NETWORK:-${DEFAULT_NPM_NETWORK}}"
if [[ "${NPM_NETWORK}" != "${DEFAULT_NPM_NETWORK}" ]]; then
  ${SUDO} docker network inspect "${NPM_NETWORK}" >/dev/null 2>&1 \
    || die "Docker-Netzwerk '${NPM_NETWORK}' existiert nicht. Anleitung: ${NPM_GUIDE}"
  success "Docker-Netzwerk '${NPM_NETWORK}' gefunden."
fi

while :; do read -rp "Chat-Domain (z.B. chat.example.de): " CHAT_DOMAIN; is_domain "${CHAT_DOMAIN}" && break || warn "Ungueltige Domain."; done
while :; do read -rp "Admin-Panel-Domain (z.B. chat-admin.example.de): " ADMIN_DOMAIN; is_domain "${ADMIN_DOMAIN}" && break || warn "Ungueltige Domain."; done
[[ "${CHAT_DOMAIN}" != "${ADMIN_DOMAIN}" ]] || die "Chat- und Admin-Domain muessen verschieden sein."
while :; do read -rp "Admin-E-Mail: " ADMIN_EMAIL; is_email "${ADMIN_EMAIL}" && break || warn "Ungueltige E-Mail."; done
DEFAULT_ADMIN_USERNAME="${ADMIN_EMAIL%%@*}"
read -rp "Admin-Username [${DEFAULT_ADMIN_USERNAME}]: " ADMIN_USERNAME
ADMIN_USERNAME="${ADMIN_USERNAME:-${DEFAULT_ADMIN_USERNAME}}"
read -rp "Admin-Anzeigename [${ADMIN_USERNAME}]: " ADMIN_NAME
ADMIN_NAME="${ADMIN_NAME:-${ADMIN_USERNAME}}"
while :; do
  read -rsp "Admin-Passwort (mind. 12 Zeichen): " ADMIN_PASS; echo
  [[ "${#ADMIN_PASS}" -ge 12 ]] || { warn "Zu kurz."; continue; }
  read -rsp "Wiederholung: " ADMIN_PASS_2; echo
  [[ "${ADMIN_PASS}" == "${ADMIN_PASS_2}" ]] && break || warn "Passwoerter stimmen nicht ueberein."
done

printf '%b\n' "\n${BOLD}Zusammenfassung${RESET}"
echo "------------------------------------------------------------"
printf 'Installationspfad: %s\nChat-Domain:       %s\nAdmin-Domain:      %s\nAdmin-E-Mail:      %s\nRepo-Branch:       %s\nNPM-Netzwerk:      %s\n' \
  "${INSTALL_DIR}" "${CHAT_DOMAIN}" "${ADMIN_DOMAIN}" "${ADMIN_EMAIL}" "${LIBRECHAT_BRANCH}" "${NPM_NETWORK}"
read -rp "Installation starten? [j/N]: " CONFIRM
[[ "${CONFIRM,,}" == "j" ]] || { warn "Abgebrochen (keine oder verneinende Eingabe)."; exit 0; }

# -----------------------------------------------------------------------------
# Schritt 2: Repository holen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 2: LibreChat Repository${RESET}"
echo "------------------------------------------------------------"
# INSTALL_DIR wurde bereits direkt nach der Eingabe auf Nichtexistenz geprueft.
# Zur Sicherheit (z.B. TOCTOU, parallele Ausfuehrung) hier erneut pruefen statt
# ein bestehendes Verzeichnis zu aktualisieren/ueberschreiben.
[[ ! -e "${INSTALL_DIR}" ]] || die "${INSTALL_DIR} existiert bereits. Abbruch, um eine bestehende Installation nicht zu ueberschreiben."
${SUDO} git clone --depth=1 --branch "${LIBRECHAT_BRANCH}" "${LIBRECHAT_REPO}" "${INSTALL_DIR}"
cd "${INSTALL_DIR}"
[[ -f .env.example ]] || die ".env.example fehlt im Repository."
[[ -f docker-compose.yml ]] || die "docker-compose.yml fehlt im Repository."
[[ -f librechat.example.yaml ]] || die "librechat.example.yaml fehlt im Repository."
success "Repository bereit."

# -----------------------------------------------------------------------------
# Schritt 3: .env erzeugen und patchen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 3: .env erzeugen und patchen${RESET}"
echo "------------------------------------------------------------"
if [[ -f .env ]]; then
  ${SUDO} cp .env ".env.bak.$(date +%Y%m%d-%H%M%S)"
  warn "Bestehende .env gesichert und wird aktualisiert."
else
  ${SUDO} cp .env.example .env
fi
${SUDO} chmod 600 .env

CREDS_KEY="$(rand_hex 64)"
CREDS_IV="$(rand_hex 32)"
JWT_SECRET="$(rand_hex 64)"
JWT_REFRESH_SECRET="$(rand_hex 64)"
MEILI_MASTER_KEY="$(rand_hex 32)"
ADMIN_PANEL_SESSION_SECRET="$(rand_hex 64)"

patch_env() {
  local key="$1" value="$2" escaped
  escaped="$(printf '%s' "$value" | sed -e 's/[&|]/\\&/g')"
  if grep -qE "^${key}=" .env; then
    ${SUDO} sed -i "s|^${key}=.*|${key}=${escaped}|" .env
  else
    printf '%s=%s\n' "${key}" "${value}" | ${SUDO} tee -a .env >/dev/null
  fi
}
patch_env DOMAIN_CLIENT "https://${CHAT_DOMAIN}"
patch_env DOMAIN_SERVER "https://${CHAT_DOMAIN}"
patch_env TRUST_PROXY "1"
patch_env ALLOW_REGISTRATION "false"
patch_env CREDS_KEY "${CREDS_KEY}"
patch_env CREDS_IV "${CREDS_IV}"
patch_env JWT_SECRET "${JWT_SECRET}"
patch_env JWT_REFRESH_SECRET "${JWT_REFRESH_SECRET}"
patch_env MEILI_MASTER_KEY "${MEILI_MASTER_KEY}"
patch_env ADMIN_PANEL_SESSION_SECRET "${ADMIN_PANEL_SESSION_SECRET}"
patch_env ADMIN_PANEL_SESSION_COOKIE_SECURE "true"
success ".env geschrieben."

# -----------------------------------------------------------------------------
# Schritt 4: librechat.yaml und docker-compose.override.yml
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 4: librechat.yaml und Compose Override${RESET}"
echo "------------------------------------------------------------"
if [[ ! -f librechat.yaml ]]; then
  ${SUDO} cp librechat.example.yaml librechat.yaml
fi

${SUDO} tee docker-compose.override.yml >/dev/null <<EOF
services:
  api:
    ports: !reset []
    expose:
      - "3080"
    networks:
      - ${NPM_NETWORK}
      - default
    volumes:
      - type: bind
        source: ./librechat.yaml
        target: /app/librechat.yaml
    env_file:
      - .env

  admin-panel:
    ports: !reset []
    expose:
      - "3000"
    networks:
      - ${NPM_NETWORK}
      - default
    environment:
      - VITE_API_BASE_URL=https://${CHAT_DOMAIN}
      - API_SERVER_URL=http://api:3080

networks:
  ${NPM_NETWORK}:
    external: true
EOF

${COMPOSE_CMD} config --quiet
success "librechat.yaml und docker-compose.override.yml ok."

# -----------------------------------------------------------------------------
# Schritt 5: Stack starten
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 5: Stack starten${RESET}"
echo "------------------------------------------------------------"
${COMPOSE_CMD} pull
${COMPOSE_CMD} up -d

wait_running() {
  local service="$1" cid state health
  info "Warte auf Service ${service}..."
  for _ in {1..80}; do
    cid="$(${COMPOSE_CMD} ps -q "${service}" 2>/dev/null || true)"
    if [[ -n "${cid}" ]]; then
      state="$(${SUDO} docker inspect --format '{{.State.Status}}' "${cid}" 2>/dev/null || true)"
      health="$(${SUDO} docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${cid}" 2>/dev/null || true)"
      if [[ "${health}" == "healthy" || ( "${health}" == "none" && "${state}" == "running" ) ]]; then
        success "${service} ist bereit (${state}, health=${health})."
        return 0
      fi
      [[ "${state}" == "exited" || "${state}" == "dead" ]] && break
    fi
    sleep 3
  done
  ${COMPOSE_CMD} ps || true
  ${COMPOSE_CMD} logs --tail=80 "${service}" || true
  die "Service ${service} wurde nicht bereit."
}

wait_running mongodb
wait_running meilisearch
wait_running rag_api
wait_running api
wait_running admin-panel

# -----------------------------------------------------------------------------
# Schritt 6: Admin-User anlegen (kein Registrierungsformular, kein Mailversand)
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 6: Admin-User anlegen${RESET}"
echo "------------------------------------------------------------"
set +e
CREATE_OUTPUT="$(${COMPOSE_CMD} exec -T api node config/create-user.js \
  "${ADMIN_EMAIL}" "${ADMIN_USERNAME}" "${ADMIN_NAME}" "${ADMIN_PASS}" --email-verified=True 2>&1)"
CREATE_RC=$?
set -e
if echo "${CREATE_OUTPUT}" | grep -qiE 'already exists|user exists|duplicate'; then
  warn "Admin-User existiert bereits."
elif [[ ${CREATE_RC} -ne 0 ]]; then
  error "Admin-User konnte nicht automatisch angelegt werden. Ausgabe:"
  echo "${CREATE_OUTPUT}" | sed 's/^/    /'
  warn "Manuell nachholen: cd ${INSTALL_DIR} && ${COMPOSE_CMD} exec api node config/create-user.js <email> <username> <name> <passwort> --email-verified=True"
else
  success "Admin-User angelegt."
fi

echo ""
${COMPOSE_CMD} ps
echo ""
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"
printf '%b\n' "${GREEN}${BOLD}#                                           #${RESET}"
printf '%b\n' "${GREEN}${BOLD}#         Installation erfolgreich          #${RESET}"
printf '%b\n' "${GREEN}${BOLD}#                                           #${RESET}"
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"

HOST_IPV4="$(detect_public_ipv4)"

printf '%b\n' "\n${BLUE}${BOLD}Naechste Schritte${RESET}"
printf '%b\n' "${BLUE}------------------------------------------------------------${RESET}"

if [[ -n "${HOST_IPV4}" ]]; then
cat <<DNS

1) Beim Domain-Provider zwei A-Records auf diesen Host setzen:

   ${HOST_IPV4}   A   (TTL 300)   ${CHAT_DOMAIN}
   ${HOST_IPV4}   A   (TTL 300)   ${ADMIN_DOMAIN}
DNS
else
  warn "Oeffentliche IPv4 konnte nicht automatisch ermittelt werden."
  echo "   Bitte die Server-IP manuell ermitteln und je einen A-Record fuer"
  echo "   ${CHAT_DOMAIN} und ${ADMIN_DOMAIN} beim Domain-Provider anlegen."
fi

CHECK="${GREEN}✓${RESET}"
cat <<NEXT

2) Proxy Hosts im Nginx Proxy Manager anlegen:

   Chat (Reiter Details):
     Domain:             ${CHAT_DOMAIN}
     Forward Hostname:   api
     Forward Port:       3080
NEXT
printf '     Websockets Support: %b\n' "${CHECK}"
cat <<NEXT
   Chat (Reiter SSL):
     SSL Certificate:    Request a new SSL Certificate (Let's Encrypt)
NEXT
printf '     Force SSL:          %b\n' "${CHECK}"
printf '     HTTP/2 Support:     %b\n' "${CHECK}"
printf '     HSTS Enabled:       %b\n' "${CHECK}"
printf '     HSTS Subdomains:    %b  (falls Subdomains genutzt werden)\n' "${CHECK}"
cat <<NEXT

   Admin-Panel (Reiter Details):
     Domain:             ${ADMIN_DOMAIN}
     Forward Hostname:   admin-panel
     Forward Port:       3000
NEXT
printf '     Websockets Support: %b\n' "${CHECK}"
cat <<NEXT
   Admin-Panel (Reiter SSL):
     SSL Certificate:    Request a new SSL Certificate (Let's Encrypt)
NEXT
printf '     Force SSL:          %b\n' "${CHECK}"
printf '     HTTP/2 Support:     %b\n' "${CHECK}"
printf '     HSTS Enabled:       %b\n' "${CHECK}"
printf '     HSTS Subdomains:    %b  (falls Subdomains genutzt werden)\n' "${CHECK}"

cat <<NEXT

3) Login:
   LibreChat:  https://${CHAT_DOMAIN}
   Admin-Panel: https://${ADMIN_DOMAIN}
   Admin-Username: ${ADMIN_USERNAME}
   Admin-Mail: ${ADMIN_EMAIL}
   Admin-Passwort: (wie oben vergeben)

Wichtige Befehle:
  Logs:    cd ${INSTALL_DIR} && ${COMPOSE_CMD} logs -f
  Status:  cd ${INSTALL_DIR} && ${COMPOSE_CMD} ps
  Update:  cd ${INSTALL_DIR} && git pull && ${COMPOSE_CMD} pull && ${COMPOSE_CMD} up -d

GitHub-Referenz:
  https://github.com/nephilim75/scripts/tree/main/librechat/install

NEXT