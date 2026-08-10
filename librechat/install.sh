#!/usr/bin/env bash
# ============================================================================
# install.sh — pc-fee LibreChat Installer v5
# ============================================================================
# Schritte:
#   0    Voraussetzungen
#   0.5  Konflikt-Schutz (nichts überschreiben)
#   1    Interaktive Eingaben
#   2    Templates rendern (envsubst)
#   3    Admin-Seed in MongoDB (Node im librechat-api-Image + mongosh)
#   4    docker compose up + Health-Checks + NPM-Hinweise
#
# KEIN Python irgendwo. bcrypt-Hash via Node aus dem offiziellen
# LibreChat-Image (hat bcrypt als Dependency). Insert via mongosh aus
# dem mongo-Image (hat mongosh eingebaut).
# ============================================================================

set -euo pipefail
shopt -s nullglob

# --- Konstanten ------------------------------------------------------------
readonly DEFAULT_INSTALL_DIR="/opt/librechat"
readonly DEFAULT_NETWORK="shared_proxy"
readonly BLOG_NPM_URL="https://pc-fee.com/2026/05/03/nginx-proxy-manager/"
readonly BLOG_DOCKER_URL="https://pc-fee.com/2026/05/03/docker-compose/"
readonly MIN_RAM_MB=2048
readonly MIN_DISK_GB=10
readonly MIN_DOCKER_MAJOR=20
readonly MIN_PASSWORD_LEN=12
readonly APP_PORTS=(3080 3000 27017 7700 5432)
readonly COMPOSE_HEALTH_TIMEOUT=180

# --- Farben -----------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'
  C_BLU=$'\e[34m'; C_BLD=$'\e[1m'; C_RST=$'\e[0m'
else
  C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_BLD=''; C_RST=''
fi

log()   { printf '%s[*]%s %s\n' "${C_BLU}" "${C_RST}" "$*"; }
ok()    { printf '%s[✓]%s %s\n' "${C_GRN}" "${C_RST}" "$*"; }
warn()  { printf '%s[!]%s %s\n' "${C_YEL}" "${C_RST}" "$*" >&2; }
err()   { printf '%s[✗]%s %s\n' "${C_RED}" "${C_RST}" "$*" >&2; }
hdr()   { printf '\n%s== %s ==%s\n' "${C_BLD}" "$*" "${C_RST}"; }
die()   { err "$*"; exit 1; }

prompt() {
  local label="$1" default="${2:-}"
  local suffix=" [$default]"
  [[ -z "$default" ]] && suffix=""
  local reply
  read -r -p "$(printf '%s%s:%s ' "${label}" "${suffix}" "")" reply || true
  [[ -z "$reply" ]] && reply="$default"
  printf '%s' "$reply"
}

confirm() {
  local label="$1" default="${2:-j}"
  local yn="J/n"; [[ "$default" == "n" ]] && yn="j/N"
  local reply
  while true; do
    read -r -p "$(printf '%s [%s]: ' "${label}" "${yn}")" reply || true
    reply="${reply:-$default}"
    case "${reply,,}" in
      j|y|ja|yes) return 0 ;;
      n|no|nein)  return 1 ;;
    esac
  done
}

validate_path() {
  local p="$1"
  [[ "$p" == /* ]] || return 1
  [[ "$p" != *" "* ]] || return 1
  [[ "$p" =~ ^[A-Za-z0-9/_.-]+$ ]] || return 1
  if [[ -e "$p" ]]; then
    [[ -w "$p" ]] || return 1
  else
    [[ -w "$(dirname "$p")" ]] || return 1
  fi
  return 0
}

# ============================================================================
hdr "pc-fee LibreChat Installer v5 — Schritte 0 / 0.5 / 1 / 2 / 3 / 4"

MODE="install"
CONF_FILE=""
INSTALL_DIR="${DEFAULT_INSTALL_DIR}"

# ============================================================================
# SCHRITT 0: Voraussetzungen
# ============================================================================
hdr "Schritt 0: Voraussetzungs-Check"

log "Prüfe Benutzerrechte…"
if [[ "$(id -u)" -ne 0 ]]; then
  if ! sudo -n true 2>/dev/null; then
    die "Root oder passwortloses sudo erforderlich. Bitte: sudo $0"
  fi
  SUDO="sudo"
else
  SUDO=""
fi
ok "Root/sudo verfügbar"

log "Prüfe Betriebssystem…"
[[ -f /etc/os-release ]] || die "/etc/os-release fehlt. Nur Debian 12/13 unterstützt."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "debian" ]] || die "Nicht-Debian (ID=${ID:-?}). Anleitung: ${BLOG_DOCKER_URL}"
case "${VERSION_ID:-}" in
  12|13) ok "Debian ${VERSION_ID} erkannt" ;;
  *)     die "Debian ${VERSION_ID:-?} nicht unterstützt." ;;
esac

log "Prüfe Architektur…"
case "$(uname -m)" in
  x86_64|aarch64) ok "Architektur ok" ;;
  *)              die "Architektur $(uname -m) nicht unterstützt." ;;
esac

log "Prüfe RAM…"
RAM_FREE_MB="$(free -m | awk '/^Mem:/ {print $7}')"
[[ "${RAM_FREE_MB}" -ge "${MIN_RAM_MB}" ]] || die "Zu wenig RAM: ${RAM_FREE_MB} MB (≥ ${MIN_RAM_MB} MB nötig)."
ok "RAM: ${RAM_FREE_MB} MB frei"

log "Prüfe Speicher…"
DISK_FREE_GB="$(df -BG /var/lib/docker 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' || echo 0)"
[[ "${DISK_FREE_GB}" -ge "${MIN_DISK_GB}" ]] || die "Zu wenig Speicher: ${DISK_FREE_GB} GB (≥ ${MIN_DISK_GB} GB nötig)."
ok "Speicher: ${DISK_FREE_GB} GB frei"

log "Prüfe Docker…"
command -v docker >/dev/null 2>&1 || die "Docker fehlt. Anleitung: ${BLOG_DOCKER_URL}"
DOCKER_VERSION="$(docker --version | awk '{print $3}' | tr -d ',')"
DOCKER_MAJOR="$(echo "${DOCKER_VERSION}" | cut -d. -f1)"
[[ "${DOCKER_MAJOR}" -ge "${MIN_DOCKER_MAJOR}" ]] || die "Docker ${DOCKER_VERSION} zu alt (≥ ${MIN_DOCKER_MAJOR}.x nötig). Update: ${BLOG_DOCKER_URL}"
ok "Docker ${DOCKER_VERSION}"

log "Prüfe docker compose Plugin…"
docker compose version >/dev/null 2>&1 || die "'docker compose' Plugin fehlt. Installiere: ${SUDO} apt install docker-compose-plugin (Debian 12+). Hilfe: ${BLOG_DOCKER_URL}"
COMPOSE_VERSION="$(docker compose version --short 2>/dev/null || echo unknown)"
ok "docker compose ${COMPOSE_VERSION}"

log "Prüfe curl…"
command -v curl >/dev/null 2>&1 || die "curl fehlt. Installiere: ${SUDO} apt install -y curl"
ok "curl vorhanden"

log "Prüfe envsubst (Template-Rendering)…"
command -v envsubst >/dev/null 2>&1 || die "envsubst fehlt. Installiere: ${SUDO} apt install -y gettext-base  (siehe ${BLOG_DOCKER_URL})"
ok "envsubst vorhanden"

log "Prüfe Nginx Proxy Manager…"
NPM_RUNNING="$(docker ps --filter name=nginx-proxy-manager --filter status=running --format '{{.Names}}' || true)"
[[ -n "${NPM_RUNNING}" ]] || die "NPM läuft nicht. Anleitung: ${BLOG_NPM_URL}"
NPM_COUNT="$(echo "${NPM_RUNNING}" | wc -l)"
[[ "${NPM_COUNT}" -eq 1 ]] || die "Mehrere NPM-Container: '${NPM_RUNNING}'. Bitte aufräumen."
ok "NPM läuft: ${NPM_RUNNING}"

log "Prüfe Ports 80/443…"
PORTS_80_443="$(ss -tlnp 2>/dev/null | grep -E ':(80|443)\s' || true)"
[[ -n "${PORTS_80_443}" ]] || die "Ports 80/443 nicht belegt (NPM sollte sie halten)."
ok "Ports 80/443 ok"

ok "Schritt 0 abgeschlossen"

# ============================================================================
# SCHRITT 0.5: Konflikt-Check (Schutzregel)
# ============================================================================
hdr "Schritt 0.5: Konflikt-Check"

CONFLICT_FOUND=0

log "Bestehende LibreChat-Container (Name)…"
EXISTING="$(docker ps -a --format '{{.Names}} {{.Image}}' 2>/dev/null \
  | grep -iE '(^|[-_])(librechat|admin-panel|chat-)' || true)"
if [[ -n "${EXISTING}" ]]; then
  err "Container gefunden:"; echo "${EXISTING}" | sed 's/^/    /'
  err "Auflösung: docker rm -f <name>"
  CONFLICT_FOUND=1
fi

log "Bestehende Container mit LibreChat-Images…"
IMG_HITS="$(docker ps -a --format '{{.Names}} {{.Image}}' 2>/dev/null \
  | grep -iE 'registry\.librechat\.ai' || true)"
if [[ -n "${IMG_HITS}" ]]; then
  err "Image-Treffer:"; echo "${IMG_HITS}" | sed 's/^/    /'
  err "Auflösung: docker rm -f <name>"
  CONFLICT_FOUND=1
fi

log "Bestehende LibreChat-Volumes…"
EX_VOL="$(docker volume ls --format '{{.Name}}' 2>/dev/null \
  | grep -iE '(librechat|^chat-)' || true)"
if [[ -n "${EX_VOL}" ]]; then
  err "Volumes:"; echo "${EX_VOL}" | sed 's/^/    /'
  err "Auflösung: docker volume rm <name>   (löscht Daten!)"
  CONFLICT_FOUND=1
fi

log "Bestehende LibreChat-Netzwerke…"
EX_NET="$(docker network ls --format '{{.Name}}' 2>/dev/null \
  | grep -iE 'librechat' || true)"
if [[ -n "${EX_NET}" ]]; then
  err "Netzwerke:"; echo "${EX_NET}" | sed 's/^/    /'
  err "Auflösung: docker network rm <name>"
  CONFLICT_FOUND=1
fi

log "Belegte App-Ports ${APP_PORTS[*]}…"
PORT_REX=":$(
  IFS='|'; echo "${APP_PORTS[*]}"
)"
PORT_HITS="$(ss -tlnp 2>/dev/null | grep -E "${PORT_REX}\s" || true)"
if [[ -n "${PORT_HITS}" ]]; then
  err "Ports belegt:"; echo "${PORT_HITS}" | sed 's/^/    /'
  err "Auflösung: docker stop <container>"
  CONFLICT_FOUND=1
fi

[[ "${CONFLICT_FOUND}" -eq 0 ]] || die "Konflikte gefunden. Schutzregel: Abbruch."
ok "Keine Konflikte"

# ============================================================================
# SCHRITT 1: Interaktive Eingaben
# ============================================================================
hdr "Schritt 1: Konfiguration abfragen"

log "Wohin soll LibreChat installiert werden?"
INSTALL_DIR="$(prompt '  Installationspfad' "${DEFAULT_INSTALL_DIR}")"
INSTALL_DIR="${INSTALL_DIR%/}"
[[ -z "${INSTALL_DIR}" ]] && die "Leerer Pfad nicht erlaubt"

CONF_FILE="${INSTALL_DIR}/.librechat-install.conf"
if [[ -f "${CONF_FILE}" ]]; then
  warn "Bestehende Installation erkannt → Reconfigure-Modus"
  MODE="reconfigure"
  # shellcheck disable=SC1090
  source "${CONF_FILE}" || true
fi

while ! validate_path "${INSTALL_DIR}"; do
  err "Pfad '${INSTALL_DIR}' ungültig (absolut, keine Leerzeichen, beschreibbar)."
  INSTALL_DIR="$(prompt '  Anderer Installationspfad' "${DEFAULT_INSTALL_DIR}")"
  INSTALL_DIR="${INSTALL_DIR%/}"
done

if [[ "${MODE}" == "install" && -e "${INSTALL_DIR}" ]]; then
  die "Pfad '${INSTALL_DIR}' existiert bereits. Anderen Pfad wählen."
fi

${SUDO} mkdir -p "${INSTALL_DIR}"
INSTALL_DIR="$(cd "${INSTALL_DIR}" && pwd -P)"
ok "Installationspfad: ${INSTALL_DIR}"

log "Welches Docker-Netzwerk nutzt dein NPM?"
NETWORK_NAME="$(prompt '  Docker-Netzwerk für NPM' "${DEFAULT_NETWORK}")"
[[ -z "${NETWORK_NAME}" ]] && NETWORK_NAME="${DEFAULT_NETWORK}"
docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1 \
  || die "Netzwerk '${NETWORK_NAME}' existiert nicht. Vorher anlegen oder anderen Namen wählen."
ok "Netzwerk: ${NETWORK_NAME}"

log "Welche Domain für den Chat? (A-Record muss auf den VPS zeigen.)"
DOMAIN="$(prompt '  Chat-Domain (z. B. chat.deinedomain.de)' 'chat.deinedomain.de')"
[[ -z "${DOMAIN}" ]] && die "Chat-Domain leer"
[[ "${DOMAIN}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$ ]] \
  || die "Domain '${DOMAIN}' sieht ungültig aus"

log "Welche Domain für das Admin-Panel?"
ADMIN_DOMAIN="$(prompt '  Admin-Domain (z. B. chat-admin.deinedomain.de)' 'chat-admin.deinedomain.de')"
[[ -z "${ADMIN_DOMAIN}" ]] && die "Admin-Domain leer"
[[ "${ADMIN_DOMAIN}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$ ]] \
  || die "Domain '${ADMIN_DOMAIN}' sieht ungültig aus"

ADMIN_EMAIL="$(prompt '  Admin-E-Mail' '')"
[[ "${ADMIN_EMAIL}" =~ ^[^@]+@[^@]+\.[^@]+$ ]] || die "E-Mail ungültig"

ADMIN_NAME="$(prompt '  Admin-Anzeigename' '')"
[[ -z "${ADMIN_NAME}" ]] && die "Admin-Name leer"

while true; do
  read -r -s -p "  Admin-Passwort (mind. ${MIN_PASSWORD_LEN} Zeichen): " pass1; echo
  [[ -z "$pass1" ]] && { err "leer"; continue; }
  [[ "${#pass1}" -ge "${MIN_PASSWORD_LEN}" ]] || { err "zu kurz"; continue; }
  read -r -s -p "  Passwort wiederholen: " pass2; echo
  if [[ "$pass1" == "$pass2" ]]; then
    ADMIN_PASS="$pass1"
    unset pass1 pass2
    break
  fi
  err "Passwörter stimmen nicht überein"
done
history -c 2>/dev/null || true
ok "Admin-Passwort gesetzt"

log "JWT-Secret: leer = automatisch generieren."
JWT_SECRET_INPUT="$(prompt '  JWT-Secret (oder leer)' '')"
JWT_SECRET_GENERATED=0
if [[ -z "${JWT_SECRET_INPUT}" ]]; then
  JWT_SECRET="$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | xxd -p -c 64)"
  echo
  echo "    Auto-generiert: ${JWT_SECRET}"
  echo
  if ! confirm "  Diesen Wert in ${INSTALL_DIR}/.env speichern?" "j"; then
    die "Abgebrochen. Mit eigenem Wert erneut starten."
  fi
  JWT_SECRET_GENERATED=1
else
  JWT_SECRET="${JWT_SECRET_INPUT}"
fi

if confirm "  Meilisearch (Volltextsuche) installieren?" "j"; then
  INSTALL_MEILI=1
else
  INSTALL_MEILI=0
fi

hdr "Zusammenfassung"
echo "  Installationspfad:   ${INSTALL_DIR}"
echo "  Docker-Netzwerk:     ${NETWORK_NAME}"
echo "  Chat-Domain:         ${DOMAIN}"
echo "  Admin-Domain:        ${ADMIN_DOMAIN}"
echo "  Admin-E-Mail:        ${ADMIN_EMAIL}"
echo "  Admin-Name:          ${ADMIN_NAME}"
echo "  JWT-Secret:          ${JWT_SECRET_GENERATED:+auto-generiert}${JWT_SECRET_GENERATED:-eigenes}"
echo "  Meilisearch:         $([[ ${INSTALL_MEILI} -eq 1 ]] && echo ja || echo nein)"
echo
confirm "  Mit diesen Einstellungen fortfahren?" "j" || die "Abgebrochen."

ok "Schritt 1 abgeschlossen"

# ============================================================================
# SCHRITT 2: Templates rendern (envsubst)
# ============================================================================
hdr "Schritt 2: Templates rendern (envsubst)"

log "Lege Datenverzeichnisse an…"
${SUDO} mkdir -p "${INSTALL_DIR}/data/mongo"
[[ "${INSTALL_MEILI}" -eq 1 ]] && ${SUDO} mkdir -p "${INSTALL_DIR}/data/meili"
ok "Datenverzeichnisse ok"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"
[[ -d "${TEMPLATE_DIR}" ]] || die "Template-Verzeichnis '${TEMPLATE_DIR}' fehlt. Repo vollständig klonen."
ok "Templates gefunden in ${TEMPLATE_DIR}"

log "Erzeuge interne Secrets…"
CREDS_KEY="$(openssl rand -hex 32)"
CREDS_IV="$(openssl rand -hex 16)"
MEILI_API_KEY=""
if [[ "${INSTALL_MEILI}" -eq 1 ]]; then
  MEILI_API_KEY="$(openssl rand -hex 32)"
fi
export CREDS_KEY CREDS_IV MEILI_API_KEY
ok "Secrets erzeugt"

export INSTALL_DIR NETWORK_NAME DOMAIN ADMIN_DOMAIN ADMIN_EMAIL ADMIN_NAME
export JWT_SECRET INSTALL_MEILI

MEILI_SUFFIX="$([ "${INSTALL_MEILI}" -eq 1 ] && echo 'with-meili' || echo 'without-meili')"
log "Verwende Template-Variante: ${MEILI_SUFFIX}"

log "Rendere docker-compose.yml…"
${SUDO} envsubst < "${TEMPLATE_DIR}/docker-compose.${MEILI_SUFFIX}.tmpl" \
                  > "${INSTALL_DIR}/docker-compose.yml"
${SUDO} chmod 644 "${INSTALL_DIR}/docker-compose.yml"

log "Rendere librechat.yaml…"
${SUDO} envsubst < "${TEMPLATE_DIR}/librechat.yaml.${MEILI_SUFFIX}.tmpl" \
                  > "${INSTALL_DIR}/librechat.yaml"
${SUDO} chmod 644 "${INSTALL_DIR}/librechat.yaml"

log "Rendere .env…"
${SUDO} envsubst < "${TEMPLATE_DIR}/.env.tmpl" \
                  > "${INSTALL_DIR}/.env"
${SUDO} chmod 600 "${INSTALL_DIR}/.env"

log "Schreibe .librechat-install.conf…"
cat > "${INSTALL_DIR}/.librechat-install.conf" <<EOF
# pc-fee LibreChat Installer — Konfigurations-Datei
# Wird im Reconfigure-Modus gelesen. NICHT manuell editieren.
INSTALL_DIR="${INSTALL_DIR}"
NETWORK_NAME="${NETWORK_NAME}"
DOMAIN="${DOMAIN}"
ADMIN_DOMAIN="${ADMIN_DOMAIN}"
ADMIN_EMAIL="${ADMIN_EMAIL}"
ADMIN_NAME="${ADMIN_NAME}"
INSTALL_MEILI="${INSTALL_MEILI}"
INSTALL_DATE="$(date -u +%FT%TZ)"
EOF
${SUDO} chmod 600 "${INSTALL_DIR}/.librechat-install.conf"

unset CREDS_KEY CREDS_IV MEILI_API_KEY JWT_SECRET ADMIN_PASS

ok "Schritt 2 abgeschlossen"

# ============================================================================
# SCHRITT 3: Admin-Seed in MongoDB (Node + mongosh, kein Python)
# ============================================================================
hdr "Schritt 3: Admin-User in MongoDB anlegen"

cd "${INSTALL_DIR}"
${SUDO} docker compose up -d mongodb

log "Warte auf MongoDB (max. 60s)..."
HEALTH_TIMEOUT=60
HEALTHY=false
for ((i=1; i<=HEALTH_TIMEOUT; i++)); do
  MONGO_CID="$(${SUDO} docker compose ps -q mongodb 2>/dev/null || true)"
  STATUS="$(${SUDO} docker inspect --format='{{.State.Health.Status}}' "${MONGO_CID}" 2>/dev/null || echo 'starting')"
  if [[ "${STATUS}" == "healthy" ]]; then
    HEALTHY=true
    break
  fi
  sleep 1
done
[[ "${HEALTHY}" == "true" ]] || die "MongoDB wurde nicht gesund. Prüfe: cd ${INSTALL_DIR} && docker compose logs mongodb"
ok "MongoDB ist gesund"

# 3.1 bcrypt-Hash via Node aus dem librechat-api-Image generieren
log "Erzeuge bcrypt-Hash via Node (aus librechat-api-Image)…"
HASH_OUTPUT="$(${SUDO} docker run --rm \
  --entrypoint node \
  registry.librechat.ai/danny-avila/librechat:dev-latest \
  -e "const b=require('bcrypt');b.hash(process.argv[1],12).then(h=>console.log(h));" \
  -- "${ADMIN_PASS}" 2>&1 | tail -1)"

if [[ -z "${HASH_OUTPUT}" || "${HASH_OUTPUT}" == *"Error"* || "${HASH_OUTPUT}" != \$2* ]]; then
  die "bcrypt-Hash fehlgeschlagen. Output: ${HASH_OUTPUT}"
fi
ok "Hash erzeugt"

# 3.2 User via mongosh anlegen (im mongodb-Container)
log "Lege User in MongoDB an…"
MONGO_CID="$(${SUDO} docker compose ps -q mongodb 2>/dev/null)"
${SUDO} docker exec -i "${MONGO_CID}" mongosh librechat --quiet --eval "
  const doc = {
    email: '${ADMIN_EMAIL}',
    username: '${ADMIN_NAME}',
    password: '${HASH_OUTPUT}',
    role: 'ADMIN',
    emailVerified: true,
    provider: 'local',
    createdAt: new Date(),
    updatedAt: new Date()
  };
  const existing = db.users.findOne({email: doc.email});
  if (existing) {
    print('User existiert bereits. Setze Rolle auf ADMIN.');
    db.users.updateOne({_id: existing._id}, {\$set: {role: 'ADMIN', updatedAt: new Date()}});
  } else {
    const r = db.users.insertOne(doc);
    print('Angelegt: ' + r.insertedId);
  }
" || die "Mongo-Insert fehlgeschlagen."

ok "Admin-User in MongoDB"
unset ADMIN_PASS HASH_OUTPUT

ok "Schritt 3 abgeschlossen"

# ============================================================================
# SCHRITT 4: docker compose up + Health-Checks
# ============================================================================
hdr "Schritt 4: Container starten + Health-Checks"

log "Starte alle Container…"
${SUDO} docker compose up -d

log "Warte auf api + admin-panel (max. ${COMPOSE_HEALTH_TIMEOUT}s)…"
HEALTHY=false
for ((i=1; i<=COMPOSE_HEALTH_TIMEOUT; i++)); do
  API_CID="$(${SUDO} docker compose ps -q api 2>/dev/null || true)"
  AP_CID="$(${SUDO} docker compose ps -q admin-panel 2>/dev/null || true)"
  API_STATUS="$(${SUDO} docker inspect --format='{{.State.Health.Status}}' "${API_CID}" 2>/dev/null || echo 'starting')"
  AP_STATUS="$(${SUDO} docker inspect --format='{{.State.Health.Status}}' "${AP_CID}" 2>/dev/null || echo 'starting')"
  if [[ "${API_STATUS}" == "healthy" && "${AP_STATUS}" == "healthy" ]]; then
    HEALTHY=true
    break
  fi
  sleep 1
done

if [[ "${HEALTHY}" != "true" ]]; then
  warn "Nicht alle Container sind nach ${COMPOSE_HEALTH_TIMEOUT}s healthy."
  warn "Diagnose:"
  ${SUDO} docker compose ps
  ${SUDO} docker compose logs --tail=30 api admin-panel
  die "Container-Start fehlgeschlagen. Logs oben prüfen."
fi

ok "Beide Services sind healthy"

# ============================================================================
hdr "Schritte 0, 0.5, 1, 2, 3, 4 fertig ✓"

cat <<EOF

${C_GRN}==> Installation abgeschlossen!${C_RST}

${C_BLD}==> Naechste Schritte (manuell):${C_RST}

  1. NPM-Proxy-Hosts anlegen:

     Host 1 - Chat:
       Domain:        ${DOMAIN}
       Scheme:        http
       Forward Host:  api
       Forward Port:  3080
       Websockets:    AN
       SSL:           Let's Encrypt

     Host 2 - Admin-Panel:
       Domain:        ${ADMIN_DOMAIN}
       Scheme:        http
       Forward Host:  admin-panel
       Forward Port:  3000
       Websockets:    AN
       SSL:           Let's Encrypt

  2. Erster Login:
     Browser -> https://${DOMAIN}
     Login mit: ${ADMIN_EMAIL}  /  <dein Passwort>

  3. API-Keys in ${INSTALL_DIR}/librechat.yaml eintragen
     (danach: cd ${INSTALL_DIR} && sudo docker compose restart api)

${C_BLD}==> Status:${C_RST}
$(${SUDO} docker compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}')

EOF

log "Fertig. Konfig gespeichert in ${INSTALL_DIR}/.librechat-install.conf"
exit 0
