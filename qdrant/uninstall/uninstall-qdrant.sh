#!/usr/bin/env bash
# =============================================================================
# Qdrant Uninstall Script - powered by pc-fee.com
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Entfernt eine mit install-qdrant.sh installierte Qdrant-Instanz.
#
# ACHTUNG - UNWIDERRUFLICH: Mit dem Installationsverzeichnis werden ALLE
# Collections geloescht (Vektoren, Payloads, Indizes) - also z.B. die
# Wissensbasis deiner n8n-RAG-Workflows. Vorher unbedingt mit --dry-run pruefen
# und ein Backup sicherstellen (backup-qdrant.sh --backup).
#
# Scope - entfernt wird ausschliesslich, was zur erkannten Qdrant-Installation
# gehoert:
#   - der Qdrant-Container dieser Compose-Datei
#   - das Installationsverzeichnis: docker-compose.yml, .env (API-Key),
#     storage/ (alle Collections), snapshots/ (Arbeitsordner)
#   - NUR nach eigener Rueckfrage: das Backup-Verzeichnis (Update-Backups und
#     Snapshot-Saetze, Default /opt/qdrant-backups)
#   - NUR nach eigener Rueckfrage: die lokalen qdrant/qdrant-Images
#
# Wird NIE angefasst:
#   - das Docker-Netzwerk (Standard: shared_proxy) - es wird von weiteren
#     Stacks (n8n, LibreChat, Nginx Proxy Manager, ...) mitgenutzt
#   - Container anderer Stacks; Proxy Hosts im Nginx Proxy Manager;
#     n8n-Credentials, die auf Qdrant zeigen; Cron-Eintraege; Logdateien
#     (diese werden nur erkannt und gemeldet)
#
# Nutzung als 1-Zeiler (von ueberall, kein vorheriger Download noetig):
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/uninstall/uninstall-qdrant.sh)"
#
# Optionen:
#   --dir <pfad>   Installationspfad fest vorgeben (ueberspringt die Erkennung)
#   --dry-run      Zeigt nur, was entfernt wuerde - loescht nichts
#   --yes          Ueberspringt alle Sicherheitsabfragen (wie ASSUME_YES=1)
#   --help         Diese Hilfe anzeigen
#
# Umgebungsvariablen (fuer unbeaufsichtigten Betrieb):
#   INSTALL_DIR    wie --dir
#   ASSUME_YES=1   wie --yes (loescht dann auch Backups und Images ungefragt)
#
# Ohne echtes Terminal (z.B. Cron) wird nichts geloescht, ausser ASSUME_YES=1
# ist ausdruecklich gesetzt.
#
# Voraussetzungen: root (bzw. sudo), Docker + Docker Compose.
#
# Autor: Nils Weber (n8n Automation Architect, pc-fee.com)
#
# AI Transparency: Dieses Script wurde mit Unterstuetzung von KI erstellt und
# vor Veroeffentlichung geprueft. Es entfernt unwiderruflich Daten - bitte
# vorher mit --dry-run pruefen und ein Backup sicherstellen.
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
readonly DEFAULT_DIR="/opt/qdrant"
readonly DEFAULT_BACKUP_DIR="/opt/qdrant-backups"
readonly IMAGE_REPO="qdrant/qdrant"
readonly STORAGE_MOUNT="/qdrant/storage"
readonly REPO_RAW="https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant"
readonly INSTALL_SCRIPT_URL="${REPO_RAW}/install/install-qdrant.sh"
readonly BACKUP_SCRIPT_URL="${REPO_RAW}/backup/backup-qdrant.sh"

# -- Optionen ------------------------------------------------------------------
DRY_RUN=0

usage() {
  cat <<'USAGE'
Qdrant Uninstall Script - powered by pc-fee.com

Entfernt eine mit install-qdrant.sh installierte Qdrant-Instanz: Container und
Installationsverzeichnis (inkl. ALLER Collections), auf Wunsch die Backups und
die Docker-Images - jeweils mit eigener Rueckfrage. Das Docker-Netzwerk
(shared_proxy) bleibt unangetastet.

Optionen:
  --dir <pfad>   Installationspfad fest vorgeben (ueberspringt die Erkennung)
  --dry-run      Zeigt nur, was entfernt wuerde - loescht nichts
  --yes          Ueberspringt alle Sicherheitsabfragen (wie ASSUME_YES=1)
  --help         Diese Hilfe anzeigen

Umgebungsvariablen: INSTALL_DIR, ASSUME_YES

Beispiele:
  sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/uninstall/uninstall-qdrant.sh)"
  sudo ./uninstall-qdrant.sh --dry-run
  sudo ./uninstall-qdrant.sh --dir /srv/qdrant
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)     INSTALL_DIR="${2:-}"; shift 2 || true ;;
    --dir=*)   INSTALL_DIR="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y)  ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         echo "Unbekannte Option: $1 (siehe --help)" >&2; exit 1 ;;
  esac
done
readonly DRY_RUN

# -- Eingabequelle -------------------------------------------------------------
# Wird das Script per 'curl ... | bash' gestartet, liegt auf stdin der Script-
# Text selbst - ein 'read' wuerde ihn verschlucken. Deshalb immer vom Terminal
# lesen. Ohne Terminal wird nichts geloescht, ausser ASSUME_YES=1 ist gesetzt.
# Achtung: '[[ -r /dev/tty ]]' prueft nur die Rechtebits und ist auch dann wahr,
# wenn es gar kein steuerndes Terminal gibt (z.B. Cron). Deshalb wirklich oeffnen.
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

# ask_yesno <prompt> <default: j|n> -> Rueckgabewert via $? (0 = ja)
ask_yesno() {
  local prompt="$1" default="${2:-n}" input="" hint="j/N"
  [[ "${default,,}" == "j" ]] && hint="J/n"
  if [[ "${ASSUME_YES:-0}" == "1" ]]; then
    info "ASSUME_YES gesetzt - uebersprungene Abfrage: ${prompt}"
    return 0
  fi
  if [[ "${INTERACTIVE}" -eq 0 ]]; then
    warn "Kein Terminal fuer die Rueckfrage verfuegbar: ${prompt}"
    warn "Ohne Bestaetigung wird nichts entfernt (ASSUME_YES=1 setzen, falls gewollt)."
    return 1
  fi
  echo ""
  echo -ne "${BOLD}${prompt}${RESET} [${CYAN}${hint}${RESET}]: "
  read -r input <"${TTY}" || true
  input="${input:-${default}}"
  [[ "${input,,}" == "j" || "${input,,}" == "y" ]]
}

# run <befehl...> - im Dry-Run nur anzeigen, sonst ausfuehren.
run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo -e "${YELLOW}   [DRY-RUN]${RESET} $*"
  else
    "$@"
  fi
}

# -- Banner --------------------------------------------------------------------
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
printf '%b\n' "${BOLD} Qdrant Uninstall - powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo -e " Entfernt eine mit ${BOLD}install-qdrant.sh${RESET} installierte Qdrant-Instanz:"
echo -e " Container und Installationsverzeichnis ${RED}inkl. ALLER Collections${RESET},"
echo -e " auf Wunsch Backups und Images (jeweils eigene Rueckfrage)."
echo ""
echo -e " ${YELLOW}Wird NICHT angefasst:${RESET} das Docker-Netzwerk (shared_proxy) und"
echo -e " die Container anderer Stacks (n8n, LibreChat, Nginx Proxy Manager, ...)."
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo -e " ${YELLOW}${BOLD}DRY-RUN aktiv:${RESET} es wird nichts geloescht, nur angezeigt."
fi
echo "------------------------------------------------------------"

# -- Root-Check ----------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  die "Bitte als root oder mit sudo ausfuehren."
fi
cd / 2>/dev/null || die "Konnte nicht nach / wechseln."

# -- Voraussetzungen pruefen ---------------------------------------------------
command -v docker &>/dev/null || die "Docker ist nicht installiert - hier gibt es nichts zu entfernen."
docker info &>/dev/null || die "Docker-Daemon laeuft nicht. Bitte starten: systemctl start docker"
if docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
else
  die "Docker Compose nicht gefunden."
fi
readonly COMPOSE_CMD

# -- Installationspfad ermitteln -----------------------------------------------
# Identische Erkennung wie im Update-Script: Container-Label -> Volume-Quelle
# -> Standardpfad. Ein Verzeichnis gilt als Qdrant-Installation, wenn es eine
# Compose-Datei mit qdrant/qdrant-Image enthaelt.
compose_file_of() {
  local d="$1" f
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    if [[ -f "${d}/${f}" ]] && grep -qE "image:[[:space:]]*[\"']?${IMAGE_REPO}(:|[\"']?[[:space:]]*$)" "${d}/${f}"; then
      echo "${d}/${f}"
      return 0
    fi
  done
  return 1
}

detect_dirs() {
  local -a raw=() out=()
  local cid d existing seen
  while IFS= read -r cid; do
    [[ -n "${cid}" ]] || continue
    d=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "${cid}" 2>/dev/null || true)
    [[ -n "${d}" && "${d}" == /* ]] && raw+=("${d}")
    d=$(docker inspect --format "{{range .Mounts}}{{if eq .Destination \"${STORAGE_MOUNT}\"}}{{.Source}}{{end}}{{end}}" "${cid}" 2>/dev/null || true)
    [[ -n "${d}" && "${d}" == /* ]] && raw+=("$(dirname "${d}")")
  done < <(docker ps -a --format '{{.ID}} {{.Image}}' | awk -v img="${IMAGE_REPO}" 'index($2, img) == 1 {print $1}')
  raw+=("${DEFAULT_DIR}")
  for d in "${raw[@]}"; do
    compose_file_of "${d}" >/dev/null 2>&1 || continue
    seen=0
    for existing in ${out[@]+"${out[@]}"}; do
      [[ "${existing}" == "${d}" ]] && seen=1
    done
    [[ "${seen}" -eq 0 ]] && out+=("${d}")
  done
  [[ "${#out[@]}" -gt 0 ]] && printf '%s\n' "${out[@]}"
  return 0
}

# Alle Container mit Qdrant-Image (auch verwaiste, deren Verzeichnis schon weg ist).
mapfile -t QDRANT_CONTAINERS < <(docker ps -a --format '{{.Names}} {{.Image}}' | awk -v img="${IMAGE_REPO}" 'index($2, img) == 1 {print $1}')

if [[ -n "${INSTALL_DIR:-}" ]]; then
  INSTALL_DIR="${INSTALL_DIR%/}"
  [[ -d "${INSTALL_DIR}" ]] || die "Angegebener Pfad existiert nicht: ${INSTALL_DIR}"
  compose_file_of "${INSTALL_DIR}" >/dev/null \
    || die "In ${INSTALL_DIR} liegt keine Compose-Datei mit einem ${IMAGE_REPO}-Image - aus Sicherheitsgruenden wird hier nichts geloescht."
  info "Installationspfad (vorgegeben): ${INSTALL_DIR}"
else
  mapfile -t FOUND < <(detect_dirs)
  case "${#FOUND[@]}" in
    0)
      if [[ "${#QDRANT_CONTAINERS[@]}" -gt 0 ]]; then
        warn "Kein Installationsverzeichnis gefunden, aber es existieren noch Qdrant-Container:"
        for c in "${QDRANT_CONTAINERS[@]}"; do echo -e "   - ${CYAN}${c}${RESET}"; done
        if ask_yesno "${BOLD}Diese verwaisten Container entfernen?${RESET}" "n"; then
          for c in "${QDRANT_CONTAINERS[@]}"; do run docker rm -f "${c}"; done
          success "Verwaiste Container entfernt."
        else
          warn "Abgebrochen. Es wurde nichts veraendert."
        fi
        exit 0
      fi
      success "Nichts zu tun - keine Qdrant-Installation und keine Container gefunden."
      exit 0
      ;;
    1)
      INSTALL_DIR="${FOUND[0]}"
      info "Installation erkannt: ${INSTALL_DIR}"
      ;;
    *)
      echo ""
      warn "Mehrere Qdrant-Installationen gefunden:"
      for i in "${!FOUND[@]}"; do
        echo -e "   ${BOLD}$((i + 1)))${RESET} ${CYAN}${FOUND[$i]}${RESET}"
      done
      [[ "${INTERACTIVE}" -eq 1 ]] \
        || die "Kein Terminal fuer die Rueckfrage verfuegbar. Bitte --dir <pfad> setzen."
      choice=""
      echo ""
      echo -ne "${BOLD}Welche soll entfernt werden?${RESET} [${CYAN}1${RESET}]: "
      read -r choice <"${TTY}" || true
      choice="${choice:-1}"
      { [[ "${choice}" =~ ^[0-9]+$ ]] && [[ "${choice}" -ge 1 ]] && [[ "${choice}" -le "${#FOUND[@]}" ]]; } \
        || die "Ungueltige Auswahl: ${choice}"
      INSTALL_DIR="${FOUND[$((choice - 1))]}"
      ;;
  esac
fi
readonly INSTALL_DIR

# Sicherheitsnetz: niemals System-Verzeichnisse loeschen, auch wenn dort
# zufaellig eine passende Compose-Datei liegt.
case "${INSTALL_DIR}" in
  /|/opt|/srv|/home|/root|/usr|/var|/etc|/bin|/sbin|/lib|/boot|/tmp|/mnt|/media)
    die "${INSTALL_DIR} ist ein System-Verzeichnis - aus Sicherheitsgruenden wird es nicht geloescht."
    ;;
esac

COMPOSE_FILE="$(compose_file_of "${INSTALL_DIR}")"
readonly COMPOSE_FILE
ENV_FILE="${INSTALL_DIR}/.env"
BACKUP_DIR=""
if [[ -f "${ENV_FILE}" ]]; then
  BACKUP_DIR="$(sed -n 's/^[[:space:]]*QDRANT_BACKUP_DIR=//p' "${ENV_FILE}" | tail -n 1 | sed -e 's/^["'\'']//' -e 's/["'\'']$//')"
  DOMAIN="$(sed -n 's/^[[:space:]]*QDRANT_DOMAIN=//p' "${ENV_FILE}" | tail -n 1 | sed -e 's/^["'\'']//' -e 's/["'\'']$//')"
fi
BACKUP_DIR="${BACKUP_DIR:-${DEFAULT_BACKUP_DIR}}"
BACKUP_DIR="${BACKUP_DIR%/}"
DOMAIN="${DOMAIN:-}"
readonly BACKUP_DIR DOMAIN

# -- Bestandsaufnahme ----------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Bestandsaufnahme${RESET}"
echo "------------------------------------------------------------"

CONTAINERS=$(${COMPOSE_CMD} -f "${COMPOSE_FILE}" ps -a --format '{{.Name}}' 2>/dev/null || true)
NETWORKS=""
if [[ -n "${CONTAINERS}" ]]; then
  info "Folgende Container werden entfernt:"
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    echo -e "   - ${CYAN}${c}${RESET} ($(docker inspect -f '{{.Config.Image}}, {{.State.Status}}' "${c}" 2>/dev/null || echo '?'))"
    NETWORKS+="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "${c}" 2>/dev/null || true) "
  done <<<"${CONTAINERS}"
else
  warn "Kein Container zu dieser Compose-Datei gefunden (evtl. schon entfernt)."
fi

# Collections zaehlen (ohne API): jedes Unterverzeichnis von storage/collections.
COLL_LIST=""
if [[ -d "${INSTALL_DIR}/storage/collections" ]]; then
  COLL_LIST=$(find "${INSTALL_DIR}/storage/collections" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort || true)
fi
COLL_COUNT=0
[[ -n "${COLL_LIST}" ]] && COLL_COUNT=$(printf '%s\n' "${COLL_LIST}" | wc -l | tr -d ' ')

echo ""
info "Folgendes Verzeichnis wird entfernt: ${BOLD}${INSTALL_DIR}${RESET} ($(du -sh "${INSTALL_DIR}" 2>/dev/null | cut -f1))"
echo -e "     ${YELLOW}+- $(basename "${COMPOSE_FILE}")${RESET}"
[[ -f "${ENV_FILE}" ]] && \
  echo -e "     ${YELLOW}+- .env${RESET}            - enthaelt den API-Key"
if [[ -d "${INSTALL_DIR}/storage" ]]; then
  echo -e "     ${YELLOW}+- storage/${RESET}        - ${RED}${COLL_COUNT} Collection(s)${RESET}, $(du -sh "${INSTALL_DIR}/storage" 2>/dev/null | cut -f1)"
  if [[ -n "${COLL_LIST}" ]]; then
    while IFS= read -r c; do [[ -n "$c" ]] && echo -e "          - ${c}"; done <<<"${COLL_LIST}"
  fi
fi
[[ -d "${INSTALL_DIR}/snapshots" ]] && \
  echo -e "     ${YELLOW}+- snapshots/${RESET}      - Qdrant-Arbeitsordner, $(du -sh "${INSTALL_DIR}/snapshots" 2>/dev/null | cut -f1)"
OTHER_FILES=$(find "${INSTALL_DIR}" -mindepth 1 -maxdepth 1 ! -name "$(basename "${COMPOSE_FILE}")" ! -name '.env' ! -name 'storage' ! -name 'snapshots' -printf '%f\n' 2>/dev/null || true)
if [[ -n "${OTHER_FILES}" ]]; then
  while IFS= read -r f; do [[ -n "$f" ]] && echo -e "     ${YELLOW}+- ${f}${RESET}  - (nicht vom Installer angelegt, wird mitgeloescht)"; done <<<"${OTHER_FILES}"
fi

# Backups: eigenes Verzeichnis, eigene Abfrage.
UPD_COUNT=0
SET_COUNT=0
BACKUP_SIZE="0"
if [[ -d "${BACKUP_DIR}" ]]; then
  UPD_COUNT=$(find "${BACKUP_DIR}" -maxdepth 1 -name 'qdrant-update_*.tar.gz' -type f 2>/dev/null | wc -l | tr -d ' ')
  SET_COUNT=$(find "${BACKUP_DIR}" -maxdepth 1 -mindepth 1 -name 'snapshots_*' -type d 2>/dev/null | wc -l | tr -d ' ')
  BACKUP_SIZE=$(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1)
  echo ""
  info "Backup-Verzeichnis ${BOLD}${BACKUP_DIR}${RESET} (${BACKUP_SIZE}) - separate Abfrage, Standard: behalten"
  echo -e "     - ${UPD_COUNT} Update-Backup(s), ${SET_COUNT} Snapshot-Satz/Saetze"
fi

# Andere Container am selben Netzwerk: die laufen weiter.
for net in $(echo "${NETWORKS}" | tr ' ' '\n' | sort -u); do
  [[ -n "${net}" ]] || continue
  OTHERS=$(docker network inspect "${net}" --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' 2>/dev/null \
    | grep -v '^$' | grep -vxF -f <(printf '%s\n' "${CONTAINERS}") || true)
  if [[ -n "${OTHERS}" ]]; then
    echo ""
    info "Am Netzwerk '${net}' haengen weitere Container - sie laufen unveraendert weiter:"
    while IFS= read -r c; do [[ -n "$c" ]] && echo -e "   - ${CYAN}${c}${RESET}"; done <<<"${OTHERS}"
  fi
done

# Weitere Qdrant-Container ausserhalb dieser Installation: nur melden.
FOREIGN=""
for c in ${QDRANT_CONTAINERS[@]+"${QDRANT_CONTAINERS[@]}"}; do
  printf '%s\n' "${CONTAINERS}" | grep -qxF -- "${c}" || FOREIGN+="${c} "
done
if [[ -n "${FOREIGN}" ]]; then
  echo ""
  warn "Weitere Qdrant-Container, die NICHT zu ${INSTALL_DIR} gehoeren (werden nicht angefasst): ${FOREIGN}"
fi

# Images ermitteln (ueber mehrere Updates koennen sich mehrere Tags ansammeln).
mapfile -t IMAGE_LINES < <(docker images --format '{{.Repository}}:{{.Tag}}	{{.ID}}' 2>/dev/null | awk -v img="${IMAGE_REPO}:" 'index($1, img) == 1' || true)
if [[ "${#IMAGE_LINES[@]}" -gt 0 ]]; then
  echo ""
  info "Lokal vorhandene Qdrant-Images (werden nur nach eigener Rueckfrage geloescht):"
  for line in "${IMAGE_LINES[@]}"; do
    echo -e "   - ${CYAN}${line%%$'\t'*}${RESET} ($(echo "${line##*$'\t'}" | cut -c1-19))"
  done
fi

echo ""
echo -e " ${RED}${BOLD}Unwiderruflich:${RESET} Alle Collections in storage/ (Vektoren, Payloads,"
echo -e " Indizes) sind danach weg - n8n-Workflows, die Qdrant nutzen, schlagen fehl."
if [[ "${SET_COUNT}" -eq 0 && "${DRY_RUN}" -eq 0 ]]; then
  echo -e " ${YELLOW}Es gibt noch keinen Snapshot-Satz.${RESET} Backup vorher erstellen:"
  echo -e "   ${CYAN}sudo bash -c \"\$(curl -fsSL ${BACKUP_SCRIPT_URL})\" -- --backup${RESET}"
fi

# -- Bestaetigungen - jede einzeln ---------------------------------------------
echo ""
echo "------------------------------------------------------------"
if ! ask_yesno "${RED}${BOLD}Wirklich den Container und ${INSTALL_DIR} inkl. aller Collections unwiderruflich entfernen?${RESET}" "n"; then
  warn "Abgebrochen. Es wurde nichts veraendert."
  exit 0
fi

REMOVE_BACKUPS=false
if [[ -d "${BACKUP_DIR}" ]]; then
  if ask_yesno "Auch das Backup-Verzeichnis ${BACKUP_DIR} (${BACKUP_SIZE}, ${UPD_COUNT} Update-Backups, ${SET_COUNT} Snapshot-Saetze) loeschen?" "n"; then
    REMOVE_BACKUPS=true
  fi
fi

REMOVE_IMAGES=false
if [[ "${#IMAGE_LINES[@]}" -gt 0 ]]; then
  if ask_yesno "Zusaetzlich die oben gelisteten Qdrant-Images loeschen?" "n"; then
    REMOVE_IMAGES=true
  fi
fi

# -- Entfernen -----------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Entfernen${RESET}"
echo "------------------------------------------------------------"

info "Stoppe und entferne Container (compose down - externe Netzwerke bleiben bestehen)..."
run ${COMPOSE_CMD} -f "${COMPOSE_FILE}" down --remove-orphans
success "Container entfernt."

info "Entferne Verzeichnis ${INSTALL_DIR}..."
run rm -rf "${INSTALL_DIR}"
success "Verzeichnis entfernt."

if ${REMOVE_BACKUPS}; then
  case "${BACKUP_DIR}" in
    /|/opt|/srv|/home|/root|/usr|/var|/etc|/tmp|/mnt|/media)
      warn "${BACKUP_DIR} ist ein System-Verzeichnis - wird aus Sicherheitsgruenden nicht geloescht." ;;
    *)
      info "Entferne Backup-Verzeichnis ${BACKUP_DIR}..."
      run rm -rf "${BACKUP_DIR}"
      success "Backups entfernt." ;;
  esac
else
  [[ -d "${BACKUP_DIR}" ]] && info "Backups bleiben erhalten: ${BACKUP_DIR}"
fi

if ${REMOVE_IMAGES}; then
  info "Entferne Images..."
  for line in "${IMAGE_LINES[@]}"; do
    run docker rmi "${line%%$'\t'*}" || warn "Image ${line%%$'\t'*} konnte nicht entfernt werden (evtl. noch von einem anderen Container genutzt)."
  done
  success "Image-Bereinigung abgeschlossen."
else
  info "Images bleiben erhalten."
fi

# -- Abschluss -----------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo -e "${YELLOW}${BOLD} DRY-RUN beendet - es wurde NICHTS geloescht.${RESET}"
else
  echo -e "${GREEN}${BOLD} Qdrant entfernt.${RESET}"
fi
echo "------------------------------------------------------------"
echo ""
echo -e " Unangetastet geblieben: das Docker-Netzwerk und alle Container anderer"
echo -e " Stacks (Nginx Proxy Manager, n8n, ...)."
echo ""

# Uebrig gebliebene Reste, die dieses Script bewusst nicht anfasst.
if crontab -l 2>/dev/null | grep -qE 'update-qdrant|backup-qdrant'; then
  warn "In der root-Crontab stehen noch Eintraege fuer update-qdrant.sh/backup-qdrant.sh."
  warn "Bitte manuell entfernen: crontab -e"
  echo ""
fi
for f in /var/log/qdrant-update.log /var/log/qdrant-backup.log; do
  [[ -f "${f}" ]] && info "Die Logdatei ${f} bleibt erhalten."
done
echo ""
if [[ -n "${DOMAIN}" ]]; then
  echo -e " Manuell entfernen, falls nicht mehr gebraucht:"
  echo -e "   - im Nginx Proxy Manager den Proxy Host ${CYAN}${DOMAIN}${RESET}"
  echo -e "   - beim Domain-Provider den A-Record fuer ${CYAN}${DOMAIN}${RESET}"
else
  echo -e " Manuell entfernen, falls nicht mehr gebraucht: den Proxy Host im"
  echo -e " Nginx Proxy Manager und den A-Record beim Domain-Provider."
fi
echo -e "   - in n8n die Qdrant-Credentials (sie zeigen jetzt ins Leere)"
echo ""
echo -e " Neuinstallation jederzeit moeglich mit:"
echo -e " ${CYAN}sudo bash -c \"\$(curl -fsSL ${INSTALL_SCRIPT_URL})\"${RESET}"
echo ""
echo -e " Mehr Tipps & Tutorials: ${CYAN}https://pc-fee.com/blog${RESET}"
echo -e " GitHub:                 ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
