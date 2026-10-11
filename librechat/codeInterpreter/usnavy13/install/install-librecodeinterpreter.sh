#!/usr/bin/env bash
# =============================================================================
# LibreCodeInterpreter Installer
# - installiert https://github.com/usnavy13/LibreCodeInterpreter unter /opt
# - kein Port wird an den Host gebunden, Zugriff ausschliesslich ueber ein
#   bestehendes externes Docker-Netzwerk eines Nginx Proxy Managers (NPM)
# - generiert automatisch den MASTER_API_KEY (Zugang zum Admin-Dashboard) und
#   einen API-Key fuer LibreChat und zeigt beide am Ende an
#
# -----------------------------------------------------------------------------
# AI-Transparenzhinweis:
# Dieses Skript wurde unter Einsatz von KI-Modellen recherchiert, erstellt und
# iterativ ueberarbeitet. Alle technischen Aussagen wurden gegen die offizielle
# Projekt-Dokumentation und den Quellcode geprueft. Vor produktivem Einsatz
# eigenverantwortlich pruefen.
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

# -- Eingabequelle -------------------------------------------------------------
# 'read' ohne Umleitung liest von stdin. Beim dokumentierten Aufruf
# (sudo bash -c "$(curl -fsSL ...)") ist stdin noch das Terminal - wird das
# Skript stattdessen wie "curl ... | sudo bash" aufgerufen, landet der Rest
# des Skripttexts auf stdin und 'read' verschluckt ihn statt einer echten
# Eingabe (die Domain-Abfrage wuerde dann endlos "Ungueltige Domain." melden,
# ohne dass je eine echte Eingabe ankommen koennte).
if { : </dev/tty; } 2>/dev/null; then
  TTY=/dev/tty
else
  die "Kein Terminal fuer interaktive Eingaben verfuegbar. Bitte das Skript lokal herunterladen und ausfuehren, oder mit 'sudo bash -c \"\$(curl -fsSL ...)\"' aufrufen (nicht per 'curl | bash')."
fi
readonly TTY

readonly REPO_URL="https://github.com/usnavy13/LibreCodeInterpreter.git"
readonly DEFAULT_INSTALL_DIR="/opt/LibreCodeInterpreter"
readonly DEFAULT_NPM_NETWORK="shared_proxy"
readonly NPM_GUIDE="https://pc-fee.com/2026/05/03/nginx-proxy-manager/"

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "Bitte als root ausfuehren oder sudo installieren."
  SUDO="sudo"
fi

clear
printf '%b\n' "${BOLD}${CYAN}LibreCodeInterpreter Installer${RESET}"
echo "Installiert LibreCodeInterpreter hinter einem Nginx Proxy Manager via"
echo "Docker Compose. Kein Port wird an den Host gebunden."
echo "------------------------------------------------------------"

# -----------------------------------------------------------------------------
# Schritt 0: Voraussetzungen pruefen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 0: Voraussetzungen${RESET}"
echo "------------------------------------------------------------"

command -v git >/dev/null 2>&1 || die "git ist nicht installiert. Bitte zuerst installieren (z.B. apt-get install -y git)."
success "git gefunden: $(git --version)"

command -v docker >/dev/null 2>&1 || die "Docker ist nicht installiert."
success "Docker gefunden: $(docker --version)"

${SUDO} docker info >/dev/null 2>&1 || die "Docker-Daemon laeuft nicht oder ist nicht erreichbar."
success "Docker-Daemon laeuft."

${SUDO} docker compose version >/dev/null 2>&1 || die "Docker Compose Plugin nicht gefunden."
COMPOSE_CMD="${SUDO} docker compose"
success "Docker Compose Plugin gefunden: $(${COMPOSE_CMD} version --short 2>/dev/null || ${COMPOSE_CMD} version)"

command -v openssl >/dev/null 2>&1 || die "openssl ist nicht installiert (wird fuer den API-Key gebraucht)."
success "openssl gefunden."

# Das Docker-Netzwerk allein genuegt als Pruefung nicht: Es kann bestehen,
# waehrend NPM gar nicht laeuft. Die Installation liefe dann sauber durch, aber
# die Domain waere spaeter unerreichbar - ohne dass irgendwo ein Fehler stand.
if ${SUDO} docker ps --format '{{.Image}}' | grep -qi 'nginx-proxy-manager'; then
  success "Nginx Proxy Manager Container laeuft."
else
  die "Kein laufender Nginx Proxy Manager Container gefunden. Anleitung: ${NPM_GUIDE}"
fi

if [[ -e "${DEFAULT_INSTALL_DIR}" ]]; then
  die "Installationsverzeichnis ${DEFAULT_INSTALL_DIR} existiert bereits. Bitte pruefen/entfernen."
fi
success "Kein bestehendes Installationsverzeichnis gefunden."

# -----------------------------------------------------------------------------
# Schritt 1: Konfiguration abfragen
# -----------------------------------------------------------------------------
is_domain() { [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; }
detect_public_ipv4() {
  local ip
  ip="$(curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  [[ -z "${ip}" ]] && ip="$(curl -fsS4 --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  printf '%s' "${ip}"
}

printf '%b\n' "\n${BOLD}Schritt 1: Konfiguration${RESET}"
echo "------------------------------------------------------------"

read -rp "Docker-Netzwerk des Nginx Proxy Managers [${DEFAULT_NPM_NETWORK}]: " NPM_NETWORK <"${TTY}"
NPM_NETWORK="${NPM_NETWORK:-${DEFAULT_NPM_NETWORK}}"
${SUDO} docker network inspect "${NPM_NETWORK}" >/dev/null 2>&1 \
  || die "Docker-Netzwerk '${NPM_NETWORK}' existiert nicht. Anleitung: ${NPM_GUIDE}"
success "Docker-Netzwerk '${NPM_NETWORK}' gefunden."

while :; do
  read -rp "Domain fuer den Code-Interpreter (z.B. code.example.de): " DOMAIN <"${TTY}"
  is_domain "${DOMAIN}" && break || warn "Ungueltige Domain."
done

printf '%b\n' "\n${BOLD}Zusammenfassung${RESET}"
echo "------------------------------------------------------------"
printf 'Installationspfad: %s\nDomain:            %s\nNPM-Netzwerk:      %s\n' \
  "${DEFAULT_INSTALL_DIR}" "${DOMAIN}" "${NPM_NETWORK}"
read -rp "Installation starten? [j/N]: " CONFIRM <"${TTY}"
[[ "${CONFIRM,,}" == "j" ]] || { warn "Abgebrochen (keine oder verneinende Eingabe)."; exit 0; }

# -----------------------------------------------------------------------------
# Schritt 2: Repository holen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 2: Repository${RESET}"
echo "------------------------------------------------------------"
${SUDO} git clone --depth=1 "${REPO_URL}" "${DEFAULT_INSTALL_DIR}"
cd "${DEFAULT_INSTALL_DIR}"
[[ -f .env.example ]] || die ".env.example fehlt im Repository."
[[ -f docker-compose.yml ]] || die "docker-compose.yml fehlt im Repository."
success "Repository bereit."

# -----------------------------------------------------------------------------
# Schritt 3: .env erzeugen und patchen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 3: .env erzeugen${RESET}"
echo "------------------------------------------------------------"
${SUDO} cp .env.example .env
${SUDO} chmod 600 .env

MASTER_API_KEY="$(openssl rand -hex 32)"

patch_env() {
  local key="$1" value="$2" escaped
  escaped="$(printf '%s' "$value" | sed -e 's/[&|]/\\&/g')"
  # Die .env ist chmod 600 und gehoert root - ohne ${SUDO} scheitert schon das
  # Lesen, wenn das Skript per sudo aus einem normalen Nutzerkonto laeuft. Der
  # grep wuerde dann faelschlich "Schluessel nicht vorhanden" melden und die
  # Zeile ein zweites Mal anhaengen, statt die bestehende zu ersetzen.
  if ${SUDO} grep -qE "^${key}=" .env; then
    ${SUDO} sed -i "s|^${key}=.*|${key}=${escaped}|" .env
  elif ${SUDO} grep -qE "^#\s*${key}=" .env; then
    ${SUDO} sed -i "s|^#\s*${key}=.*|${key}=${escaped}|" .env
  else
    printf '%s=%s\n' "${key}" "${value}" | ${SUDO} tee -a .env >/dev/null
  fi
}

patch_env MASTER_API_KEY "${MASTER_API_KEY}"
success ".env geschrieben (MASTER_API_KEY gesetzt)."

# -----------------------------------------------------------------------------
# Schritt 4: docker-compose.override.yml
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 4: Compose Override${RESET}"
echo "------------------------------------------------------------"
# "ports: !reset []" entfernt jede Host-Port-Bindung aus der Upstream-Datei,
# unabhaengig davon, wie sie dort geschrieben ist. Das ist robuster, als in der
# .env eine PORT-Variable auf 127.0.0.1 zu setzen: Ob und wie Upstream diese
# Variable im ports-Mapping verwendet, kann sich jederzeit aendern - und viele
# Anwendungen lesen PORT zusaetzlich selbst als Lauschadresse, wo ein Wert wie
# "127.0.0.1:8000" zum Startfehler fuehrt.
# NPM erreicht den Container ohnehin ueber den Container-Namen im gemeinsamen
# Docker-Netzwerk, ein Host-Port wird also nicht gebraucht.
${SUDO} tee docker-compose.override.yml >/dev/null <<EOF
services:
  api:
    ports: !reset []
    expose:
      - "8000"
    networks:
      - default
      - ${NPM_NETWORK}

networks:
  ${NPM_NETWORK}:
    external: true
EOF

${COMPOSE_CMD} config --quiet
success "docker-compose.override.yml ok."

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
  for _ in {1..60}; do
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

wait_running redis
wait_running garage
wait_running api

CONTAINER_NAME="$(${COMPOSE_CMD} ps -q api | xargs -r ${SUDO} docker inspect --format '{{.Name}}' | sed 's#^/##')"
[[ -z "${CONTAINER_NAME}" ]] && CONTAINER_NAME="code-interpreter-api"

# Sicherheits-Check: kein oeffentlicher Port am Host
if ${SUDO} docker port "${CONTAINER_NAME}" 2>/dev/null | grep -q '0\.0\.0\.0\|\[::\]'; then
  warn "Es scheint ein oeffentlich gebundener Port zu existieren - bitte pruefen: docker port ${CONTAINER_NAME}"
else
  success "Kein oeffentlicher Port am Host gebunden (nur ueber ${NPM_NETWORK} erreichbar)."
fi

# -----------------------------------------------------------------------------
# Schritt 6: API-Key fuer LibreChat anlegen
# -----------------------------------------------------------------------------
# Angelegt ueber die Admin-Schnittstelle IM Container: Die Domain ist zu diesem
# Zeitpunkt noch nicht erreichbar (DNS und NPM-Proxy fehlen noch). Mehrere
# Versuche, weil die API kurz nach "healthy" gelegentlich noch nicht antwortet.
printf '%b\n' "\n${BOLD}Schritt 6: API-Key fuer LibreChat${RESET}"
echo "------------------------------------------------------------"
LIBRECHAT_KEY=""
for _ in {1..5}; do
  LIBRECHAT_KEY="$(${COMPOSE_CMD} exec -T api python3 -c '
import json,sys,urllib.request as u
r=u.Request("http://localhost:8000/api/v1/admin/keys",
  data=json.dumps({"name":"LibreChat"}).encode(),
  headers={"x-api-key":sys.argv[1],"Content-Type":"application/json"})
print(json.load(u.urlopen(r,timeout=15))["api_key"])
' "${MASTER_API_KEY}" 2>/dev/null || true)"
  [[ "${LIBRECHAT_KEY}" =~ ^[A-Za-z0-9_-]+$ ]] && break
  LIBRECHAT_KEY=""
  sleep 3
done

if [[ -n "${LIBRECHAT_KEY}" ]]; then
  success "API-Key fuer LibreChat angelegt (Name: LibreChat)."
else
  warn "API-Key konnte nicht automatisch angelegt werden."
  warn "Bitte spaeter im Dashboard manuell anlegen und unten statt <KEY> einsetzen."
  LIBRECHAT_KEY="<KEY>"
fi

# -----------------------------------------------------------------------------
# Abschluss / Naechste Schritte
# -----------------------------------------------------------------------------
HOST_IPV4="$(detect_public_ipv4)"
readonly LC_ENV="/opt/librechat/.env"

echo ""
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"
printf '%b\n' "${GREEN}${BOLD}#         Installation erfolgreich          #${RESET}"
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"

printf '%b\n' "\n${BLUE}${BOLD}Naechste Schritte${RESET}"
printf '%b\n' "${BLUE}------------------------------------------------------------${RESET}"

if [[ -n "${HOST_IPV4}" ]]; then
cat <<DNS

1) Beim Domain-Provider einen A-Record auf diesen Host setzen:

   ${HOST_IPV4}   A   (TTL 300)   ${DOMAIN}
DNS
else
  echo ""
  warn "Oeffentliche IPv4 konnte nicht automatisch ermittelt werden."
  echo "   Bitte die Server-IP manuell ermitteln und einen A-Record fuer"
  echo "   ${DOMAIN} beim Domain-Provider anlegen."
fi

# Die Befehle fuer den Nutzer stehen bewusst immer mit sudo da: als root
# schadet es nicht, ohne root wuerden sie sonst scheitern. Beim Anhaengen an
# die .env deshalb "| sudo tee -a" statt ">>" (die Umleitung macht die eigene
# Shell, nicht sudo).
cat <<NEXT

2) Proxy Host im Nginx Proxy Manager anlegen:

   Reiter Details:
     Domain:             ${DOMAIN}
     Scheme:             http
     Forward Hostname:   ${CONTAINER_NAME}
     Forward Port:       8000
     Websockets Support: an

   Reiter SSL:
     SSL Certificate:    Request a new SSL Certificate (Let's Encrypt)
     Force SSL:          an
     HTTP/2 Support:     an
     HSTS Enabled:       an

Schluessel dieser Installation:

   MASTER_API_KEY (Dashboard):   ${MASTER_API_KEY}
   API-Key fuer LibreChat:       ${LIBRECHAT_KEY}

   Der MASTER_API_KEY steht auch in: ${DEFAULT_INSTALL_DIR}/.env

3) Code-Interpreter in LibreChat eintragen - diesen Befehl kopieren
   und auf dem LibreChat-Server ausfuehren:

     sudo sed -i -E '/^#?\s*LIBRECHAT_CODE_(BASEURL|API_KEY)=/d' ${LC_ENV} && echo "LIBRECHAT_CODE_BASEURL=https://${LIBRECHAT_KEY}@${DOMAIN}" | sudo tee -a ${LC_ENV} >/dev/null

   Danach LibreChat stoppen und starten - ein 'docker restart' allein
   liest die .env NICHT neu ein:

     sudo docker stop LibreChat && sudo docker start LibreChat

   Pruefen, ob der Wert angekommen ist:

     sudo docker exec LibreChat env | grep LIBRECHAT_CODE

4) CodeInterpreter Dashboard (optional):
NEXT

printf '%b\n' "   ${CYAN}https://${DOMAIN}/admin-dashboard${RESET}"

cat <<NEXT

   Anmeldung mit dem MASTER_API_KEY (siehe oben).

   Der API-Key fuer LibreChat (Name: LibreChat) wurde automatisch
   angelegt. Im Dashboard lassen sich weitere Keys manuell anlegen,
   sperren und loeschen.

   Der MASTER_API_KEY ist NICHT der Schluessel fuer LibreChat. Er dient
   allein der Anmeldung am Dashboard.


Nuetzliche Befehle:
  Logs:    cd ${DEFAULT_INSTALL_DIR} && sudo docker compose logs -f api
  Status:  cd ${DEFAULT_INSTALL_DIR} && sudo docker compose ps
  Update:  cd ${DEFAULT_INSTALL_DIR} && sudo docker compose pull && sudo docker compose up -d
  Health:  curl -s https://${DOMAIN}/health

GitHub-Referenz:
  https://github.com/nephilim75/scripts/tree/main/librechat/codeInterpreter/usnavy13

NEXT
