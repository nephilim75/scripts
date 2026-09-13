#!/usr/bin/env bash
# =============================================================================
# SearXNG Install Script - powered by pc-fee.com
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Installiert eine selbst gehostete SearXNG-Instanz (Metasuchmaschine) via
# Docker Compose im shared_proxy-Netzwerk - aufbauend auf:
# https://pc-fee.com/searxng/
#
# Voraussetzungen:
#   - Docker ist installiert und laeuft
#   - Nginx Proxy Manager laeuft bereits im shared_proxy-Netzwerk
#     Anleitung: https://pc-fee.com/nginx-proxy-manager/
#
# Wichtige Design-Entscheidung dieses Scripts:
#   SearXNGs eingebauter Rate-Limiter/Bot-Schutz (server.limiter) wird
#   ABSICHTLICH DEAKTIVIERT, damit Automatisierungen (z.B. n8n-Agenten, die
#   ueber die JSON-API suchen) niemals ausgebremst oder blockiert werden.
#   Das bedeutet: diese Instanz hat KEINEN eingebauten Schutz vor Missbrauch.
#   Deshalb schreibt dieses Script am Ende einen deutlichen Hinweis, die
#   Web-Oberflaeche zusaetzlich ueber eine Nginx-Proxy-Manager-Access-List
#   (HTTP-Basic-Auth und/oder IP-Allowlist) abzusichern.
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

# -- Konstanten ----------------------------------------------------------------
readonly SEARXNG_GUIDE="https://pc-fee.com/searxng/"
readonly NPM_GUIDE="https://pc-fee.com/nginx-proxy-manager/"
readonly PROXY_NETWORK="shared_proxy"
readonly SEARXNG_IMAGE_REPO="searxng/searxng"

# -- Eingabequelle -------------------------------------------------------------
# Wird das Script per 'curl ... | bash' gestartet, liest bash es von stdin.
# Ein 'read' wuerde dann Zeilen des Scripts selbst verschlucken - Teile des
# Scripts wuerden nie ausgefuehrt. Deshalb IMMER vom Terminal lesen.
# Achtung: '[[ -r /dev/tty ]]' prueft nur die Rechtebits und ist auch dann
# wahr, wenn es gar kein steuerndes Terminal gibt (z.B. Cron). Deshalb wirklich
# oeffnen.
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

ask() {
  # ask <variable> <prompt> <default>
  local var="$1" prompt="$2" default="$3" input=""
  echo ""
  if [[ "${INTERACTIVE}" -eq 1 ]]; then
    echo -ne "${BOLD}${prompt}${RESET} [${CYAN}${default}${RESET}]: "
    read -r input <"${TTY}" || true
  else
    echo -e "${BOLD}${prompt}${RESET}: ${CYAN}${default}${RESET} (Vorgabe, kein Terminal)"
  fi
  printf -v "${var}" '%s' "${input:-${default}}"
}

ask_nodefault() {
  # ask_nodefault <variable> <prompt>
  local var="$1" prompt="$2" input=""
  while [[ -z "$input" ]]; do
    echo ""
    echo -ne "${BOLD}${prompt}${RESET}: "
    [[ "${INTERACTIVE}" -eq 1 ]] || die "Keine Eingabe moeglich (kein Terminal). Bitte Domain vorab per Variable setzen oder Script interaktiv starten."
    read -r input <"${TTY}" || true
    [[ -z "$input" ]] && warn "Eingabe darf nicht leer sein."
  done
  printf -v "${var}" '%s' "${input}"
}

ask_yesno() {
  # ask_yesno <prompt> <default: j|n> -> Rueckgabewert via $? (0 = ja)
  local prompt="$1" default="${2:-n}" input="" hint="j/N"
  [[ "${default,,}" == "j" ]] && hint="J/n"
  echo ""
  if [[ "${INTERACTIVE}" -eq 1 ]]; then
    echo -ne "${BOLD}${prompt}${RESET} [${CYAN}${hint}${RESET}]: "
    read -r input <"${TTY}" || true
  else
    echo -e "${BOLD}${prompt}${RESET}: ${CYAN}${default}${RESET} (Vorgabe, kein Terminal)"
  fi
  input="${input:-${default}}"
  [[ "${input,,}" == "j" || "${input,,}" == "y" ]]
}

generate_secret() {
  # Erzeugt einen 64-stelligen Hex-Secret (256 Bit) fuer server.secret_key.
  if command -v openssl &>/dev/null; then
    openssl rand -hex 32
  else
    tr -dc 'a-f0-9' </dev/urandom | head -c 64
    echo ""
  fi
}

# -- Banner --------------------------------------------------------------------
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
printf '%b\n' "${BOLD} SearXNG Installer - powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo "Installiert eine selbst gehostete SearXNG-Metasuche via Docker Compose"
echo "im Netzwerk '${PROXY_NETWORK}', hinter deinem Nginx Proxy Manager."
echo ""
echo -e "${YELLOW}Hinweis:${RESET} Der eingebaute Rate-Limiter/Bot-Schutz wird bewusst"
echo -e "DEAKTIVIERT, damit Automatisierungen (z.B. n8n) nie ausgebremst werden."
echo -e "Details dazu und zur empfohlenen Absicherung folgen weiter unten."
echo "------------------------------------------------------------"

# -- Root-Check ----------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  die "Bitte als root oder mit sudo ausfuehren."
fi

# Unbedingt in ein garantiert existierendes Verzeichnis wechseln. Wurde das
# Verzeichnis der aufrufenden Shell zwischenzeitlich geloescht, scheitern
# sonst spaetere Aufrufe mit 'getcwd: cannot access parent directories'. Das
# Script nutzt ausschliesslich absolute Pfade.
cd / 2>/dev/null || die "Konnte nicht nach / wechseln."

# -- Voraussetzungen pruefen ---------------------------------------------------
echo ""
echo -e "${BOLD} Voraussetzungen${RESET}"
echo -e "------------------------------------------------------------"

if ! command -v docker &>/dev/null; then
  die "Docker ist nicht installiert.\n\n  Anleitung auf pc-fee.com:\n  https://pc-fee.com/docker-compose/\n\n  Danach dieses Script erneut starten."
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
else
  die "Docker Compose nicht gefunden.\n\n  Anleitung auf pc-fee.com:\n  https://pc-fee.com/docker-compose/"
fi
readonly COMPOSE_CMD
success "Docker Compose gefunden: ${COMPOSE_CMD}"

if ! docker network inspect "${PROXY_NETWORK}" &>/dev/null; then
  die "Docker-Netzwerk '${PROXY_NETWORK}' nicht gefunden.\n\n  Dieses Script setzt einen laufenden Nginx Proxy Manager voraus.\n  Anleitung auf pc-fee.com:\n  ${NPM_GUIDE}\n\n  Danach dieses Script erneut starten."
fi
success "Docker-Netzwerk '${PROXY_NETWORK}' gefunden."

if ! docker ps --format '{{.Image}}' | grep -q 'nginx-proxy-manager'; then
  warn "Es wurde kein laufender Nginx-Proxy-Manager-Container gefunden."
  warn "Ohne NPM ist SearXNG nach der Installation von aussen nicht erreichbar."
  ask_yesno "Trotzdem fortfahren?" "n" || die "Installation abgebrochen."
else
  success "Nginx Proxy Manager laeuft."
fi

# -- Bestehende Installation pruefen -------------------------------------------
if docker ps -a --format '{{.Image}}' | grep -q "${SEARXNG_IMAGE_REPO}"; then
  echo ""
  warn "Es laeuft bereits ein SearXNG-Container."
  echo -e " Dieses Script bricht ab, um eine bestehende Installation nicht zu ueberschreiben."
  echo -e " Zum Aktualisieren siehe update-searxng.sh, zum Entfernen uninstall-searxng.sh."
  die "Installation abgebrochen."
fi

# -- Konfiguration ---------------------------------------------------------------
echo ""
echo -e "${BOLD} Konfiguration${RESET}"
echo -e "------------------------------------------------------------"

ask_nodefault SEARXNG_DOMAIN "Deine SearXNG-Domain (z.B. search.meinedomain.de)"
ask INSTALL_DIR "Installationspfad" "/opt/searxng"
ask SEARXNG_TAG "SearXNG-Image-Tag" "latest"
ask TIMEZONE "Zeitzone" "Europe/Berlin"

echo ""
info "Die JSON-API (/search?format=json) wird fuer Automatisierungen wie n8n"
info "benoetigt und ist standardmaessig nicht freigegeben."
# Unter 'set -e' darf der Rueckgabewert von ask_yesno nicht ungeprueft in $?
# landen - ein 'nein' (Exit-Code 1) wuerde das Script sonst sofort beenden.
# Deshalb ueber if/else abfragen statt '$?' auszulesen.
if ask_yesno "JSON-API zusaetzlich zur HTML-Oberflaeche aktivieren?" "j"; then
  ENABLE_JSON=0
else
  ENABLE_JSON=1
fi

SEARXNG_SECRET=$(generate_secret)
readonly SEARXNG_SECRET

# -- Zusammenfassung -------------------------------------------------------------
echo ""
echo -e "${BOLD} Zusammenfassung${RESET}"
echo -e "------------------------------------------------------------"
echo -e " Domain:             ${CYAN}${SEARXNG_DOMAIN}${RESET}"
echo -e " Installationspfad:  ${CYAN}${INSTALL_DIR}${RESET}"
echo -e " Image-Tag:          ${CYAN}${SEARXNG_TAG}${RESET}"
echo -e " Zeitzone:           ${CYAN}${TIMEZONE}${RESET}"
if [[ "${ENABLE_JSON}" -eq 0 ]]; then
  echo -e " JSON-API:           ${CYAN}aktiviert${RESET} (fuer n8n & Co.)"
else
  echo -e " JSON-API:           ${YELLOW}deaktiviert${RESET} (nur HTML-Oberflaeche)"
fi
echo -e " Secret Key:         ${CYAN}[automatisch generiert]${RESET}"
echo -e " Rate-Limiter:       ${YELLOW}deaktiviert${RESET} (bewusste Entscheidung, siehe oben)"
echo -e " Netzwerk:           ${CYAN}${PROXY_NETWORK}${RESET}"
echo ""
ask_yesno "Alles korrekt? Installation starten?" "j" || { warn "Installation abgebrochen."; exit 0; }

# -- Installation ------------------------------------------------------------
echo ""
echo -e "${BOLD} Installation${RESET}"
echo -e "------------------------------------------------------------"

info "Erstelle Verzeichnisse unter ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}/config" "${INSTALL_DIR}/backups"
success "Verzeichnisse erstellt."

info "Schreibe settings.yml..."
if [[ "${ENABLE_JSON}" -eq 0 ]]; then
  FORMATS_YAML=$'    - html\n    - json'
else
  FORMATS_YAML=$'    - html'
fi
cat > "${INSTALL_DIR}/config/settings.yml" <<EOF
# settings.yml - generiert von pc-fee.com Install-Script
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# use_default_settings: true laedt SearXNGs eingebaute Standardkonfiguration
# (u.a. die komplette Engine-Liste) und laesst nur die hier gesetzten Werte
# darueber greifen. Siehe: https://docs.searxng.org/admin/settings/index.html

use_default_settings: true

general:
  instance_name: "SearXNG (${SEARXNG_DOMAIN})"

server:
  secret_key: "${SEARXNG_SECRET}"
  base_url: "https://${SEARXNG_DOMAIN}/"
  # Bewusst deaktiviert: siehe Kopfkommentar dieses Scripts und die
  # Abschlussmeldung nach der Installation.
  limiter: false
  image_proxy: true

search:
  formats:
${FORMATS_YAML}
EOF
success "settings.yml geschrieben."

info "Schreibe docker-compose.yml..."
cat > "${INSTALL_DIR}/docker-compose.yml" <<EOF
# docker-compose.yml - generiert von pc-fee.com Install-Script
# SearXNG hinter Nginx Proxy Manager
# Mehr Infos: ${SEARXNG_GUIDE}

services:
  searxng:
    image: ${SEARXNG_IMAGE_REPO}:${SEARXNG_TAG}
    container_name: searxng
    restart: unless-stopped
    environment:
      - TZ=${TIMEZONE}
    expose:
      - "8080"
    volumes:
      - ${INSTALL_DIR}/config:/etc/searxng
    networks:
      - ${PROXY_NETWORK}

networks:
  ${PROXY_NETWORK}:
    external: true
EOF
success "docker-compose.yml geschrieben."

info "Starte SearXNG..."
# Bewusst kein 'cd': Wurde das aktuelle Verzeichnis der aufrufenden Shell
# zwischenzeitlich geloescht, scheitert jedes cd mit
# 'getcwd: cannot access parent directories'. Mit -f ist der Compose-Aufruf
# unabhaengig vom Arbeitsverzeichnis.
${COMPOSE_CMD} -f "${INSTALL_DIR}/docker-compose.yml" up -d
success "Container gestartet."

# -- Abschluss -----------------------------------------------------------------
echo ""
echo -e "${BOLD}============================================================${RESET}"
success "SearXNG wurde installiert."
echo -e "${BOLD}============================================================${RESET}"
echo ""
echo -e "${BOLD} Naechste Schritte: Proxy Host in Nginx Proxy Manager${RESET}"
echo -e "------------------------------------------------------------"
echo -e " ${BOLD}Reiter Details${RESET}:"
echo -e "   Domain:             ${CYAN}${SEARXNG_DOMAIN}${RESET}"
echo -e "   Scheme:             ${CYAN}http${RESET}"
echo -e "   Forward Hostname:   ${CYAN}searxng${RESET}"
echo -e "   Forward Port:       ${CYAN}8080${RESET}"
echo -e "   Block Common Exploits aktivieren"
echo -e " ${BOLD}Reiter SSL${RESET}:"
echo -e "   SSL Certificate: Request a new Certificate with Let's Encrypt"
echo -e "   Force SSL, HTTP/2 Support und HSTS aktivieren"
echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "${BOLD} WICHTIG: Kein eingebauter Rate-Limiter/Bot-Schutz${RESET}"
echo -e "${BOLD}============================================================${RESET}"
echo ""
echo -e " Diese Installation laeuft bewusst ${YELLOW}ohne${RESET} SearXNGs Limiter."
echo -e " Vorteil: n8n-Agenten und andere Automatisierungen werden von"
echo -e " SearXNG selbst ${BOLD}nie${RESET} gebremst oder blockiert, egal wie viele"
echo -e " Anfragen sie stellen."
echo -e " Nachteil: Es gibt keinerlei eingebauten Schutz gegen Missbrauch,"
echo -e " falls jemand anderes die URL findet - inklusive der JSON-API."
echo ""
echo -e " ${BOLD}Empfehlung:${RESET} Die Web-Oberflaeche zusaetzlich ueber eine"
echo -e " ${BOLD}Nginx Proxy Manager Access List${RESET} absichern (Basic-Auth"
echo -e " und/oder IP-Allowlist):"
echo -e "   1. NPM-Oberflaeche -> ${CYAN}Access Lists${RESET} -> ${CYAN}Add Access List${RESET}"
echo -e "   2. Nutzer/Passwort und/oder erlaubte IP-Bereiche eintragen"
echo -e "   3. Am Proxy Host von ${CYAN}${SEARXNG_DOMAIN}${RESET} unter ${CYAN}Details${RESET} diese"
echo -e "      Access List auswaehlen"
echo -e "   Deine internen Aufrufer (z.B. n8n im ${PROXY_NETWORK}-Netzwerk, ueber"
echo -e "   ${CYAN}http://searxng:8080${RESET}) sind davon nicht betroffen - eine Access"
echo -e "   List greift nur am Proxy Host, also fuer Zugriffe von aussen."
echo ""
if [[ "${ENABLE_JSON}" -eq 0 ]]; then
  echo -e " JSON-API fuer n8n (HTTP Request Node), z.B. intern:"
  echo -e "   ${CYAN}http://searxng:8080/search?q=<suchbegriff>&format=json${RESET}"
  echo ""
fi
echo -e " Mehr Tipps & Tutorials: ${CYAN}${SEARXNG_GUIDE}${RESET}"
echo -e " GitHub:                 ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
