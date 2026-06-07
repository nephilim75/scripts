#!/usr/bin/env bash
# =============================================================================
# Nginx Proxy Manager Install Script - powered by pc-fee.com
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Installiert den Nginx Proxy Manager (NPM) via Docker Compose im
# shared_proxy-Netzwerk - aufbauend auf:
# https://pc-fee.com/2026/05/03/nginx-proxy-manager/
#
# Voraussetzungen:
#   - Docker ist installiert und laeuft
#   - Anleitung Docker: https://pc-fee.com/2026/05/03/docker-compose/
#
# Autor: Nils Weber (n8n Automation Architect, pc-fee.com)
#
# AI Transparency: Dieses Script wurde mit Unterstuetzung von KI erstellt
# (Nils Weber, KI-Assistent bei pc-fee.com) und vor Veroeffentlichung geprueft.
# Nutzung auf eigene Gefahr. Backups sind Pflicht.
# =============================================================================
set -euo pipefail

# -- Farben --------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# -- Hilfsfunktionen -----------------------------------------------------------
info()    { echo -e "${CYAN}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[FEHLER]${RESET} $*"; }
die()     { error "$*"; exit 1; }

ask() {
  local var="$1" prompt="$2" default="$3" input
  echo ""
  echo -ne "${BOLD}${prompt}${RESET} [${CYAN}${default}${RESET}]: "
  read -r input
  eval "${var}=\"${input:-${default}}\""
}

ask_nodefault() {
  local var="$1" prompt="$2" input=""
  while [[ -z "$input" ]]; do
    echo ""
    echo -ne "${BOLD}${prompt}${RESET}: "
    read -r input
    [[ -z "$input" ]] && warn "Eingabe darf nicht leer sein."
  done
  eval "${var}=\"${input}\""
}

# -- Header --------------------------------------------------------------------
echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "${BOLD} Nginx Proxy Manager - Installer (pc-fee.com)${RESET}"
echo -e "${BOLD}============================================================${RESET}"

# -- Root-Check ----------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  die "Bitte als root oder mit sudo ausfuehren."
fi

# -- Voraussetzungen pruefen ---------------------------------------------------
echo ""
echo -e "${BOLD} Voraussetzungen${RESET}"
echo -e "------------------------------------------------------------"

# Docker installiert?
if ! command -v docker &>/dev/null; then
  die "Docker ist nicht installiert.\n\n  Anleitung auf pc-fee.com:\n  https://pc-fee.com/2026/05/03/docker-compose/\n\n  Danach dieses Script erneut starten."
fi
success "Docker gefunden: $(docker --version 2>&1)"

# Docker-Daemon laeuft?
if ! docker info &>/dev/null; then
  die "Docker-Daemon laeuft nicht. Bitte starten: sudo systemctl start docker"
fi
success "Docker-Daemon laeuft."

# Docker Compose vorhanden?
if docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
else
  die "Docker Compose nicht gefunden.\n\n  Anleitung auf pc-fee.com:\n  https://pc-fee.com/2026/05/03/docker-compose/"
fi
success "Docker Compose gefunden: ${COMPOSE_CMD}"

# -- Bestehende Installation pruefen -------------------------------------------
if docker ps -a --format '{{.Image}}' | grep -q 'nginx-proxy-manager'; then
  echo ""
  warn "Es laeuft bereits ein Nginx-Proxy-Manager-Container."
  echo -e " Dieses Script bricht ab, um eine bestehende Installation nicht zu ueberschreiben."
  die "Installation abgebrochen."
fi

# -- shared_proxy-Netzwerk -----------------------------------------------------
if ! docker network inspect shared_proxy &>/dev/null; then
  echo ""
  warn "Das Docker-Netzwerk 'shared_proxy' existiert nicht."
  echo -ne " ${BOLD}Jetzt erstellen?${RESET} [${CYAN}j${RESET}/n]: "
  read -r create_net
  if [[ "${create_net,,}" != "n" ]]; then
    docker network create shared_proxy
    success "Netzwerk 'shared_proxy' erstellt."
  else
    die "Netzwerk 'shared_proxy' fehlt. Installation abgebrochen."
  fi
else
  success "Docker-Netzwerk 'shared_proxy' gefunden."
fi

# -- Konfiguration -------------------------------------------------------------
echo ""
echo -e "${BOLD} Konfiguration${RESET}"
echo -e "------------------------------------------------------------"

ask INSTALL_DIR "Installationspfad" "/opt/nginx-proxy-manager"

echo ""
info "Erstinstallation: Port 81 (Adminpanel) wird zunaechst OFFEN gebunden,"
info "damit du das Panel erreichst und einen Proxy Host + SSL einrichten kannst."
info "Danach haertest du die Installation ab (Anleitung folgt am Ende)."
# Erstinstallation immer offen - sonst Henne-Ei-Problem (Panel nicht erreichbar).
PORT81="81:81"

# -- Zusammenfassung -----------------------------------------------------------
echo ""
echo -e "${BOLD} Zusammenfassung${RESET}"
echo -e "------------------------------------------------------------"
echo -e " Installationspfad: ${CYAN}${INSTALL_DIR}${RESET}"
echo -e " Port 80 (HTTP):    ${CYAN}80:80${RESET}"
echo -e " Port 443 (HTTPS):  ${CYAN}443:443${RESET}"
echo -e " Port 81 (Admin):   ${CYAN}${PORT81}${RESET} (offen - wird spaeter abgehaertet)"
echo -e " Netzwerk:          ${CYAN}shared_proxy${RESET}"
echo ""
echo -ne "${BOLD}Alles korrekt? Installation starten?${RESET} [${CYAN}j${RESET}/n]: "
read -r confirm
if [[ "${confirm,,}" == "n" ]]; then
  warn "Installation abgebrochen."
  exit 0
fi

# -- Installation --------------------------------------------------------------
echo ""
echo -e "${BOLD} Installation${RESET}"
echo -e "------------------------------------------------------------"

info "Erstelle Verzeichnisse unter ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}/data" "${INSTALL_DIR}/letsencrypt" "${INSTALL_DIR}/backups"
success "Verzeichnisse erstellt."

info "Schreibe docker-compose.yml..."
cat > "${INSTALL_DIR}/docker-compose.yml" <<EOF
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: always
    ports:
      - '80:80'
      - '${PORT81}'
      - '443:443'
    volumes:
      - ${INSTALL_DIR}/data:/data
      - ${INSTALL_DIR}/letsencrypt:/etc/letsencrypt
    networks:
      - shared_proxy

networks:
  shared_proxy:
    external: true
EOF
success "docker-compose.yml geschrieben."

info "Starte Nginx Proxy Manager..."
cd "${INSTALL_DIR}"
${COMPOSE_CMD} up -d
success "Container gestartet."

# -- Abschluss -----------------------------------------------------------------
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo ""
echo -e "${BOLD}============================================================${RESET}"
success "Nginx Proxy Manager wurde installiert."
echo ""
echo -e " Adminpanel: ${CYAN}http://${SERVER_IP:-SERVER-IP}:81${RESET}"
echo ""
echo -e " Standard-Login (bitte sofort aendern):"
echo -e "   E-Mail:   ${CYAN}admin@example.com${RESET}"
echo -e "   Passwort: ${CYAN}changeme${RESET}"
echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "${BOLD} NAECHSTE SCHRITTE: Security / Hardening${RESET}"
echo -e "${BOLD}============================================================${RESET}"
echo ""
echo -e " Port 81 ist fuer die Ersteinrichtung absichtlich ${YELLOW}offen${RESET}."
echo -e " Bitte fuehre jetzt die Hardening-Schritte aus (SSL, 2FA, Port 81 lokal binden):"
echo -e " ${CYAN}https://pc-fee.com/nginx-proxy-manager/#security${RESET}"
echo ""
echo -e "${BOLD}============================================================${RESET}"
echo ""
