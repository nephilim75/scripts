#!/usr/bin/env bash
# =============================================================================
# Docker & Docker Compose Updater für Debian
# - Gegenstück zu install-docker.sh:
#   https://docs.docker.com/engine/install/debian/
# - prüft, ob Docker überhaupt aus dem offiziellen Docker-apt-Repository stammt
#   (docker-ce), und bricht bei Distro-Paketen wie docker.io kontrolliert ab
# - prüft GPG-Schlüssel und Repository-Eintrag und repariert sie bei Bedarf
#   (z.B. nach einem Debian-Release-Upgrade, wenn der Codename nicht mehr passt)
# - zeigt installierte vs. verfügbare Versionen sowie laufende Container an
# - zeigt vor dem eigentlichen Start eine Zusammenfassung und fragt explizit
#   nach Bestätigung; danach begleitet das Skript jeden Schritt mit Ausgaben
# - aktualisiert ausschliesslich die Docker-Pakete (kein dist-upgrade), startet
#   den Dienst bei Bedarf neu und verifiziert das Ergebnis
#
# -----------------------------------------------------------------------------
# AI-Transparenzhinweis:
# Dieses Skript wurde unter Einsatz von KI-Modellen (Claude Opus 5, Anthropic)
# recherchiert, erstellt und iterativ überarbeitet. Alle technischen Aussagen
# wurden gegen die offizielle Docker-Dokumentation geprüft. Vor produktivem
# Einsatz eigenverantwortlich prüfen.
# -----------------------------------------------------------------------------
# =============================================================================
# shellcheck disable=SC2154  # rc wird innerhalb des trap-Strings selbst gesetzt
# shellcheck disable=SC2034  # BLUE derzeit ungenutzt, für künftige Log-Stufen vorgesehen
set -Eeuo pipefail
trap 'rc=$?; echo "[FEHLER] Abbruch in Zeile ${LINENO} (Exit ${rc})." >&2; exit ${rc}' ERR

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { printf '%b\n' "${CYAN}[INFO]${RESET}  $*"; }
success() { printf '%b\n' "${GREEN}[OK]${RESET}    $*"; }
warn()    { printf '%b\n' "${YELLOW}[WARN]${RESET}  $*"; }
error()   { printf '%b\n' "${RED}[FEHLER]${RESET} $*"; }
die()     { error "$*"; exit 1; }

readonly DOCKER_GPG_URL="https://download.docker.com/linux/debian/gpg"
readonly DOCKER_APT_REPO_BASE="https://download.docker.com/linux/debian"
readonly KEYRING_DIR="/etc/apt/keyrings"
readonly KEYRING_PATH="${KEYRING_DIR}/docker.asc"
readonly SOURCES_LIST_PATH="/etc/apt/sources.list.d/docker.list"
readonly OFFICIAL_GUIDE="https://docs.docker.com/engine/install/debian/"
readonly DOCKER_PACKAGES=(
    docker-ce
    docker-ce-cli
    containerd.io
    docker-buildx-plugin
    docker-compose-plugin
)

# Optionen (Umgebungsvariablen):
#   ASSUME_YES=1        Überspringt die Bestätigungsabfrage vor dem Update
#                       (z.B. für automatisierte/unbeaufsichtigte Läufe)
#   SKIP_REPO_FIX=1     Repository/GPG-Schlüssel nur prüfen, nicht reparieren

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "Bitte als root ausführen oder sudo installieren."
  SUDO="sudo"
fi

# apt-Ausgaben unabhängig von der Systemsprache auswerten
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# Banner
# -----------------------------------------------------------------------------
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
printf '%b\n' "${BOLD} Docker & Docker Compose Updater – powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET}"
echo ""
echo "Aktualisiert eine bestehende Docker-Installation aus dem offiziellen"
echo "Docker-apt-Repository und repariert dabei bei Bedarf Schlüssel und"
echo "Repository-Eintrag. Siehe auch: ${OFFICIAL_GUIDE}"
echo "------------------------------------------------------------"

# -----------------------------------------------------------------------------
# Schritt 1: System und bestehende Installation erkennen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 1: Systemerkennung${RESET}"
echo "------------------------------------------------------------"

if [ ! -r /etc/os-release ]; then
    die "/etc/os-release nicht gefunden – dies scheint kein unterstütztes Debian-System zu sein."
fi

# shellcheck source=/dev/null
. /etc/os-release

OS_ID="${ID:-unknown}"
OS_ID_LIKE="${ID_LIKE:-}"
OS_CODENAME="${VERSION_CODENAME:-}"
OS_VERSION_ID="${VERSION_ID:-}"

info "Erkanntes System: ${PRETTY_NAME:-unbekannt} (ID=$OS_ID, VERSION_ID=$OS_VERSION_ID, CODENAME=$OS_CODENAME)"

if [ "$OS_ID" != "debian" ]; then
    if [[ "$OS_ID_LIKE" == *debian* ]]; then
        warn "Es wurde '$OS_ID' erkannt (Debian-basiert), nicht 'debian' selbst."
        die "Abbruch, da kein reines Debian erkannt wurde. Bitte das passende Docker-Update-Skript für '$OS_ID' verwenden."
    else
        die "Dieses Skript unterstützt nur Debian. Erkanntes System: '$OS_ID'."
    fi
fi

[ -n "$OS_CODENAME" ] || die "Konnte VERSION_CODENAME nicht aus /etc/os-release ermitteln. Abbruch."

ARCH="$(dpkg --print-architecture)"
info "Erkannte CPU-Architektur: $ARCH"

if ! command -v docker >/dev/null 2>&1; then
    error "Docker ist auf diesem System nicht installiert."
    die "Bitte zuerst install-docker.sh ausführen – dieses Skript aktualisiert nur eine bestehende Installation."
fi

if ! dpkg-query -W -f='${db:Status-Status}' docker-ce 2>/dev/null | grep -q '^installed$'; then
    error "Es ist zwar ein 'docker' vorhanden ($(docker --version 2>/dev/null || echo 'Version unbekannt')),"
    error "aber nicht das Paket 'docker-ce' aus dem offiziellen Docker-Repository."
    error "Vermutlich stammt die Installation aus den Debian-Paketen (docker.io) oder"
    error "von convenience script/Snap. Dieses Skript kann das nicht sinnvoll aktualisieren."
    die "Bitte install-docker.sh verwenden – es entfernt die Alt-Pakete und installiert sauber neu."
fi

success "Bestehende Installation erkannt: $(docker --version)"
COMPOSE_BEFORE="$(docker compose version 2>/dev/null || echo 'nicht installiert')"
info "Docker Compose: ${COMPOSE_BEFORE}"

# -----------------------------------------------------------------------------
# Schritt 2: GPG-Schlüssel und Repository prüfen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 2: Schlüssel und Repository prüfen${RESET}"
echo "------------------------------------------------------------"

REPO_ACTION="nichts zu tun"
KEY_MISSING="nein"
REPO_NEEDS_WRITE="nein"

if [ -s "${KEYRING_PATH}" ]; then
    success "GPG-Schlüssel vorhanden: ${KEYRING_PATH}"
else
    warn "GPG-Schlüssel fehlt oder ist leer: ${KEYRING_PATH}"
    KEY_MISSING="ja"
fi

EXPECTED_REPO_LINE="deb [arch=${ARCH} signed-by=${KEYRING_PATH}] ${DOCKER_APT_REPO_BASE} ${OS_CODENAME} stable"

if [ -f "${SOURCES_LIST_PATH}" ]; then
    CURRENT_REPO_LINE="$(grep -v '^[[:space:]]*#' "${SOURCES_LIST_PATH}" | grep -m1 '^[[:space:]]*deb ' || true)"
    info "Aktueller Eintrag: ${CURRENT_REPO_LINE:-<leer>}"
    if [ "${CURRENT_REPO_LINE}" = "${EXPECTED_REPO_LINE}" ]; then
        success "Repository-Eintrag passt zu '${OS_CODENAME}' (${ARCH})."
    else
        warn "Repository-Eintrag passt nicht zum laufenden System."
        warn "Erwartet: ${EXPECTED_REPO_LINE}"
        REPO_NEEDS_WRITE="ja"
    fi
else
    warn "Repository-Datei fehlt: ${SOURCES_LIST_PATH}"
    REPO_NEEDS_WRITE="ja"
fi

if [ "${KEY_MISSING}" = "ja" ] || [ "${REPO_NEEDS_WRITE}" = "ja" ]; then
    if [ "${SKIP_REPO_FIX:-0}" = "1" ]; then
        REPO_ACTION="Reparatur nötig, aber SKIP_REPO_FIX=1 gesetzt"
        warn "SKIP_REPO_FIX=1 gesetzt – Schlüssel/Repository werden nicht angefasst."
    else
        REPO_ACTION="Schlüssel und/oder Repository-Eintrag werden erneuert"
    fi
fi

# -----------------------------------------------------------------------------
# Laufende Container erfassen
# -----------------------------------------------------------------------------
RUNNING_CONTAINERS="$(${SUDO} docker ps --format '{{.Names}} ({{.Image}})' 2>/dev/null || true)"
RUNNING_COUNT=0
[ -n "${RUNNING_CONTAINERS}" ] && RUNNING_COUNT="$(printf '%s\n' "${RUNNING_CONTAINERS}" | wc -l)"

# -----------------------------------------------------------------------------
# Zusammenfassung vor dem Start
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Zusammenfassung${RESET}"
echo "------------------------------------------------------------"
printf 'System:              %s\n' "${PRETTY_NAME:-unbekannt}"
printf 'Architektur:         %s\n' "$ARCH"
printf 'Docker Engine:       %s\n' "$(docker --version)"
printf 'Docker Compose:      %s\n' "${COMPOSE_BEFORE}"
printf 'Repository/Key:      %s\n' "${REPO_ACTION}"
printf 'Laufende Container:  %s\n' "${RUNNING_COUNT}"
if [ "${RUNNING_COUNT}" -gt 0 ]; then
    printf '%s\n' "${RUNNING_CONTAINERS}" | sed 's/^/                     - /'
fi
echo ""
echo "Folgendes wird gleich passieren:"
echo "  1) Schlüssel/Repository prüfen und bei Bedarf erneuern"
echo "  2) Paketlisten aktualisieren (apt-get update)"
echo "  3) Verfügbare Versionen der Docker-Pakete ermitteln"
echo "  4) Nur die Docker-Pakete aktualisieren (docker-ce, docker-ce-cli,"
echo "     containerd.io, docker-buildx-plugin, docker-compose-plugin)"
echo "  5) Docker-Dienst prüfen und bei Bedarf starten"
echo "  6) Ergebnis verifizieren (docker --version, docker compose version)"
echo ""
if [ "${RUNNING_COUNT}" -gt 0 ]; then
    warn "Beim Paket-Upgrade wird der Docker-Daemon neu gestartet. Laufende"
    warn "Container werden dabei kurz gestoppt und je nach Restart-Policy"
    warn "(restart: unless-stopped / always) wieder gestartet. Container ohne"
    warn "Restart-Policy bleiben gestoppt und müssen manuell wieder hochgefahren"
    warn "werden (z.B. 'docker compose up -d' im jeweiligen Stack-Verzeichnis)."
fi
warn "Es werden ausschliesslich die oben genannten Docker-Pakete aktualisiert –"
warn "kein 'apt-get upgrade' über das gesamte System."

if [ "${ASSUME_YES:-0}" = "1" ]; then
    info "ASSUME_YES=1 gesetzt, überspringe die Bestätigungsabfrage."
else
    echo ""
    read -rp "Update jetzt starten? [j/N]: " CONFIRM
    [[ "${CONFIRM,,}" == "j" ]] || { warn "Abgebrochen (keine oder verneinende Eingabe)."; exit 0; }
fi

# -----------------------------------------------------------------------------
# Schritt 3: Schlüssel und Repository bei Bedarf erneuern
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 3: Schlüssel und Repository${RESET}"
echo "------------------------------------------------------------"

if [ "${SKIP_REPO_FIX:-0}" = "1" ]; then
    info "SKIP_REPO_FIX=1 gesetzt, überspringe Reparatur."
else
    if [ "${KEY_MISSING}" = "ja" ]; then
        info "Hole den offiziellen Docker-GPG-Schlüssel ..."
        ${SUDO} install -m 0755 -d "${KEYRING_DIR}"
        curl -fsSL "${DOCKER_GPG_URL}" | ${SUDO} tee "${KEYRING_PATH}" >/dev/null
        ${SUDO} chmod a+r "${KEYRING_PATH}"
        success "GPG-Schlüssel unter ${KEYRING_PATH} abgelegt."
    else
        info "GPG-Schlüssel unverändert."
    fi

    if [ "${REPO_NEEDS_WRITE}" = "ja" ]; then
        if [ -f "${SOURCES_LIST_PATH}" ]; then
            BACKUP_PATH="${SOURCES_LIST_PATH}.bak-$(date +%Y%m%d%H%M%S)"
            ${SUDO} cp -a "${SOURCES_LIST_PATH}" "${BACKUP_PATH}"
            info "Bisherige Repository-Datei gesichert: ${BACKUP_PATH}"
        fi
        echo "${EXPECTED_REPO_LINE}" | ${SUDO} tee "${SOURCES_LIST_PATH}" >/dev/null
        success "Repository-Eintrag geschrieben: ${SOURCES_LIST_PATH}"
        info "  -> ${EXPECTED_REPO_LINE}"
    else
        info "Repository-Eintrag unverändert."
    fi
fi

# -----------------------------------------------------------------------------
# Schritt 4: Paketlisten aktualisieren und Versionen vergleichen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 4: Verfügbare Versionen${RESET}"
echo "------------------------------------------------------------"
info "Aktualisiere Paketlisten ..."
if ! ${SUDO} apt-get update -y; then
    error "apt-get update ist fehlgeschlagen. Möglicherweise stellt Docker für"
    error "den Codename '$OS_CODENAME' (noch) kein Repository bereit."
    error "Prüfe ${DOCKER_APT_REPO_BASE}/dists/ auf verfügbare Versionen."
    exit 1
fi

UPGRADABLE=()
printf '\n%-22s %-31s %s\n' "Paket" "installiert" "verfügbar"
echo "--------------------------------------------------------------------------------"
for pkg in "${DOCKER_PACKAGES[@]}"; do
    INSTALLED_VERSION="$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true)"
    if ! dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null | grep -q '^installed$'; then
        INSTALLED_VERSION=""
    fi
    CANDIDATE_VERSION="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2}' || true)"
    printf '%-22s %-31s %s\n' "$pkg" "${INSTALLED_VERSION:-nicht installiert}" "${CANDIDATE_VERSION:-unbekannt}"
    if [ -n "$INSTALLED_VERSION" ] && [ -n "$CANDIDATE_VERSION" ] && [ "$CANDIDATE_VERSION" != "(none)" ] \
       && [ "$INSTALLED_VERSION" != "$CANDIDATE_VERSION" ]; then
        UPGRADABLE+=("$pkg")
    fi
done
echo ""

if [ "${#UPGRADABLE[@]}" -eq 0 ]; then
    success "Alle Docker-Pakete sind bereits auf dem aktuellen Stand."
    UPDATE_RESULT="keine Aktualisierung nötig"
else
    info "Zu aktualisieren: ${UPGRADABLE[*]}"
    UPDATE_RESULT="aktualisiert: ${UPGRADABLE[*]}"
fi

# -----------------------------------------------------------------------------
# Schritt 5: Docker-Pakete aktualisieren
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 5: Pakete aktualisieren${RESET}"
echo "------------------------------------------------------------"
if [ "${#UPGRADABLE[@]}" -eq 0 ]; then
    info "Nichts zu tun, überspringe das Upgrade."
else
    warn "Je nach Internetverbindung und Serverleistung kann das ein paar Minuten"
    warn "dauern - bitte nicht abbrechen."
    ${SUDO} apt-get install -y --only-upgrade "${UPGRADABLE[@]}"
    success "Docker-Pakete aktualisiert."
fi

# -----------------------------------------------------------------------------
# Schritt 6: Dienst prüfen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 6: Dienst prüfen${RESET}"
echo "------------------------------------------------------------"
if command -v systemctl >/dev/null 2>&1; then
    if ${SUDO} systemctl is-active --quiet docker; then
        success "Docker-Dienst läuft."
    else
        warn "Docker-Dienst läuft nicht, starte ihn ..."
        ${SUDO} systemctl start docker
        success "Docker-Dienst gestartet."
    fi
    ${SUDO} systemctl is-enabled --quiet docker || {
        warn "Docker-Dienst war nicht für den Autostart aktiviert, aktiviere ihn ..."
        ${SUDO} systemctl enable docker >/dev/null 2>&1 || true
    }
else
    ${SUDO} service docker start >/dev/null 2>&1 || true
    warn "systemd nicht gefunden, 'service docker start' wurde versucht."
fi

# -----------------------------------------------------------------------------
# Schritt 7: Verifikation
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 7: Verifikation${RESET}"
echo "------------------------------------------------------------"
DOCKER_VERSION_OUTPUT="$(docker --version 2>/dev/null || true)"
COMPOSE_VERSION_OUTPUT="$(docker compose version 2>/dev/null || true)"

[ -n "$DOCKER_VERSION_OUTPUT" ] || die "Verifikation fehlgeschlagen: 'docker --version' liefert keine Ausgabe."
success "Docker Engine: $DOCKER_VERSION_OUTPUT"

[ -n "$COMPOSE_VERSION_OUTPUT" ] || die "Verifikation fehlgeschlagen: 'docker compose version' liefert keine Ausgabe."
success "Docker Compose: $COMPOSE_VERSION_OUTPUT"

RUNNING_AFTER="$(${SUDO} docker ps --format '{{.Names}}' 2>/dev/null | wc -l)"

# -----------------------------------------------------------------------------
# Abschluss
# -----------------------------------------------------------------------------
echo ""
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"
printf '%b\n' "${GREEN}${BOLD}#           Update abgeschlossen            #${RESET}"
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"
echo ""
printf '%b\n' "${BOLD}Zusammenfassung${RESET}"
echo "------------------------------------------------------------"
printf 'System:              %s\n' "${PRETTY_NAME:-unbekannt}"
printf 'Repository/Key:      %s\n' "${REPO_ACTION}"
printf 'Pakete:              %s\n' "${UPDATE_RESULT}"
printf 'Docker Engine:       %s\n' "$DOCKER_VERSION_OUTPUT"
printf 'Docker Compose:      %s\n' "$COMPOSE_VERSION_OUTPUT"
printf 'Container vorher:    %s\n' "${RUNNING_COUNT}"
printf 'Container nachher:   %s\n' "${RUNNING_AFTER}"
echo ""
if [ "${RUNNING_AFTER}" -lt "${RUNNING_COUNT}" ]; then
    warn "Es laufen weniger Container als vor dem Update. Container ohne"
    warn "Restart-Policy müssen manuell gestartet werden, z.B. mit"
    warn "'docker compose up -d' im jeweiligen Stack-Verzeichnis."
fi
info "Wichtige Befehle:"
echo "  Status:  systemctl status docker"
echo "  Version: docker --version && docker compose version"
echo "  Container: docker ps -a"
echo "  Logs:    journalctl -u docker -f"
