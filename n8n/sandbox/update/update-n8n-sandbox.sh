#!/usr/bin/env bash
# =============================================================================
#  n8n Sandbox Update Script – powered by pc-fee.com
#  https://pc-fee.com | https://github.com/nephilim75/scripts
#
#  Aktualisiert eine mit install-n8n-sandbox.sh installierte n8n-Sandbox auf
#  eine neue Image-Version. Da die Compose-Vorlage des Install-Scripts alle
#  drei Sandbox-Images über eine einzige Variable (SANDBOX_IMAGE_TAG) in der
#  .env steuert, genügt es, diese Variable zu aktualisieren – es muss keine
#  docker-compose.yml editiert werden.
#
#  Ablauf: verfügbare Version ermitteln (Docker Hub) -> Zielversion abfragen
#  -> prüfen, ob sie für alle benötigten Images existiert -> Backup (.env,
#  docker-compose.yml, mTLS-Volume) -> Update -> Health Check -> bei Fehler
#  automatischer Rollback -> alte Images aufräumen.
#
#  Nutzung als 1-Zeiler:
#    bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/update/update-n8n-sandbox.sh)
#
#  Optionen:
#    --dry-run   Zeigt nur, was getan würde, ändert aber nichts.
#
#  Umgebungsvariablen (für unbeaufsichtigten Betrieb):
#    INSTALL_DIR     Installationspfad (Default: /opt/n8n-sandbox)
#    TARGET_VERSION  Zielversion, überspringt die Abfrage (z.B. 1.4.0)
#    BACKUP_DIR      Backup-Verzeichnis (Default: <INSTALL_DIR>/backups)
#    MAX_BACKUPS     Anzahl aufzubewahrender Backups (Default: 5)
#    ASSUME_YES=1    Überspringt alle Sicherheitsabfragen
#
#  Das Script erkennt selbst, ob es als root läuft; falls nicht, wird jeder
#  privilegierte Befehl automatisch mit sudo ausgeführt (siehe
#  install-n8n-sandbox.sh für den Hintergrund dazu).
#
#  Mehr Infos: https://pc-fee.com/blog
#
#  AI Transparency: Dieses Script wurde von Claude (Anthropic) im Auftrag
#  von pc-fee.com erstellt und vor Veroeffentlichung geprueft. Nutzung auf
#  eigene Gefahr. Backups sind Pflicht.
# =============================================================================

set -euo pipefail

# ── Farben ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Konstanten ────────────────────────────────────────────────────────────────
readonly INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/install/install-n8n-sandbox.sh"

# Images wie im Compose-Template von install-n8n-sandbox.sh (GHCR – das sind
# die tatsächlich gezogenen/laufenden Images):
readonly GHCR_IMAGE_API="ghcr.io/n8n-io/n8n-sandbox-service-api"
readonly GHCR_IMAGE_RUNNER="ghcr.io/n8n-io/n8n-sandbox-service-runner-dind"
readonly GHCR_IMAGE_SANDBOX="ghcr.io/n8n-io/n8n-sandbox-service-sandbox"

# Dieselben Images werden zusätzlich auf Docker Hub veröffentlicht (siehe
# https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/RELEASE.md) –
# dessen öffentliche REST-API ist (anders als bei GHCR) ohne Token-Dance
# abfragbar und wird hier ausschließlich zur Versions-Erkennung genutzt.
# Gezogen wird trotzdem weiterhin von GHCR (s.o.), es ändert sich nichts an
# der Bezugsquelle der Images selbst.
readonly HUB_IMAGE_API="n8nio/n8n-sandbox-service-api"
readonly HUB_IMAGE_RUNNER="n8nio/n8n-sandbox-service-runner-dind"
readonly HUB_IMAGE_SANDBOX="n8nio/n8n-sandbox-service-sandbox"

# Als Env-Var überschreibbar (z.B. für Tests) statt fest verdrahtet.
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-30}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-2}"

# ── Optionen ──────────────────────────────────────────────────────────────────
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) ;;
  esac
done
readonly DRY_RUN

# run <befehl...>  – führt den Befehl aus, oder zeigt ihn im --dry-run nur an
run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${RESET} $*"
  else
    "$@"
  fi
}

# ── Eingabequelle ─────────────────────────────────────────────────────────────
# Siehe install-n8n-sandbox.sh: IMMER vom Terminal lesen, falls vorhanden,
# damit Prompts auch bei 'bash <(curl ...)' / 'curl ... | bash' funktionieren.
if { exec 3<>/dev/tty; } 2>/dev/null; then
  exec 3<&-
  TTY=/dev/tty
  INTERACTIVE=1
else
  TTY=/dev/null
  INTERACTIVE=0
fi
readonly TTY INTERACTIVE

# ── Hilfsfunktionen ───────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[FEHLER]${RESET} $*"; }
die()     { error "$*"; exit 1; }

ask() {
  local var="$1" prompt="$2" default="$3" input=""
  local preset="${!var:-}"
  [[ -n "$preset" ]] && default="$preset"
  echo ""
  if [[ "${INTERACTIVE}" -eq 1 ]]; then
    echo -ne "${BOLD}${prompt}${RESET} [${CYAN}${default}${RESET}]: "
    read -r input <"${TTY}" || true
  else
    echo -e "${BOLD}${prompt}${RESET}: ${CYAN}${default}${RESET} (Vorgabe, kein Terminal)"
  fi
  printf -v "${var}" '%s' "${input:-${default}}"
}

# ask_yesno <prompt> <default: j|n> -> Rueckgabewert via $? (0 = ja)
ask_yesno() {
  local prompt="$1" default="${2:-j}" input=""
  local hint="J/n"
  [[ "${default,,}" == "n" ]] && hint="j/N"
  if [[ "${ASSUME_YES:-0}" -eq 1 ]]; then
    echo -e "${BOLD}${prompt}${RESET} [${CYAN}${hint}${RESET}]: ${CYAN}j${RESET} (ASSUME_YES=1)"
    return 0
  fi
  echo ""
  if [[ "${INTERACTIVE}" -eq 1 ]]; then
    echo -ne "${BOLD}${prompt}${RESET} [${CYAN}${hint}${RESET}]: "
    read -r input <"${TTY}" || true
  else
    input="${default}"
    echo -e "${BOLD}${prompt}${RESET}: ${CYAN}${default}${RESET} (Vorgabe, kein Terminal)"
  fi
  input="${input:-${default}}"
  [[ "${input,,}" == "j" || "${input,,}" == "y" ]]
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo -e "${CYAN}"
cat <<'LOGO'
               __
 _ __  __ ___ / _|___ ___   __ ___ _ __
| '_ \/ _|___|  _/ -_) -_)_/ _/ _ \ '  \
| .__/\__|   |_| \___\___(_)__\___/_|_|_|
|_|
LOGO
echo -e "${RESET}"
echo -e "${BOLD}  n8n Sandbox Service – Update-Script – powered by pc-fee.com${RESET}"
echo -e "  ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo -e "  Aktualisiert eine bestehende ${BOLD}n8n-Sandbox${RESET}-Installation auf eine"
echo -e "  neue Image-Version, inkl. Backup, Health Check und Rollback bei Fehlern."
[[ "${DRY_RUN}" -eq 1 ]] && echo -e "  ${YELLOW}${BOLD}--dry-run aktiv: Es wird nichts verändert.${RESET}"
echo ""
echo -e "────────────────────────────────────────────────────────────"

# ── root/sudo ─────────────────────────────────────────────────────────────────
SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "Bitte als root ausführen oder sudo installieren."
  SUDO="sudo"
fi

cd / 2>/dev/null || die "Konnte nicht nach / wechseln."

# ── Voraussetzungen prüfen ────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Voraussetzungen${RESET}"
echo -e "────────────────────────────────────────────────────────────"
info "Prüfe Voraussetzungen..."

command -v curl &>/dev/null || die "curl ist nicht installiert."

if ! command -v docker &>/dev/null; then
  die "Docker ist nicht installiert."
fi
success "Docker gefunden: $(docker --version 2>&1)"

if ! ${SUDO} docker info &>/dev/null; then
  die "Docker-Daemon läuft nicht. Bitte starten: sudo systemctl start docker"
fi
success "Docker-Daemon läuft."

if ${SUDO} docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="${SUDO} docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="${SUDO} docker-compose"
else
  die "Docker Compose nicht gefunden."
fi
success "Docker Compose gefunden: $($COMPOSE_CMD version --short 2>/dev/null || $COMPOSE_CMD version)"

# ── Installationspfad ─────────────────────────────────────────────────────────
ask INSTALL_DIR "Installationspfad" "/opt/n8n-sandbox"

ENV_FILE="${INSTALL_DIR}/.env"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"

if [[ ! -f "${ENV_FILE}" ]] || [[ ! -f "${COMPOSE_FILE}" ]]; then
  die "Keine n8n-Sandbox-Installation unter '${INSTALL_DIR}' gefunden (.env/docker-compose.yml fehlen).\n\n       Zum Installieren:\n       bash <(curl -fsSL ${INSTALL_SCRIPT_URL})"
fi
success "Installation unter '${INSTALL_DIR}' gefunden."

if ! ${SUDO} docker ps -a --format '{{.Names}}' | grep -qiE 'sandbox-api|sandbox-certs|sandbox-runner'; then
  die "Unter '${INSTALL_DIR}' liegt zwar eine .env/docker-compose.yml, aber es sind keine\n       Sandbox-Container vorhanden. Bitte erst installieren oder INSTALL_DIR prüfen."
fi
success "Sandbox-Container gefunden."

# ── Aktuelle Version ermitteln ────────────────────────────────────────────────
get_current_version() {
  ${SUDO} grep -E '^SANDBOX_IMAGE_TAG=' "${ENV_FILE}" 2>/dev/null | head -1 | cut -d'=' -f2- || true
}

CURRENT_VERSION="$(get_current_version)"
[[ -z "${CURRENT_VERSION}" ]] && die "Konnte SANDBOX_IMAGE_TAG nicht aus ${ENV_FILE} lesen."

if [[ "${CURRENT_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  info "Aktuell installierter Image-Tag: ${BOLD}${CURRENT_VERSION}${RESET} (gepinnte Version)"
else
  info "Aktuell installierter Image-Tag: ${BOLD}${CURRENT_VERSION}${RESET} (kein fester Versions-Pin)"
  warn "Dieses Script pinnt Updates immer auf eine konkrete Version (statt auf einen"
  warn "beweglichen Tag wie 'latest'/'stable'), damit ein Rollback zuverlässig möglich ist."
fi

# ── Docker Hub: Versionen ermitteln ───────────────────────────────────────────
# Docker Hub dient hier ausschließlich als Quelle für die Versionsnummern
# (siehe Kommentar zu HUB_IMAGE_* oben) – gezogen wird weiterhin von GHCR.
get_latest_version() {
  local image=$1
  curl -s --max-time 10 \
    "https://hub.docker.com/v2/repositories/${image}/tags?page_size=100&ordering=last_updated" \
    | grep -o '"name":"[0-9]*\.[0-9]*\.[0-9]*"' \
    | grep -o '[0-9]*\.[0-9]*\.[0-9]*' \
    | sort -t. -k1,1n -k2,2n -k3,3n -u \
    | tail -1
}

tag_exists_on_hub() {
  local image=$1 version=$2
  curl -s --max-time 10 \
    "https://hub.docker.com/v2/repositories/${image}/tags/${version}/" \
    | grep -c '"name"' || true
}

echo ""
echo -e "────────────────────────────────────────────────────────────"
echo -e "${BOLD}  Versionsprüfung${RESET}"
echo -e "────────────────────────────────────────────────────────────"
info "Frage verfügbare Versionen auf Docker Hub ab..."

LATEST_API=$(get_latest_version "${HUB_IMAGE_API}")
LATEST_RUNNER=$(get_latest_version "${HUB_IMAGE_RUNNER}")

[[ -z "${LATEST_API}" ]] && die "Konnte neueste Version von ${HUB_IMAGE_API} nicht ermitteln (Docker Hub nicht erreichbar?)."
[[ -z "${LATEST_RUNNER}" ]] && die "Konnte neueste Version von ${HUB_IMAGE_RUNNER} nicht ermitteln (Docker Hub nicht erreichbar?)."

info "Neueste ${HUB_IMAGE_API}:    ${BOLD}${LATEST_API}${RESET}"
info "Neueste ${HUB_IMAGE_RUNNER}: ${BOLD}${LATEST_RUNNER}${RESET}"

if [[ "${LATEST_API}" != "${LATEST_RUNNER}" ]]; then
  warn "API- und Runner-Image sind auf Docker Hub aktuell NICHT auf derselben neuesten"
  warn "Versionsnummer (${LATEST_API} vs. ${LATEST_RUNNER}). Das kann bei frisch"
  warn "veröffentlichten Releases kurzzeitig vorkommen (siehe RELEASE.md im"
  warn "n8n-sandbox-service-Repo). Verwende die niedrigere der beiden als Vorschlag."
fi

# Numerischer Versionsvergleich statt lexikographisch (sonst wäre z.B.
# "1.9.0" > "1.10.0", weil '9' > '1'): die niedrigere der beiden Versionen
# gewinnt als Vorschlag, damit nie eine Version vorgeschlagen wird, die für
# eines der beiden Images noch gar nicht existiert.
LOWER_VERSION=$(printf '%s\n%s\n' "${LATEST_API}" "${LATEST_RUNNER}" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)
LATEST_VERSION="${LOWER_VERSION}"

if [[ "${CURRENT_VERSION}" == "${LATEST_VERSION}" ]]; then
  warn "Du bist bereits auf der neuesten bekannten Version (${CURRENT_VERSION})."
  if ! ask_yesno "Trotzdem fortfahren?" "n"; then
    info "Abgebrochen."
    exit 0
  fi
fi

ask TARGET_VERSION "Auf welche Version updaten?" "${LATEST_VERSION}"

info "Prüfe, ob Version ${TARGET_VERSION} für alle benötigten Images existiert..."
CHECK_API=$(tag_exists_on_hub "${HUB_IMAGE_API}" "${TARGET_VERSION}")
CHECK_RUNNER=$(tag_exists_on_hub "${HUB_IMAGE_RUNNER}" "${TARGET_VERSION}")
CHECK_SANDBOX=$(tag_exists_on_hub "${HUB_IMAGE_SANDBOX}" "${TARGET_VERSION}")

[[ "${CHECK_API}" -eq 0 ]] && die "${HUB_IMAGE_API}:${TARGET_VERSION} existiert nicht."
[[ "${CHECK_RUNNER}" -eq 0 ]] && die "${HUB_IMAGE_RUNNER}:${TARGET_VERSION} existiert nicht."
if [[ "${CHECK_SANDBOX}" -eq 0 ]]; then
  warn "${HUB_IMAGE_SANDBOX}:${TARGET_VERSION} existiert nicht (Sandbox-Template-Image)."
  warn "Das ist das Image, das der Runner intern für jede Code-Ausführung startet –"
  warn "ohne dieses Image funktioniert die Sandbox nach dem Update nicht."
  if ! ask_yesno "Trotzdem fortfahren?" "n"; then
    info "Abgebrochen."
    exit 0
  fi
fi
success "Version ${TARGET_VERSION} ist verfügbar."

# ── Zusammenfassung & Bestätigung ─────────────────────────────────────────────
echo ""
echo -e "────────────────────────────────────────────────────────────"
echo -e "${BOLD}  Zusammenfassung${RESET}"
echo -e "────────────────────────────────────────────────────────────"
echo -e "  Installationspfad: ${CYAN}${INSTALL_DIR}${RESET}"
echo -e "  Von Version:       ${CYAN}${CURRENT_VERSION}${RESET}"
echo -e "  Auf Version:       ${CYAN}${TARGET_VERSION}${RESET}"
echo ""

if [[ "${TARGET_VERSION}" == "${CURRENT_VERSION}" ]]; then
  warn "Ziel- und Ist-Version sind identisch – es wird nur neu gepullt/gestartet."
fi

if ! ask_yesno "Update jetzt starten?" "j"; then
  info "Abgebrochen."
  exit 0
fi

# ── Volume-Name ermitteln ─────────────────────────────────────────────────────
# Named Volume statt Bind-Mount: der tatsächliche Docker-Volume-Name trägt
# ein Compose-Projekt-Präfix. Zuverlässiger Weg, ihn zu finden: über das von
# Compose gesetzte Label "com.docker.compose.project.working_dir" statt über
# den (nicht garantierten) Projektnamen zu raten.
get_volume_name() {
  local vol
  vol=$(${SUDO} docker volume ls -q \
    --filter "label=com.docker.compose.project.working_dir=${INSTALL_DIR}" \
    --filter "label=com.docker.compose.volume=sandbox-tls" 2>/dev/null | head -1)
  if [[ -z "${vol}" ]]; then
    local base proj
    base="$(basename "${INSTALL_DIR}")"
    # printf statt echo/Pipe direkt aus basename, damit kein Zeilenumbruch
    # mit in die tr-Ersetzung gerät (der sonst als '-' am Ende landen würde).
    proj=$(printf '%s' "${base}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-')
    vol="${proj}_sandbox-tls"
  fi
  echo "${vol}"
}

VOLUME_NAME="$(get_volume_name)"
if ${SUDO} docker volume inspect "${VOLUME_NAME}" &>/dev/null; then
  info "mTLS-Volume gefunden: ${VOLUME_NAME}"
else
  warn "mTLS-Volume '${VOLUME_NAME}' nicht gefunden – Volume-Backup wird übersprungen."
  VOLUME_NAME=""
fi

# ── Backup ────────────────────────────────────────────────────────────────────
ask BACKUP_DIR "Backup-Verzeichnis" "${INSTALL_DIR}/backups"
ask MAX_BACKUPS "Wie viele Backups behalten?" "5"

BACKUP_PATH=""

create_backup() {
  echo ""
  info "Erstelle Backup..."

  local backup_name
  backup_name="sandbox_backup_${CURRENT_VERSION}_$(date +%Y%m%d_%H%M%S)"
  local backup_path="${BACKUP_DIR}/${backup_name}"

  run ${SUDO} mkdir -p "${backup_path}"

  run ${SUDO} cp "${ENV_FILE}" "${backup_path}/.env"
  success ".env gesichert."

  run ${SUDO} cp "${COMPOSE_FILE}" "${backup_path}/docker-compose.yml"
  success "docker-compose.yml gesichert."

  if [[ -n "${VOLUME_NAME}" ]]; then
    # mTLS-Zertifikate werden zwar von bootstrap-mtls.sh idempotent neu
    # bootstrapped (kein Regen ohne SANDBOX_TLS_REGEN=1) – das Backup ist
    # trotzdem ein zusätzliches Sicherheitsnetz, keine Voraussetzung fürs
    # Rollback.
    if run ${SUDO} docker run --rm \
      -v "${VOLUME_NAME}:/from:ro" \
      -v "${backup_path}:/to" \
      alpine sh -c "cd /from && tar czf /to/sandbox-tls.tar.gz ."; then
      success "mTLS-Volume gesichert (sandbox-tls.tar.gz)."
    else
      warn "mTLS-Volume-Backup fehlgeschlagen – Update läuft trotzdem weiter."
    fi
  fi

  success "Backup erstellt: ${backup_path}"

  if [[ "${DRY_RUN}" -ne 1 ]]; then
    local backup_count
    backup_count=$(${SUDO} find "${BACKUP_DIR}" -maxdepth 1 -type d -name 'sandbox_backup_*' 2>/dev/null | wc -l)
    if [[ "${backup_count}" -gt "${MAX_BACKUPS}" ]]; then
      local to_delete=$(( backup_count - MAX_BACKUPS ))
      info "Rotiere alte Backups (behalte ${MAX_BACKUPS}, lösche ${to_delete})..."
      ${SUDO} find "${BACKUP_DIR}" -maxdepth 1 -type d -name 'sandbox_backup_*' -printf '%T@ %p\n' \
        | sort -n | head -n "${to_delete}" | cut -d' ' -f2- \
        | while IFS= read -r old; do ${SUDO} rm -rf "${old}"; done
      success "Alte Backups bereinigt."
    fi
  fi

  BACKUP_PATH="${backup_path}"
}

# ── Update ────────────────────────────────────────────────────────────────────
update_env() {
  info "Aktualisiere SANDBOX_IMAGE_TAG in .env..."
  run ${SUDO} sed -i "s|^SANDBOX_IMAGE_TAG=.*|SANDBOX_IMAGE_TAG=${TARGET_VERSION}|" "${ENV_FILE}"
  success ".env aktualisiert (SANDBOX_IMAGE_TAG=${TARGET_VERSION})."
}

pull_images() {
  info "Lade Images (${TARGET_VERSION})..."
  (cd "${INSTALL_DIR}" && run $COMPOSE_CMD pull)
  success "Images geladen."
}

restart_stack() {
  info "Starte Stack neu..."
  (cd "${INSTALL_DIR}" && run $COMPOSE_CMD down)
  (cd "${INSTALL_DIR}" && run $COMPOSE_CMD up -d)
  success "Stack gestartet."
}

# ── Health Check ──────────────────────────────────────────────────────────────
# Interner Docker-Healthcheck-Status statt externem curl auf die öffentliche
# Domain: NPM/DNS sind für diesen Stack optional und liegen außerhalb der
# Kontrolle dieses Scripts (siehe install-n8n-sandbox.sh) – der Container
# selbst weiß zuverlässig, ob er gesund ist.
health_check() {
  info "Warte auf Health Check der Sandbox-API (max. $((HEALTH_CHECK_RETRIES * HEALTH_CHECK_INTERVAL))s)..."

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${RESET} Health Check übersprungen."
    return 0
  fi

  local attempt=0 api_cid status
  while [[ "${attempt}" -lt "${HEALTH_CHECK_RETRIES}" ]]; do
    attempt=$(( attempt + 1 ))
    api_cid=$( (cd "${INSTALL_DIR}" && $COMPOSE_CMD ps -q sandbox-api 2>/dev/null) || true)
    if [[ -n "${api_cid}" ]]; then
      status=$(${SUDO} docker inspect -f '{{.State.Health.Status}}' "${api_cid}" 2>/dev/null || echo "unknown")
      if [[ "${status}" == "healthy" ]]; then
        success "Sandbox-API ist healthy."
        return 0
      fi
    fi
    sleep "${HEALTH_CHECK_INTERVAL}"
  done

  error "Sandbox-API meldet nach $((HEALTH_CHECK_RETRIES * HEALTH_CHECK_INTERVAL))s keinen 'healthy'-Status."
  return 1
}

# ── Rollback ──────────────────────────────────────────────────────────────────
rollback() {
  echo ""
  error "Fehler aufgetreten – starte Rollback auf Version ${CURRENT_VERSION}..."

  if [[ -n "${BACKUP_PATH}" ]]; then
    run ${SUDO} cp "${BACKUP_PATH}/.env" "${ENV_FILE}"
    warn ".env aus Backup wiederhergestellt (SANDBOX_IMAGE_TAG=${CURRENT_VERSION})."

    if [[ -n "${VOLUME_NAME}" ]] && [[ -f "${BACKUP_PATH}/sandbox-tls.tar.gz" ]]; then
      if run ${SUDO} docker run --rm \
        -v "${VOLUME_NAME}:/to" \
        -v "${BACKUP_PATH}:/from:ro" \
        alpine sh -c "rm -rf /to/* && tar xzf /from/sandbox-tls.tar.gz -C /to"; then
        warn "mTLS-Volume aus Backup wiederhergestellt."
      else
        warn "mTLS-Volume-Wiederherstellung fehlgeschlagen (Zertifikate werden ggf. neu gebootstrapped)."
      fi
    fi
  else
    run ${SUDO} sed -i "s|^SANDBOX_IMAGE_TAG=.*|SANDBOX_IMAGE_TAG=${CURRENT_VERSION}|" "${ENV_FILE}"
    warn "SANDBOX_IMAGE_TAG in .env zurückgesetzt auf ${CURRENT_VERSION}."
  fi

  (cd "${INSTALL_DIR}" && run $COMPOSE_CMD down)
  (cd "${INSTALL_DIR}" && run $COMPOSE_CMD up -d)
  warn "Stack mit Version ${CURRENT_VERSION} neu gestartet."

  echo ""
  error "Rollback abgeschlossen. Bitte Status manuell prüfen:"
  echo -e "  ${CYAN}cd ${INSTALL_DIR} && ${COMPOSE_CMD} logs -f${RESET}"
  echo ""
}

# ── Alte Images aufräumen ─────────────────────────────────────────────────────
cleanup_old_images() {
  [[ "${TARGET_VERSION}" == "${CURRENT_VERSION}" ]] && return 0

  echo ""
  if ! ask_yesno "Alte Images (Version ${CURRENT_VERSION}) jetzt löschen?" "j"; then
    info "Alte Images bleiben erhalten."
    return 0
  fi

  info "Räume alte Images auf..."
  local cleaned=0
  for image in "${GHCR_IMAGE_API}" "${GHCR_IMAGE_RUNNER}"; do
    if ${SUDO} docker image inspect "${image}:${CURRENT_VERSION}" &>/dev/null; then
      if run ${SUDO} docker rmi "${image}:${CURRENT_VERSION}" &>/dev/null; then
        success "Gelöscht: ${image}:${CURRENT_VERSION}"
        cleaned=$(( cleaned + 1 ))
      else
        warn "Konnte ${image}:${CURRENT_VERSION} nicht löschen (evtl. noch referenziert)."
      fi
    fi
  done
  [[ "${cleaned}" -eq 0 ]] && info "Keine alten Images gefunden/gelöscht."

  # Hinweis wie im Uninstall-Script: das Sandbox-Template-Image läuft im
  # inneren Docker-in-Docker-Daemon des Runners und ist vom Host aus nicht
  # unabhängig sichtbar/löschbar.
  info "Hinweis: ${GHCR_IMAGE_SANDBOX} (Sandbox-Template) liegt im inneren DinD-"
  info "Daemon von sandbox-runner-1 und wird dort automatisch bei Bedarf neu gezogen."
}

# ── Hauptprogramm ─────────────────────────────────────────────────────────────
create_backup

trap 'rollback' ERR

update_env
pull_images
restart_stack

if ! health_check; then
  trap - ERR
  rollback
  exit 1
fi

trap - ERR

cleanup_old_images

# ── Abschluss ─────────────────────────────────────────────────────────────────
echo ""
echo -e "────────────────────────────────────────────────────────────"
echo -e "${GREEN}${BOLD}  ✓ Update abgeschlossen!${RESET}"
echo -e "────────────────────────────────────────────────────────────"
echo ""
echo -e "  Version:  ${CYAN}${CURRENT_VERSION}${RESET} → ${CYAN}${TARGET_VERSION}${RESET}"
echo -e "  Backup:   ${CYAN}${BACKUP_PATH}${RESET}"
echo ""
echo -e "  Status prüfen:"
echo -e "  ${CYAN}cd ${INSTALL_DIR} && ${COMPOSE_CMD} ps${RESET}"
echo ""
echo -e "  Mehr Tipps & Tutorials: ${CYAN}https://pc-fee.com/blog${RESET}"
echo -e "  GitHub:                 ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
