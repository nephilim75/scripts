#!/usr/bin/env bash
# =============================================================================
# Qdrant Update Script - powered by pc-fee.com
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Aktualisiert eine mit install-qdrant.sh installierte Qdrant-Instanz:
#   1. Zusammenfassung: wo liegt die Installation, welche Version laeuft
#   2. Prueft auf Neuerungen (GitHub-Releases) und plant den Update-Pfad.
#      Qdrant migriert seinen Speicher nur Minor-Version fuer Minor-Version:
#      Zwischenversionen duerfen NICHT uebersprungen werden. Das Script
#      faehrt deshalb jede Zwischen-Minor-Version (jeweils neuester Patch)
#      einzeln an, z.B. v1.17.1 -> v1.18.3 -> v1.19.2.
#      Quelle: https://qdrant.tech/documentation/upgrades/
#   3. Zeigt AKTUELLER STAND -> ZUKUENFTIGER STAND und laedt die Images vorab
#      (der laufende Container bleibt dabei unberuehrt)
#   4. Rueckfragen (Anzahl aufzubewahrender Backups), dann EINE Bestaetigung
#   5. Durchfuehrung: Qdrant stoppen, Backup (docker-compose.yml, .env und
#      storage/ als tar.gz), Compose-Konfiguration validieren, jede Version
#      starten und pruefen (Bereitschaft, Version, alle Collections)
#   6. Behaelt nur die N neuesten Update-Backups (Default: 5)
#
# Ohne Bestaetigung wird nichts veraendert. Fuer Cron: --yes bzw. ASSUME_YES=1.
#
# Nutzung als 1-Zeiler (von ueberall, kein vorheriger Download noetig):
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/update/update-qdrant.sh)"
#
# Optionen:
#   --dir <pfad>     Installationspfad fest vorgeben (ueberspringt die Erkennung)
#   --to <vX.Y.Z>    Zielversion statt der neuesten stabilen Version
#   --keep <n>       Anzahl aufzubewahrender Update-Backups (Default: 5)
#   --dry-run        Zeigt nur, was passieren wuerde - aendert und laedt nichts
#   --yes            Ueberspringt die Rueckfragen (wie ASSUME_YES=1, fuer Cron)
#   --help           Diese Hilfe anzeigen
#
# Umgebungsvariablen (fuer unbeaufsichtigten Betrieb, z.B. Cron):
#   INSTALL_DIR      wie --dir
#   TARGET_VERSION   wie --to
#   KEEP_BACKUPS     wie --keep
#   ASSUME_YES=1     wie --yes
#   LOG_FILE         Logdatei (Default: /var/log/qdrant-update.log)
#
# Voraussetzungen: root (bzw. sudo), Docker + Docker Compose, curl, tar.
#
# Autor: Nils Weber (n8n Automation Architect, pc-fee.com)
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
readonly BLOG_URL="https://pc-fee.com/blog"
readonly DEFAULT_DIR="/opt/qdrant"
readonly DEFAULT_BACKUP_DIR="/opt/qdrant-backups"
readonly IMAGE_REPO="qdrant/qdrant"
readonly STORAGE_MOUNT="/qdrant/storage"
readonly READY_TIMEOUT=300
readonly UPGRADE_DOC="https://qdrant.tech/documentation/upgrades/"

# -- Optionen ------------------------------------------------------------------
DRY_RUN=0
KEEP="${KEEP_BACKUPS:-}"
TARGET="${TARGET_VERSION:-}"
LOG="${LOG_FILE:-/var/log/qdrant-update.log}"

usage() {
  cat <<'USAGE'
Qdrant Update Script - powered by pc-fee.com

Aktualisiert eine mit install-qdrant.sh installierte Qdrant-Instanz - mit
Backup vor der Aenderung und ohne Minor-Versionen zu ueberspringen (Qdrant
migriert seinen Speicher nur Schritt fuer Schritt).

Optionen:
  --dir <pfad>     Installationspfad fest vorgeben (ueberspringt die Erkennung)
  --to <vX.Y.Z>    Zielversion statt der neuesten stabilen Version
  --keep <n>       Anzahl aufzubewahrender Update-Backups (Default: 5)
  --dry-run        Zeigt nur, was passieren wuerde - aendert und laedt nichts
  --yes            Ueberspringt die Rueckfragen (wie ASSUME_YES=1, fuer Cron)
  --help           Diese Hilfe anzeigen

Das Script zeigt erst AKTUELLER STAND -> ZUKUENFTIGER STAND und fragt nach,
bevor Qdrant gestoppt, gesichert und aktualisiert wird.

Umgebungsvariablen: INSTALL_DIR, TARGET_VERSION, KEEP_BACKUPS, ASSUME_YES, LOG_FILE

Beispiele:
  sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/update/update-qdrant.sh)"
  sudo ./update-qdrant.sh --dry-run
  sudo ./update-qdrant.sh --to v1.19.2 --keep 10
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)     INSTALL_DIR="${2:-}"; shift 2 || true ;;
    --dir=*)   INSTALL_DIR="${1#*=}"; shift ;;
    --to)      TARGET="${2:-}"; shift 2 || true ;;
    --to=*)    TARGET="${1#*=}"; shift ;;
    --keep)    KEEP="${2:-}"; shift 2 || true ;;
    --keep=*)  KEEP="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y)  ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         echo "Unbekannte Option: $1 (siehe --help)" >&2; exit 1 ;;
  esac
done
readonly DRY_RUN

KEEP_GIVEN=1
if [[ -z "${KEEP}" ]]; then
  KEEP=5
  KEEP_GIVEN=0
fi
if ! [[ "${KEEP}" =~ ^[0-9]+$ ]] || [[ "${KEEP}" -lt 1 ]]; then
  echo "--keep erwartet eine positive Ganzzahl (erhalten: '${KEEP}')." >&2
  exit 1
fi

if [[ -n "${TARGET}" ]]; then
  [[ "${TARGET}" == v* ]] || TARGET="v${TARGET}"
  if ! [[ "${TARGET}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "--to erwartet eine Version im Format vX.Y.Z (erhalten: '${TARGET}')." >&2
    exit 1
  fi
fi

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

# ask_value <variable> <prompt> <default> - ohne Terminal/mit ASSUME_YES: Default
ask_value() {
  local var="$1" prompt="$2" default="$3" input=""
  if [[ "${ASSUME_YES:-0}" != "1" && "${INTERACTIVE}" -eq 1 ]]; then
    echo ""
    echo -ne "${BOLD}${prompt}${RESET} [${CYAN}${default}${RESET}]: "
    read -r input <"${TTY}" || true
  fi
  printf -v "${var}" '%s' "${input:-${default}}"
}

# ver_lt a b -> 0, wenn Version a < b (Format vX.Y.Z oder X.Y.Z)
ver_lt() {
  local a="${1#v}" b="${2#v}"
  [[ "${a}" != "${b}" ]] && [[ "$(printf '%s\n%s\n' "${a}" "${b}" | sort -V | head -n 1)" == "${a}" ]]
}

minor_of() { local v="${1#v}"; v="${v#*.}"; echo "${v%%.*}"; }
major_of() { local v="${1#v}"; echo "${v%%.*}"; }

# Alle stabilen Qdrant-Versionen (vX.Y.Z), aufsteigend sortiert. Zuerst ueber
# die GitHub-Releases, bei Ausfall ueber die Docker-Hub-Tags.
fetch_release_tags() {
  local page out="" chunk url
  for page in 1 2 3; do
    chunk="$(curl -fsSL --max-time 15 -H 'Accept: application/vnd.github+json' \
              "https://api.github.com/repos/qdrant/qdrant/releases?per_page=100&page=${page}" 2>/dev/null \
            | grep -oE '"tag_name": *"v[0-9]+\.[0-9]+\.[0-9]+"' \
            | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || true)"
    [[ -z "${chunk}" ]] && break
    out+="${chunk}"$'\n'
  done
  if [[ -z "${out//$'\n'/}" ]]; then
    url="https://hub.docker.com/v2/repositories/qdrant/qdrant/tags?page_size=100&name=v"
    for page in 1 2 3 4 5; do
      chunk="$(curl -fsSL --max-time 15 "${url}&page=${page}" 2>/dev/null \
              | grep -oE '"name": *"v[0-9]+\.[0-9]+\.[0-9]+"' \
              | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || true)"
      [[ -z "${chunk}" ]] && break
      out+="${chunk}"$'\n'
    done
  fi
  printf '%s' "${out}" | grep -v '^$' | sort -uV || true
}

# plan_path <von> <nach> -> Zwischenversionen + Ziel, je eine Zeile.
# Rueckgabe 2: Major-Wechsel, 3: Zwischenversion nicht in der Release-Liste.
plan_path() {
  local cur="$1" tgt="$2" cmaj cmin tmaj tmin m best
  cmaj="$(major_of "${cur}")"; cmin="$(minor_of "${cur}")"
  tmaj="$(major_of "${tgt}")"; tmin="$(minor_of "${tgt}")"
  [[ "${cmaj}" == "${tmaj}" ]] || return 2
  for ((m = cmin + 1; m < tmin; m++)); do
    best="$(printf '%s\n' "${ALL_TAGS[@]+"${ALL_TAGS[@]}"}" | grep -E "^v${cmaj}\.${m}\.[0-9]+$" | sort -V | tail -n 1 || true)"
    [[ -n "${best}" ]] || return 3
    echo "${best}"
  done
  echo "${tgt}"
}

# urlencode <text> - Collection-Namen sicher in eine URL einsetzen
urlencode() {
  local LC_ALL=C s="$1" o="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "${c}" in
      [a-zA-Z0-9._~-]) o+="${c}" ;;
      *) printf -v c '%%%02X' "'${c}"; o+="${c}" ;;
    esac
  done
  printf '%s' "${o}"
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
printf '%b\n' "${BOLD} Qdrant Update - powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo -e " ${YELLOW}${BOLD}DRY-RUN aktiv:${RESET} es wird nichts veraendert und nichts geladen."
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

command -v curl &>/dev/null || die "'curl' nicht gefunden - wird fuer Versionspruefung und Funktionstest gebraucht."
command -v tar &>/dev/null || die "'tar' nicht gefunden - wird fuer das Backup gebraucht."

# -- Installationspfad ermitteln -----------------------------------------------
# Ein Verzeichnis gilt als Qdrant-Installation, wenn es eine Compose-Datei
# enthaelt, die auf ein qdrant/qdrant-Image verweist.
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

  # 1. Container mit Qdrant-Image: Compose-Working-Dir aus dem Label lesen.
  while IFS= read -r cid; do
    [[ -n "${cid}" ]] || continue
    d=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "${cid}" 2>/dev/null || true)
    [[ -n "${d}" && "${d}" == /* ]] && raw+=("${d}")
    # 2. Fallback: Quelle des storage-Mounts, eine Ebene hoeher.
    d=$(docker inspect --format "{{range .Mounts}}{{if eq .Destination \"${STORAGE_MOUNT}\"}}{{.Source}}{{end}}{{end}}" "${cid}" 2>/dev/null || true)
    [[ -n "${d}" && "${d}" == /* ]] && raw+=("$(dirname "${d}")")
  done < <(docker ps -a --format '{{.ID}} {{.Image}}' | awk -v img="${IMAGE_REPO}" 'index($2, img) == 1 {print $1}')

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
  INSTALL_DIR="${INSTALL_DIR%/}"
  [[ -d "${INSTALL_DIR}" ]] || die "Angegebener Pfad existiert nicht: ${INSTALL_DIR}"
  compose_file_of "${INSTALL_DIR}" >/dev/null \
    || die "In ${INSTALL_DIR} liegt keine Compose-Datei mit einem ${IMAGE_REPO}-Image."
  info "Installationspfad (vorgegeben): ${INSTALL_DIR}"
else
  mapfile -t FOUND < <(detect_dirs)
  case "${#FOUND[@]}" in
    0)
      die "Keine Qdrant-Installation gefunden.\n  Erwartet wurde eine Compose-Datei mit ${IMAGE_REPO}-Image,\n  z.B. unter ${DEFAULT_DIR}.\n  Pfad ggf. direkt angeben: --dir /pfad/zur/installation"
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
ENV_FILE="${INSTALL_DIR}/.env"
readonly ENV_FILE

env_value() {
  # env_value <KEY> - Wert aus der .env der Installation (ohne sie zu sourcen)
  [[ -f "${ENV_FILE}" ]] || return 0
  sed -n "s/^[[:space:]]*$1=//p" "${ENV_FILE}" | tail -n 1 | sed -e 's/^["'\'']//' -e 's/["'\'']$//'
}

BACKUP_DIR="$(env_value QDRANT_BACKUP_DIR)"
BACKUP_DIR="${BACKUP_DIR:-${DEFAULT_BACKUP_DIR}}"
readonly BACKUP_DIR
API_KEY="${QDRANT_API_KEY:-$(env_value QDRANT_API_KEY)}"

# Image-Referenz aus der Compose-Datei lesen statt fest zu verdrahten.
IMAGE_LINE_RE="^([[:space:]]*image:[[:space:]]*[\"']?)${IMAGE_REPO}(:[^\"'[:space:]]+)?([\"']?.*)$"
IMAGE=$(grep -E "${IMAGE_LINE_RE}" "${COMPOSE_FILE}" | head -n 1 | sed -E "s|${IMAGE_LINE_RE}|${IMAGE_REPO}\2|")
[[ -n "${IMAGE}" ]] || die "Konnte die Image-Zeile in ${COMPOSE_FILE} nicht lesen."
if [[ "${IMAGE}" == *:* ]]; then ORIG_TAG="${IMAGE##*:}"; else ORIG_TAG="latest"; fi
readonly ORIG_TAG
FLOATING=0
[[ "${ORIG_TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || FLOATING=1
readonly FLOATING

# Container + Netzwerk aus Compose ermitteln (Name kann abweichen).
CID="$(${COMPOSE_CMD} -f "${COMPOSE_FILE}" ps -a -q 2>/dev/null | head -n 1 || true)"
CNAME=""
[[ -n "${CID}" ]] && CNAME="$(docker inspect -f '{{.Name}}' "${CID}" 2>/dev/null | sed 's|^/||' || true)"

container_ip() {
  # IP des Containers im ersten Netzwerk. Der Host erreicht Container in einem
  # Bridge-Netzwerk direkt ueber diese IP - ohne gebundenen Port.
  local id
  id="$(${COMPOSE_CMD} -f "${COMPOSE_FILE}" ps -q 2>/dev/null | head -n 1 || true)"
  [[ -n "${id}" ]] || return 0
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "${id}" 2>/dev/null | awk '{print $1}'
}

QIP=""
api() {
  # api <pfad> - GET gegen die laufende Instanz (mit API-Key, falls bekannt)
  local -a hdr=()
  [[ -n "${API_KEY}" ]] && hdr=(-H "api-key: ${API_KEY}")
  curl -fsS --max-time 30 ${hdr[@]+"${hdr[@]}"} "http://${QIP}:6333$1"
}

running_version() {
  curl -fsS --max-time 5 "http://${QIP}:6333/" 2>/dev/null \
    | grep -oE '"version": *"[^"]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true
}

list_collections() {
  api /collections 2>/dev/null | grep -oE '"name": *"[^"]*"' | sed -E 's/"name": *"(.*)"/\1/' || true
}

collection_info() {
  # collection_info <name> -> "<status> <points>"
  local j st pts
  j="$(api "/collections/$(urlencode "$1")" 2>/dev/null || true)"
  st="$(printf '%s' "${j}" | grep -oE '"status": *"[a-z]+"' | head -n 1 | grep -oE '[a-z]+"$' | tr -d '"' || true)"
  pts="$(printf '%s' "${j}" | grep -oE '"points_count": *[0-9]+' | head -n 1 | grep -oE '[0-9]+$' || true)"
  echo "${st:-unbekannt} ${pts:-?}"
}

wait_ready() {
  # wait_ready <sekunden> - wartet, bis /readyz antwortet; setzt QIP neu
  local t="$1" i
  for ((i = 0; i < t; i++)); do
    QIP="$(container_ip)"
    if [[ -n "${QIP}" ]] && curl -fsS --max-time 3 "http://${QIP}:6333/readyz" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

set_image_tag() {
  # set_image_tag <tag> - nur die Image-Zeile der Compose-Datei anpassen
  sed -i -E "s|${IMAGE_LINE_RE}|\1${IMAGE_REPO}:$1\3|" "${COMPOSE_FILE}"
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

# -- 1. Zusammenfassung --------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} 1. Bestandsaufnahme${RESET}  $(date '+%F %T')"
echo "------------------------------------------------------------"
echo -e " Installation:   ${CYAN}${INSTALL_DIR}${RESET}"
echo -e " Compose-Datei:  ${CYAN}${COMPOSE_FILE}${RESET}"
echo -e " Image:          ${CYAN}${IMAGE}${RESET}"
echo -e " Container:      ${CYAN}${CNAME:-nicht vorhanden}${RESET}"
echo -e " Backups:        ${CYAN}${BACKUP_DIR}${RESET}"
[[ -n "${API_KEY}" ]] || warn "Kein API-Key in ${ENV_FILE} gefunden - die Collections koennen nicht geprueft werden.\n         (Bei einer Instanz ohne Key ist das egal, sonst QDRANT_API_KEY=... vor den Aufruf setzen.)"

WAS_RUNNING=0
CUR_VERSION=""
if [[ -n "${CID}" ]] && [[ "$(docker inspect -f '{{.State.Running}}' "${CID}" 2>/dev/null)" == "true" ]]; then
  WAS_RUNNING=1
  if wait_ready 20; then
    CUR_VERSION="$(running_version)"
  else
    warn "Qdrant laeuft, antwortet aber nicht auf /readyz."
  fi
fi
if [[ -z "${CUR_VERSION}" && "${FLOATING}" -eq 0 ]]; then
  CUR_VERSION="${ORIG_TAG#v}"
  info "Version aus der Compose-Datei uebernommen (Container laeuft nicht): ${CUR_VERSION}"
fi
[[ -n "${CUR_VERSION}" ]] || die "Die laufende Qdrant-Version laesst sich nicht ermitteln (Container gestoppt, Tag '${ORIG_TAG}').\n  Bitte Qdrant starten und das Script erneut ausfuehren:\n  ${COMPOSE_CMD} -f ${COMPOSE_FILE} up -d"
CUR_VERSION="v${CUR_VERSION#v}"
readonly CUR_VERSION WAS_RUNNING
echo -e " Laufende Version: ${CYAN}${CUR_VERSION}${RESET}$([[ "${WAS_RUNNING}" -eq 1 ]] || echo " (Container gestoppt)")"

declare -a COLLECTIONS=()
declare -A COLL_BEFORE=()
if [[ "${WAS_RUNNING}" -eq 1 && -n "${QIP}" && -n "${API_KEY}" ]]; then
  mapfile -t COLLECTIONS < <(list_collections)
  if [[ "${#COLLECTIONS[@]}" -gt 0 ]]; then
    info "Collections (${#COLLECTIONS[@]}):"
    for c in "${COLLECTIONS[@]}"; do
      read -r st pts <<<"$(collection_info "${c}")"
      COLL_BEFORE["${c}"]="${pts}"
      echo -e "   - ${CYAN}${c}${RESET}: ${pts} Punkte, Status ${st}"
    done
  else
    info "Keine Collections vorhanden."
  fi
fi

STORAGE_BYTES=$(du -s -B1 "${INSTALL_DIR}/storage" 2>/dev/null | cut -f1 || echo 0)
STORAGE_HUMAN=$(du -sh "${INSTALL_DIR}/storage" 2>/dev/null | cut -f1 || echo "?")
info "Datenbestand storage/: ${STORAGE_HUMAN}"

BACKUP_COUNT=0
if [[ -d "${BACKUP_DIR}" ]]; then
  BACKUP_COUNT=$(find "${BACKUP_DIR}" -maxdepth 1 -name 'qdrant-update_*.tar.gz' -type f 2>/dev/null | wc -l | tr -d ' ')
fi
info "Vorhandene Update-Backups: ${BACKUP_COUNT}"

# -- 2. Pruefung auf Neuerungen ------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} 2. Pruefung auf Neuerungen${RESET}"
echo "------------------------------------------------------------"
info "Lade die Liste der Qdrant-Releases (der laufende Container bleibt unberuehrt)..."
mapfile -t ALL_TAGS < <(fetch_release_tags)
if [[ "${#ALL_TAGS[@]}" -gt 0 ]]; then
  LATEST="${ALL_TAGS[-1]}"
  success "${#ALL_TAGS[@]} Releases gefunden, neueste stabile Version: ${LATEST}"
else
  LATEST=""
  warn "Die Release-Liste konnte nicht geladen werden (GitHub und Docker Hub nicht erreichbar)."
fi

if [[ -z "${TARGET}" ]]; then
  [[ -n "${LATEST}" ]] || die "Ohne Release-Liste kann keine Zielversion bestimmt werden.\n  Zielversion direkt angeben: --to vX.Y.Z"
  TARGET="${LATEST}"
elif [[ "${#ALL_TAGS[@]}" -gt 0 ]] && ! printf '%s\n' "${ALL_TAGS[@]}" | grep -qx "${TARGET}"; then
  die "Version ${TARGET} ist kein stabiles Qdrant-Release.\n  Uebersicht: https://github.com/qdrant/qdrant/releases"
fi
readonly TARGET

if [[ "${CUR_VERSION}" == "${TARGET}" ]]; then
  echo ""
  echo "------------------------------------------------------------"
  success "NOCHANGE: Qdrant ${CUR_VERSION} ist bereits aktuell."
  echo "------------------------------------------------------------"
  echo -e " Kein Backup, kein Neustart, keine Aenderung."
  echo ""
  exit 0
fi
if ver_lt "${TARGET}" "${CUR_VERSION}"; then
  die "Zielversion ${TARGET} ist aelter als die laufende Version ${CUR_VERSION}.\n  Ein Downgrade wird nicht unterstuetzt - dafuer das Update-Backup zurueckspielen."
fi

if [[ "${#ALL_TAGS[@]}" -eq 0 ]] && (( $(minor_of "${TARGET}") - $(minor_of "${CUR_VERSION}") > 1 )); then
  die "Ohne Release-Liste kann der Update-Pfad ueber mehrere Minor-Versionen nicht geplant werden.\n  Bitte spaeter erneut versuchen oder in Einzelschritten mit --to aktualisieren."
fi

set +e
PATH_OUT="$(plan_path "${CUR_VERSION}" "${TARGET}")"
rc=$?
set -e
case "${rc}" in
  0) ;;
  2) die "Wechsel der Major-Version (${CUR_VERSION} -> ${TARGET}) wird nicht automatisch durchgefuehrt.\n  Bitte die Release Notes lesen: https://github.com/qdrant/qdrant/releases" ;;
  *) die "Fuer eine Zwischen-Minor-Version wurde kein Release gefunden - der Update-Pfad ist unvollstaendig.\n  Bitte in Einzelschritten mit --to aktualisieren. Hintergrund: ${UPGRADE_DOC}" ;;
esac
mapfile -t HOPS <<<"${PATH_OUT}"
readonly HOPS

TS=$(date +%F_%H-%M-%S)
BACKUP_FILE="${BACKUP_DIR}/qdrant-update_${TS}_${CUR_VERSION}.tar.gz"
readonly BACKUP_FILE

# -- 3. AKTUELLER STAND -> ZUKUENFTIGER STAND ----------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} 3. AKTUELLER STAND -> ZUKUENFTIGER STAND${RESET}"
echo "------------------------------------------------------------"
printf " %-16s %-22s %s\n" "Komponente" "AKTUELL" "ZUKUENFTIG"
printf " %-16s %-22s ${GREEN}%s${RESET}\n" "Qdrant" "${CUR_VERSION}" "${TARGET}"
if [[ "${FLOATING}" -eq 1 ]]; then
  printf " %-16s %-22s %s\n" "Image-Tag" "${ORIG_TAG}" "${ORIG_TAG} (wenn er auf ${TARGET} zeigt, sonst ${TARGET})"
else
  printf " %-16s %-22s ${GREEN}%s${RESET}\n" "Image-Tag" "${ORIG_TAG}" "${TARGET}"
fi
echo ""
if [[ "${#HOPS[@]}" -gt 1 ]]; then
  echo -e " ${BOLD}Update-Pfad${RESET} (Qdrant erlaubt kein Ueberspringen von Minor-Versionen):"
else
  echo -e " ${BOLD}Update-Pfad:${RESET}"
fi
echo -e "   ${CUR_VERSION} -> $(printf '%s -> ' "${HOPS[@]}" | sed 's/ -> $//')"
echo ""
info "Release Notes: https://github.com/qdrant/qdrant/releases"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo ""
  echo "------------------------------------------------------------"
  echo -e "${YELLOW}${BOLD} DRY-RUN beendet - es wurde nichts veraendert.${RESET}"
  echo "------------------------------------------------------------"
  echo -e " Nach einer Rueckfrage wuerde folgen:"
  echo -e "   1. Images laden: $(printf "${IMAGE_REPO}:%s " "${HOPS[@]}")"
  echo -e "   2. Qdrant stoppen (${COMPOSE_CMD} stop)"
  echo -e "   3. Backup nach ${CYAN}${BACKUP_FILE}${RESET} (~${STORAGE_HUMAN} Daten)"
  echo -e "   4. je Version: Image-Tag setzen, compose config pruefen, up -d, Bereitschaft/Version/Collections pruefen"
  echo -e "   5. Update-Backups ueber ${KEEP} hinaus entfernen"
  echo ""
  exit 0
fi

info "Lade die benoetigten Images vorab - der laufende Container bleibt unberuehrt..."
for h in "${HOPS[@]}"; do
  docker pull "${IMAGE_REPO}:${h}" >/dev/null \
    || die "Image ${IMAGE_REPO}:${h} konnte nicht geladen werden. Es wurde nichts veraendert."
  success "Geladen: ${IMAGE_REPO}:${h}"
done

# Speicherplatz pruefen: das Backup wird hoechstens so gross wie storage/.
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}" 2>/dev/null || true
AVAIL_BYTES=$(df -PB1 "${BACKUP_DIR}" 2>/dev/null | awk 'NR == 2 {print $4}' || echo 0)
if [[ "${AVAIL_BYTES:-0}" -lt "${STORAGE_BYTES:-0}" ]]; then
  die "Zu wenig Platz fuer das Backup in ${BACKUP_DIR}: frei $(numfmt --to=iec "${AVAIL_BYTES}" 2>/dev/null || echo "${AVAIL_BYTES}"), benoetigt bis zu ${STORAGE_HUMAN}.\n  Es wurde nichts veraendert."
fi

# -- 4. Rueckfragen und Bestaetigung -------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} 4. Rueckfragen${RESET}"
echo "------------------------------------------------------------"
if [[ "${KEEP_GIVEN}" -eq 0 ]]; then
  while true; do
    ask_value KEEP "Wie viele Update-Backups sollen aufbewahrt werden?" "${KEEP}"
    [[ "${KEEP}" =~ ^[0-9]+$ ]] && [[ "${KEEP}" -ge 1 ]] && break
    warn "Bitte eine positive Ganzzahl eingeben."
    KEEP=5
  done
fi
readonly KEEP
DROP_COUNT=$(( BACKUP_COUNT + 1 > KEEP ? BACKUP_COUNT + 1 - KEEP : 0 ))

echo ""
echo -e " ${BOLD}Es wird:${RESET}"
echo -e "   1. Qdrant gestoppt - ${YELLOW}Ausfallzeit bis zum Ende des Updates${RESET} (n8n-Workflows mit Qdrant schlagen solange fehl)"
echo -e "   2. ${CYAN}docker-compose.yml, .env, storage/${RESET} gesichert nach ${CYAN}${BACKUP_FILE}${RESET}"
echo -e "   3. nacheinander gestartet und geprueft: ${HOPS[*]}"
if [[ "${DROP_COUNT}" -gt 0 ]]; then
  echo -e "   4. ${DROP_COUNT} altes Update-Backup entfernt (es bleiben die ${KEEP} neuesten)"
else
  echo -e "   4. kein altes Backup entfernt (es bleiben bis zu ${KEEP})"
fi
echo ""
echo -e " ${BOLD}Unveraendert bleibt:${RESET}"
echo -e "   - die .env inkl. API-Key"
echo -e "   - das Docker-Netzwerk und alle anderen Stacks darauf"
echo -e "   - Snapshot-Backups des Backup-Scripts"
echo ""
echo "------------------------------------------------------------"
if ! ask_yesno "${BOLD}Update jetzt durchfuehren?${RESET}" "n"; then
  warn "Abgebrochen. Es wurde nichts veraendert."
  echo -e " Die geladenen Images bleiben lokal liegen."
  exit 0
fi

# -- 5. Durchfuehrung ----------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
echo -e "${BOLD} 5. Durchfuehrung${RESET}"
echo "------------------------------------------------------------"

print_rollback() {
  echo ""
  echo -e " ${BOLD}Rollback auf ${CUR_VERSION}:${RESET}"
  echo -e "   ${CYAN}${COMPOSE_CMD} -f ${COMPOSE_FILE} down${RESET}"
  echo -e "   ${CYAN}mv ${INSTALL_DIR}/storage ${INSTALL_DIR}/storage.failed-${TS}${RESET}"
  echo -e "   ${CYAN}tar xzf ${BACKUP_FILE} -C ${INSTALL_DIR}${RESET}"
  if [[ "${FLOATING}" -eq 1 ]]; then
    # Der Floating-Tag (z.B. latest) zeigt inzwischen auf die neue Version -
    # fuer den Rollback muss die alte Version fest eingetragen werden.
    echo -e "   ${CYAN}sed -i 's|${IMAGE_REPO}:${ORIG_TAG}|${IMAGE_REPO}:${CUR_VERSION}|' ${COMPOSE_FILE}${RESET}"
  fi
  echo -e "   ${CYAN}${COMPOSE_CMD} -f ${COMPOSE_FILE} up -d${RESET}"
  if [[ "${FLOATING}" -eq 1 ]]; then
    echo -e " Der Tag '${ORIG_TAG}' zeigt inzwischen auf die neue Version - deshalb legt"
    echo -e " der sed-Befehl die alte Version ${CUR_VERSION} fest."
  else
    echo -e " Das Archiv enthaelt auch die alte docker-compose.yml mit dem Tag ${ORIG_TAG}."
  fi
  echo -e " Laeuft alles wieder, ${INSTALL_DIR}/storage.failed-${TS} loeschen."
  echo ""
}

info "Stoppe Qdrant..."
${COMPOSE_CMD} -f "${COMPOSE_FILE}" stop
success "Qdrant gestoppt."

info "Erstelle Backup (das kann bei grossen Collections dauern)..."
BACKUP_ITEMS=("$(basename "${COMPOSE_FILE}")" "storage")
[[ -f "${ENV_FILE}" ]] && BACKUP_ITEMS+=(".env")
# --sparse: Qdrant legt WAL-Dateien sparse an - ohne die Option wuerden sie
# beim Zurueckspielen auf volle Groesse aufgeblaeht.
if ! tar --sparse -czf "${BACKUP_FILE}" -C "${INSTALL_DIR}" "${BACKUP_ITEMS[@]}"; then
  rm -f "${BACKUP_FILE}"
  warn "Backup fehlgeschlagen - starte Qdrant unveraendert wieder."
  [[ "${WAS_RUNNING}" -eq 1 ]] && ${COMPOSE_CMD} -f "${COMPOSE_FILE}" start
  die "Update abgebrochen, es wurde nichts veraendert."
fi
chmod 600 "${BACKUP_FILE}"
success "Backup erstellt: $(basename "${BACKUP_FILE}") ($(du -h "${BACKUP_FILE}" | cut -f1))"

for h in "${HOPS[@]}"; do
  echo ""
  info "Schritt auf ${h}..."
  set_image_tag "${h}"
  if ! ${COMPOSE_CMD} -f "${COMPOSE_FILE}" config --quiet; then
    error "Die Compose-Konfiguration ist nach dem Setzen von ${h} ungueltig."
    print_rollback
    exit 1
  fi
  ${COMPOSE_CMD} -f "${COMPOSE_FILE}" up -d
  info "Warte auf Bereitschaft (bis zu ${READY_TIMEOUT}s - grosse Collections laden laenger)..."
  if ! wait_ready "${READY_TIMEOUT}"; then
    error "Qdrant ${h} meldet sich nicht als bereit."
    echo -e " Logs: ${CYAN}${COMPOSE_CMD} -f ${COMPOSE_FILE} logs --tail 100${RESET}"
    print_rollback
    exit 1
  fi
  NOW="v$(running_version)"
  if [[ "${NOW}" != "${h}" ]]; then
    error "Erwartet wurde ${h}, es laeuft aber ${NOW}."
    print_rollback
    exit 1
  fi
  success "Qdrant ${h} laeuft."
done

# Collections nach dem Update pruefen: alle muessen da sein, Punktzahl gleich.
PROBLEMS=0
if [[ "${#COLLECTIONS[@]}" -gt 0 ]]; then
  echo ""
  info "Pruefe die Collections..."
  mapfile -t AFTER < <(list_collections)
  for c in "${COLLECTIONS[@]}"; do
    if ! printf '%s\n' "${AFTER[@]+"${AFTER[@]}"}" | grep -qxF -- "${c}"; then
      error "Collection fehlt nach dem Update: ${c}"
      PROBLEMS=1
      continue
    fi
    read -r st pts <<<"$(collection_info "${c}")"
    if [[ "${pts}" != "${COLL_BEFORE[${c}]}" ]]; then
      warn "${c}: ${COLL_BEFORE[${c}]} -> ${pts} Punkte (Status ${st}) - bitte pruefen."
      PROBLEMS=1
    else
      success "${c}: ${pts} Punkte, Status ${st}"
    fi
  done
fi

# War ein Floating-Tag (z.B. latest) eingetragen, wieder darauf zurueckstellen -
# aber nur, wenn er tatsaechlich auf die Zielversion zeigt.
FINAL_TAG="${TARGET}"
if [[ "${FLOATING}" -eq 1 ]]; then
  if docker pull "${IMAGE_REPO}:${ORIG_TAG}" >/dev/null 2>&1 \
     && [[ "$(docker image inspect -f '{{.Id}}' "${IMAGE_REPO}:${ORIG_TAG}" 2>/dev/null)" == "$(docker image inspect -f '{{.Id}}' "${IMAGE_REPO}:${TARGET}" 2>/dev/null)" ]]; then
    set_image_tag "${ORIG_TAG}"
    ${COMPOSE_CMD} -f "${COMPOSE_FILE}" config --quiet && ${COMPOSE_CMD} -f "${COMPOSE_FILE}" up -d >/dev/null
    wait_ready "${READY_TIMEOUT}" || warn "Qdrant meldet sich nach dem Zurueckstellen auf '${ORIG_TAG}' nicht als bereit."
    FINAL_TAG="${ORIG_TAG}"
    info "Image-Tag wieder auf '${ORIG_TAG}' gestellt (zeigt auf ${TARGET})."
  else
    warn "Der Tag '${ORIG_TAG}' zeigt nicht auf ${TARGET} - die Compose-Datei bleibt auf ${TARGET} festgelegt."
  fi
fi

if [[ "${WAS_RUNNING}" -eq 0 ]]; then
  info "Qdrant war vor dem Update gestoppt und laeuft jetzt. Stoppen mit:"
  echo -e "   ${CYAN}${COMPOSE_CMD} -f ${COMPOSE_FILE} stop${RESET}"
fi

# Zwischenversionen werden nicht mehr gebraucht. Das alte Image bleibt fuer
# einen Rollback liegen.
for h in "${HOPS[@]}"; do
  [[ "${h}" == "${TARGET}" ]] && continue
  docker rmi "${IMAGE_REPO}:${h}" >/dev/null 2>&1 || true
done
docker image prune -f >/dev/null 2>&1 || true

# Rotation erst jetzt - das frische Backup zaehlt mit.
mapfile -t OLD_BACKUPS < <(ls -1t "${BACKUP_DIR}"/qdrant-update_*.tar.gz 2>/dev/null | tail -n "+$((KEEP + 1))" || true)
if [[ "${#OLD_BACKUPS[@]}" -gt 0 ]]; then
  info "Entferne ${#OLD_BACKUPS[@]} alte(s) Update-Backup(s) (behalte die letzten ${KEEP})."
  for old in "${OLD_BACKUPS[@]}"; do rm -f "${old}"; done
fi

# -- Abschluss -----------------------------------------------------------------
echo ""
echo "------------------------------------------------------------"
if [[ "${PROBLEMS}" -eq 0 ]]; then
  echo -e "${GREEN}${BOLD} Update abgeschlossen: ${CUR_VERSION} -> ${TARGET}${RESET}  $(date '+%F %T')"
else
  echo -e "${YELLOW}${BOLD} Update durchgefuehrt (${CUR_VERSION} -> ${TARGET}), aber mit Auffaelligkeiten - siehe oben.${RESET}"
fi
echo "------------------------------------------------------------"
echo -e " Image-Tag in der Compose-Datei: ${CYAN}${FINAL_TAG}${RESET}"
echo -e " Update-Backup:                  ${CYAN}${BACKUP_FILE}${RESET}"
print_rollback
echo -e " ${BOLD}Hinweis:${RESET} Snapshots, die das Backup-Script mit ${CUR_VERSION} erstellt hat,"
echo -e " lassen sich nur auf derselben oder der naechsten Minor-Version zurueckspielen."
echo -e " Am besten jetzt einen frischen Snapshot erstellen:"
echo -e "   ${CYAN}sudo bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/backup/backup-qdrant.sh)\" -- --backup${RESET}"
echo ""
echo -e " Mehr Tipps & Tutorials: ${CYAN}${BLOG_URL}${RESET}"
echo ""
[[ "${PROBLEMS}" -eq 0 ]] || exit 2
