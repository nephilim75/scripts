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
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

# -- Konstanten ----------------------------------------------------------------
readonly SEARXNG_GUIDE="https://pc-fee.com/searxng/"
readonly NPM_GUIDE="https://pc-fee.com/nginx-proxy-manager/"
readonly PROXY_NETWORK="shared_proxy"
readonly SEARXNG_IMAGE_REPO="searxng/searxng"
readonly UPDATE_SCRIPT_URL="https://raw.githubusercontent.com/nephilim75/scripts/main/searxng/update/update-searxng.sh"

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

detect_public_ipv4() {
  # Oeffentliche IPv4 des Hosts - fuer den A-Record-Hinweis am Ende.
  # Zwei Quellen, damit ein Ausfall eines Dienstes den Hinweis nicht kippt.
  local ip
  ip="$(curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  [[ -z "${ip}" ]] && ip="$(curl -fsS4 --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  printf '%s' "${ip}"
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
info "Optional: Die JSON-API (/search?format=json) wird nur fuer den"
info "programmatischen Zugriff gebraucht - z.B. wenn du in n8n mit"
info "AI-Assistant/Agenten arbeitest und diese im Web suchen sollen,"
info "oder fuer eigene Abfragen per HTTP Request Node. Fuer die reine"
info "Weboberflaeche im Browser wird sie nicht benoetigt."
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
  echo -e " JSON-API:           ${CYAN}aktiviert${RESET} (fuer programmatischen Zugriff)"
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
${COMPOSE_CMD} -f "${INSTALL_DIR}/docker-compose.yml" ps
echo ""
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"
printf '%b\n' "${GREEN}${BOLD}#                                           #${RESET}"
printf '%b\n' "${GREEN}${BOLD}#         Installation erfolgreich          #${RESET}"
printf '%b\n' "${GREEN}${BOLD}#                                           #${RESET}"
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"

HOST_IPV4="$(detect_public_ipv4)"

printf '%b\n' "\n${BLUE}${BOLD}Naechste Schritte${RESET}"
printf '%b\n' "${BLUE}------------------------------------------------------------${RESET}"

CHECK="${GREEN}✓${RESET}"
if [[ -n "${HOST_IPV4}" ]]; then
cat <<DNS

1) Beim Domain-Provider einen A-Record (Alias) auf diesen Host setzen:

   ${HOST_IPV4}   A   (TTL 300)   ${SEARXNG_DOMAIN}

   Das muss VOR Schritt 2 passieren: Let's Encrypt prueft die Domain
   ueber genau diesen Eintrag - ohne ihn schlaegt die Zertifikats-
   ausstellung im Nginx Proxy Manager fehl.
DNS
else
  warn "Oeffentliche IPv4 konnte nicht automatisch ermittelt werden."
cat <<DNS

1) Beim Domain-Provider einen A-Record (Alias) auf diesen Host setzen:

   <Server-IP>   A   (TTL 300)   ${SEARXNG_DOMAIN}

   Server-IP manuell ermitteln (z.B. 'curl -4 ifconfig.me'). Das muss VOR
   Schritt 2 passieren: Let's Encrypt prueft die Domain ueber genau diesen
   Eintrag - ohne ihn schlaegt die Zertifikatsausstellung fehl.
DNS
fi

cat <<NEXT

2) Proxy Host im Nginx Proxy Manager anlegen
   (Hosts -> Proxy Hosts -> Add Proxy Host):

   Reiter Details:
     Domain Names:          ${SEARXNG_DOMAIN}
     Scheme:                http
     Forward Hostname:      searxng
     Forward Port:          8080
NEXT
printf '     Cache Assets:          %b\n' "${CHECK}"
printf '     Block Common Exploits: %b\n' "${CHECK}"
cat <<NEXT

   Reiter SSL:
     SSL Certificate:       Request a new SSL Certificate (Let's Encrypt)
NEXT
printf '     Force SSL:             %b\n' "${CHECK}"
printf '     HTTP/2 Support:        %b\n' "${CHECK}"
printf '     HSTS Enabled:          %b\n' "${CHECK}"
cat <<NEXT

   Erst nach dem Speichern des Proxy Hosts ist die Suche von aussen
   erreichbar - der Container selbst oeffnet keinen Port auf dem Host.

3) Aufrufen:
   Weboberflaeche:  https://${SEARXNG_DOMAIN}
NEXT
if [[ "${ENABLE_JSON}" -eq 0 ]]; then
cat <<NEXT

4) Optional: SearXNG als Websuche fuer n8n AI-Assistant und Agenten

   Diese SearXNG-Instanz ist die Websuche, die der AI-Assistant und
   die Agenten in n8n nutzen koennen, um im Web zu recherchieren.
   Nur relevant, wenn du in n8n damit arbeitest - und auch dann
   optional. Fuer den normalen n8n-Betrieb (Workflows, Nodes,
   Webhooks) wird SearXNG nicht gebraucht.

   Beim Einrichten des AI-Assistenten erscheint der Dialog
   "Add web search" - dort "SearXNG" auswaehlen und diese Instanz
   als Instance URL eintragen:

     n8n laeuft auf DIESEM Server (Netzwerk ${PROXY_NETWORK}):
       Instance URL:  http://searxng:8080

     n8n laeuft woanders (anderer Server, anderes Netz, Cloud):
       Instance URL:  https://${SEARXNG_DOMAIN}

   Ein API-Key wird nicht gebraucht - die Instanz gehoert dir.

   Achtung: Der Dialog hat kein Feld fuer Zugangsdaten. Sicherst du
   die Domain unten per Access List mit Basic-Auth ab, kommt der
   AI-Assistent von aussen nicht mehr durch. Dann entweder die
   interne Instance URL nutzen oder in der Access List mit einer
   IP-Allowlist statt Basic-Auth arbeiten.

5) Optional: JSON-API direkt abfragen (z.B. n8n HTTP Request Node):

     intern:  http://searxng:8080/search?q=<begriff>&format=json
     extern:  https://${SEARXNG_DOMAIN}/search?q=<begriff>&format=json

   Methode GET, Query-Parameter 'q' = Suchbegriff, 'format' = json.
NEXT
else
cat <<NEXT

4) JSON-Format ist deaktiviert
   Die Suche im Browser funktioniert damit ganz normal. Gebraucht
   wird das JSON-Format nur fuer den programmatischen Zugriff -
   etwa als Websuche fuer n8ns AI-Assistant/Agenten oder fuer
   eigene Abfragen per HTTP Request Node.

   Jederzeit nachruestbar: in ${INSTALL_DIR}/config/settings.yml
   unter 'search: formats:' die Zeile '- json' ergaenzen und
   neu starten:
     ${COMPOSE_CMD} -f ${INSTALL_DIR}/docker-compose.yml up -d
NEXT
fi

printf '%b\n' "\n${YELLOW}${BOLD}Wichtig: kein Rate-Limiter aktiv${RESET}"
printf '%b\n' "${YELLOW}------------------------------------------------------------${RESET}"
cat <<LIMITER

Der eingebaute Rate-Limiter/Bot-Schutz ist bewusst deaktiviert, damit
Automatisierungen (z.B. n8n-Agenten) nie ausgebremst oder blockiert werden.
Damit hat die Instanz aber auch keinen eigenen Schutz gegen Missbrauch.

Zugriff von aussen einschraenken (empfohlen):

   1) NPM -> Access Lists -> Add Access List
   2) Basic-Auth-Nutzer und/oder erlaubte IP-Bereiche eintragen
   3) Am Proxy Host ${SEARXNG_DOMAIN} unter Details auswaehlen

Interne Aufrufer im Netzwerk ${PROXY_NETWORK} (http://searxng:8080) sind
davon nicht betroffen - eine Access List greift nur am Proxy Host.
LIMITER

printf '%b\n' "\n${BLUE}${BOLD}Wichtige Befehle${RESET}"
printf '%b\n' "${BLUE}------------------------------------------------------------${RESET}"
cat <<CMDS

  Logs:      ${COMPOSE_CMD} -f ${INSTALL_DIR}/docker-compose.yml logs -f
  Status:    ${COMPOSE_CMD} -f ${INSTALL_DIR}/docker-compose.yml ps
  Neustart:  ${COMPOSE_CMD} -f ${INSTALL_DIR}/docker-compose.yml restart
  Update:    sudo bash -c "\$(curl -fsSL ${UPDATE_SCRIPT_URL})"

Konfiguration:
  ${INSTALL_DIR}/config/settings.yml   (enthaelt den secret_key)
  ${INSTALL_DIR}/docker-compose.yml

Anleitung:
  ${SEARXNG_GUIDE}

GitHub-Referenz:
  https://github.com/nephilim75/scripts/tree/main/searxng/install

CMDS
