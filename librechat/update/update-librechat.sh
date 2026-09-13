#!/usr/bin/env bash
# =============================================================================
# LibreChat Update Script - powered by pc-fee.com
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Aktualisiert eine mit install-librechat.sh installierte LibreChat-Instanz:
#   1. Bestandsaufnahme: Installation, Container, Git-Stand, Images, Config
#   2. Prueft auf Neuerungen: git fetch (Repository) + compose pull (Images);
#      der laufende Stack bleibt dabei unberuehrt
#   3. Zeigt eine Zusammenfassung JETZT -> NACHHER und fragt nach Bestaetigung
#   4. Erst danach: Backup von .env, librechat.yaml,
#      docker-compose.override.yml und ein mongodump der LibreChat-Datenbank
#   5. git merge --ff-only, Compose-Validierung, Stack neu hochfahren
#   6. Behaelt nur die N neuesten Backups (Default: 5), raeumt dangling Images auf
#
# Ohne Bestaetigung wird nichts veraendert. Fuer Cron: --yes bzw. ASSUME_YES=1.
#
# Nutzung als 1-Zeiler (von ueberall, kein vorheriger Download noetig):
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/update/update-librechat.sh)"
#
# Optionen:
#   --dir <pfad>   Installationspfad fest vorgeben (ueberspringt die Erkennung)
#   --keep <n>     Anzahl aufzubewahrender Backups (Default: 5)
#   --no-db        Kein mongodump - nur die Konfigurationsdateien sichern
#   --dry-run      Zeigt nur, was passieren wuerde - aendert nichts
#   --yes          Ueberspringt die Bestaetigung (wie ASSUME_YES=1, fuer Cron)
#   --help         Diese Hilfe anzeigen
#
# Umgebungsvariablen (fuer unbeaufsichtigten Betrieb, z.B. Cron):
#   INSTALL_DIR    wie --dir
#   KEEP_BACKUPS   wie --keep
#   ASSUME_YES=1   wie --yes
#   LOG_FILE       Logdatei (Default: /var/log/librechat-update.log)
#
# Der Installationspfad wird automatisch ermittelt (Container-Label ->
# Bind-Mount-Quelle -> /opt/librechat). Nur wenn mehrere Installationen
# gefunden werden, fragt das Script nach.
#
# Voraussetzungen: root (bzw. sudo), Docker + Docker Compose, git, tar.
#
# AI Transparency: Dieses Script wurde mit Unterstuetzung von KI erstellt und
# vor Veroeffentlichung geprueft. Nutzung auf eigene Gefahr.
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
readonly LIBRECHAT_GUIDE="https://github.com/nephilim75/scripts/tree/main/librechat"
readonly DEFAULT_DIR="/opt/librechat"
# Marker, an dem eine Compose-Datei als LibreChat-Stack erkannt wird. Bewusst
# eng gefasst: ein blosses "librechat" wuerde auch fremde Stacks treffen.
readonly IMAGE_MARKER="danny-avila/librechat"
readonly MONGO_DB_NAME="LibreChat"
readonly BACKUP_PREFIX="librechat"

# -- Optionen ------------------------------------------------------------------
DRY_RUN=0
WITH_DB=1
KEEP="${KEEP_BACKUPS:-5}"
LOG="${LOG_FILE:-/var/log/librechat-update.log}"

usage() {
  cat <<'USAGE'
LibreChat Update Script - powered by pc-fee.com

Aktualisiert eine mit install-librechat.sh installierte LibreChat-Instanz:
Backup (.env, librechat.yaml, docker-compose.override.yml + mongodump),
git merge --ff-only, Image-Pull, Neustart des Stacks nur bei tatsaechlicher
Neuerung, Aufraeumen alter Backups und Images.

Optionen:
  --dir <pfad>   Installationspfad fest vorgeben (ueberspringt die Erkennung)
  --keep <n>     Anzahl aufzubewahrender Backups (Default: 5)
  --no-db        Kein mongodump - nur die Konfigurationsdateien sichern
  --dry-run      Zeigt nur, was passieren wuerde - aendert nichts
  --yes          Ueberspringt die Bestaetigung (wie ASSUME_YES=1, fuer Cron)
  --help         Diese Hilfe anzeigen

Das Script zeigt erst eine Zusammenfassung (JETZT -> NACHHER) und fragt nach,
bevor Backup, Repository-Update und Neustart starten.

Umgebungsvariablen: INSTALL_DIR, KEEP_BACKUPS, ASSUME_YES, LOG_FILE

Beispiele:
  sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/update/update-librechat.sh)"
  sudo ./update-librechat.sh --dry-run
  sudo ./update-librechat.sh --dir /srv/librechat --keep 10
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)     INSTALL_DIR="${2:-}"; shift 2 || true ;;
    --dir=*)   INSTALL_DIR="${1#*=}"; shift ;;
    --keep)    KEEP="${2:-}"; shift 2 || true ;;
    --keep=*)  KEEP="${1#*=}"; shift ;;
    --no-db)   WITH_DB=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y)  ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         echo "Unbekannte Option: $1 (siehe --help)" >&2; exit 1 ;;
  esac
done
readonly DRY_RUN WITH_DB

if ! [[ "${KEEP}" =~ ^[0-9]+$ ]] || [[ "${KEEP}" -lt 1 ]]; then
  echo "--keep erwartet eine positive Ganzzahl (erhalten: '${KEEP}')." >&2
  exit 1
fi
readonly KEEP

# -- Eingabequelle -------------------------------------------------------------
# Wird das Script per 'curl ... | bash' gestartet, liegt auf stdin der Script-
# Text selbst - ein 'read' wuerde ihn verschlucken. Deshalb immer vom Terminal
# lesen. Ohne Terminal (z.B. Cron) wird nie gefragt, sondern abgebrochen.
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
    warn "Ohne Bestaetigung wird nichts veraendert (fuer Cron: --yes bzw. ASSUME_YES=1)."
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
printf '%b\n' "${BOLD} LibreChat Update - powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo -e " ${YELLOW}${BOLD}DRY-RUN aktiv:${RESET} es wird nichts veraendert, nur angezeigt."
fi
echo "------------------------------------------------------------"

# -- Root-Check ----------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
  die "Bitte als root oder mit sudo ausfuehren."
fi

# Unbedingt in ein garantiert existierendes Verzeichnis wechseln. Wurde die CWD
# der aufrufenden Shell zwischenzeitlich geloescht, scheitern spaetere Aufrufe
# sonst mit 'getcwd: cannot access parent directories'. Das Script arbeitet
# ausschliesslich mit absoluten Pfaden.
cd / 2>/dev/null || die "Konnte nicht nach / wechseln."

# -- Voraussetzungen pruefen ---------------------------------------------------
command -v docker &>/dev/null || die "Docker ist nicht installiert."
docker info &>/dev/null || die "Docker-Daemon laeuft nicht. Bitte starten: systemctl start docker"

if docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
else
  die "Docker Compose nicht gefunden."
fi
readonly COMPOSE_CMD

command -v tar &>/dev/null || die "'tar' nicht gefunden - wird fuer das Backup gebraucht."

HAVE_GIT=1
command -v git &>/dev/null || HAVE_GIT=0

# -- Installationspfad ermitteln -----------------------------------------------
# Ein Verzeichnis gilt als LibreChat-Installation, wenn es eine Compose-Datei
# enthaelt, die auf ein danny-avila/librechat-Image verweist.
compose_file_of() {
  local d="$1" f
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    if [[ -f "${d}/${f}" ]] && grep -qi "${IMAGE_MARKER}" "${d}/${f}"; then
      echo "${d}/${f}"
      return 0
    fi
  done
  return 1
}

detect_dirs() {
  local -a raw=() out=()
  local cid d existing seen

  # 1. Container mit LibreChat-Image: Compose-Working-Dir aus dem Label lesen.
  while IFS= read -r cid; do
    [[ -n "${cid}" ]] || continue
    d=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "${cid}" 2>/dev/null || true)
    [[ -n "${d}" && "${d}" == /* ]] && raw+=("${d}")
    # 2. Fallback: Quelle des /app/.env-Bind-Mounts - deren Elternverzeichnis
    #    ist das Installationsverzeichnis.
    d=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/.env"}}{{.Source}}{{end}}{{end}}' "${cid}" 2>/dev/null || true)
    [[ -n "${d}" && "${d}" == /* ]] && raw+=("$(dirname "${d}")")
    d=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/uploads"}}{{.Source}}{{end}}{{end}}' "${cid}" 2>/dev/null || true)
    [[ -n "${d}" && "${d}" == /* ]] && raw+=("$(dirname "${d}")")
  done < <(docker ps -a --format '{{.ID}} {{.Image}}' | awk -v img="${IMAGE_MARKER}" 'index($2, img) {print $1}')

  # 3. Standardpfad des Installers.
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

if [[ -n "${INSTALL_DIR:-}" ]]; then
  [[ -d "${INSTALL_DIR}" ]] || die "Angegebener Pfad existiert nicht: ${INSTALL_DIR}"
  compose_file_of "${INSTALL_DIR}" >/dev/null \
    || die "In ${INSTALL_DIR} liegt keine Compose-Datei mit einem ${IMAGE_MARKER}-Image."
  info "Installationspfad (vorgegeben): ${INSTALL_DIR}"
else
  mapfile -t FOUND < <(detect_dirs)
  case "${#FOUND[@]}" in
    0)
      die "Keine LibreChat-Installation gefunden.\n  Erwartet wurde eine Compose-Datei mit ${IMAGE_MARKER}-Image,\n  z.B. unter ${DEFAULT_DIR}.\n  Pfad ggf. direkt angeben: --dir /pfad/zur/installation"
      ;;
    1)
      INSTALL_DIR="${FOUND[0]}"
      info "Installation erkannt: ${INSTALL_DIR}"
      ;;
    *)
      echo ""
      warn "Mehrere LibreChat-Installationen gefunden:"
      for i in "${!FOUND[@]}"; do
        echo -e "   ${BOLD}$((i + 1)))${RESET} ${CYAN}${FOUND[$i]}${RESET}"
      done
      [[ "${INTERACTIVE}" -eq 1 ]] \
        || die "Kein Terminal fuer die Rueckfrage verfuegbar. Bitte --dir <pfad> setzen (z.B. im Cron-Eintrag)."
      choice=""
      echo ""
      echo -ne "${BOLD}Welche soll aktualisiert werden?${RESET} [${CYAN}1${RESET}]: "
      read -r choice <"${TTY}" || true
      choice="${choice:-1}"
      { [[ "${choice}" =~ ^[0-9]+$ ]] && [[ "${choice}" -ge 1 ]] && [[ "${choice}" -le "${#FOUND[@]}" ]]; } \
        || die "Ungueltige Auswahl: ${choice}"
      INSTALL_DIR="${FOUND[$((choice - 1))]}"
      ;;
  esac
fi
readonly INSTALL_DIR

COMPOSE_FILE="$(compose_file_of "${INSTALL_DIR}")"
readonly COMPOSE_FILE
BACKUP_DIR="${INSTALL_DIR}/backups"
readonly BACKUP_DIR

# Compose immer aus dem Installationsverzeichnis heraus aufrufen: nur so zieht
# Docker Compose die docker-compose.override.yml (Ports, NPM-Netzwerk) und die
# .env automatisch mit. Ein blosses '-f docker-compose.yml' wuerde das Override
# ignorieren und beim 'up' die Host-Ports wieder oeffnen.
dc() { ( cd "${INSTALL_DIR}" && ${COMPOSE_CMD} "$@" ); }
# Wie run(), aber fuer Compose-Aufrufe: zeigt im Dry-Run den Befehl so an, wie
# er tatsaechlich ausgefuehrt wuerde, statt den Funktionsnamen "dc".
dc_run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo -e "${YELLOW}   [DRY-RUN]${RESET} (cd ${INSTALL_DIR} && ${COMPOSE_CMD} $*)"
  else
    dc "$@"
  fi
}

# -- Logging -------------------------------------------------------------------
# Ab hier alles zusaetzlich in die Logdatei schreiben (wichtig fuer Cron-Laeufe).
if [[ "${DRY_RUN}" -eq 0 ]]; then
  if ! touch "${LOG}" 2>/dev/null; then
    warn "Logdatei ${LOG} nicht beschreibbar - Ausgabe nur auf der Konsole."
  else
    exec > >(tee -a "${LOG}") 2>&1
  fi
fi

echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Update${RESET}  $(date '+%F %T')"
echo "------------------------------------------------------------"
echo -e " Installation:  ${CYAN}${INSTALL_DIR}${RESET}"
echo -e " Compose-Datei: ${CYAN}${COMPOSE_FILE}${RESET}"
[[ -f "${INSTALL_DIR}/docker-compose.override.yml" ]] \
  && echo -e " Override:      ${CYAN}${INSTALL_DIR}/docker-compose.override.yml${RESET}"
echo -e " Backups:       ${CYAN}${BACKUP_DIR}${RESET} (die letzten ${KEEP})"
echo ""

# -- Bestandsaufnahme ----------------------------------------------------------
echo "------------------------------------------------------------"
echo -e "${BOLD} Bestandsaufnahme${RESET}"
echo "------------------------------------------------------------"

CONTAINERS=$(dc ps -a --format '{{.Name}} ({{.State}})' 2>/dev/null || true)
if [[ -n "${CONTAINERS}" ]]; then
  info "Container:"
  while IFS= read -r c; do [[ -n "$c" ]] && echo -e "   - ${CYAN}${c}${RESET}"; done <<<"${CONTAINERS}"
else
  warn "Kein Container zu dieser Compose-Datei gefunden (gestoppt oder entfernt?)."
fi

# Image-Referenzen kommen aus der Compose-Config, damit auch gepinnte Tags und
# das Admin-Panel-Image mitgenommen werden.
mapfile -t IMAGES < <(dc config --images 2>/dev/null | sort -u || true)
[[ "${#IMAGES[@]}" -gt 0 ]] || die "Konnte die Image-Liste nicht aus der Compose-Config lesen. Stimmen .env und Override-Datei?"

declare -A OLD_IDS=()
info "Images laut Compose-Config:"
for img in "${IMAGES[@]}"; do
  OLD_IDS["${img}"]="$(docker image inspect "${img}" -f '{{.Id}}' 2>/dev/null || true)"
  if [[ -n "${OLD_IDS[${img}]}" ]]; then
    echo -e "   - ${CYAN}${img}${RESET} (${OLD_IDS[${img}]:7:12})"
  else
    echo -e "   - ${CYAN}${img}${RESET} ${YELLOW}(lokal noch nicht vorhanden)${RESET}"
  fi
done

# Git-Stand. Der Installer legt die Installation als flachen Clone an, deshalb
# spaeter '--depth=1' beim Fetch - sonst wuerde aus dem flachen Clone still ein
# vollstaendiger und der Plattenbedarf vervielfacht sich.
GIT_OK=0
GIT_BRANCH=""
GIT_OLD=""
GIT_OLD_DATE=""
GIT_DIRTY=""
if [[ "${HAVE_GIT}" -eq 1 && -d "${INSTALL_DIR}/.git" ]]; then
  GIT_OK=1
  GIT_BRANCH="$(git -C "${INSTALL_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
  if [[ "${GIT_BRANCH}" == "HEAD" ]]; then
    GIT_BRANCH="${LIBRECHAT_BRANCH:-main}"
    warn "Repository haengt in einem Detached HEAD - es wird gegen '${GIT_BRANCH}' geprueft."
  fi
  GIT_OLD="$(git -C "${INSTALL_DIR}" rev-parse HEAD 2>/dev/null || true)"
  GIT_OLD_DATE="$(git -C "${INSTALL_DIR}" log -1 --format=%cd --date=short 2>/dev/null || true)"
  GIT_DIRTY="$(git -C "${INSTALL_DIR}" status --porcelain --untracked-files=no 2>/dev/null || true)"
  info "Repository: Branch ${GIT_BRANCH}, Stand ${GIT_OLD:0:7} (${GIT_OLD_DATE:-unbekannt})"
  if [[ -n "${GIT_DIRTY}" ]]; then
    warn "Lokal geaenderte, versionierte Dateien im Repository:"
    while IFS= read -r l; do [[ -n "$l" ]] && echo -e "   ${YELLOW}${l}${RESET}"; done <<<"${GIT_DIRTY}"
    warn "Das Repository-Update wird deshalb uebersprungen - nur die Images werden aktualisiert."
    warn "Aufloesen mit: git -C ${INSTALL_DIR} checkout -- <datei>   (verwirft die Aenderung)"
  fi
elif [[ "${HAVE_GIT}" -eq 0 ]]; then
  warn "git ist nicht installiert - nur die Images koennen aktualisiert werden."
else
  warn "Kein Git-Repository unter ${INSTALL_DIR} - nur die Images koennen aktualisiert werden."
fi

# Zu sichernde Konfigurationsdateien. Alle drei stehen in LibreChats offizieller
# .gitignore (.env*, librechat.yaml, docker-compose.override.yml) und werden von
# einem Repository-Update daher nicht angefasst - gesichert werden sie trotzdem,
# weil sie die einzigen nicht reproduzierbaren Dateien der Installation sind.
declare -a BACKUP_ITEMS=()
for item in .env librechat.yaml docker-compose.override.yml; do
  [[ -e "${INSTALL_DIR}/${item}" ]] && BACKUP_ITEMS+=("${item}")
done
if [[ "${#BACKUP_ITEMS[@]}" -gt 0 ]]; then
  info "Zu sichernde Konfiguration: ${BACKUP_ITEMS[*]}"
else
  warn "Keine der erwarteten Konfigurationsdateien gefunden (.env, librechat.yaml, docker-compose.override.yml)."
fi

# mongodump laeuft im laufenden mongodb-Container. Ohne laufenden Container gibt
# es keinen konsistenten Dump - dann wird nur die Konfiguration gesichert.
DB_DUMP=0
if [[ "${WITH_DB}" -eq 1 ]]; then
  MONGO_STATE="$(dc ps -a --format '{{.Service}} {{.State}}' 2>/dev/null | awk '$1=="mongodb"{print $2}' || true)"
  if [[ "${MONGO_STATE}" != "running" ]]; then
    warn "Der Service 'mongodb' laeuft nicht (Status: ${MONGO_STATE:-nicht vorhanden}) - es wird kein Datenbank-Dump erstellt."
  elif ! dc exec -T mongodb sh -c 'command -v mongodump' >/dev/null 2>&1; then
    warn "'mongodump' ist im mongodb-Container nicht verfuegbar - es wird kein Datenbank-Dump erstellt."
  else
    DB_DUMP=1
    info "Datenbank-Dump: mongodump der Datenbank '${MONGO_DB_NAME}' (ohne Downtime)"
  fi
else
  info "Datenbank-Dump per --no-db abgeschaltet - es wird nur die Konfiguration gesichert."
fi

BACKUP_COUNT=0
if [[ -d "${BACKUP_DIR}" ]]; then
  BACKUP_COUNT=$(find "${BACKUP_DIR}" -maxdepth 1 -name "${BACKUP_PREFIX}_*.tar.gz" -type f 2>/dev/null | wc -l | tr -d ' ')
fi
info "Vorhandene Backups: ${BACKUP_COUNT} in ${BACKUP_DIR} (es werden ${KEEP} behalten)"

# -- Auf Neuerungen pruefen ----------------------------------------------------
# Beides veraendert den laufenden Stack nicht: der Fetch schreibt nur in
# .git/, der Pull laedt hoechstens Image-Layer. Alles, was den Dienst
# tatsaechlich anfasst, passiert erst nach der Bestaetigung weiter unten.
echo ""
GIT_NEW=""
GIT_NEW_DATE=""
GIT_CHANGED=0
if [[ "${GIT_OK}" -eq 1 && -z "${GIT_DIRTY}" ]]; then
  info "Pruefe das Repository auf neue Commits (git fetch)..."
  if [[ "$(git -C "${INSTALL_DIR}" rev-parse --is-shallow-repository 2>/dev/null || echo false)" == "true" ]]; then
    run git -C "${INSTALL_DIR}" fetch --depth=1 origin "${GIT_BRANCH}"
  else
    run git -C "${INSTALL_DIR}" fetch origin "${GIT_BRANCH}"
  fi
  if [[ "${DRY_RUN}" -eq 0 ]]; then
    GIT_NEW="$(git -C "${INSTALL_DIR}" rev-parse FETCH_HEAD 2>/dev/null || true)"
    GIT_NEW_DATE="$(git -C "${INSTALL_DIR}" log -1 --format=%cd --date=short FETCH_HEAD 2>/dev/null || true)"
    [[ -n "${GIT_NEW}" && "${GIT_NEW}" != "${GIT_OLD}" ]] && GIT_CHANGED=1
  fi
fi

info "Pruefe auf neue Images (${COMPOSE_CMD} pull)..."
info "Es werden nur Layer geladen - die laufenden Container bleiben unberuehrt."
dc_run pull

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo "------------------------------------------------------------"
  echo -e "${YELLOW}${BOLD} DRY-RUN beendet - es wurde nichts veraendert.${RESET}"
  echo "------------------------------------------------------------"
  echo -e " Ob es Neuerungen gibt, laesst sich ohne Fetch/Pull nicht feststellen -"
  echo -e " beides wurde uebersprungen. Bei einer Neuerung wuerde nach einer"
  echo -e " Rueckfrage folgen:"
  echo -e "   1. Backup nach ${CYAN}${BACKUP_DIR}/${BACKUP_PREFIX}_<zeitstempel>.tar.gz${RESET}"
  [[ "${GIT_OK}" -eq 1 ]] && echo -e "   2. ${CYAN}git -C ${INSTALL_DIR} merge --ff-only FETCH_HEAD${RESET}"
  echo -e "   3. ${CYAN}${COMPOSE_CMD} up -d${RESET} im Verzeichnis ${INSTALL_DIR}"
  echo -e "   4. Backups ueber ${KEEP} hinaus entfernen, dangling Images aufraeumen"
  echo ""
  exit 0
fi

declare -A NEW_IDS=()
IMAGES_CHANGED=0
for img in "${IMAGES[@]}"; do
  NEW_IDS["${img}"]="$(docker image inspect "${img}" -f '{{.Id}}' 2>/dev/null || true)"
  [[ -n "${NEW_IDS[${img}]}" ]] || die "Image ${img} ist nach dem Pull nicht lokal vorhanden."
  [[ "${OLD_IDS[${img}]}" != "${NEW_IDS[${img}]}" ]] && IMAGES_CHANGED=1
done

# -- Nichts Neues: hier ist Schluss, ohne irgendetwas anzufassen ----------------
if [[ "${GIT_CHANGED}" -eq 0 && "${IMAGES_CHANGED}" -eq 0 ]]; then
  echo ""
  echo "------------------------------------------------------------"
  success "NOCHANGE: bereits aktuell (Repository ${GIT_OLD:0:7}, alle Images unveraendert)"
  echo "------------------------------------------------------------"
  echo -e " Kein Backup, kein Neustart, keine Aenderung am Stack."
  echo ""
  exit 0
fi

# -- Zusammenfassung -----------------------------------------------------------
TS=$(date +%F_%H-%M-%S)
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_PREFIX}_${TS}.tar.gz"

mapfile -t DROP_BACKUPS < <(ls -1t "${BACKUP_DIR}"/${BACKUP_PREFIX}_*.tar.gz 2>/dev/null | tail -n "+${KEEP}" || true)

echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Zusammenfassung${RESET}"
echo "------------------------------------------------------------"
echo -e " Installation:  ${CYAN}${INSTALL_DIR}${RESET}"
echo ""
if [[ "${GIT_OK}" -eq 1 ]]; then
  if [[ "${GIT_CHANGED}" -eq 1 ]]; then
    echo -e " ${BOLD}Repository${RESET}"
    echo -e "   JETZT      ${GIT_OLD:0:7}  (${GIT_OLD_DATE:-unbekannt})"
    echo -e "   NACHHER    ${GREEN}${GIT_NEW:0:7}${RESET}  (${GIT_NEW_DATE:-unbekannt})  ${GREEN}<- neu${RESET}"
  elif [[ -n "${GIT_DIRTY}" ]]; then
    echo -e " ${BOLD}Repository${RESET}  ${YELLOW}uebersprungen (lokale Aenderungen)${RESET}"
  else
    echo -e " ${BOLD}Repository${RESET}  unveraendert (${GIT_OLD:0:7})"
  fi
  echo ""
fi
echo -e " ${BOLD}Images${RESET}"
for img in "${IMAGES[@]}"; do
  if [[ "${OLD_IDS[${img}]}" != "${NEW_IDS[${img}]}" ]]; then
    # Image-IDs beginnen mit "sha256:" - fuer die Anzeige die ersten 12 Zeichen
    # des eigentlichen Digests, wie es auch 'docker images' zeigt.
    old_short="${OLD_IDS[${img}]:7:12}"
    echo -e "   ${GREEN}neu${RESET}           ${img}"
    echo -e "                 ${old_short:-(noch nicht vorhanden)} -> ${GREEN}${NEW_IDS[${img}]:7:12}${RESET}"
  else
    echo -e "   unveraendert  ${img}"
  fi
done
echo ""
echo -e " ${BOLD}Es wird:${RESET}"
if [[ "${#BACKUP_ITEMS[@]}" -gt 0 || "${DB_DUMP}" -eq 1 ]]; then
  echo -ne "   1. gesichert nach ${CYAN}$(basename "${BACKUP_FILE}")${RESET}: "
  [[ "${#BACKUP_ITEMS[@]}" -gt 0 ]] && echo -n "${BACKUP_ITEMS[*]}"
  [[ "${DB_DUMP}" -eq 1 ]] && echo -n " + mongodump (${MONGO_DB_NAME})"
  echo ""
else
  echo -e "   1. ${YELLOW}kein Backup erstellt${RESET} (keine Konfiguration gefunden, kein Dump moeglich)"
fi
if [[ "${GIT_CHANGED}" -eq 1 ]]; then
  echo -e "   2. das Repository per ${CYAN}merge --ff-only${RESET} auf ${GIT_NEW:0:7} gebracht"
else
  echo -e "   2. das Repository nicht angefasst"
fi
echo -e "   3. die Compose-Konfiguration validiert und der Stack neu hochgefahren"
echo -e "      - kurze Downtime, je nach Host meist unter einer Minute"
if [[ "${#DROP_BACKUPS[@]}" -gt 0 ]]; then
  echo -e "   4. ${#DROP_BACKUPS[@]} alte(s) Backup(s) entfernt, aeltestes: ${CYAN}$(basename "${DROP_BACKUPS[-1]}")${RESET}"
else
  echo -e "   4. kein altes Backup entfernt (${BACKUP_COUNT} von ${KEEP} belegt)"
fi
echo -e "   5. dangling Images auf diesem Host aufgeraeumt"
echo ""
echo -e " ${BOLD}Unveraendert bleibt:${RESET}"
echo -e "   - ${CYAN}.env${RESET}, ${CYAN}librechat.yaml${RESET} und ${CYAN}docker-compose.override.yml${RESET}"
echo -e "     (stehen in LibreChats .gitignore und werden vom Merge nicht beruehrt)"
echo -e "   - deine Chats, Nutzer und Dateien in ${CYAN}data-node/${RESET}, ${CYAN}uploads/${RESET}, ${CYAN}images/${RESET}"
echo -e "   - das Docker-Netzwerk und alle anderen Stacks darauf"
echo ""

# -- Bestaetigung --------------------------------------------------------------
echo "------------------------------------------------------------"
if ! ask_yesno "${BOLD}Update jetzt durchfuehren?${RESET}" "n"; then
  warn "Abgebrochen. Es wurde nichts veraendert."
  echo -e " Geladene Images und Commits liegen lokal und werden beim naechsten Lauf verwendet."
  exit 0
fi

# -- Durchfuehrung -------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} Durchfuehrung${RESET}"
echo "------------------------------------------------------------"

if [[ "${#BACKUP_ITEMS[@]}" -gt 0 || "${DB_DUMP}" -eq 1 ]]; then
  info "Erstelle Backup..."
  mkdir -p "${BACKUP_DIR}"
  chmod 700 "${BACKUP_DIR}"
  STAGE="$(mktemp -d "${BACKUP_DIR}/.tmp-backup-XXXXXX")" || die "Konnte kein temporaeres Verzeichnis anlegen."
  trap 'rm -rf "${STAGE}"' EXIT

  if [[ "${#BACKUP_ITEMS[@]}" -gt 0 ]]; then
    mkdir -p "${STAGE}/config"
    for item in "${BACKUP_ITEMS[@]}"; do
      cp -a "${INSTALL_DIR}/${item}" "${STAGE}/config/"
    done
    success "Konfiguration gesichert: ${BACKUP_ITEMS[*]}"
  fi

  if [[ "${DB_DUMP}" -eq 1 ]]; then
    info "Erstelle mongodump der Datenbank '${MONGO_DB_NAME}' (der Stack laeuft dabei weiter)..."
    # --archive schreibt nach stdout, deshalb 'exec -T' ohne TTY. Schlaegt der
    # Dump fehl, bricht das Script ab, bevor irgendetwas veraendert wurde.
    if dc exec -T mongodb mongodump --archive --gzip --db "${MONGO_DB_NAME}" > "${STAGE}/mongodump-${MONGO_DB_NAME}.archive.gz"; then
      success "Datenbank gesichert ($(du -h "${STAGE}/mongodump-${MONGO_DB_NAME}.archive.gz" | cut -f1))."
    else
      die "mongodump ist fehlgeschlagen - Update abgebrochen, es wurde nichts veraendert."
    fi
  fi

  {
    echo "ERSTELLT=${TS}"
    echo "HOST=$(hostname 2>/dev/null || echo unbekannt)"
    echo "INSTALL_DIR=${INSTALL_DIR}"
    echo "GIT_COMMIT_VOR_UPDATE=${GIT_OLD:-unbekannt}"
    echo "KONFIGURATION=${BACKUP_ITEMS[*]:-keine}"
    echo "DATENBANK=$( [[ "${DB_DUMP}" -eq 1 ]] && echo "mongodump-${MONGO_DB_NAME}.archive.gz" || echo "nicht gesichert" )"
  } > "${STAGE}/manifest.txt"

  # -C: relative Pfade im Archiv, unabhaengig vom Arbeitsverzeichnis.
  tar czf "${BACKUP_FILE}" -C "${STAGE}" .
  chmod 600 "${BACKUP_FILE}"
  rm -rf "${STAGE}"
  trap - EXIT
  success "Backup erstellt: $(basename "${BACKUP_FILE}") ($(du -h "${BACKUP_FILE}" | cut -f1))"
fi

if [[ "${GIT_CHANGED}" -eq 1 ]]; then
  info "Aktualisiere das Repository (merge --ff-only)..."
  # --ff-only statt 'git pull': schlaegt sauber fehl, statt bei lokalen Commits
  # einen Merge-Commit oder Konflikte im Installationsverzeichnis zu erzeugen.
  if ! git -C "${INSTALL_DIR}" merge --ff-only FETCH_HEAD; then
    error "Fast-Forward nicht moeglich - das Repository wurde nicht veraendert."
    error "Bitte manuell pruefen: git -C ${INSTALL_DIR} status"
    die "Abbruch vor dem Neustart. Das Backup liegt unter ${BACKUP_FILE:-<keines>}."
  fi
  success "Repository auf $(git -C "${INSTALL_DIR}" rev-parse --short HEAD) gebracht."
fi

info "Validiere die Compose-Konfiguration..."
# Nach einem Repository-Update kann sich die Basis-Compose-Datei geaendert haben
# (z.B. neue/umbenannte Services). Passt das Override nicht mehr dazu, faellt
# das hier auf - vor dem 'up', nicht mittendrin.
if ! dc config --quiet; then
  error "Die Compose-Konfiguration ist nach dem Update ungueltig."
  error "Haeufigste Ursache: docker-compose.override.yml verweist auf einen Service,"
  error "den es in der neuen docker-compose.yml nicht mehr gibt."
  die "Der Stack wurde NICHT neu gestartet. Bitte die Override-Datei anpassen."
fi
success "Compose-Konfiguration ist gueltig."

info "Fahre den Stack neu hoch..."
dc up -d
success "UPDATED: $( [[ "${GIT_CHANGED}" -eq 1 ]] && echo "${GIT_OLD:0:7} -> ${GIT_NEW:0:7}" || echo "Images aktualisiert" )"

echo ""
dc ps || true

# Rotation erst jetzt - das frische Backup zaehlt mit.
mapfile -t OLD_BACKUPS < <(ls -1t "${BACKUP_DIR}"/${BACKUP_PREFIX}_*.tar.gz 2>/dev/null | tail -n "+$((KEEP + 1))" || true)
if [[ "${#OLD_BACKUPS[@]}" -gt 0 ]]; then
  echo ""
  info "Entferne ${#OLD_BACKUPS[@]} alte(s) Backup(s) (behalte die letzten ${KEEP})."
  for old in "${OLD_BACKUPS[@]}"; do rm -f "${old}"; done
fi

echo ""
info "Raeume alte (dangling) Images auf..."
docker image prune -f >/dev/null
success "Aufgeraeumt."

# -- Hinweise auf Reste --------------------------------------------------------
# Meilisearch-Daten liegen in einem versionierten Verzeichnis (meili_data_vX.Y.Z).
# Hebt LibreChat die Meilisearch-Version an, zeigt die Compose-Datei auf ein
# neues Verzeichnis und der alte Datenbestand bleibt als toter Ordner liegen.
mapfile -t MEILI_DIRS < <(find "${INSTALL_DIR}" -maxdepth 1 -type d -name 'meili_data_*' -printf '%f\n' 2>/dev/null | sort || true)
if [[ "${#MEILI_DIRS[@]}" -gt 1 ]]; then
  CURRENT_MEILI="$(grep -oE 'meili_data_[^:"[:space:]]+' "${COMPOSE_FILE}" | head -n 1 || true)"
  echo ""
  warn "Mehrere Meilisearch-Datenverzeichnisse gefunden:"
  for d in "${MEILI_DIRS[@]}"; do
    if [[ "${d}" == "${CURRENT_MEILI}" ]]; then
      echo -e "   - ${CYAN}${d}${RESET} (aktuell in Benutzung)"
    else
      echo -e "   - ${YELLOW}${d}${RESET} ($(du -sh "${INSTALL_DIR}/${d}" 2>/dev/null | cut -f1), verwaist)"
    fi
  done
  warn "Verwaiste Verzeichnisse stammen aus aelteren Meilisearch-Versionen und"
  warn "werden von diesem Script bewusst nicht geloescht. Der Suchindex baut sich"
  warn "im neuen Verzeichnis selbst wieder auf - nach einer Kontrolle koennen die"
  warn "alten Ordner von Hand entfernt werden."
fi

# -- Abschluss -----------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${GREEN}${BOLD} Update abgeschlossen.${RESET}  $(date '+%F %T')"
echo "------------------------------------------------------------"
if [[ -f "${BACKUP_FILE}" ]]; then
  echo -e " Backup: ${CYAN}${BACKUP_FILE}${RESET}"
  echo ""
  echo -e " Rollback bei Problemen:"
  echo -e "   ${CYAN}cd ${INSTALL_DIR} && ${COMPOSE_CMD} down${RESET}"
  echo -e "   ${CYAN}mkdir -p /tmp/lc-restore && tar xzf ${BACKUP_FILE} -C /tmp/lc-restore${RESET}"
  echo -e "   ${CYAN}cp /tmp/lc-restore/config/* ${INSTALL_DIR}/${RESET}"
  [[ "${GIT_CHANGED}" -eq 1 ]] && \
  echo -e "   ${CYAN}git -C ${INSTALL_DIR} checkout ${GIT_OLD:0:7}${RESET}   (alter Repository-Stand)"
  echo -e "   ${CYAN}cd ${INSTALL_DIR} && ${COMPOSE_CMD} up -d${RESET}"
  if [[ "${DB_DUMP}" -eq 1 ]]; then
    echo -e "   ${CYAN}${COMPOSE_CMD} exec -T mongodb mongorestore --archive --gzip --drop < /tmp/lc-restore/mongodump-${MONGO_DB_NAME}.archive.gz${RESET}"
  fi
  echo ""
fi
echo -e " Hinweis: Hat sich ${CYAN}.env.example${RESET} geaendert, muessen neue Variablen"
echo -e " ggf. von Hand in die ${CYAN}.env${RESET} uebernommen werden - siehe das LibreChat-Changelog."
echo ""
echo -e " Mehr Tipps & Tutorials: ${CYAN}https://pc-fee.com/blog${RESET}"
echo -e " GitHub:                 ${CYAN}${LIBRECHAT_GUIDE}${RESET}"
echo ""
