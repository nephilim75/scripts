#!/usr/bin/env bash
# =============================================================================
# Nginx Proxy Manager Auto-Install Script - powered by pc-fee.com
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Installiert den Nginx Proxy Manager (NPM) via Docker Compose im
# gewuenschten Docker-Netzwerk, legt automatisch einen Admin-Account an,
# erstellt den ersten Proxy Host fuer die Admin-Domain mit SSL und bindet
# Port 81 abschliessend lokal.
#
# Aufbauend auf:
# https://pc-fee.com/2026/05/03/nginx-proxy-manager/
#
# Voraussetzungen:
#   - Docker ist installiert und laeuft
#   - Anleitung Docker: https://pc-fee.com/2026/05/03/docker-compose/
#   - DNS A-Record fuer die Admin-Domain zeigt auf die oeffentliche Server-IPv4
#   - Ports 80 und 443 sind frei und von aussen erreichbar
#
# Nutzung als 1-Zeiler (von ueberall, kein vorheriger Download noetig):
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/install/install-npm.sh)"
#
# Updates (auf neue NPM-Versionen): update-npm.sh
# Entfernen:                        uninstall-npm.sh
#
# Getestete NPM-Version: siehe NPM_VERSION (per Umgebungsvariable ueberschreibbar,
# z. B. NPM_VERSION=2.15.1 bash install.sh). Die API-Aufrufe sind auf diese
# Version abgestimmt; mit anderen Versionen bitte vorher testen.
#
# Herausgeber: pc-fee.com
#
# AI Transparency: Dieses Script wurde mit Unterstuetzung von KI erstellt.
# "Nils Weber" ist die KI-Assistenz-Persona von pc-fee.com (n8n Automation
# Architect), kein menschlicher Autor. Das Script wurde vor Veroeffentlichung
# geprueft. Nutzung auf eigene Gefahr. Backups sind Pflicht.
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
readonly NPM_GUIDE="https://pc-fee.com/2026/05/03/nginx-proxy-manager/"
readonly DOCKER_COMPOSE_GUIDE="https://pc-fee.com/2026/05/03/docker-compose/"
readonly NPM_VERSION="${NPM_VERSION:-2.15.1}"
readonly NPM_IMAGE="jc21/nginx-proxy-manager:${NPM_VERSION}"
readonly NPM_CONTAINER_NAME="nginx-proxy-manager"
readonly NPM_API="http://127.0.0.1:81"

# -- Eingabequelle -------------------------------------------------------------
if [[ -r /dev/tty ]] && { : <>/dev/tty; } 2>/dev/null; then
  TTY=/dev/tty
  INTERACTIVE=1
else
  TTY=/dev/null
  INTERACTIVE=0
fi
readonly TTY INTERACTIVE

# -- Temporaeres Arbeitsverzeichnis (nur root-lesbar, wird immer entfernt) ------
umask 077
WORK_DIR="$(mktemp -d)"
readonly WORK_DIR
cleanup() { rm -rf "${WORK_DIR}"; }
trap cleanup EXIT

# -- Hilfsfunktionen -----------------------------------------------------------
info()    { echo -e "${CYAN}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[FEHLER]${RESET} $*"; }
die()     { error "$*"; exit 1; }

ask() {
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
  local var="$1" prompt="$2" input=""
  [[ "${INTERACTIVE}" -eq 1 ]] || die "Keine Eingabe moeglich (kein Terminal)."
  while [[ -z "$input" ]]; do
    echo ""
    echo -ne "${BOLD}${prompt}${RESET}: "
    read -r input <"${TTY}" || true
    [[ -z "$input" ]] && warn "Eingabe darf nicht leer sein."
  done
  printf -v "${var}" '%s' "${input}"
}

ask_yesno() {
  local var="$1" prompt="$2" default="$3" input=""
  echo ""
  while true; do
    echo -ne "${BOLD}${prompt}${RESET} [j/n, Vorgabe ${CYAN}${default}${RESET}]: "
    if [[ "${INTERACTIVE}" -eq 1 ]]; then
      read -r input <"${TTY}" || true
    else
      echo "(kein Terminal, verwende Vorgabe)"
    fi
    input="${input:-${default}}"
    input="${input,,}"
    case "$input" in
      j|ja)   printf -v "${var}" '%s' "1"; return 0 ;;
      n|nein) printf -v "${var}" '%s' "0"; return 0 ;;
    esac
    warn "Bitte 'j' oder 'n' eingeben."
    input=""
  done
}

is_domain() {
  [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,63}$ ]]
}

# Bewusst einfache, aber strikte Pruefung: verhindert Platzhalter wie *.tld,
# Leerzeichen und Anfuehrungszeichen (die sonst das JSON/YAML brechen wuerden).
is_email() {
  local e="$1"
  [[ "$e" =~ ^[a-z0-9._%+-]+@([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] || return 1
  case "${e##*.}" in
    tld|local|localhost|example|invalid|test|lan|home|internal) return 1 ;;
  esac
  case "${e#*@}" in
    deine-domain.*|example.com|example.org|example.net) return 1 ;;
  esac
  return 0
}

is_ipv4() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

# Verhindert, dass rm -rf / backup auf Systempfade losgelassen wird.
is_safe_dir() {
  local p
  [[ -n "${1:-}" && "$1" == /* && "$1" != *".."* ]] || return 1
  p="$(realpath -m -- "$1")"
  case "$p" in
    /|/bin|/boot|/dev|/etc|/home|/lib|/lib32|/lib64|/media|/mnt|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/usr/*|/var|/var/lib|/var/lib/docker|/var/lib/docker/*)
      return 1 ;;
  esac
  return 0
}

# Pruefen, ob ein TCP-Port auf dem Host belegt ist (0 = belegt).
port_busy() {
  ss -ltnH "( sport = :$1 )" 2>/dev/null | grep -q .
}

extract_json_value() {
  local file="$1" key="$2"
  if command -v python3 &>/dev/null; then
    python3 - "$file" "$key" <<'PY' 2>/dev/null || true
import json, sys
with open(sys.argv[1]) as f:
    v = json.load(f).get(sys.argv[2], "")
print("" if v is None else v)
PY
  elif command -v jq &>/dev/null; then
    jq -r --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null || true
  else
    # Fallback ohne python3/jq: erkennt Strings UND Zahlen.
    sed -n 's/.*"'"${key}"'"[[:space:]]*:[[:space:]]*"\{0,1\}\([^",}]*\)"\{0,1\}.*/\1/p' "$file" | head -n1
  fi
}

# API-Aufruf. Gibt immer einen HTTP-Code aus ("000" bei Verbindungsfehlern),
# damit set -e das Script nicht kommentarlos beendet.
# Nutzung: api METHOD PATH OUTFILE [PAYLOADFILE] [TIMEOUT]
api() {
  local method="$1" path="$2" out="$3" data="${4:-}" timeout="${5:-30}" code
  local -a args=(-s -o "$out" -w '%{http_code}' --max-time "$timeout"
                 -X "$method" -H "Content-Type: application/json")
  [[ -f "${WORK_DIR}/auth.hdr" ]] && args+=(-H "@${WORK_DIR}/auth.hdr")
  [[ -n "$data" ]] && args+=(--data-binary "@${data}")
  : >"$out"
  code="$(curl "${args[@]}" "${NPM_API}${path}" 2>/dev/null)" || code="000"
  echo "${code:0:3}"
}

api_fail() {
  local what="$1" code="$2" out="$3"
  echo ""
  error "${what} fehlgeschlagen (HTTP ${code})."
  if [[ -s "$out" ]]; then
    warn "Antwort der API:"
    cat "$out" || true
    echo ""
  fi
  [[ "$code" == "000" ]] && warn "Keine Verbindung zur API. Container-Logs: docker logs ${NPM_CONTAINER_NAME}"
}

# Ordnet eine fehlgeschlagene Zertifikatsanfrage ein (Antwort der NPM-API).
#   ratelimit - Let's-Encrypt-Limit erreicht, Wiederholen ist sinnlos
#   dns       - Domain nicht aufloesbar / kein passender Eintrag
#   challenge - HTTP-Challenge nicht erreichbar (Port 80, Firewall, falsche IP)
#   other     - alles andere (Wiederholen kann helfen)
cert_error_kind() {
  local f="$1"
  if grep -qiE 'too many (certificates|failed authorizations|new orders)|rateLimited|rate[- ]limit' "$f" 2>/dev/null; then
    echo ratelimit
  elif grep -qiE 'NXDOMAIN|DNS problem|no valid A records' "$f" 2>/dev/null; then
    echo dns
  elif grep -qiE 'Timeout during connect|Connection refused|Invalid response from|unauthorized' "$f" 2>/dev/null; then
    echo challenge
  else
    echo other
  fi
}

# "retry after 2026-09-18 02:47:50 UTC" -> "2026-09-18 02:47:50 UTC (04:47 Uhr deutscher Zeit)"
cert_retry_after() {
  local f="$1" ts out
  ts="$(grep -oE 'retry after [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} UTC' "$f" 2>/dev/null \
        | head -n 1 | sed 's/^retry after //' || true)"
  [[ -n "$ts" ]] || return 0
  out="$ts"
  if [[ -e /usr/share/zoneinfo/Europe/Berlin ]]; then
    local de
    de="$(TZ=Europe/Berlin date -d "$ts" '+%d.%m.%Y %H:%M' 2>/dev/null || true)"
    [[ -n "$de" ]] && out="${out} (${de} Uhr deutscher Zeit)"
  fi
  echo "$out"
}

wait_for_npm_api() {
  local attempts=60 i
  info "Warte auf NPM-API unter ${NPM_API}..."
  for ((i=1; i<=attempts; i++)); do
    if curl -sf --max-time 5 "${NPM_API}/api/" >/dev/null 2>&1; then
      success "NPM-API ist erreichbar."
      return 0
    fi
    sleep 2
  done
  die "NPM-API wurde nach ${attempts} Versuchen nicht erreichbar. Logs: docker logs ${NPM_CONTAINER_NAME}"
}

# docker-compose.yml schreiben.
#   $1 = Port-Binding fuer 81 (z. B. "81:81" oder "127.0.0.1:81:81")
#   $2 = 1, um INITIAL_ADMIN_* zu setzen (nur fuer den Erststart)
write_compose() {
  local port81="$1" with_admin="$2"
  {
    cat <<EOF
services:
  app:
    image: '${NPM_IMAGE}'
    container_name: ${NPM_CONTAINER_NAME}
    restart: always
    ports:
      - '80:80'
      - '${port81}'
      - '443:443'
EOF
    if [[ "$with_admin" == "1" ]]; then
      cat <<EOF
    environment:
      INITIAL_ADMIN_EMAIL: '${ADMIN_EMAIL}'
      INITIAL_ADMIN_PASSWORD: '${ADMIN_PASSWORD}'
EOF
    fi
    cat <<EOF
    volumes:
      - ${INSTALL_DIR}/data:/data
      - ${INSTALL_DIR}/letsencrypt:/etc/letsencrypt
    networks:
      - ${PROXY_NETWORK}

networks:
  ${PROXY_NETWORK}:
    external: true
EOF
  } >"${INSTALL_DIR}/docker-compose.yml"
  chmod 600 "${INSTALL_DIR}/docker-compose.yml"
}

# Sichert und entfernt eine Liste von Verzeichnissen (Bind-Mounts).
# Namensschema und Archivaufbau entsprechen update-npm.sh: npm_<zeitstempel>*.tar.gz
# mit relativen Pfaden (data/, letsencrypt/), wiederherstellbar per
#   tar xzf <backup> -C <installationspfad>
# Die Backups zaehlen damit auch bei der Rotation von update-npm.sh mit.
backup_and_remove_dirs() {
  local label="$1"; shift
  local ts dest d
  ts="$(date +%F_%H-%M-%S)"
  dest="${BACKUP_ROOT}/npm_${ts}_${label}.tar.gz"
  mkdir -p "${BACKUP_ROOT}"
  local -a existing=() tar_args=()
  for d in "$@"; do
    [[ -e "$d" ]] || continue
    is_safe_dir "$d" || die "Unsicherer Pfad, breche ab: ${d}"
    d="$(realpath -m -- "$d")"
    existing+=("$d")
    tar_args+=(-C "$(dirname -- "$d")" "$(basename -- "$d")")
  done
  if [[ ${#existing[@]} -gt 0 ]]; then
    info "Sichere alte Daten nach ${dest}..."
    tar -czf "$dest" "${tar_args[@]}" \
      || die "Backup fehlgeschlagen. Es wurde nichts geloescht."
    chmod 600 "$dest"
    success "Backup erstellt: ${dest}"
    rm -rf -- "${existing[@]}"
  fi
}

# -- Banner --------------------------------------------------------------------
[[ "${INTERACTIVE}" -eq 1 && -t 1 ]] && clear
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
printf '%b\n' "${BOLD} Nginx Proxy Manager Auto-Installer - powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo "Installiert NPM ${NPM_VERSION} via Docker Compose, erstellt Admin + ersten"
echo "Proxy Host mit SSL-Zertifikat und bindet Port 81 anschliessend lokal."
echo "------------------------------------------------------------"

# -- Root-Check ----------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  die "Bitte als root oder mit sudo ausfuehren."
fi

cd / 2>/dev/null || die "Konnte nicht nach / wechseln."

# -- Voraussetzungen pruefen ---------------------------------------------------
echo ""
echo -e "${BOLD} Voraussetzungen${RESET}"
echo -e "------------------------------------------------------------"

if ! command -v docker &>/dev/null; then
  die "Docker ist nicht installiert.\n\n  Anleitung auf pc-fee.com:\n  ${DOCKER_COMPOSE_GUIDE}\n\n  Danach dieses Script erneut starten."
fi
success "Docker gefunden: $(docker --version 2>&1)"

if ! docker info &>/dev/null; then
  die "Docker-Daemon laeuft nicht. Bitte starten: sudo systemctl start docker"
fi
success "Docker-Daemon laeuft."

if docker compose version &>/dev/null; then
  COMPOSE=(docker compose)
elif command -v docker-compose &>/dev/null; then
  COMPOSE=(docker-compose)
else
  die "Docker Compose nicht gefunden.\n\n  Anleitung auf pc-fee.com:\n  ${DOCKER_COMPOSE_GUIDE}"
fi
success "Docker Compose gefunden: ${COMPOSE[*]}"

for bin in curl openssl tar realpath; do
  command -v "$bin" &>/dev/null \
    || die "${bin} ist nicht installiert. Bitte nachinstallieren (z. B. sudo apt install ${bin/realpath/coreutils})."
done
success "curl, openssl, tar gefunden."

HAVE_SS=1
if ! command -v ss &>/dev/null; then
  HAVE_SS=0
  warn "'ss' (iproute2) nicht gefunden - Port-Pruefung wird uebersprungen."
fi

HAVE_GETENT=1
if ! command -v getent &>/dev/null; then
  HAVE_GETENT=0
  warn "'getent' nicht gefunden - automatische DNS-Pruefung wird uebersprungen."
fi

# -- Konfiguration -------------------------------------------------------------
echo ""
echo -e "${BOLD} Konfiguration${RESET}"
echo -e "------------------------------------------------------------"

INSTALL_DIR=""
while true; do
  ask INSTALL_DIR "Installationspfad" "/opt/nginx-proxy-manager"
  if is_safe_dir "$INSTALL_DIR"; then
    INSTALL_DIR="$(realpath -m -- "$INSTALL_DIR")"
    break
  fi
  [[ "${INTERACTIVE}" -eq 1 ]] || die "Ungueltiger Installationspfad: ${INSTALL_DIR}"
  warn "Ungueltiger Pfad. Bitte einen absoluten, eigenen Pfad angeben (kein Systemverzeichnis)."
done
readonly BACKUP_ROOT="${INSTALL_DIR}/backups"

DOMAIN=""
while [[ -z "$DOMAIN" ]] || ! is_domain "$DOMAIN"; do
  ask_nodefault DOMAIN "Domain fuer das NPM-Adminpanel (z. B. npm.meine-domain.de)"
  DOMAIN="${DOMAIN,,}"
  is_domain "$DOMAIN" || warn "Ungueltige Domain. Bitte erneut eingeben."
done

echo ""
echo -e " Die Admin-Email wird auch fuer ${CYAN}Let's Encrypt${RESET} verwendet und muss"
echo -e " eine echte, erreichbare Adresse sein (keine Platzhalter)."
ADMIN_EMAIL=""
while true; do
  ask_nodefault ADMIN_EMAIL "Admin-Email fuer NPM"
  ADMIN_EMAIL="${ADMIN_EMAIL,,}"
  is_email "$ADMIN_EMAIL" && break
  warn "Ungueltige oder Platzhalter-Email. Bitte eine echte Adresse eingeben."
  ADMIN_EMAIL=""
done

PROXY_NETWORK=""
while true; do
  ask PROXY_NETWORK "Docker-Netzwerkname" "shared_proxy"
  [[ "$PROXY_NETWORK" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] && break
  [[ "${INTERACTIVE}" -eq 1 ]] || die "Ungueltiger Netzwerkname: ${PROXY_NETWORK}"
  warn "Ungueltiger Netzwerkname (erlaubt: Buchstaben, Ziffern, _ . -)."
done
if [[ "$PROXY_NETWORK" != "shared_proxy" ]]; then
  warn "Die uebrigen Scripts im Repo (n8n, SearXNG, n8n-Sandbox) erwarten fest das"
  warn "Netzwerk 'shared_proxy'. Mit '${PROXY_NETWORK}' muessen diese Stacks von Hand"
  warn "angepasst werden."
  NET_OK=""
  ask_yesno NET_OK "Trotzdem '${PROXY_NETWORK}' verwenden?" "n"
  if [[ "$NET_OK" != "1" ]]; then
    PROXY_NETWORK="shared_proxy"
    info "Verwende 'shared_proxy'."
  fi
fi

# -- Oeffentliche IP ermitteln -------------------------------------------------
SERVER_IP=""
for url in https://api.ipify.org https://ifconfig.me https://ipv4.icanhazip.com; do
  SERVER_IP="$(curl -4 -sf --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
  is_ipv4 "$SERVER_IP" && break
  SERVER_IP=""
done
if [[ -z "$SERVER_IP" ]]; then
  SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  warn "Oeffentliche IPv4 konnte nicht ermittelt werden. Verwende lokale IP: ${SERVER_IP:-unbekannt}"
  warn "Hinter NAT/Cloud-Firewall kann diese von der oeffentlichen IP abweichen."
fi

# -- DNS-Pruefung --------------------------------------------------------------
echo ""
echo -e "${BOLD} DNS-Voraussetzung${RESET}"
echo -e "------------------------------------------------------------"
echo -e " Damit Let's Encrypt das SSL-Zertifikat fuer ${CYAN}${DOMAIN}${RESET}"
echo -e " erstellen kann, MUSS ein ${CYAN}A-Record${RESET} auf ${CYAN}${SERVER_IP:-die Server-IP}${RESET} zeigen."
echo ""

DNS_OK=0
if [[ "$HAVE_GETENT" -eq 1 ]]; then
  DNS_IPS="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ' || true)"
  DNS_IPS="${DNS_IPS% }"
  if [[ -z "$DNS_IPS" ]]; then
    warn "${DOMAIN} loest aktuell auf keine IPv4-Adresse auf."
  elif [[ -n "$SERVER_IP" && " ${DNS_IPS} " == *" ${SERVER_IP} "* ]]; then
    success "DNS korrekt: ${DOMAIN} -> ${SERVER_IP}"
    DNS_OK=1
  else
    warn "${DOMAIN} zeigt auf: ${DNS_IPS} (erwartet: ${SERVER_IP:-unbekannt})"
    warn "Hinweis: Bei Proxy-/CDN-Diensten (z. B. Cloudflare-Proxy) ist das normal,"
    warn "HTTP-Challenge und Port 80 muessen dann trotzdem durchgereicht werden."
  fi
fi

if [[ "$DNS_OK" -ne 1 ]]; then
  CONTINUE_DNS=""
  ask_yesno CONTINUE_DNS "DNS nicht bestaetigt. Trotzdem fortfahren?" "n"
  if [[ "$CONTINUE_DNS" != "1" ]]; then
    warn "Installation abgebrochen. Bitte zuerst den DNS A-Record setzen"
    warn "(Propagation kann einige Minuten dauern) und das Script erneut starten."
    exit 0
  fi
fi

# -- Zufaelliges Admin-Passwort ------------------------------------------------
# Nur alphanumerisch: sicher in YAML, JSON und Shell.
ADMIN_PASSWORD="$(openssl rand -base64 48 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c 32 || true)"
if [[ ${#ADMIN_PASSWORD} -lt 32 ]]; then
  ADMIN_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)"
fi
[[ ${#ADMIN_PASSWORD} -eq 32 ]] || die "Konnte kein Admin-Passwort erzeugen."

# -- Bestehende Installation pruefen -------------------------------------------
EXISTING_CONTAINER="$(
  {
    docker ps -a --format '{{.Names}} {{.Image}}' 2>/dev/null \
      | awk '$2 ~ /(^|\/)jc21\/nginx-proxy-manager(:|@|$)/ {print $1}'
    docker ps -a --format '{{.Names}}' --filter "name=^/${NPM_CONTAINER_NAME}$" 2>/dev/null
  } | sort -u | head -n1 || true
)"

OLD_COMPOSE_DIR=""
OLD_BIND_DIRS=()
OLD_VOLUMES=()
if [[ -n "$EXISTING_CONTAINER" ]]; then
  OLD_COMPOSE_DIR="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "$EXISTING_CONTAINER" 2>/dev/null || true)"
  [[ "$OLD_COMPOSE_DIR" == "<no value>" ]] && OLD_COMPOSE_DIR=""
  while IFS='|' read -r mtype msrc mname mdest; do
    [[ "$mdest" == "/data" || "$mdest" == "/etc/letsencrypt" ]] || continue
    if [[ "$mtype" == "bind" ]]; then
      OLD_BIND_DIRS+=("$msrc")
    elif [[ "$mtype" == "volume" && -n "$mname" ]]; then
      OLD_VOLUMES+=("$mname")
    fi
  done < <(docker inspect -f '{{range .Mounts}}{{.Type}}|{{.Source}}|{{.Name}}|{{.Destination}}{{"\n"}}{{end}}' "$EXISTING_CONTAINER" 2>/dev/null || true)
fi

EXISTING_DB=0
if [[ -f "${INSTALL_DIR}/data/database.sqlite" ]] || \
   { [[ -d "${INSTALL_DIR}/data" ]] && [[ -n "$(ls -A "${INSTALL_DIR}/data" 2>/dev/null)" ]]; }; then
  EXISTING_DB=1
fi

REINSTALL=0
if [[ -n "$EXISTING_CONTAINER" || "$EXISTING_DB" -eq 1 ]]; then
  echo ""
  if [[ -n "$EXISTING_CONTAINER" ]]; then
    warn "Es existiert bereits ein Container: ${EXISTING_CONTAINER}"
    [[ -n "$OLD_COMPOSE_DIR" ]] && warn "  Compose-Verzeichnis: ${OLD_COMPOSE_DIR}"
    for d in "${OLD_BIND_DIRS[@]}"; do warn "  Daten (Bind-Mount): ${d}"; done
    for v in "${OLD_VOLUMES[@]}"; do warn "  Daten (Volume):     ${v}"; done
  fi
  if [[ "$EXISTING_DB" -eq 1 ]]; then
    warn "Unter ${INSTALL_DIR}/data liegen bereits NPM-Daten (alte Datenbank)."
  fi
  warn "Eine Neuinstallation ENTFERNT alle bestehenden Proxy Hosts, Zertifikate"
  warn "und Einstellungen, da NPM eine frische Datenbank braucht, um den"
  warn "Admin-Account automatisch anzulegen. Vorher wird ein Backup unter"
  warn "${BACKUP_ROOT} erstellt (Bind-Mounts; Docker-Volumes werden nur geloescht)."
  echo ""
  warn "Jede Neuinstallation fordert ein NEUES Let's-Encrypt-Zertifikat fuer"
  warn "${DOMAIN} an. Let's Encrypt stellt pro exakter Domain hoechstens 5 Zertifikate"
  warn "in 7 Tagen aus - danach schlaegt die Installation bis zum Ablauf der Sperre fehl."
  warn "Fuer Testlaeufe besser jeweils eine andere Subdomain verwenden."
  echo ""

  [[ "${INTERACTIVE}" -eq 1 ]] \
    || die "Bestehende Installation erkannt, aber kein Terminal fuer Rueckfrage vorhanden. Abbruch."

  action=""
  while [[ "$action" != "a" && "$action" != "b" ]]; do
    echo -ne "${BOLD}Was soll passieren?${RESET} [${CYAN}a${RESET}=abbrechen (empfohlen), ${CYAN}b${RESET}=Backup + neu installieren]: "
    read -r action <"${TTY}" || true
    action="${action,,}"
    [[ "$action" != "a" && "$action" != "b" ]] && warn "Bitte 'a' oder 'b' eingeben."
  done

  if [[ "$action" == "a" ]]; then
    warn "Installation abgebrochen. Bestehende Installation bleibt erhalten."
    exit 0
  fi
  REINSTALL=1
fi

# -- Port-Pruefung -------------------------------------------------------------
if [[ "$HAVE_SS" -eq 1 ]]; then
  BUSY_PORTS=()
  for p in 80 443 81; do
    port_busy "$p" || continue
    # Ports, die der zu ersetzende NPM-Container selbst belegt, sind ok.
    if [[ "$REINSTALL" -eq 1 && -n "$EXISTING_CONTAINER" ]] && \
       [[ -n "$(docker port "$EXISTING_CONTAINER" "${p}/tcp" 2>/dev/null || true)" ]]; then
      continue
    fi
    BUSY_PORTS+=("$p")
  done
  if [[ ${#BUSY_PORTS[@]} -gt 0 ]]; then
    for p in "${BUSY_PORTS[@]}"; do
      error "Port ${p} ist bereits belegt:"
      ss -ltnpH "( sport = :${p} )" 2>/dev/null | sed 's/^/         /' || true
    done
    die "Bitte den blockierenden Dienst stoppen (z. B. systemctl disable --now apache2 nginx) und erneut starten."
  fi
  success "Ports 80, 81 und 443 sind frei."
fi

# -- Zusammenfassung -----------------------------------------------------------
echo ""
echo -e "${BOLD} Zusammenfassung${RESET}"
echo -e "------------------------------------------------------------"
echo -e " NPM-Version:       ${CYAN}${NPM_VERSION}${RESET}"
echo -e " Installationspfad: ${CYAN}${INSTALL_DIR}${RESET}"
echo -e " Domain:            ${CYAN}${DOMAIN}${RESET}"
echo -e " Admin-Email:       ${CYAN}${ADMIN_EMAIL}${RESET}"
echo -e " Server-IPv4:       ${CYAN}${SERVER_IP:-unbekannt}${RESET}"
echo -e " Port 80 (HTTP):    ${CYAN}80:80${RESET}"
echo -e " Port 443 (HTTPS):  ${CYAN}443:443${RESET}"
echo -e " Port 81 (Admin):   ${CYAN}81:81${RESET} (wird nach erfolgreicher Einrichtung auf 127.0.0.1:81 gebunden)"
echo -e " Netzwerk:          ${CYAN}${PROXY_NETWORK}${RESET}"
[[ "$REINSTALL" -eq 1 ]] && echo -e " Bestehende Daten:  ${YELLOW}werden gesichert und entfernt${RESET}"
echo ""

CONFIRM=""
ask_yesno CONFIRM "Alles korrekt? Installation starten?" "n"
if [[ "$CONFIRM" != "1" ]]; then
  warn "Installation abgebrochen."
  exit 0
fi

# -- Installation --------------------------------------------------------------
echo ""
echo -e "${BOLD} Installation${RESET}"
echo -e "------------------------------------------------------------"

info "Erstelle Verzeichnisse unter ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}" "${BACKUP_ROOT}"
chmod 700 "${INSTALL_DIR}" "${BACKUP_ROOT}"

# -- Alte Installation entfernen (erst nach Bestaetigung) ----------------------
if [[ "$REINSTALL" -eq 1 ]]; then
  if [[ -n "$EXISTING_CONTAINER" ]]; then
    info "Stoppe und entferne bestehende NPM-Installation..."
    if [[ -n "$OLD_COMPOSE_DIR" && -f "${OLD_COMPOSE_DIR}/docker-compose.yml" ]]; then
      "${COMPOSE[@]}" -f "${OLD_COMPOSE_DIR}/docker-compose.yml" down >/dev/null 2>&1 || true
    fi
    docker rm -f "$EXISTING_CONTAINER" >/dev/null 2>&1 || true
    backup_and_remove_dirs "old-install" "${OLD_BIND_DIRS[@]}"
    for v in "${OLD_VOLUMES[@]}"; do
      docker volume rm "$v" >/dev/null 2>&1 && info "Volume entfernt: ${v}" \
        || warn "Volume konnte nicht entfernt werden: ${v}"
    done
  fi
  backup_and_remove_dirs "pre-reinstall" "${INSTALL_DIR}/data" "${INSTALL_DIR}/letsencrypt"
  success "Bestehende NPM-Installation entfernt."
fi

mkdir -p "${INSTALL_DIR}/data" "${INSTALL_DIR}/letsencrypt"
success "Verzeichnisse erstellt."

if docker network inspect "${PROXY_NETWORK}" &>/dev/null; then
  info "Docker-Netzwerk '${PROXY_NETWORK}' bereits vorhanden."
else
  docker network create "${PROXY_NETWORK}" >/dev/null \
    || die "Netzwerk '${PROXY_NETWORK}' konnte nicht erstellt werden."
  success "Netzwerk '${PROXY_NETWORK}' erstellt."
fi

info "Schreibe docker-compose.yml (Rechte 600)..."
write_compose "81:81" 1
success "docker-compose.yml geschrieben."

info "Lade Image und starte Nginx Proxy Manager ${NPM_VERSION}..."
"${COMPOSE[@]}" -f "${INSTALL_DIR}/docker-compose.yml" up -d \
  || die "Container konnte nicht gestartet werden."
success "Container gestartet."

# -- Warte auf API und Login ---------------------------------------------------
wait_for_npm_api

info "Hole API-Token..."
printf '{"identity":"%s","secret":"%s"}' "$ADMIN_EMAIL" "$ADMIN_PASSWORD" >"${WORK_DIR}/login.json"
TOKEN=""
HTTP_CODE="000"
for ((i=1; i<=30; i++)); do
  HTTP_CODE="$(api POST /api/tokens "${WORK_DIR}/login.out" "${WORK_DIR}/login.json")"
  if [[ "$HTTP_CODE" == "200" ]]; then
    TOKEN="$(extract_json_value "${WORK_DIR}/login.out" token)"
    [[ -n "$TOKEN" ]] && break
  fi
  [[ "$i" -lt 30 ]] && sleep 2
done

if [[ -z "$TOKEN" ]]; then
  api_fail "Login an NPM-API" "$HTTP_CODE" "${WORK_DIR}/login.out"
  die "Admin-Login nicht moeglich. Bitte Container-Logs pruefen: docker logs ${NPM_CONTAINER_NAME}"
fi
# Token nur in Datei (nicht in der Prozessliste sichtbar).
printf 'Authorization: Bearer %s\n' "$TOKEN" >"${WORK_DIR}/auth.hdr"
success "API-Token erhalten."

# -- Ersten Proxy Host anlegen (ohne SSL) --------------------------------------
proxy_payload() {
  local cert_id="$1" ssl="$2"
  cat <<EOF
{
  "domain_names": ["${DOMAIN}"],
  "forward_scheme": "http",
  "forward_host": "localhost",
  "forward_port": 81,
  "access_list_id": 0,
  "certificate_id": ${cert_id},
  "meta": {},
  "advanced_config": "",
  "block_exploits": true,
  "caching_enabled": false,
  "allow_websocket_upgrade": true,
  "http2_support": ${ssl},
  "hsts_enabled": ${ssl},
  "hsts_subdomains": ${ssl},
  "ssl_forced": ${ssl},
  "locations": []
}
EOF
}

info "Erstelle Proxy Host (${DOMAIN} -> http://localhost:81)..."
proxy_payload 0 false >"${WORK_DIR}/proxy.json"
HTTP_CODE="$(api POST /api/nginx/proxy-hosts "${WORK_DIR}/proxy.out" "${WORK_DIR}/proxy.json")"
if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
  api_fail "Erstellen des Proxy Hosts" "$HTTP_CODE" "${WORK_DIR}/proxy.out"
  die "Proxy Host konnte nicht angelegt werden."
fi
HOST_ID="$(extract_json_value "${WORK_DIR}/proxy.out" id)"
[[ "$HOST_ID" =~ ^[0-9]+$ ]] || die "Konnte ID des neuen Proxy Hosts nicht ermitteln."
success "Proxy Host erstellt (ID ${HOST_ID})."

# -- SSL-Zertifikat erstellen --------------------------------------------------
# Der POST ist synchron: NPM wartet auf certbot und liefert entweder das fertige
# Zertifikat (201) oder einen Fehler. Die Let's-Encrypt-Email ist die Email des
# Admin-Accounts.
info "Fordere Let's Encrypt SSL-Zertifikat fuer ${DOMAIN} an (kann bis zu 2 Minuten dauern)..."
cat >"${WORK_DIR}/cert.json" <<EOF
{
  "provider": "letsencrypt",
  "domain_names": ["${DOMAIN}"],
  "meta": {}
}
EOF
CERT_ID=""
CERT_ERR="other"
for ((i=1; i<=2; i++)); do
  HTTP_CODE="$(api POST /api/nginx/certificates "${WORK_DIR}/cert.out" "${WORK_DIR}/cert.json" 300)"
  if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
    CERT_ID="$(extract_json_value "${WORK_DIR}/cert.out" id)"
    break
  fi
  CERT_ERR="$(cert_error_kind "${WORK_DIR}/cert.out")"
  # Rate-Limit und DNS-Fehler aendern sich nicht in 15 Sekunden - kein zweiter Versuch.
  if [[ "$i" -lt 2 && "$CERT_ERR" != "ratelimit" && "$CERT_ERR" != "dns" ]]; then
    warn "Zertifikatsanfrage fehlgeschlagen (HTTP ${HTTP_CODE}), neuer Versuch in 15 Sekunden..."
    sleep 15
  else
    break
  fi
done
if [[ ! "$CERT_ID" =~ ^[0-9]+$ ]]; then
  # Port 81 offen lassen, Initial-Zugangsdaten aus der Compose-Datei entfernen.
  write_compose "81:81" 0
  "${COMPOSE[@]}" -f "${INSTALL_DIR}/docker-compose.yml" up -d >/dev/null 2>&1 || true

  echo ""
  case "$CERT_ERR" in
    ratelimit)
      error "Let's Encrypt hat die Anfrage abgelehnt: Rate-Limit erreicht."
      echo -e " Fuer ${CYAN}${DOMAIN}${RESET} wurden in den letzten 7 Tagen bereits zu viele"
      echo -e " Zertifikate ausgestellt (meist durch wiederholte Installationen)."
      RETRY_AT="$(cert_retry_after "${WORK_DIR}/cert.out")"
      [[ -n "$RETRY_AT" ]] && echo -e " Neuer Versuch moeglich ab: ${BOLD}${RETRY_AT}${RESET}"
      echo -e " Details: ${CYAN}https://letsencrypt.org/docs/rate-limits/${RESET}"
      ;;
    dns)
      api_fail "Erstellen des SSL-Zertifikats" "$HTTP_CODE" "${WORK_DIR}/cert.out"
      warn "Ursache: ${DOMAIN} ist per DNS nicht (korrekt) aufloesbar."
      warn "Bitte den A-Record auf ${SERVER_IP:-die Server-IP} pruefen und die Propagation abwarten."
      ;;
    challenge)
      api_fail "Erstellen des SSL-Zertifikats" "$HTTP_CODE" "${WORK_DIR}/cert.out"
      warn "Ursache: Let's Encrypt erreicht http://${DOMAIN}/.well-known/ nicht."
      warn "Bitte pruefen: A-Record zeigt auf ${SERVER_IP:-die Server-IP}, Port 80 ist in"
      warn "Provider-Firewall/Security-Group offen, kein CDN-Proxy davor."
      ;;
    *)
      api_fail "Erstellen des SSL-Zertifikats" "$HTTP_CODE" "${WORK_DIR}/cert.out"
      warn "Haeufige Ursachen: DNS zeigt nicht auf diesen Server, Port 80 ist von aussen"
      warn "nicht erreichbar (Firewall/Security-Group) oder Let's-Encrypt-Rate-Limit."
      ;;
  esac

  echo ""
  echo -e "${BOLD}============================================================${RESET}"
  echo -e "${BOLD} STAND UND NAECHSTE SCHRITTE${RESET}"
  echo -e "${BOLD}============================================================${RESET}"
  echo -e " NPM laeuft, der Admin-Account und der Proxy Host fuer ${CYAN}${DOMAIN}${RESET}"
  echo -e " (noch ohne SSL) sind angelegt. Port 81 bleibt vorerst ${YELLOW}oeffentlich${RESET}."
  echo ""
  echo -e " ${BOLD}Admin-Login:${RESET} ${CYAN}http://${SERVER_IP:-SERVER-IP}:81${RESET}"
  echo -e "   Email:    ${CYAN}${ADMIN_EMAIL}${RESET}"
  echo -e "   Passwort: ${CYAN}${ADMIN_PASSWORD}${RESET}"
  echo -e "   (wird nicht erneut angezeigt - jetzt sicher speichern)"
  echo ""
  echo -e " ${YELLOW}${BOLD}Das Script NICHT erneut starten:${RESET} eine Neuinstallation verwirft diesen"
  echo -e " Stand und fordert ein weiteres Zertifikat an."
  echo ""
  if [[ "$CERT_ERR" == "ratelimit" ]]; then
    echo -e " 1. Nach Ablauf der Sperre einloggen (siehe oben)."
  else
    echo -e " 1. Ursache beheben, dann einloggen (siehe oben)."
  fi
  echo -e " 2. ${BOLD}Certificates${RESET} -> Let's-Encrypt-Zertifikat fuer ${CYAN}${DOMAIN}${RESET} anlegen."
  echo -e " 3. ${BOLD}Proxy Hosts${RESET} -> ${DOMAIN} bearbeiten -> Reiter SSL: Zertifikat waehlen,"
  echo -e "    Force SSL, HTTP/2 und HSTS aktivieren."
  echo -e " 4. Port 81 lokal binden: in ${CYAN}${INSTALL_DIR}/docker-compose.yml${RESET}"
  echo -e "    ${CYAN}- '81:81'${RESET} durch ${CYAN}- '127.0.0.1:81:81'${RESET} ersetzen, dann:"
  echo -e "    ${CYAN}${COMPOSE[*]} -f ${INSTALL_DIR}/docker-compose.yml up -d${RESET}"
  echo -e " 5. Passwort aendern und 2FA im Benutzermenue aktivieren."
  echo ""
  if [[ "$CERT_ERR" == "ratelimit" ]]; then
    echo -e " Sofort weitermachen geht nur mit einer ${BOLD}anderen Subdomain${RESET} (eigener A-Record):"
    echo -e " dafuer in Schritt 2 und 3 statt ${DOMAIN} die neue Domain verwenden."
    echo ""
  fi
  die "SSL-Zertifikat konnte nicht erstellt werden."
fi
success "SSL-Zertifikat erstellt (ID ${CERT_ID})."

# -- Proxy Host mit SSL aktualisieren ------------------------------------------
info "Aktualisiere Proxy Host mit SSL, HSTS, HTTP/2 und Force SSL..."
proxy_payload "$CERT_ID" true >"${WORK_DIR}/update.json"
HTTP_CODE="$(api PUT "/api/nginx/proxy-hosts/${HOST_ID}" "${WORK_DIR}/update.out" "${WORK_DIR}/update.json")"
if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
  api_fail "Aktualisieren des Proxy Hosts" "$HTTP_CODE" "${WORK_DIR}/update.out"
  die "Proxy Host konnte nicht mit SSL aktualisiert werden."
fi
success "Proxy Host mit SSL, HSTS, HTTP/2 und Force SSL aktualisiert."

# -- HTTPS-Erreichbarkeit pruefen ----------------------------------------------
# Zuerst lokal (umgeht fehlendes Hairpin-NAT), dann ueber die oeffentliche IP.
info "Pruefe https://${DOMAIN}/api/ ..."
HTTPS_OK=0
for ((i=1; i<=30; i++)); do
  if curl -sf --max-time 5 --resolve "${DOMAIN}:443:127.0.0.1" "https://${DOMAIN}/api/" >/dev/null 2>&1 \
     || curl -sf --max-time 5 "https://${DOMAIN}/api/" >/dev/null 2>&1; then
    HTTPS_OK=1
    break
  fi
  sleep 2
done

BIND_LOCAL=1
if [[ "$HTTPS_OK" -eq 1 ]]; then
  success "https://${DOMAIN} liefert das Adminpanel mit gueltigem Zertifikat aus."
else
  warn "https://${DOMAIN} ist nach 60 Sekunden nicht erreichbar."
  warn "Wird Port 81 jetzt lokal gebunden, ist das Adminpanel nur noch per"
  warn "SSH-Tunnel erreichbar, bis HTTPS funktioniert."
  ask_yesno BIND_LOCAL "Port 81 trotzdem lokal (127.0.0.1) binden?" "n"
fi

# -- Compose finalisieren: Zugangsdaten entfernen, ggf. Port 81 lokal ----------
if [[ "$BIND_LOCAL" -eq 1 ]]; then
  info "Binde Admin-Port 81 lokal (127.0.0.1:81) und entferne Initial-Zugangsdaten..."
  write_compose "127.0.0.1:81:81" 0
else
  info "Port 81 bleibt oeffentlich. Entferne Initial-Zugangsdaten aus der Compose-Datei..."
  write_compose "81:81" 0
fi
"${COMPOSE[@]}" -f "${INSTALL_DIR}/docker-compose.yml" up -d >/dev/null \
  || die "Container konnte mit der finalen Konfiguration nicht gestartet werden."
wait_for_npm_api
if [[ "$BIND_LOCAL" -eq 1 ]]; then
  success "Port 81 ist jetzt nur noch unter 127.0.0.1:81 erreichbar."
else
  warn "Port 81 ist weiterhin oeffentlich erreichbar. Nach Behebung des Problems in"
  warn "${INSTALL_DIR}/docker-compose.yml '81:81' durch '127.0.0.1:81:81' ersetzen und"
  warn "'${COMPOSE[*]} -f ${INSTALL_DIR}/docker-compose.yml up -d' ausfuehren."
fi

# -- Abschluss -----------------------------------------------------------------
echo ""
echo -e "${BOLD}============================================================${RESET}"
success "Nginx Proxy Manager ${NPM_VERSION} wurde installiert und vorkonfiguriert."
echo ""
echo -e " ${BOLD}Domain:${RESET}          ${CYAN}${DOMAIN}${RESET}"
echo -e " ${BOLD}Adminpanel:${RESET}      ${CYAN}https://${DOMAIN}${RESET}"
echo -e " ${BOLD}Notfallzugang:${RESET}   ${CYAN}ssh -L 8181:127.0.0.1:81 root@${SERVER_IP:-SERVER-IP}${RESET}"
echo -e "                  danach im Browser: ${CYAN}http://localhost:8181${RESET}"
echo -e " ${BOLD}Admin-Login:${RESET}"
echo -e "   Email:    ${CYAN}${ADMIN_EMAIL}${RESET}"
echo -e "   Passwort: ${CYAN}${ADMIN_PASSWORD}${RESET}"
echo ""
echo -e " ${YELLOW}Wichtig:${RESET} Diese Zugangsdaten werden nicht noch einmal angezeigt"
echo -e "          und sind nirgends auf dem Server gespeichert."
echo -e "          Bitte sofort sicher speichern (Passwortmanager)."
echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "${BOLD} NAECHSTE SCHRITTE${RESET}"
echo -e "${BOLD}============================================================${RESET}"
echo ""
echo -e " 1. ${CYAN}https://${DOMAIN}${RESET} aufrufen und mit den oben stehenden"
echo -e "    Daten einloggen."
echo -e " 2. ${BOLD}Passwort aendern:${RESET} Ueber das Benutzermenue oben rechts ein neues,"
echo -e "    sicheres Passwort setzen."
echo -e " 3. ${BOLD}Zwei-Faktor-Authentifizierung aktivieren:${RESET} Ebenfalls im"
echo -e "    Benutzermenue einen TOTP-Authenticator einrichten."
echo -e " 4. ${BOLD}Backups:${RESET} ${CYAN}${INSTALL_DIR}/data${RESET} und ${CYAN}${INSTALL_DIR}/letsencrypt${RESET}"
echo -e "    regelmaessig sichern."
echo -e " 5. ${BOLD}Updates:${RESET} Die NPM-Version ist fest eingetragen (${NPM_VERSION})."
echo -e "    Das Update-Script erkennt neue Versionen, sichert vorher und stellt um:"
echo -e "    ${CYAN}sudo bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/update/update-npm.sh)\"${RESET}"
echo ""
echo -e "${BOLD}============================================================${RESET}"
echo -e "${BOLD} WEITERE INFOS${RESET}"
echo -e "${BOLD}============================================================${RESET}"
echo ""
echo -e " ${BOLD}Blogartikel:${RESET}"
echo -e "   ${CYAN}${NPM_GUIDE}${RESET}"
echo ""
echo -e " ${BOLD}GitHub Repository:${RESET}"
echo -e "   ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo -e "${BOLD}============================================================${RESET}"
echo ""
