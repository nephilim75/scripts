#!/usr/bin/env bash
# =============================================================================
# avila-code-interpreter Installer - powered by pc-fee.com
# https://pc-fee.com | https://github.com/nephilim75/scripts
#
# Installiert den LibreChat Code Interpreter (https://github.com/LibreChat-AI/
# code-interpreter) als eigenstaendigen Stack unter /opt/avila-code-interpreter
# hinter einem Nginx Proxy Manager (NPM).
#
# - Fertige Images: Die Dienste werden nicht lokal gebaut, sondern als fertige
#   Images der Entwickler von ghcr.io geladen (README des Projekts, Abschnitt
#   "Prebuilt images"). Nur im NsJail-Modus entstehen die Laufzeitumgebungen
#   der Sandbox (Python, Node, Bun, Bash) lokal.
# - Versionen: Installiert wird immer eine veroeffentlichte Version (Tag wie
#   v1.10.4), nie der Entwicklungsstand "main". Vorgeschlagen wird die neueste
#   Version, zu der es vollstaendige fertige Images gibt.
# - Haertung: Egress-Gateway, signierte Execution-Manifeste, Hardened Mode,
#   auf Wunsch JWT-signierte Auftraege (empfohlen). MicroVM-Modus mit eigenem
#   Gast-Kernel, wenn /dev/kvm verfuegbar ist, sonst NsJail-only.
# - Kein Port wird an den Host gebunden. Erreichbar ist der Dienst nur im
#   Docker-Netzwerk "shared_proxy" (lokal) bzw. ueber einen NPM-Proxy-Host.
# - Zwei Modi:
#     lokal  -> LibreChat laeuft auf DIESEM Server und erreicht den Dienst
#               direkt ueber den Container-Namen avila-api.
#     extern -> LibreChat laeuft auf einem anderen Server; Zugriff ueber eine
#               eigene Domain und einen Proxy Host im NPM.
# - LibreChats .env wird nur im lokalen Modus und nur auf Wunsch ergaenzt -
#   und erst, wenn der Stack nachweislich laeuft.
#
# Nutzung als 1-Zeiler (von ueberall, kein vorheriger Download noetig):
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/install/install-avila-code-interpreter.sh)"
#
# Umgebungsvariablen (optional):
#   CODEAPI_VERSION   Vorschlag fuer die Versionsabfrage (z.B. v1.10.3)
#
# Voraussetzungen: Debian 12/13, root (bzw. sudo), Docker + Docker Compose
# Plugin >= 2.24.4, git, openssl, laufender Nginx Proxy Manager, Docker-
# Netzwerk shared_proxy.
#
# AI Transparency: Dieses Script wurde mit Unterstuetzung von KI erstellt und
# vor Veroeffentlichung geprueft. Nutzung auf eigene Gefahr.
# =============================================================================
set -Eeuo pipefail
trap 'rc=$?; echo "[FEHLER] Abbruch in Zeile ${LINENO} (Exit ${rc})." >&2; exit ${rc}' ERR

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { printf '%b\n' "${CYAN}[INFO]${RESET}  $*"; }
success() { printf '%b\n' "${GREEN}[OK]${RESET}    $*"; }
warn()    { printf '%b\n' "${YELLOW}[WARN]${RESET}  $*"; }
error()   { printf '%b\n' "${RED}[FEHLER]${RESET} $*"; }
die()     { error "$*"; exit 1; }

# -----------------------------------------------------------------------------
# Konstanten
# -----------------------------------------------------------------------------
readonly REPO_URL="https://github.com/LibreChat-AI/code-interpreter.git"
readonly TAGS_URL="https://github.com/LibreChat-AI/code-interpreter/tags"
# Fertige Images der Entwickler. Sie tragen als Tag den Code-Stand
# ("sha-<commit>"), keine Versionsnummer - der Installer ermittelt den Commit
# zur gewaehlten Version selbst.
readonly GHCR_PREFIX="ghcr.io/librechat-ai/code-interpreter-"
# Ersatzvorschlag, falls sich die neueste Version nicht ermitteln laesst
# (zuletzt mit diesem Script geprueft).
readonly FALLBACK_VERSION="v1.10.4"
readonly DEFAULT_INSTALL_DIR="/opt/avila-code-interpreter"
readonly DEFAULT_LIBRECHAT_DIR="/opt/librechat"
readonly NPM_NETWORK="shared_proxy"
readonly API_CONTAINER="avila-api"
readonly API_PORT="3112"
readonly PKG_INIT_IMAGE="avila-package-init"
# "build: !reset null" in der Override-Datei braucht Docker Compose >= 2.24.4.
readonly MIN_COMPOSE_VERSION="2.24.4"
# Platzbedarf: Die sechs Images sind komprimiert rund 0,9 GB gross (gemessen
# an v1.10.4); Docker legt sie zusaetzlich entpackt ab. 6 GB lassen Reserve.
readonly MIN_FREE_MB=6000
# NsJail-Modus zusaetzlich: ~3,1 GB Laufzeitumgebungen unter data/pkgs plus
# ~1,4 GB fuer das package-init-Image, beim Entpacken kurzzeitig mehr.
readonly MIN_FREE_NSJAIL_MB=11000
readonly SWAP_FILE="/swapfile-avila-code-interpreter"
readonly SWAP_SIZE_MB=4096
readonly DOCKER_COMPOSE_GUIDE="https://pc-fee.com/2026/05/03/docker-compose/"
readonly NPM_GUIDE="https://pc-fee.com/2026/05/03/nginx-proxy-manager/"
readonly UPDATE_SCRIPT_URL="https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/update/update-avila-code-interpreter.sh"

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "Bitte als root ausfuehren oder sudo installieren."
  SUDO="sudo"
fi

is_domain() { [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; }
canon_dir() { local d="${1:-}"; d="${d/#\~/$HOME}"; printf '%s' "${d%/}"; }
detect_public_ipv4() {
  local ip
  ip="$(curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  [[ -z "${ip}" ]] && ip="$(curl -fsS4 --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  printf '%s' "${ip}"
}
has_kvm() { [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; }

# Bricht die Installation ab, nachdem schon etwas angelegt wurde, bleibt ein
# halbes Installationsverzeichnis zurueck - ein neuer Versuch wuerde dann an
# "existiert bereits" scheitern. Deshalb beim Abbruch genau sagen, was weg muss.
INSTALL_STARTED=0
INSTALL_DONE=0
on_exit() {
  local rc=$?
  if [[ "${rc}" -ne 0 && "${INSTALL_STARTED}" -eq 1 && "${INSTALL_DONE}" -eq 0 ]]; then
    echo "" >&2
    printf '%b\n' "${YELLOW}[WARN]${RESET}  Die Installation ist unvollstaendig. LibreChat wurde NICHT angefasst." >&2
    printf '%b\n' "${YELLOW}[WARN]${RESET}  Vor einem neuen Versuch aufraeumen:" >&2
    if [[ -f "${INSTALL_DIR}/docker-compose.yaml" ]]; then
      echo "          cd ${INSTALL_DIR} && ${COMPOSE_CMD} down -v && cd /" >&2
    fi
    echo "          ${SUDO:+${SUDO} }rm -rf ${INSTALL_DIR}" >&2
  fi
}
trap on_exit EXIT

# -----------------------------------------------------------------------------
# Banner
# -----------------------------------------------------------------------------
# 'clear' scheitert ohne brauchbares TERM - mit 'set -e' wuerde das Script dann
# ohne erkennbaren Grund abbrechen, deshalb der Fallback.
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
printf '%b\n' "${BOLD} Code Interpreter Installer – powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo "Installiert den LibreChat Code Interpreter (LibreChat-AI) mit fertigen"
echo "Images hinter einem Nginx Proxy Manager. Kein Port wird an den Host"
echo "gebunden."
echo "------------------------------------------------------------"

# -----------------------------------------------------------------------------
# Schritt 0: Voraussetzungen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 0: Voraussetzungen${RESET}"
echo "------------------------------------------------------------"

if command -v git >/dev/null 2>&1; then
  success "git gefunden: $(git --version)"
else
  warn "git ist nicht installiert."
  echo ""
  echo "  Die Konfiguration des Code Interpreters (Compose-Datei, Erzeuger der"
  echo "  Laufzeitumgebungen) wird aus dem offiziellen Repository geholt - ohne"
  echo "  git kann dieses Skript nicht fortfahren."
  echo ""
  echo "  Installiert wuerde es mit:"
  echo "    ${SUDO:+${SUDO} }apt-get install -y git"
  echo ""
  echo "  Das veraendert die Paketauswahl dieses Systems. Ohne ausdrueckliche"
  echo "  Zustimmung wird nichts installiert und die Installation bricht ab."
  echo ""
  read -rp "git jetzt installieren? [j/N]: " INSTALL_GIT
  [[ "${INSTALL_GIT,,}" == "j" ]] || die "Abgebrochen - es wurde nichts installiert. Bitte git selbst bereitstellen und das Skript erneut starten."
  command -v apt-get >/dev/null 2>&1 || die "apt-get nicht gefunden (nur Debian 12/13 unterstuetzt). Bitte git ueber die Paketverwaltung dieses Systems installieren."
  ${SUDO} apt-get install -y git || die "git-Installation fehlgeschlagen."
  command -v git >/dev/null 2>&1 || die "git konnte nicht installiert werden."
  success "git wurde installiert: $(git --version)"
fi

command -v docker >/dev/null 2>&1 || die "Docker ist nicht installiert. Anleitung: ${DOCKER_COMPOSE_GUIDE}"
success "Docker gefunden: $(docker --version)"

${SUDO} docker info >/dev/null 2>&1 || die "Docker-Daemon laeuft nicht oder ist nicht erreichbar. Anleitung: ${DOCKER_COMPOSE_GUIDE}"
success "Docker-Daemon laeuft."

${SUDO} docker compose version >/dev/null 2>&1 || die "Docker Compose Plugin nicht gefunden. Anleitung: ${DOCKER_COMPOSE_GUIDE}"
COMPOSE_CMD="${SUDO:+${SUDO} }docker compose"
COMPOSE_VERSION="$(${COMPOSE_CMD} version --short 2>/dev/null || true)"
COMPOSE_VERSION="${COMPOSE_VERSION#v}"
if [[ -n "${COMPOSE_VERSION}" ]] \
   && [[ "$(printf '%s\n%s\n' "${MIN_COMPOSE_VERSION}" "${COMPOSE_VERSION}" | sort -V | head -n1)" != "${MIN_COMPOSE_VERSION}" ]]; then
  die "Docker Compose ${COMPOSE_VERSION} ist zu alt - benoetigt wird mindestens ${MIN_COMPOSE_VERSION}. Anleitung: ${DOCKER_COMPOSE_GUIDE}"
fi
success "Docker Compose Plugin gefunden: ${COMPOSE_VERSION:-unbekannte Version}"

command -v openssl >/dev/null 2>&1 || die "openssl ist nicht installiert (wird fuer Secrets und Schluessel gebraucht)."
success "openssl gefunden."

# curl wird nur fuer die Anzeige der oeffentlichen IP am Ende gebraucht. Fehlt
# es, laeuft die Installation trotzdem durch - deshalb Hinweis statt Abbruch.
if command -v curl >/dev/null 2>&1; then
  success "curl gefunden."
else
  warn "curl ist nicht installiert - die oeffentliche IP fuer den A-Record kann"
  warn "am Ende nicht automatisch ermittelt werden (apt-get install -y curl)."
fi

# NPM + shared_proxy sind in beiden Modi Pflicht: lokal loesen LibreChat und der
# Interpreter darueber den Container-Namen des jeweils anderen auf, extern
# leitet NPM den Domain-Traffic dorthin weiter. Beides einzeln pruefen - ein
# bestehendes Netzwerk sagt nichts darueber, ob NPM auch laeuft.
if ${SUDO} docker ps --format '{{.Image}}' | grep -qi 'nginx-proxy-manager'; then
  success "Nginx Proxy Manager Container laeuft."
else
  die "Kein laufender Nginx Proxy Manager Container gefunden. Anleitung: ${NPM_GUIDE}"
fi
if ${SUDO} docker network inspect "${NPM_NETWORK}" >/dev/null 2>&1; then
  success "Docker-Netzwerk '${NPM_NETWORK}' gefunden."
else
  die "Docker-Netzwerk '${NPM_NETWORK}' existiert nicht. Anleitung: ${NPM_GUIDE}"
fi

# Bestehende Installation erkennen: am festen Container-Namen avila-api, nicht
# an einem Namens-Substring - fremde Stacks tragen womoeglich aehnliche Namen.
EXISTING="$(${SUDO} docker ps -a --format '{{.Names}}\t{{.Image}}' | awk -F'\t' -v n="${API_CONTAINER}" '$1==n' || true)"
if [[ -n "${EXISTING}" ]]; then
  error "Es existiert bereits ein Container ${API_CONTAINER}:"
  echo "${EXISTING}" | sed 's/^/    /'
  echo ""
  echo "  Fuer ein Update:      update-avila-code-interpreter.sh"
  echo "  Zum Entfernen:        uninstall-avila-code-interpreter.sh"
  echo "  (beide unter https://github.com/nephilim75/scripts/tree/main/librechat/codeInterpreter/LibreChat-AI)"
  die "Abbruch, um eine bestehende Installation nicht versehentlich zu ueberschreiben."
fi

# --- Versionen und fertige Images ermitteln ---------------------------------
# Welche Sandbox-Variante gebraucht wird, haengt an /dev/kvm (Schritt 4
# entscheidet nach genau derselben Bedingung).
if has_kvm; then
  SANDBOX_IMAGE="sandbox-runner"
else
  SANDBOX_IMAGE="sandbox-runner-direct"
fi
readonly SANDBOX_IMAGE
readonly STACK_IMAGES=(api worker file-server egress-gateway tool-call-server "${SANDBOX_IMAGE}")

# Alle Versionen samt Commit mit einem Aufruf holen (ls-remote liest nur). Bei
# annotierten Tags zeigt der Eintrag mit "^{}" auf den eigentlichen Commit.
declare -A TAG_COMMIT=()
while read -r sha ref; do
  [[ -n "${ref:-}" ]] || continue
  ref="${ref#refs/tags/}"
  if [[ "${ref}" == *'^{}' ]]; then
    TAG_COMMIT["${ref%'^{}'}"]="${sha}"
  elif [[ -z "${TAG_COMMIT[${ref}]:-}" ]]; then
    TAG_COMMIT["${ref}"]="${sha}"
  fi
done < <(git ls-remote --tags "${REPO_URL}" 'v*' 2>/dev/null || true)
[[ "${#TAG_COMMIT[@]}" -gt 0 ]] || die "Die Versionen des Code Interpreters sind nicht abrufbar - ist GitHub erreichbar?"

# Gibt es zu dieser Version alle fertigen Images? 'docker manifest inspect'
# liest nur die Image-Beschreibung, es wird nichts heruntergeladen.
images_available() {
  local sha="${TAG_COMMIT[$1]:-}" img
  [[ -n "${sha}" ]] || return 1
  for img in "${STACK_IMAGES[@]}"; do
    ${SUDO} docker manifest inspect "${GHCR_PREFIX}${img}:sha-${sha}" >/dev/null 2>&1 || return 1
  done
}

# Vorschlag: die neueste stabile Version (vX.Y.Z, keine -rcN) mit
# vollstaendigen Images. Fertige Images gibt es erst ab v1.10.0; zu einer
# brandneuen Version erscheinen sie womoeglich mit kurzer Verzoegerung.
LATEST_VERSION=""
while read -r v; do
  [[ -n "${v}" ]] || continue
  if images_available "${v}"; then LATEST_VERSION="${v}"; break; fi
done < <(printf '%s\n' "${!TAG_COMMIT[@]}" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -Vr | head -n 10)
if [[ -n "${LATEST_VERSION}" ]]; then
  success "Neueste Code-Interpreter-Version mit fertigen Images: ${LATEST_VERSION}"
  VERSION_DEFAULT="${LATEST_VERSION}"
else
  warn "Keine Version mit fertigen Images ermittelbar (ghcr.io erreichbar?)."
  VERSION_DEFAULT="${FALLBACK_VERSION}"
fi
[[ -n "${CODEAPI_VERSION:-}" ]] && VERSION_DEFAULT="${CODEAPI_VERSION}"

# -----------------------------------------------------------------------------
# Schritt 1: Konfiguration
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 1: Konfiguration${RESET}"
echo "------------------------------------------------------------"
read -rp "Installationspfad [${DEFAULT_INSTALL_DIR}]: " INSTALL_DIR
INSTALL_DIR="$(canon_dir "${INSTALL_DIR:-${DEFAULT_INSTALL_DIR}}")"
[[ ! -e "${INSTALL_DIR}" ]] || die "${INSTALL_DIR} existiert bereits. Abbruch, um nichts zu ueberschreiben. Bitte pruefen/entfernen oder einen anderen Pfad waehlen."
success "Installationspfad: ${INSTALL_DIR}"

echo ""
echo "1) Lokal  - LibreChat laeuft auf DIESEM Server. Kein Domain-Zugriff,"
echo "            direkte Container-zu-Container-Kommunikation."
echo "            Voraussetzung: LibreChat ist hier bereits installiert."
echo "2) Extern - LibreChat laeuft auf einem ANDEREN Server. Zugriff ueber"
echo "            eine eigene Domain via NPM."
echo "            Voraussetzung: eine Domain, die auf diesen Server zeigt."
echo ""
while :; do
  read -rp "Auswahl [1/2]: " MODE_CHOICE
  case "${MODE_CHOICE}" in
    1) MODE="lokal"; break ;;
    2) MODE="extern"; break ;;
    *) warn "Bitte 1 oder 2 eingeben." ;;
  esac
done
success "Modus: ${MODE}"

# Im lokalen Modus wird der Interpreter in LibreChats .env eingetragen - ohne
# LibreChat auf diesem Server gibt es nichts anzubinden.
LIBRECHAT_DIR=""
if [[ "${MODE}" == "lokal" ]]; then
  echo ""
  read -rp "Installationspfad von LibreChat [${DEFAULT_LIBRECHAT_DIR}]: " LIBRECHAT_DIR
  LIBRECHAT_DIR="$(canon_dir "${LIBRECHAT_DIR:-${DEFAULT_LIBRECHAT_DIR}}")"
  if [[ ! -f "${LIBRECHAT_DIR}/.env" ]]; then
    error "Unter ${LIBRECHAT_DIR} wurde keine LibreChat-Installation gefunden (.env fehlt)."
    echo ""
    echo "  Der lokale Modus setzt voraus, dass LibreChat auf DIESEM Server bereits"
    echo "  installiert ist. Moegliche naechste Schritte:"
    echo "    - LibreChat zuerst installieren, danach dieses Skript erneut starten"
    echo "    - oder Modus 2 (extern) waehlen, falls LibreChat woanders laeuft"
    die "Abbruch: keine LibreChat-Installation vorhanden."
  fi
  success "LibreChat gefunden: ${LIBRECHAT_DIR}"
fi

DOMAIN=""
if [[ "${MODE}" == "extern" ]]; then
  echo ""
  while :; do
    read -rp "Domain fuer den Code Interpreter (z.B. code.example.de): " DOMAIN
    is_domain "${DOMAIN}" && break || warn "Ungueltige Domain."
  done
  success "Domain: ${DOMAIN}"
fi

# JWT: LibreChat unterschreibt jeden Auftrag mit einem privaten Schluessel, der
# Interpreter prueft die Unterschrift mit dem oeffentlichen. Ohne JWT nimmt er
# JEDEN Auftrag an, der ihn erreicht.
echo ""
echo "Empfohlen: Auftraege per JWT signieren. LibreChat unterschreibt jeden"
echo "Auftrag, der Interpreter nimmt nur korrekt unterschriebene an."
echo "Ohne JWT fuehrt der Interpreter Code von jedem aus, der ihn erreicht."
read -rp "Codeausfuehrung per JWT absichern? [J/n]: " JWT_CONFIRM
if [[ "${JWT_CONFIRM,,}" == "n" ]]; then
  JWT_AUTH="false"
  warn "Ohne JWT-Absicherung - Zugriffsschutz nur ueber Netzwerk-Isolation."
else
  JWT_AUTH="true"
  success "JWT-Absicherung wird eingerichtet."
fi

# Version: Vorschlag ist die neueste mit fertigen Images. Geprueft wird, ob es
# sie gibt und ob alle Images vorliegen - bevor irgendetwas veraendert wird.
echo ""
while :; do
  read -rp "Code-Interpreter-Version [${VERSION_DEFAULT}]: " CODEAPI_VERSION
  CODEAPI_VERSION="${CODEAPI_VERSION:-${VERSION_DEFAULT}}"
  # "1.10.4" ohne fuehrendes v ebenfalls akzeptieren.
  [[ "${CODEAPI_VERSION}" =~ ^[0-9] ]] && CODEAPI_VERSION="v${CODEAPI_VERSION}"
  if [[ -z "${TAG_COMMIT[${CODEAPI_VERSION}]:-}" ]]; then
    warn "Version '${CODEAPI_VERSION}' gibt es nicht. Verfuegbare Versionen: ${TAGS_URL}"
    continue
  fi
  images_available "${CODEAPI_VERSION}" && break
  warn "Zu ${CODEAPI_VERSION} gibt es keine vollstaendigen fertigen Images (erst ab v1.10.0)."
done
readonly CODEAPI_VERSION
readonly CODEAPI_IMAGE_TAG="sha-${TAG_COMMIT[${CODEAPI_VERSION}]}"
if [[ -n "${LATEST_VERSION}" && "${CODEAPI_VERSION}" != "${LATEST_VERSION}" ]]; then
  warn "Version ${CODEAPI_VERSION} gewaehlt - neuer ist ${LATEST_VERSION} (spaeter per Update-Skript)."
else
  success "Version: ${CODEAPI_VERSION}"
fi

# -----------------------------------------------------------------------------
# Schritt 2: Swap-Speicher
# -----------------------------------------------------------------------------
# Bewusst VOR der Platzpruefung: die Swap-Datei belegt selbst Platz auf der
# Platte, die Pruefung soll den danach verbleibenden Platz messen.
printf '%b\n' "\n${BOLD}Schritt 2: Swap-Speicher${RESET}"
echo "------------------------------------------------------------"
info "Der Stack laeuft zusaetzlich zu LibreChat, im NsJail-Modus wird ausserdem"
info "Python aus dem Quellcode kompiliert. Auf kleinen Servern wird der"
info "Arbeitsspeicher dabei knapp - ohne Swap beendet das Betriebssystem dann"
info "Prozesse (OOM-Kill), meist ohne verstaendliche Fehlermeldung."
CURRENT_SWAP_MB="$(free -m | awk '/^Swap:/{print $2}')"
if (( CURRENT_SWAP_MB > 0 )); then
  success "Swap bereits vorhanden: ${CURRENT_SWAP_MB} MB. Kein Handlungsbedarf."
else
  warn "Kein Swap vorhanden."
  read -rp "Jetzt eine ${SWAP_SIZE_MB} MB Swap-Datei anlegen (${SWAP_FILE})? [j/N]: " SWAP_CONFIRM
  if [[ "${SWAP_CONFIRM,,}" == "j" ]]; then
    ${SUDO} fallocate -l "${SWAP_SIZE_MB}M" "${SWAP_FILE}" || ${SUDO} dd if=/dev/zero of="${SWAP_FILE}" bs=1M count="${SWAP_SIZE_MB}"
    ${SUDO} chmod 600 "${SWAP_FILE}"
    ${SUDO} mkswap "${SWAP_FILE}" >/dev/null
    ${SUDO} swapon "${SWAP_FILE}"
    if ! grep -q "^${SWAP_FILE} " /etc/fstab 2>/dev/null; then
      echo "${SWAP_FILE} none swap sw 0 0" | ${SUDO} tee -a /etc/fstab >/dev/null
    fi
    success "Swap-Datei angelegt und aktiviert (bleibt auch nach einem Neustart bestehen)."
  else
    warn "Kein Swap angelegt - es geht ohne Sicherheitsnetz weiter."
  fi
fi

# -----------------------------------------------------------------------------
# Schritt 3: Speicherplatz
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 3: Speicherplatz${RESET}"
echo "------------------------------------------------------------"
REQUIRED_FREE_MB="${MIN_FREE_MB}"
if has_kvm; then
  info "Benoetigt werden die fertigen Images (rund 0,9 GB komprimiert, Docker"
  info "legt sie zusaetzlich entpackt ab)."
else
  REQUIRED_FREE_MB="${MIN_FREE_NSJAIL_MB}"
  info "Benoetigt werden die fertigen Images (rund 0,9 GB komprimiert) und - im"
  info "NsJail-Modus - die lokal erzeugten Laufzeitumgebungen (rund 4,5 GB)."
fi
# Gemessen wird dort, wo Docker seine Images ablegt - nicht auf "/". Bei
# manchen Hostern liegt /var/lib/docker auf einer eigenen Partition.
DOCKER_ROOT="$(${SUDO} docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
[[ -d "${DOCKER_ROOT}" ]] || DOCKER_ROOT="/var/lib/docker"
[[ -d "${DOCKER_ROOT}" ]] || DOCKER_ROOT="/"
FREE_MB="$(df -Pm "${DOCKER_ROOT}" | awk 'NR==2{print $4}')"
info "Verfuegbarer Speicherplatz auf ${DOCKER_ROOT}: ${FREE_MB} MB"
info "Benoetigt (mit Reserve):          ${REQUIRED_FREE_MB} MB"
if (( FREE_MB < REQUIRED_FREE_MB )); then
  die "Weniger als ${REQUIRED_FREE_MB} MB frei. Bitte zuerst Platz schaffen - eine volle Platte kann auch LibreChat und andere Dienste auf diesem Server treffen."
fi
success "Genug Speicherplatz vorhanden."

# -----------------------------------------------------------------------------
# Schritt 4: Sandbox-Isolationsmodus
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 4: Sandbox-Isolationsmodus${RESET}"
echo "------------------------------------------------------------"
KVM_ENABLED="true"
if has_kvm; then
  success "/dev/kvm vorhanden und zugreifbar - MicroVM-Modus (eigener Gast-Kernel)."
else
  warn "/dev/kvm nicht gefunden oder nicht zugreifbar - MicroVM-Modus nicht moeglich."
  echo ""
  echo "Aus der offiziellen Projekt-Doku (README, Abschnitt 'Security disclaimer',"
  echo "https://github.com/LibreChat-AI/code-interpreter#security-disclaimer):"
  echo "  Im vollen gehaerteten Modus (MicroVM, eigener Gast-Kernel) gilt der"
  echo "  Interpreter als angemessen abgesichert. Der reine NsJail-Modus teilt"
  echo "  sich dagegen den Kernel mit dem Host und bietet spuerbar schwaechere"
  echo "  Isolation - passend fuer lokale Tests, NICHT fuer die Ausfuehrung von"
  echo "  Code aus nicht vertrauenswuerdigen Quellen."
  echo ""
  read -rp "Trotzdem mit dem NsJail-only-Modus fortfahren? [j/N]: " KVM_SKIP_CONFIRM
  [[ "${KVM_SKIP_CONFIRM,,}" == "j" ]] || die "Abgebrochen. Fuer den vollen MicroVM-Schutz wird ein Server mit /dev/kvm benoetigt."
  KVM_ENABLED="false"
  warn "NsJail-only-Modus gewaehlt - fuer Tests ok, nicht empfohlen fuer produktive Systeme mit unbekannten Nutzern."
fi

# -----------------------------------------------------------------------------
# Zusammenfassung
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Zusammenfassung${RESET}"
echo "------------------------------------------------------------"
printf 'Installationspfad: %s\n' "${INSTALL_DIR}"
printf 'Modus:             %s\n' "${MODE}"
[[ -n "${LIBRECHAT_DIR}" ]] && printf 'LibreChat:         %s\n' "${LIBRECHAT_DIR}"
[[ -n "${DOMAIN}" ]] && printf 'Domain:            %s\n' "${DOMAIN}"
printf 'Version:           %s\n' "${CODEAPI_VERSION}"
printf 'Isolation:         %s\n' "$( [[ "${KVM_ENABLED}" == "true" ]] && echo "MicroVM" || echo "NsJail-only" )"
printf 'JWT-Absicherung:   %s\n' "$( [[ "${JWT_AUTH}" == "true" ]] && echo "ja" || echo "nein" )"
printf 'NPM-Netzwerk:      %s\n' "${NPM_NETWORK}"
LC_WRITE_WANTED="false"
if [[ "${MODE}" == "lokal" && "${JWT_AUTH}" == "true" ]]; then
  echo ""
  echo "Die Anbindung (Adresse + privater JWT-Schluessel) gehoert in LibreChats"
  echo ".env. Das Skript kann sie dort eintragen - erst ganz am Ende, wenn der"
  echo "Stack nachweislich laeuft, und nach einer Sicherung der Datei."
  read -rp "Anbindung nach erfolgreicher Installation in ${LIBRECHAT_DIR}/.env eintragen? [J/n]: " LC_WRITE
  [[ "${LC_WRITE,,}" == "n" ]] || LC_WRITE_WANTED="true"
fi
echo ""
read -rp "Installation starten? [j/N]: " CONFIRM
[[ "${CONFIRM,,}" == "j" ]] || { warn "Abgebrochen (keine oder verneinende Eingabe)."; exit 0; }

# -----------------------------------------------------------------------------
# Schritt 5: Repository
# -----------------------------------------------------------------------------
# Gebraucht werden aus dem Repository die Compose-Datei, die zu den Images
# passt, und im NsJail-Modus der Erzeuger der Laufzeitumgebungen. Geholt wird
# genau die gewaehlte Version (Tag, --depth=1). Das Verzeichnis steht danach
# auf "detached HEAD" - gewollt, Versionswechsel macht das Update-Skript.
printf '%b\n' "\n${BOLD}Schritt 5: Repository${RESET}"
echo "------------------------------------------------------------"
[[ ! -e "${INSTALL_DIR}" ]] || die "${INSTALL_DIR} existiert bereits. Abbruch, um nichts zu ueberschreiben."
INSTALL_STARTED=1
${SUDO} git -c advice.detachedHead=false clone --depth=1 --branch "${CODEAPI_VERSION}" "${REPO_URL}" "${INSTALL_DIR}"
cd "${INSTALL_DIR}"
[[ -f docker-compose.yaml ]] || die "docker-compose.yaml fehlt im Repository - hat sich die Struktur geaendert?"
if [[ "${KVM_ENABLED}" == "false" ]]; then
  [[ -f docker/Dockerfile.package-init ]] || die "docker/Dockerfile.package-init fehlt im Repository - hat sich die Struktur geaendert?"
fi
success "Repository bereit (Version ${CODEAPI_VERSION})."

# -----------------------------------------------------------------------------
# Schritt 6: Secrets, Schluessel, .env
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 6: .env erzeugen${RESET}"
echo "------------------------------------------------------------"
info "Erzeuge Secrets fuer den internen Dienst-zu-Dienst-Verkehr und ein"
info "Ed25519-Schluesselpaar fuer die signierten Execution-Manifeste."

INTERNAL_SERVICE_TOKEN="$(openssl rand -hex 32)"
EGRESS_GRANT_SECRET="$(openssl rand -hex 32)"
MANIFEST_PRIV_B64="$(openssl genpkey -algorithm ed25519 -outform DER 2>/dev/null | base64 -w0)"
MANIFEST_PUB_B64="$(printf '%s' "${MANIFEST_PRIV_B64}" | base64 -d | openssl pkey -inform DER -pubout -outform DER 2>/dev/null | base64 -w0)"
[[ -n "${MANIFEST_PRIV_B64}" && -n "${MANIFEST_PUB_B64}" ]] || die "Ed25519-Schluesselpaar konnte nicht erzeugt werden."

# JWT-Schluesselpaar (getrennt vom Manifest-Schluessel). Der Verifier des
# Interpreters (service/src/auth/librechat-jwt.ts) nimmt den oeffentlichen
# Schluessel als JWK-JSON, LibreChat den privaten ebenfalls als JWK-JSON
# (packages/api/src/auth/codeapi.ts) - beides passt in je eine .env-Zeile.
# Bei Ed25519 haben die DER-Strukturen feste Laenge: die letzten 32 Byte des
# PKCS8-DER sind der private Seed ("d"), die letzten 32 Byte des SPKI-DER der
# oeffentliche Punkt ("x"). Beides base64url-kodiert ergibt ein gueltiges JWK.
readonly JWT_ISSUER="librechat"
readonly JWT_AUDIENCE="codeapi"
readonly JWT_TENANT_ID="legacy"
JWT_KID=""; JWT_PUBLIC_JWK=""; JWT_PRIVATE_JWK=""
if [[ "${JWT_AUTH}" == "true" ]]; then
  b64url() { base64 -w0 | tr '+/' '-_' | tr -d '='; }
  JWT_PRIV_PEM="$(openssl genpkey -algorithm ed25519 2>/dev/null)"
  [[ -n "${JWT_PRIV_PEM}" ]] || die "JWT-Schluesselpaar konnte nicht erzeugt werden."
  JWT_D="$(printf '%s' "${JWT_PRIV_PEM}" | openssl pkey -outform DER 2>/dev/null | tail -c 32 | b64url)"
  JWT_X="$(printf '%s' "${JWT_PRIV_PEM}" | openssl pkey -pubout -outform DER 2>/dev/null | tail -c 32 | b64url)"
  [[ -n "${JWT_D}" && -n "${JWT_X}" ]] || die "JWT-Schluessel konnten nicht in das JWK-Format umgewandelt werden."
  JWT_KID="lc-codeapi-$(date +%Y-%m)-$(openssl rand -hex 3)"
  JWT_PUBLIC_JWK="{\"crv\":\"Ed25519\",\"x\":\"${JWT_X}\",\"kty\":\"OKP\",\"kid\":\"${JWT_KID}\",\"alg\":\"EdDSA\"}"
  JWT_PRIVATE_JWK="{\"crv\":\"Ed25519\",\"d\":\"${JWT_D}\",\"x\":\"${JWT_X}\",\"kty\":\"OKP\",\"kid\":\"${JWT_KID}\",\"alg\":\"EdDSA\"}"
  unset JWT_PRIV_PEM JWT_D
  success "JWT-Schluesselpaar erzeugt (Kennung: ${JWT_KID})."
fi

{
  echo "# Erzeugt von install-avila-code-interpreter.sh am $(date '+%Y-%m-%d %H:%M')"
  echo "# Enthaelt Secrets und Schluessel - nicht weitergeben, nicht in ein Git-Repo."
  echo ""
  echo "# Version und Code-Stand der fertigen Images (das Update-Skript stellt"
  echo "# beides gemeinsam um)."
  echo "CODEAPI_VERSION=${CODEAPI_VERSION}"
  echo "CODEAPI_IMAGE_TAG=${CODEAPI_IMAGE_TAG}"
  echo ""
  echo "LOCAL_MODE=false"
  echo "CODEAPI_HARDENED_SANDBOX_MODE=true"
  echo "KVM_ENABLED=${KVM_ENABLED}"
  # Mit LOCAL_MODE=false verlangt die API eine vollstaendige JWT-Konfiguration
  # oder die ausdrueckliche Freigabe des Modus "none" (service/src/auth/
  # startup.ts) - sonst startet sie nicht.
  if [[ "${JWT_AUTH}" == "true" ]]; then
    echo "CODEAPI_AUTH_PROVIDER=librechat-jwt"
    echo "CODEAPI_JWT_ALLOWED_ALGS=EdDSA"
    echo "CODEAPI_JWT_ISSUER=${JWT_ISSUER}"
    echo "CODEAPI_JWT_AUDIENCE=${JWT_AUDIENCE}"
    echo "CODEAPI_JWT_KID=${JWT_KID}"
    echo "CODEAPI_JWT_PUBLIC_KEY=${JWT_PUBLIC_JWK}"
    echo "CODEAPI_JWT_SINGLE_TENANT_ID=${JWT_TENANT_ID}"
  else
    echo "CODEAPI_AUTH_PROVIDER=none"
    echo "CODEAPI_ALLOW_AUTH_PROVIDER_NONE=true"
  fi
  # Remote-Bridge (Anbindung externer Sandbox-Rechner) wird nicht genutzt. Die
  # Compose-Datei schaltet sie per Standardwert ein; im gehaerteten Modus
  # startet die API dann nur mit eigenem CODEAPI_BRIDGE_TOKEN (service/src/
  # secure-startup.ts). Abgeschaltet entfaellt die Schnittstelle komplett.
  echo "CODEAPI_BRIDGE_AUTH_MODE=static"
  echo "CODEAPI_BRIDGE_DYNAMIC_WORKERS=false"
  echo "CODEAPI_INTERNAL_SERVICE_TOKEN=${INTERNAL_SERVICE_TOKEN}"
  echo "CODEAPI_EGRESS_GRANT_SECRET=${EGRESS_GRANT_SECRET}"
  echo "CODEAPI_EXECUTION_MANIFEST_PRIVATE_KEY=${MANIFEST_PRIV_B64}"
  echo "SANDBOX_EXECUTION_MANIFEST_PUBLIC_KEY=${MANIFEST_PUB_B64}"
  echo "SANDBOX_REQUIRE_EGRESS_MANIFEST=true"
  # MinIO und Redis behalten die Standard-Zugangsdaten des Repositorys: beide
  # haengen nicht im shared_proxy-Netz und sind nur projektintern erreichbar.
} | ${SUDO} tee .env >/dev/null
${SUDO} chmod 600 .env
success ".env geschrieben (chmod 600)."

# Der LibreChat-Block enthaelt den PRIVATEN Schluessel - er gehoert nur auf die
# LibreChat-Seite. Abgelegt als Vorlage (chmod 600); im lokalen Modus wird er
# am Ende auf Wunsch eingetragen und die Vorlage danach geloescht.
LIBRECHAT_BLOCK_FILE=""
if [[ "${MODE}" == "lokal" ]]; then
  LC_BASEURL="http://${API_CONTAINER}:${API_PORT}/v1"
else
  LC_BASEURL="https://${DOMAIN}/v1"
fi
if [[ "${JWT_AUTH}" == "true" ]]; then
  LIBRECHAT_BLOCK_FILE="${INSTALL_DIR}/librechat-jwt-block.txt"
  ${SUDO} tee "${LIBRECHAT_BLOCK_FILE}" >/dev/null <<EOF
# ===========================================================================
# Code-Interpreter-Anbindung fuer LibreChat
# Erzeugt von install-avila-code-interpreter.sh am $(date '+%Y-%m-%d %H:%M')
# Diese Zeilen gehoeren in die .env von LibreChat. Der private Schluessel
# darf NUR dort liegen. Aeltere Zeilen mit LIBRECHAT_CODE_BASEURL= oder
# CODEAPI_ in derselben .env vorher entfernen oder auskommentieren - sonst
# gewinnt die jeweils letzte Zuweisung (typischer Fehler: "unknown_kid").
# ===========================================================================
LIBRECHAT_CODE_BASEURL=${LC_BASEURL}
CODEAPI_AUTH_PROVIDER=librechat-jwt
CODEAPI_JWT_ALGORITHM=EdDSA
CODEAPI_JWT_KID=${JWT_KID}
CODEAPI_JWT_ISSUER=${JWT_ISSUER}
CODEAPI_JWT_AUDIENCE=${JWT_AUDIENCE}
CODEAPI_JWT_TTL_SECONDS=300
CODEAPI_JWT_MINT_CACHE_SECONDS=30
CODEAPI_JWT_SINGLE_TENANT_ID=${JWT_TENANT_ID}
CODEAPI_JWT_PRIVATE_JWK_JSON=${JWT_PRIVATE_JWK}
EOF
  ${SUDO} chmod 600 "${LIBRECHAT_BLOCK_FILE}"
  success "LibreChat-Konfigurationsblock abgelegt: ${LIBRECHAT_BLOCK_FILE}"
fi

# -----------------------------------------------------------------------------
# Schritt 7: docker-compose.override.yml
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 7: Compose Override${RESET}"
echo "------------------------------------------------------------"

# Sandbox im NsJail-Modus:
# - Ohne /dev/kvm wuerde Docker beim Start versuchen, das nicht existierende
#   Geraet einzubinden - das devices-Mapping wird deshalb entfernt.
# - NsJail richtet Cgroups und Namespaces direkt am Host ein und braucht dafuer
#   CAP_SYS_ADMIN und ein freigegebenes AppArmor-Profil.
# - Healthcheck: Der Starter bindet das komplette /usr des Sandbox-Rootfs ueber
#   das /usr des Containers. Auch "docker exec" - und damit Dockers Health-
#   check - sieht danach dieses /usr; das mitgelieferte /usr/local/bin/
#   sandbox-runner-healthcheck.sh liegt dort nicht. Der Status bliebe auf
#   "starting", und service-worker (wartet auf "healthy") startet nie.
#   Abhilfe: ein eigenes Skript ausserhalb von /usr, nur mit Bash-Bordmitteln
#   (/dev/tcp statt curl), gegen denselben Endpunkt wie das Original.
SANDBOX_EXTRA=""
if [[ "${KVM_ENABLED}" == "false" ]]; then
  ${SUDO} mkdir -p ./nsjail-fix
  ${SUDO} tee ./nsjail-fix/avila-healthcheck.sh >/dev/null <<'HEALTHEOF'
#!/bin/bash
# Healthcheck des Sandbox-Runners im NsJail-Modus (erzeugt vom Installer).
# Nur Bash-Builtins: nach dem Einbinden des Sandbox-/usr fehlen curl & Co.
exec 3<>/dev/tcp/127.0.0.1/2000 || exit 1
printf 'GET /api/v2/health HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n' >&3 || exit 1
read -r statuszeile <&3 || exit 1
exec 3<&-
case "$statuszeile" in
    *" 200"*) exit 0 ;;
    *) exit 1 ;;
esac
HEALTHEOF
  ${SUDO} chmod +x ./nsjail-fix/avila-healthcheck.sh
  success "Eigenes Healthcheck-Skript fuer den NsJail-Modus erzeugt."
  SANDBOX_EXTRA='    devices: !reset []
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
    volumes:
      - ./nsjail-fix/avila-healthcheck.sh:/avila-healthcheck.sh:ro
    healthcheck:
      test: ["CMD", "/bin/bash", "/avila-healthcheck.sh"]
      interval: 5s
      timeout: 3s
      start_period: 20s
      retries: 60
'
fi

# Fertige Images statt lokalem Build: pro Dienst das Image der Entwickler,
# "build: !reset null" schaltet den Build der Basis-Compose-Datei ab. Der Tag
# kommt als Variable aus der .env - ein Versionswechsel aendert nur dort eine
# Zeile. pull_policy missing: ein sha-Tag aendert sich nie.
img() {
  printf '    image: %s%s:${CODEAPI_IMAGE_TAG:?CODEAPI_IMAGE_TAG fehlt in .env}\n    build: !reset null\n    pull_policy: missing\n' "${GHCR_PREFIX}" "$1"
}
{
  echo "# Erzeugt von install-avila-code-interpreter.sh - Marker der Installation."
  echo "# Container-Namen, fertige Images, keine Host-Ports, Netzwerk ${NPM_NETWORK}."
  echo "services:"
  echo "  api:"
  echo "    container_name: ${API_CONTAINER}"
  img api
  echo "    ports: !reset []"
  echo "    networks:"
  echo "      - default"
  echo "      - ${NPM_NETWORK}"
  echo ""
  echo "  service-worker:"
  echo "    container_name: avila-service-worker"
  img worker
  echo ""
  echo "  egress_gateway:"
  echo "    container_name: avila-egress-gateway"
  img egress-gateway
  echo "    ports: !reset []"
  echo ""
  echo "  tool_call_server:"
  echo "    container_name: avila-tool-call-server"
  img tool-call-server
  echo ""
  echo "  sandbox-runner:"
  echo "    container_name: avila-sandbox-runner"
  img "${SANDBOX_IMAGE}"
  echo "    ports: !reset []"
  printf '%s' "${SANDBOX_EXTRA}"
  echo ""
  echo "  file_server:"
  echo "    container_name: avila-file-server"
  img file-server
  echo "    ports: !reset []"
  echo ""
  echo "  redis:"
  echo "    container_name: avila-redis"
  echo "    ports: !reset []"
  echo ""
  echo "  minio:"
  echo "    container_name: avila-minio"
  echo "    ports: !reset []"
  echo ""
  echo "networks:"
  echo "  ${NPM_NETWORK}:"
  echo "    external: true"
} | ${SUDO} tee docker-compose.override.yml >/dev/null

${COMPOSE_CMD} config --quiet || die "Die Compose-Konfiguration ist ungueltig - bitte docker-compose.override.yml pruefen."
success "docker-compose.override.yml ok - kein Port wird am Host gebunden."

# -----------------------------------------------------------------------------
# Schritt 8: Images laden und Stack starten
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 8: Images laden und Stack starten${RESET}"
echo "------------------------------------------------------------"
info "Lade die fertigen Images (${CODEAPI_VERSION}) und die Basis-Images..."
${COMPOSE_CMD} pull || die "Die Images konnten nicht geladen werden (Netz zu ghcr.io / Docker Hub?)."
success "Images geladen."

# Laufzeitumgebungen (nur NsJail): Im MicroVM-Modus sind Python/Node/Bun/Bash
# fest im Image enthalten. Im NsJail-Modus liest die Sandbox sie zur Laufzeit
# vom Host (./data/pkgs -> /host-packages, siehe docker-compose.yaml). Bleibt
# das Verzeichnis leer, startet der Stack "healthy", aber JEDE Ausfuehrung
# scheitert mit "[bad_request] <runtime> is unknown". Fertige Pakete gibt es
# dafuer nicht; das Repository liefert den Erzeuger (Dockerfile.package-init).
if [[ "${KVM_ENABLED}" == "false" ]]; then
  printf '%b\n' "\n${BOLD}Laufzeitumgebungen der Sandbox erzeugen${RESET}"
  echo "------------------------------------------------------------"
  warn "Python, Node, Bun und Bash werden jetzt einmalig gebaut, Python aus dem"
  warn "Quellcode - je nach Server 10-20 Minuten. Bitte nicht abbrechen."
  ${SUDO} mkdir -p "${INSTALL_DIR}/data/pkgs"
  ${SUDO} docker build -f docker/Dockerfile.package-init -t "${PKG_INIT_IMAGE}" . \
    || die "Image fuer die Laufzeitumgebungen konnte nicht gebaut werden."
  ${SUDO} docker run --rm -v "${INSTALL_DIR}/data/pkgs:/pkgs" "${PKG_INIT_IMAGE}" \
    || die "Laufzeitumgebungen konnten nicht erzeugt werden."
  for runtime in python node bun bash; do
    [[ -e "${INSTALL_DIR}/data/pkgs/${runtime}" ]] \
      || die "Laufzeitumgebung '${runtime}' fehlt unter ${INSTALL_DIR}/data/pkgs - Abbruch."
  done
  success "Laufzeitumgebungen bereit: python, node, bun, bash."
fi

${COMPOSE_CMD} up -d

wait_running() {
  local service="$1" cid state health
  info "Warte auf Service ${service}..."
  for _ in {1..80}; do
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
  die "Service ${service} wurde nicht bereit. LibreChat wurde nicht angefasst."
}

for svc in redis minio tool_call_server egress_gateway sandbox-runner file_server api service-worker; do
  wait_running "${svc}"
done

# -----------------------------------------------------------------------------
# Schritt 9: Sicherheits-Check
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 9: Sicherheits-Check${RESET}"
echo "------------------------------------------------------------"
PUBLIC_PORT_FOUND=0
while IFS= read -r c; do
  [[ -n "${c}" ]] || continue
  if ${SUDO} docker port "${c}" 2>/dev/null | grep -q '0\.0\.0\.0\|\[::\]'; then
    warn "Container ${c} hat einen oeffentlich gebundenen Port - bitte pruefen: docker port ${c}"
    PUBLIC_PORT_FOUND=1
  fi
done < <(${COMPOSE_CMD} ps -a --format '{{.Name}}' 2>/dev/null || true)
(( PUBLIC_PORT_FOUND == 0 )) && success "Kein Container hat einen oeffentlich gebundenen Port."
# Ab hier laeuft der Stack vollstaendig - kein Aufraeum-Hinweis mehr bei Fehlern.
INSTALL_DONE=1

# -----------------------------------------------------------------------------
# Schritt 10: LibreChat anbinden (nur lokal + JWT + gewuenscht)
# -----------------------------------------------------------------------------
# Erst jetzt, da der Stack nachweislich laeuft: bricht die Installation vorher
# ab, bleibt LibreChats .env unberuehrt.
LC_ENV_WRITTEN="false"
if [[ "${LC_WRITE_WANTED}" == "true" ]]; then
  printf '%b\n' "\n${BOLD}Schritt 10: LibreChat anbinden${RESET}"
  echo "------------------------------------------------------------"
  LC_BACKUP="${LIBRECHAT_DIR}/.env.vor-code-interpreter-$(date +%Y%m%d-%H%M%S)"
  ${SUDO} cp -p "${LIBRECHAT_DIR}/.env" "${LC_BACKUP}"
  # Aeltere Eintraege auskommentieren statt Dubletten zu erzeugen.
  ${SUDO} sed -i -E 's~^(LIBRECHAT_CODE_BASEURL=|CODEAPI_)~#&~' "${LIBRECHAT_DIR}/.env"
  { echo ""; ${SUDO} cat "${LIBRECHAT_BLOCK_FILE}"; } | ${SUDO} tee -a "${LIBRECHAT_DIR}/.env" >/dev/null
  success "In LibreChats .env eingetragen (Sicherung: $(basename "${LC_BACKUP}"))."
  # Der private Schluessel steht jetzt in LibreChats .env - eine zweite Kopie
  # waere nur ein weiteres Risiko (z.B. in Backups dieses Verzeichnisses).
  ${SUDO} rm -f "${LIBRECHAT_BLOCK_FILE}"
  LIBRECHAT_BLOCK_FILE=""
  info "Vorlagendatei mit dem privaten Schluessel wurde entfernt."
  LC_ENV_WRITTEN="true"
fi

# -----------------------------------------------------------------------------
# Abschluss
# -----------------------------------------------------------------------------
echo ""
${COMPOSE_CMD} ps
echo ""
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"
printf '%b\n' "${GREEN}${BOLD}#                                           #${RESET}"
printf '%b\n' "${GREEN}${BOLD}#         Installation erfolgreich          #${RESET}"
printf '%b\n' "${GREEN}${BOLD}#                                           #${RESET}"
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"

printf '%b\n' "\n${BLUE}${BOLD}Naechste Schritte${RESET}"
printf '%b\n' "${BLUE}------------------------------------------------------------${RESET}"
echo ""

if [[ "${MODE}" == "lokal" ]]; then
  info "LibreChat erreicht den Interpreter direkt ueber den Container-Namen"
  info "${API_CONTAINER} im Netzwerk '${NPM_NETWORK}' - keine Domain, kein Proxy Host."
  echo ""
  if [[ "${LC_ENV_WRITTEN}" == "true" ]]; then
    success "Die Anbindung steht bereits in ${LIBRECHAT_DIR}/.env."
    echo ""
    echo "LibreChat liest die .env nur beim Start - es fehlt ein echter Stop+Start"
    echo "(ein reines 'docker restart' genuegt NICHT):"
    echo ""
    echo "  docker stop LibreChat && docker start LibreChat"
  elif [[ "${JWT_AUTH}" == "true" ]]; then
    printf '%b\n' "${YELLOW}${BOLD}>>> Letzter offener Schritt - ohne ihn laeuft nichts. <<<${RESET}"
    echo ""
    echo "Den Block aus dieser Datei in ${LIBRECHAT_DIR}/.env uebernehmen:"
    echo ""
    printf '%b\n' "  ${BOLD}${LIBRECHAT_BLOCK_FILE}${RESET}"
    echo ""
    echo "Vorher in der .env aeltere Zeilen mit LIBRECHAT_CODE_BASEURL= oder"
    echo "CODEAPI_ entfernen oder auskommentieren (die letzte Zuweisung gewinnt)."
    echo "Danach die Vorlagendatei loeschen und LibreChat stoppen und starten:"
    echo ""
    echo "  rm ${LIBRECHAT_BLOCK_FILE}"
    echo "  docker stop LibreChat && docker start LibreChat"
  else
    echo "In ${LIBRECHAT_DIR}/.env eintragen, danach LibreChat stoppen und starten"
    echo "(ein reines 'docker restart' liest die .env NICHT neu):"
    echo ""
    echo "  LIBRECHAT_CODE_BASEURL=${LC_BASEURL}"
    echo "  docker stop LibreChat && docker start LibreChat"
  fi
else
  HOST_IPV4="$(detect_public_ipv4)"
  if [[ -n "${HOST_IPV4}" ]]; then
    cat <<DNS
1) Beim Domain-Provider einen A-Record auf diesen Host setzen:

   ${HOST_IPV4}   A   (TTL 300)   ${DOMAIN}
DNS
  else
    warn "Oeffentliche IPv4 konnte nicht automatisch ermittelt werden."
    echo "1) Beim Domain-Provider einen A-Record fuer ${DOMAIN} auf diesen Server setzen."
  fi
  CHECK="${GREEN}✓${RESET}"
  cat <<NEXT

2) Proxy Host im Nginx Proxy Manager anlegen:

   Reiter Details:
     Domain:             ${DOMAIN}
     Scheme:             http
     Forward Hostname:   ${API_CONTAINER}
     Forward Port:       ${API_PORT}
NEXT
  printf '     Websockets Support: %b\n' "${CHECK}"
  cat <<NEXT
   Reiter SSL:
     SSL Certificate:    Request a new SSL Certificate (Let's Encrypt)
NEXT
  printf '     Force SSL:          %b\n' "${CHECK}"
  printf '     HTTP/2 Support:     %b\n' "${CHECK}"
  printf '     HSTS Enabled:       %b\n' "${CHECK}"
  echo ""
  echo "   Empfohlen: im NPM eine Access List anlegen, die nur die IP des"
  echo "   LibreChat-Servers zulaesst, und dem Proxy Host zuweisen."
  echo ""
  if [[ "${JWT_AUTH}" == "true" ]]; then
    echo "3) Den Block aus dieser Datei auf den LibreChat-Server uebertragen und"
    echo "   dort in die .env einfuegen (aeltere LIBRECHAT_CODE_BASEURL=/CODEAPI_-"
    echo "   Zeilen vorher entfernen):"
    echo ""
    printf '%b\n' "     ${BOLD}${LIBRECHAT_BLOCK_FILE}${RESET}"
    echo ""
    echo "   Danach LibreChat stoppen und starten (kein reines 'docker restart'):"
    echo "     docker stop LibreChat && docker start LibreChat"
    echo ""
    warn "Die Datei enthaelt den PRIVATEN Signierschluessel. Nach dem Uebertragen"
    warn "hier loeschen: rm ${LIBRECHAT_BLOCK_FILE}"
  else
    echo "3) In LibreChats .env eintragen, danach LibreChat stoppen und starten:"
    echo ""
    echo "     LIBRECHAT_CODE_BASEURL=${LC_BASEURL}"
    echo ""
    warn "Ohne JWT ist der Dienst ueber die Domain fuer jeden erreichbar, der sie"
    warn "kennt - die Access List im NPM ist dann der einzige Schutz."
  fi
fi

echo ""
if [[ "${KVM_ENABLED}" == "true" ]]; then
  success "Isolation: MicroVM-Modus (eigener Gast-Kernel, laut Projekt-Doku angemessen abgesichert)."
else
  warn "Isolation: NsJail-only-Modus (teilt sich den Host-Kernel, laut Projekt-Doku"
  warn "geeignet fuer Tests, nicht fuer produktive Systeme mit unbekannten Nutzern)."
fi
if [[ "${JWT_AUTH}" == "true" ]]; then
  success "Authentifizierung: Auftraege werden per JWT signiert und geprueft (EdDSA)."
else
  warn "Authentifizierung: keine - Absicherung nur ueber die Netzwerk-Isolation."
fi

cat <<NEXT

Wichtige Befehle:
  Logs:    cd ${INSTALL_DIR} && ${COMPOSE_CMD} logs -f
  Status:  cd ${INSTALL_DIR} && ${COMPOSE_CMD} ps
  Version: ${CODEAPI_VERSION}
  Update:  sudo bash -c "\$(curl -fsSL ${UPDATE_SCRIPT_URL})"

GitHub-Referenz:
  https://github.com/nephilim75/scripts/tree/main/librechat/codeInterpreter/LibreChat-AI

NEXT
