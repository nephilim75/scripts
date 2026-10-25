#!/usr/bin/env bash
# =============================================================================
# Qdrant Install Script - powered by pc-fee.com
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Installiert eine selbst gehostete Qdrant-Vektordatenbank via Docker Compose
# im gemeinsamen Proxy-Netzwerk (Standard: shared_proxy) - gedacht als
# Vector Store fuer n8n (Qdrant Vector Store Node, AI-Agenten, RAG).
#
# Zugriff:
#   - intern im Proxy-Netzwerk:  http://qdrant:6333   (z.B. von n8n)
#   - von aussen ueber deinen Nginx Proxy Manager: https://<domain>
#     inkl. Web-Dashboard unter https://<domain>/dashboard
#   Es wird KEIN Port an den Host gebunden. Nur die REST-API (6333) wird
#   genutzt, gRPC (6334) bleibt ungenutzt und wird nicht freigegeben.
#
# Absicherung:
#   Das Script erzeugt einen Admin-API-Key (QDRANT__SERVICE__API_KEY) und zeigt
#   ihn am Ende EINMAL an. Er liegt danach nur noch in <installpfad>/.env
#   (Rechte 600). Ohne Key waere die Instanz ueber die Domain offen im Netz.
#
# Voraussetzungen:
#   - Docker + Docker Compose sind installiert und laufen
#     Anleitung: https://pc-fee.com/docker-compose/
#   - Nginx Proxy Manager laeuft bereits im Proxy-Netzwerk
#     Anleitung: https://pc-fee.com/nginx-proxy-manager/
#
# Nutzung als 1-Zeiler (von ueberall, kein vorheriger Download noetig):
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/install/install-qdrant.sh)"
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
readonly BLOG_URL="https://pc-fee.com/blog"
readonly DOCKER_GUIDE="https://pc-fee.com/docker-compose/"
readonly NPM_GUIDE="https://pc-fee.com/nginx-proxy-manager/"
readonly QDRANT_IMAGE_REPO="qdrant/qdrant"
readonly NPM_IMAGE_MARKER="jc21/nginx-proxy-manager"
readonly CONTAINER_NAME="qdrant"
readonly DEFAULT_INSTALL_DIR="/opt/qdrant"
readonly DEFAULT_BACKUP_DIR="/opt/qdrant-backups"
readonly DEFAULT_NETWORK="shared_proxy"
readonly REPO_RAW="https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant"
readonly UPDATE_SCRIPT_URL="${REPO_RAW}/update/update-qdrant.sh"
readonly BACKUP_SCRIPT_URL="${REPO_RAW}/backup/backup-qdrant.sh"
readonly UNINSTALL_SCRIPT_URL="${REPO_RAW}/uninstall/uninstall-qdrant.sh"

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
    [[ "${INTERACTIVE}" -eq 1 ]] || die "Keine Eingabe moeglich (kein Terminal). Bitte das Script interaktiv starten."
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

is_domain() { [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; }

generate_secret() {
  # 64 Hex-Zeichen (256 Bit) fuer den Admin-API-Key.
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

latest_qdrant_release() {
  # Neueste stabile Qdrant-Version (vX.Y.Z) ermitteln - erst ueber die GitHub-
  # Releases, bei Ausfall ueber die Docker-Hub-Tags. Nur reine vX.Y.Z-Tags
  # zaehlen (keine -rc, -unprivileged, gpu-... Varianten).
  local tags=""
  tags="$(curl -fsSL --max-time 15 -H 'Accept: application/vnd.github+json' \
            'https://api.github.com/repos/qdrant/qdrant/releases?per_page=30' 2>/dev/null \
          | grep -oE '"tag_name": *"v[0-9]+\.[0-9]+\.[0-9]+"' \
          | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || true)"
  if [[ -z "${tags}" ]]; then
    tags="$(curl -fsSL --max-time 15 \
              'https://hub.docker.com/v2/repositories/qdrant/qdrant/tags?page_size=100&ordering=last_updated' 2>/dev/null \
            | grep -oE '"name": *"v[0-9]+\.[0-9]+\.[0-9]+"' \
            | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || true)"
  fi
  [[ -n "${tags}" ]] && printf '%s\n' "${tags}" | sort -uV | tail -n 1
  return 0
}

container_ip() {
  # IP des Containers im Proxy-Netzwerk. Der Host erreicht Container in einem
  # Bridge-Netzwerk direkt ueber diese IP - ohne dass ein Port gebunden wird.
  docker inspect -f "{{with index .NetworkSettings.Networks \"${PROXY_NETWORK}\"}}{{.IPAddress}}{{end}}" "${CONTAINER_NAME}" 2>/dev/null || true
}

# -- Banner --------------------------------------------------------------------
clear 2>/dev/null || true
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
printf '%b\n' "${BOLD} Qdrant Installer - powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo "Installiert die Vektordatenbank Qdrant via Docker Compose im gemeinsamen"
echo "Proxy-Netzwerk, hinter deinem Nginx Proxy Manager - z.B. als Vector Store"
echo "fuer n8n. Es wird kein Port an den Host gebunden."
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

# -- Schritt 0: Voraussetzungen ------------------------------------------------
echo ""
echo -e "${BOLD} Schritt 0: Voraussetzungen${RESET}"
echo -e "------------------------------------------------------------"

if ! command -v docker &>/dev/null; then
  die "Docker ist nicht installiert.\n\n  Anleitung auf pc-fee.com:\n  ${DOCKER_GUIDE}\n\n  Danach dieses Script erneut starten."
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
  die "Docker Compose nicht gefunden.\n\n  Anleitung auf pc-fee.com:\n  ${DOCKER_GUIDE}"
fi
readonly COMPOSE_CMD
success "Docker Compose gefunden: ${COMPOSE_CMD}"

# curl wird fuer die Versionsabfrage und den Funktionstest nach dem Start
# gebraucht. Nicht automatisch installieren - nur nach Zustimmung.
if ! command -v curl &>/dev/null; then
  warn "'curl' ist nicht installiert - es wird fuer Versionsabfrage und Funktionstest gebraucht."
  if command -v apt-get &>/dev/null && ask_yesno "curl jetzt per apt-get installieren?" "j"; then
    apt-get update -qq && apt-get install -y -qq curl >/dev/null
    success "curl installiert."
  else
    die "Bitte curl installieren und das Script erneut starten."
  fi
else
  success "curl gefunden."
fi

# NPM-Container und Netzwerk werden EINZELN geprueft: ein vorhandenes
# Netzwerk allein sagt nichts darueber, ob NPM auch wirklich laeuft.
if docker ps --format '{{.Image}}' | grep -q "${NPM_IMAGE_MARKER}"; then
  success "Nginx Proxy Manager laeuft."
  NPM_RUNNING=1
else
  warn "Es wurde kein laufender Nginx-Proxy-Manager-Container gefunden."
  warn "Ohne NPM ist Qdrant nur intern im Proxy-Netzwerk erreichbar,"
  warn "nicht ueber deine Domain und nicht ueber das Web-Dashboard."
  echo -e "  Anleitung: ${CYAN}${NPM_GUIDE}${RESET}"
  ask_yesno "Trotzdem fortfahren?" "n" || die "Installation abgebrochen."
  NPM_RUNNING=0
fi
readonly NPM_RUNNING

# Bestehende Installation ueber den Image-Marker erkennen, nicht ueber einen
# Namens-Grep (ein Container namens 'qdrant-xyz' muss nichts mit Qdrant zu
# tun haben, ein Qdrant-Container kann beliebig heissen).
EXISTING=$(docker ps -a --format '{{.Names}} {{.Image}}' | awk -v img="${QDRANT_IMAGE_REPO}" 'index($2, img) == 1 {print $1}' || true)
if [[ -n "${EXISTING}" ]]; then
  echo ""
  warn "Es existiert bereits ein Qdrant-Container:"
  while IFS= read -r c; do [[ -n "$c" ]] && echo -e "   - ${CYAN}${c}${RESET}"; done <<<"${EXISTING}"
  echo -e " Dieses Script bricht ab, um eine bestehende Installation nicht zu ueberschreiben."
  echo -e " Aktualisieren:  ${CYAN}sudo bash -c \"\$(curl -fsSL ${UPDATE_SCRIPT_URL})\"${RESET}"
  echo -e " Entfernen:      ${CYAN}sudo bash -c \"\$(curl -fsSL ${UNINSTALL_SCRIPT_URL})\"${RESET}"
  die "Installation abgebrochen."
fi
success "Keine bestehende Qdrant-Installation gefunden."

if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
  die "Es gibt bereits einen Container mit dem Namen '${CONTAINER_NAME}' (kein Qdrant-Image).\n  Bitte zuerst umbenennen oder entfernen - der Name wird als Hostname im Proxy-Netzwerk gebraucht."
fi

# -- Schritt 1: Konfiguration --------------------------------------------------
echo ""
echo -e "${BOLD} Schritt 1: Konfiguration${RESET}"
echo -e "------------------------------------------------------------"

while true; do
  ask_nodefault QDRANT_DOMAIN "Deine Qdrant-Domain (z.B. qdrant.meinedomain.de)"
  QDRANT_DOMAIN="${QDRANT_DOMAIN,,}"
  is_domain "${QDRANT_DOMAIN}" && break
  warn "Ungueltige Domain: '${QDRANT_DOMAIN}' (erwartet z.B. qdrant.meinedomain.de, ohne https://)."
done

while true; do
  ask INSTALL_DIR "Installationspfad" "${DEFAULT_INSTALL_DIR}"
  INSTALL_DIR="${INSTALL_DIR%/}"
  if [[ "${INSTALL_DIR}" != /* ]]; then
    warn "Bitte einen absoluten Pfad angeben (beginnend mit /)."
  elif [[ -e "${INSTALL_DIR}" ]] && [[ -n "$(ls -A "${INSTALL_DIR}" 2>/dev/null)" ]]; then
    warn "${INSTALL_DIR} existiert bereits und ist nicht leer - bitte einen anderen Pfad waehlen."
    warn "(Bestehende Daten werden von diesem Script nie ueberschrieben.)"
  else
    break
  fi
done

while true; do
  ask BACKUP_DIR "Backup-Verzeichnis (fuer Update- und Snapshot-Backups)" "${DEFAULT_BACKUP_DIR}"
  BACKUP_DIR="${BACKUP_DIR%/}"
  if [[ "${BACKUP_DIR}" != /* ]]; then
    warn "Bitte einen absoluten Pfad angeben (beginnend mit /)."
  elif [[ "${BACKUP_DIR}" == "${INSTALL_DIR}" || "${BACKUP_DIR}" == "${INSTALL_DIR}/"* ]]; then
    warn "Das Backup-Verzeichnis darf nicht im Installationsverzeichnis liegen"
    warn "(sonst wuerde es beim Deinstallieren mitgeloescht und beim Update mitgesichert)."
  else
    break
  fi
done

while true; do
  ask PROXY_NETWORK "Docker-Netzwerk des Nginx Proxy Managers" "${DEFAULT_NETWORK}"
  if docker network inspect "${PROXY_NETWORK}" &>/dev/null; then
    break
  fi
  warn "Docker-Netzwerk '${PROXY_NETWORK}' existiert nicht."
  NPM_NETS=$(docker ps --format '{{.ID}} {{.Image}}' | awk -v img="${NPM_IMAGE_MARKER}" 'index($2, img) {print $1}' \
    | xargs -r docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null | tr ' ' '\n' | grep -v '^$' | sort -u || true)
  if [[ -n "${NPM_NETS}" ]]; then
    info "Dein Nginx Proxy Manager haengt an diesen Netzwerken: $(echo "${NPM_NETS}" | tr '\n' ' ')"
  fi
  [[ "${INTERACTIVE}" -eq 1 ]] || die "Netzwerk '${PROXY_NETWORK}' fehlt.\n  Anleitung Nginx Proxy Manager: ${NPM_GUIDE}"
done
readonly PROXY_NETWORK
success "Docker-Netzwerk '${PROXY_NETWORK}' gefunden."

if [[ "${NPM_RUNNING}" -eq 1 ]]; then
  NPM_ON_NET=$(docker network inspect "${PROXY_NETWORK}" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || true)
  NPM_NAMES=$(docker ps --format '{{.Names}} {{.Image}}' | awk -v img="${NPM_IMAGE_MARKER}" 'index($2, img) {print $1}')
  found=0
  for n in ${NPM_NAMES}; do
    [[ " ${NPM_ON_NET} " == *" ${n} "* ]] && found=1
  done
  if [[ "${found}" -eq 0 ]]; then
    warn "Der Nginx Proxy Manager haengt NICHT am Netzwerk '${PROXY_NETWORK}'."
    warn "Er koennte Qdrant dann nicht ueber den Hostnamen '${CONTAINER_NAME}' erreichen."
    ask_yesno "Trotzdem mit diesem Netzwerk fortfahren?" "n" || die "Installation abgebrochen."
  fi
fi

info "Ermittle die neueste stabile Qdrant-Version..."
LATEST_TAG="$(latest_qdrant_release)"
if [[ -n "${LATEST_TAG}" ]]; then
  success "Neueste Version: ${LATEST_TAG}"
  TAG_DEFAULT="${LATEST_TAG}"
else
  warn "Die neueste Version konnte nicht ermittelt werden (GitHub und Docker Hub nicht erreichbar)."
  warn "Als Vorgabe wird 'latest' angeboten. Empfohlen ist eine feste Version (z.B. v1.19.2),"
  warn "damit das Update-Script die Versionsschritte sauber planen kann."
  TAG_DEFAULT="latest"
fi
echo ""
info "Eine feste Version (vX.Y.Z) ist empfohlen: Qdrant-Updates duerfen keine"
info "Minor-Version ueberspringen, das Update-Script plant die Schritte dann selbst."
while true; do
  ask QDRANT_TAG "Qdrant-Image-Tag" "${TAG_DEFAULT}"
  [[ "${QDRANT_TAG}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] && break
  warn "Ungueltiges Image-Tag: '${QDRANT_TAG}'."
done

echo ""
info "Qdrant sendet standardmaessig anonyme Nutzungsstatistiken (Telemetrie) an"
info "den Hersteller. Inhalte deiner Collections werden dabei nicht uebertragen."
if ask_yesno "Telemetrie deaktivieren?" "j"; then
  TELEMETRY_DISABLED="true"
else
  TELEMETRY_DISABLED="false"
fi

QDRANT_API_KEY="$(generate_secret)"
[[ "${#QDRANT_API_KEY}" -ge 32 ]] || die "API-Key konnte nicht erzeugt werden."
readonly QDRANT_API_KEY

# -- Zusammenfassung -----------------------------------------------------------
echo ""
echo -e "${BOLD} Zusammenfassung${RESET}"
echo -e "------------------------------------------------------------"
echo -e " Domain:             ${CYAN}${QDRANT_DOMAIN}${RESET}"
echo -e " Installationspfad:  ${CYAN}${INSTALL_DIR}${RESET}"
echo -e " Backup-Verzeichnis: ${CYAN}${BACKUP_DIR}${RESET}"
echo -e " Netzwerk:           ${CYAN}${PROXY_NETWORK}${RESET}"
echo -e " Image:              ${CYAN}${QDRANT_IMAGE_REPO}:${QDRANT_TAG}${RESET}"
echo -e " Container/Hostname: ${CYAN}${CONTAINER_NAME}${RESET} (intern: http://${CONTAINER_NAME}:6333)"
echo -e " API:                ${CYAN}nur REST (6333)${RESET}, kein gRPC, kein Host-Port"
echo -e " Admin-API-Key:      ${CYAN}[automatisch generiert, wird am Ende angezeigt]${RESET}"
if [[ "${TELEMETRY_DISABLED}" == "true" ]]; then
  echo -e " Telemetrie:         ${CYAN}deaktiviert${RESET}"
else
  echo -e " Telemetrie:         ${YELLOW}aktiv${RESET}"
fi
echo ""
ask_yesno "Alles korrekt? Installation starten?" "j" || { warn "Installation abgebrochen. Es wurde nichts veraendert."; exit 0; }

# -- Schritt 2: Installation ---------------------------------------------------
echo ""
echo -e "${BOLD} Schritt 2: Installation${RESET}"
echo -e "------------------------------------------------------------"

# Image zuerst laden: ein falsches Tag soll scheitern, BEVOR etwas auf der
# Platte angelegt wurde.
info "Lade Image ${QDRANT_IMAGE_REPO}:${QDRANT_TAG}..."
if ! docker pull "${QDRANT_IMAGE_REPO}:${QDRANT_TAG}"; then
  die "Image ${QDRANT_IMAGE_REPO}:${QDRANT_TAG} konnte nicht geladen werden.\n  Tag pruefen: https://hub.docker.com/r/qdrant/qdrant/tags\n  Es wurde nichts veraendert."
fi
success "Image geladen."

info "Erstelle Verzeichnisse..."
mkdir -p "${INSTALL_DIR}/storage" "${INSTALL_DIR}/snapshots"
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"
success "Verzeichnisse erstellt: ${INSTALL_DIR}/{storage,snapshots}, ${BACKUP_DIR}"

info "Schreibe .env (enthaelt den API-Key, Rechte 600)..."
umask 077
cat > "${INSTALL_DIR}/.env" <<EOF
# .env - generiert von pc-fee.com Install-Script ($(date '+%F %T'))
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Enthaelt den Admin-API-Key - wie ein Passwort behandeln.
# Aenderungen hier wirken erst nach einer Neuerstellung des Containers:
#   ${COMPOSE_CMD} -f ${INSTALL_DIR}/docker-compose.yml up -d
# (ein 'docker restart qdrant' uebernimmt geaenderte Werte NICHT).

QDRANT_API_KEY=${QDRANT_API_KEY}
QDRANT_TELEMETRY_DISABLED=${TELEMETRY_DISABLED}

# Von den pc-fee.com-Scripts (Update/Backup/Uninstall) gelesen:
QDRANT_DOMAIN=${QDRANT_DOMAIN}
QDRANT_BACKUP_DIR=${BACKUP_DIR}
EOF
umask 022
chmod 600 "${INSTALL_DIR}/.env"
success ".env geschrieben."

info "Schreibe docker-compose.yml..."
cat > "${INSTALL_DIR}/docker-compose.yml" <<EOF
# docker-compose.yml - generiert von pc-fee.com Install-Script
# Qdrant hinter Nginx Proxy Manager, ohne Host-Ports.
# https://pc-fee.com | https://github.com/nephilim75/scripts

services:
  qdrant:
    image: ${QDRANT_IMAGE_REPO}:${QDRANT_TAG}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    environment:
      - QDRANT__SERVICE__API_KEY=\${QDRANT_API_KEY}
      - QDRANT__TELEMETRY_DISABLED=\${QDRANT_TELEMETRY_DISABLED}
    # Nur die REST-API - gRPC (6334) wird bewusst nicht genutzt.
    expose:
      - "6333"
    volumes:
      - ${INSTALL_DIR}/storage:/qdrant/storage
      - ${INSTALL_DIR}/snapshots:/qdrant/snapshots
    networks:
      - ${PROXY_NETWORK}

networks:
  ${PROXY_NETWORK}:
    external: true
EOF
success "docker-compose.yml geschrieben."

if ! ${COMPOSE_CMD} -f "${INSTALL_DIR}/docker-compose.yml" config --quiet; then
  die "Die erzeugte Compose-Konfiguration ist ungueltig - bitte ${INSTALL_DIR}/docker-compose.yml pruefen."
fi

info "Starte Qdrant..."
# Bewusst kein 'cd': Mit -f ist der Compose-Aufruf unabhaengig vom
# Arbeitsverzeichnis. Die .env wird neben der Compose-Datei gefunden.
${COMPOSE_CMD} -f "${INSTALL_DIR}/docker-compose.yml" up -d
success "Container gestartet."

# -- Schritt 3: Funktionstest --------------------------------------------------
echo ""
echo -e "${BOLD} Schritt 3: Funktionstest${RESET}"
echo -e "------------------------------------------------------------"

QDRANT_IP=""
READY=0
for _ in $(seq 1 60); do
  QDRANT_IP="$(container_ip)"
  if [[ -n "${QDRANT_IP}" ]] && curl -fsS --max-time 3 "http://${QDRANT_IP}:6333/readyz" >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 1
done

RUNNING_VERSION=""
if [[ "${READY}" -eq 1 ]]; then
  success "Qdrant ist bereit (${QDRANT_IP}:6333 im Netzwerk ${PROXY_NETWORK})."
  RUNNING_VERSION="$(curl -fsS --max-time 5 "http://${QDRANT_IP}:6333/" 2>/dev/null | grep -oE '"version": *"[^"]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^"]*' || true)"
  [[ -n "${RUNNING_VERSION}" ]] && success "Laufende Version: ${RUNNING_VERSION}"
  CODE_NOKEY="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://${QDRANT_IP}:6333/collections" || true)"
  CODE_KEY="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H "api-key: ${QDRANT_API_KEY}" "http://${QDRANT_IP}:6333/collections" || true)"
  if [[ "${CODE_NOKEY}" == "401" && "${CODE_KEY}" == "200" ]]; then
    success "API-Key aktiv: ohne Key 401, mit Key 200."
  else
    warn "API-Key-Pruefung unerwartet (ohne Key: ${CODE_NOKEY}, mit Key: ${CODE_KEY})."
    warn "Bitte die Logs pruefen: ${COMPOSE_CMD} -f ${INSTALL_DIR}/docker-compose.yml logs"
  fi
else
  warn "Qdrant hat sich nach 60 Sekunden nicht als bereit gemeldet."
  warn "Bitte die Logs pruefen: ${COMPOSE_CMD} -f ${INSTALL_DIR}/docker-compose.yml logs"
fi

# -- Abschluss -----------------------------------------------------------------
echo ""
${COMPOSE_CMD} -f "${INSTALL_DIR}/docker-compose.yml" ps
echo ""
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"
printf '%b\n' "${GREEN}${BOLD}#                                           #${RESET}"
printf '%b\n' "${GREEN}${BOLD}#         Installation erfolgreich          #${RESET}"
printf '%b\n' "${GREEN}${BOLD}#                                           #${RESET}"
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"

printf '%b\n' "\n${YELLOW}${BOLD}Dein Admin-API-Key - jetzt sicher speichern!${RESET}"
printf '%b\n' "${YELLOW}------------------------------------------------------------${RESET}"
echo ""
echo -e "   ${BOLD}${QDRANT_API_KEY}${RESET}"
echo ""
echo "   Dieser Key wird nur JETZT angezeigt und nirgendwo protokolliert."
echo "   Er liegt ausserdem in ${INSTALL_DIR}/.env (nur fuer root lesbar)."
echo "   Am besten gleich im Passwort-Manager ablegen."

HOST_IPV4="$(detect_public_ipv4)"

printf '%b\n' "\n${BLUE}${BOLD}Naechste Schritte${RESET}"
printf '%b\n' "${BLUE}------------------------------------------------------------${RESET}"

CHECK="${GREEN}✓${RESET}"
CROSS="${RED}✗${RESET}"
if [[ -n "${HOST_IPV4}" ]]; then
cat <<DNS

1) Beim Domain-Provider einen A-Record auf diesen Host setzen:

   ${HOST_IPV4}   A   (TTL 300)   ${QDRANT_DOMAIN}

   Das muss VOR Schritt 2 passieren: Let's Encrypt prueft die Domain
   ueber genau diesen Eintrag - ohne ihn schlaegt die Zertifikats-
   ausstellung im Nginx Proxy Manager fehl.
DNS
else
  warn "Oeffentliche IPv4 konnte nicht automatisch ermittelt werden."
cat <<DNS

1) Beim Domain-Provider einen A-Record auf diesen Host setzen:

   <Server-IP>   A   (TTL 300)   ${QDRANT_DOMAIN}

   Server-IP manuell ermitteln (z.B. 'curl -4 ifconfig.me'). Das muss VOR
   Schritt 2 passieren: Let's Encrypt prueft die Domain ueber genau diesen
   Eintrag - ohne ihn schlaegt die Zertifikatsausstellung fehl.
DNS
fi

cat <<NEXT

2) Proxy Host im Nginx Proxy Manager anlegen
   (Hosts -> Proxy Hosts -> Add Proxy Host):

   Reiter Details:
     Domain Names:          ${QDRANT_DOMAIN}
     Scheme:                http
     Forward Hostname:      ${CONTAINER_NAME}
     Forward Port:          6333
NEXT
printf '     Cache Assets:          %b\n' "${CROSS}"
printf '     Block Common Exploits: %b\n' "${CHECK}"
printf '     Websockets Support:    %b\n' "${CROSS}"
cat <<NEXT

   Reiter SSL:
     SSL Certificate:       Request a new SSL Certificate (Let's Encrypt)
NEXT
printf '     Force SSL:             %b\n' "${CHECK}"
printf '     HTTP/2 Support:        %b\n' "${CHECK}"
printf '     HSTS Enabled:          %b\n' "${CHECK}"
cat <<NEXT

   Erst nach dem Speichern des Proxy Hosts ist Qdrant von aussen
   erreichbar - der Container selbst oeffnet keinen Port auf dem Host.

3) Web-Dashboard aufrufen:

     https://${QDRANT_DOMAIN}/dashboard

   Das Dashboard fragt nach dem API-Key (siehe oben).

4) Qdrant in n8n einbinden
   (Credentials -> Add Credential -> "Qdrant API"):

     n8n laeuft auf DIESEM Server (Netzwerk ${PROXY_NETWORK}):
       Qdrant URL:  http://${CONTAINER_NAME}:6333
     n8n laeuft woanders (anderer Server, Cloud):
       Qdrant URL:  https://${QDRANT_DOMAIN}

       API Key:     <der Admin-API-Key von oben>

   Die interne URL ist schneller und unabhaengig vom Proxy - sie
   funktioniert nur, wenn der n8n-Container ebenfalls am Netzwerk
   ${PROXY_NETWORK} haengt.
NEXT

printf '%b\n' "\n${BLUE}${BOLD}Wichtige Befehle${RESET}"
printf '%b\n' "${BLUE}------------------------------------------------------------${RESET}"
cat <<CMDS

  Logs:      ${COMPOSE_CMD} -f ${INSTALL_DIR}/docker-compose.yml logs -f
  Status:    ${COMPOSE_CMD} -f ${INSTALL_DIR}/docker-compose.yml ps
  Neustart:  ${COMPOSE_CMD} -f ${INSTALL_DIR}/docker-compose.yml restart
  Update:    sudo bash -c "\$(curl -fsSL ${UPDATE_SCRIPT_URL})"
  Backup:    sudo bash -c "\$(curl -fsSL ${BACKUP_SCRIPT_URL})"

  Nach Aenderungen an der .env (z.B. neuer API-Key) den Container neu
  erstellen - ein 'docker restart' uebernimmt die Werte NICHT:
    ${COMPOSE_CMD} -f ${INSTALL_DIR}/docker-compose.yml up -d

Dateien:
  ${INSTALL_DIR}/docker-compose.yml
  ${INSTALL_DIR}/.env         - enthaelt den API-Key
  ${INSTALL_DIR}/storage/     - alle Collections
  ${INSTALL_DIR}/snapshots/   - Arbeitsordner fuer Snapshots
  ${BACKUP_DIR}/   - Backups der Update- und Backup-Scripts

Mehr Tipps & Tutorials:
  ${BLOG_URL}

GitHub-Referenz:
  https://github.com/nephilim75/scripts/tree/main/qdrant/install

CMDS
