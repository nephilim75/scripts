#!/usr/bin/env bash
# =============================================================================
# Docker & Docker Compose Uninstaller für Debian
# - Gegenstück zu install-docker.sh:
#   https://docs.docker.com/engine/install/debian/
# - nimmt zuerst Bestand auf (Container, Images, Volumes, Speicherbelegung) und
#   zeigt alles in einer Zusammenfassung, bevor irgendetwas entfernt wird
# - entfernt das gemeinsame Docker-Netzwerk "shared_proxy", falls vorhanden
#   (typisches Reverse-Proxy-Netz mehrerer Stacks)
# - stoppt laufende Container, deaktiviert den Dienst, purged die offiziellen
#   Docker-Pakete und entfernt apt-Repository und GPG-Schlüssel
# - Nutzdaten (/var/lib/docker, /var/lib/containerd, /etc/docker) bleiben
#   standardmässig erhalten und werden nur nach einer ZWEITEN, ausdrücklichen
#   Bestätigung (oder mit PURGE_DATA=1 / --purge-data) gelöscht
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

readonly KEYRING_PATH="/etc/apt/keyrings/docker.asc"
readonly SOURCES_LIST_PATH="/etc/apt/sources.list.d/docker.list"
readonly SHARED_NETWORK="shared_proxy"
readonly DOCKER_PACKAGES=(
    docker-ce
    docker-ce-cli
    containerd.io
    docker-buildx-plugin
    docker-compose-plugin
    docker-ce-rootless-extras
    docker-model-plugin
)
readonly DATA_PATHS=(
    /var/lib/docker
    /var/lib/containerd
    /etc/docker
)

# Optionen (Umgebungsvariablen oder Parameter):
#   PURGE_DATA=1 | --purge-data     Zusätzlich alle Docker-Daten löschen
#                                   (Images, Container, Volumes, /etc/docker,
#                                    Gruppe "docker") – unwiederbringlich
#   KEEP_NETWORK=1 | --keep-network Netzwerk "shared_proxy" NICHT entfernen
#   ASSUME_YES=1 | --yes            Alle Rückfragen mit "ja" beantworten
#                                   (auch die für das Löschen der Daten, wenn
#                                    PURGE_DATA gesetzt ist)

PURGE_DATA="${PURGE_DATA:-0}"
KEEP_NETWORK="${KEEP_NETWORK:-0}"
ASSUME_YES="${ASSUME_YES:-0}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --purge-data)   PURGE_DATA=1 ;;
        --keep-network) KEEP_NETWORK=1 ;;
        --yes|-y)       ASSUME_YES=1 ;;
        -h|--help)
            echo "Verwendung: uninstall-docker.sh [--purge-data] [--keep-network] [--yes]"
            exit 0
            ;;
        *) die "Unbekannte Option: $1 (siehe --help)" ;;
    esac
    shift
done

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "Bitte als root ausführen oder sudo installieren."
  SUDO="sudo"
fi

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
printf '%b\n' "${BOLD} Docker & Docker Compose Uninstaller – powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET}"
echo ""
echo "Entfernt Docker Engine, Docker Compose Plugin, apt-Repository und"
echo "GPG-Schlüssel. Nutzdaten bleiben erhalten, sofern sie nicht ausdrücklich"
echo "mit abgewählt werden."
echo "------------------------------------------------------------"

# -----------------------------------------------------------------------------
# Schritt 1: Bestandsaufnahme
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 1: Bestandsaufnahme${RESET}"
echo "------------------------------------------------------------"

if [ -r /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
fi
info "System: ${PRETTY_NAME:-unbekannt}"

DOCKER_PRESENT="nein"
DOCKER_VERSION_OUTPUT="nicht installiert"
if command -v docker >/dev/null 2>&1; then
    DOCKER_PRESENT="ja"
    DOCKER_VERSION_OUTPUT="$(docker --version 2>/dev/null || echo 'Version unbekannt')"
    info "Gefunden: ${DOCKER_VERSION_OUTPUT}"
else
    warn "Kein 'docker'-Befehl gefunden."
fi

INSTALLED_PACKAGES=()
for pkg in "${DOCKER_PACKAGES[@]}"; do
    if dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null | grep -q '^installed$'; then
        INSTALLED_PACKAGES+=("$pkg")
    fi
done

DAEMON_RUNNING="nein"
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet docker 2>/dev/null; then
    DAEMON_RUNNING="ja"
fi

CONTAINERS_RUNNING="0"
CONTAINERS_TOTAL="0"
IMAGES_TOTAL="0"
VOLUMES_TOTAL="0"
NETWORK_PRESENT="nein"
NETWORK_CONTAINERS=""

if [ "${DAEMON_RUNNING}" = "ja" ]; then
    CONTAINERS_RUNNING="$(${SUDO} docker ps -q 2>/dev/null | wc -l)"
    CONTAINERS_TOTAL="$(${SUDO} docker ps -aq 2>/dev/null | wc -l)"
    IMAGES_TOTAL="$(${SUDO} docker images -q 2>/dev/null | wc -l)"
    VOLUMES_TOTAL="$(${SUDO} docker volume ls -q 2>/dev/null | wc -l)"
    if ${SUDO} docker network inspect "${SHARED_NETWORK}" >/dev/null 2>&1; then
        NETWORK_PRESENT="ja"
        # shellcheck disable=SC2016  # Go-Template für docker, darf nicht von der Shell expandiert werden
        NETWORK_CONTAINERS="$(${SUDO} docker network inspect "${SHARED_NETWORK}" \
            -f '{{range $k, $v := .Containers}}{{$v.Name}} {{end}}' 2>/dev/null || true)"
        info "Netzwerk '${SHARED_NETWORK}' gefunden.${NETWORK_CONTAINERS:+ Verbunden: ${NETWORK_CONTAINERS}}"
    else
        info "Netzwerk '${SHARED_NETWORK}' existiert nicht (nichts zu entfernen)."
    fi
else
    warn "Docker-Daemon läuft nicht – Container/Images/Netzwerke können nicht"
    warn "aufgelistet werden. Das Netzwerk '${SHARED_NETWORK}' verschwindet mit"
    warn "den Daten unter /var/lib/docker (nur bei --purge-data)."
fi

DATA_SIZE="unbekannt"
if [ -d /var/lib/docker ]; then
    DATA_SIZE="$(${SUDO} du -sh /var/lib/docker 2>/dev/null | awk '{print $1}' || true)"
    DATA_SIZE="${DATA_SIZE:-unbekannt}"
fi

if [ "${DOCKER_PRESENT}" = "nein" ] && [ "${#INSTALLED_PACKAGES[@]}" -eq 0 ] \
   && [ ! -f "${SOURCES_LIST_PATH}" ] && [ ! -f "${KEYRING_PATH}" ]; then
    success "Auf diesem System ist nichts zu deinstallieren – Docker ist bereits entfernt."
    exit 0
fi

# -----------------------------------------------------------------------------
# Zusammenfassung vor dem Start
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Zusammenfassung${RESET}"
echo "------------------------------------------------------------"
printf 'System:              %s\n' "${PRETTY_NAME:-unbekannt}"
printf 'Docker Engine:       %s\n' "${DOCKER_VERSION_OUTPUT}"
printf 'Dienst läuft:        %s\n' "${DAEMON_RUNNING}"
printf 'Pakete installiert:  %s\n' "${INSTALLED_PACKAGES[*]:-keine}"
printf 'Container:           %s laufend / %s insgesamt\n' "${CONTAINERS_RUNNING}" "${CONTAINERS_TOTAL}"
printf 'Images / Volumes:    %s / %s\n' "${IMAGES_TOTAL}" "${VOLUMES_TOTAL}"
printf 'Netzwerk:            %s\n' "${SHARED_NETWORK} – ${NETWORK_PRESENT}"
printf 'Daten (/var/lib):    %s\n' "${DATA_SIZE}"
echo ""
echo "Folgendes wird gleich passieren:"
echo "  1) Alle laufenden Container stoppen"
if [ "${NETWORK_PRESENT}" = "ja" ] && [ "${KEEP_NETWORK}" != "1" ]; then
    echo "  2) Netzwerk '${SHARED_NETWORK}' entfernen"
else
    echo "  2) Netzwerk '${SHARED_NETWORK}' überspringen (nicht vorhanden oder KEEP_NETWORK=1)"
fi
echo "  3) Docker-Dienst stoppen und deaktivieren"
echo "  4) Docker-Pakete purgen (Pakete inkl. ihrer Konfiguration)"
echo "  5) apt-Repository (${SOURCES_LIST_PATH}) und GPG-Schlüssel"
echo "     (${KEYRING_PATH}) entfernen, Paketlisten aktualisieren"
if [ "${PURGE_DATA}" = "1" ]; then
    echo "  6) ALLE Docker-Daten löschen: ${DATA_PATHS[*]} sowie die Gruppe 'docker'"
else
    echo "  6) Daten behalten: ${DATA_PATHS[*]} bleiben unangetastet"
fi
echo ""
if [ "${PURGE_DATA}" = "1" ]; then
    warn "PURGE_DATA ist aktiv: Images, Container und Volumes (${DATA_SIZE}) werden"
    warn "unwiederbringlich gelöscht. Datenbanken, Uploads und Konfigurationen in"
    warn "Docker-Volumes sind danach weg."
else
    info "Die Daten unter /var/lib/docker bleiben erhalten. Eine spätere"
    info "Neuinstallation findet Images und Volumes wieder vor."
fi

if [ "${ASSUME_YES}" = "1" ]; then
    info "ASSUME_YES=1 gesetzt, überspringe die Bestätigungsabfrage."
else
    echo ""
    read -rp "Deinstallation jetzt starten? [j/N]: " CONFIRM
    [[ "${CONFIRM,,}" == "j" ]] || { warn "Abgebrochen (keine oder verneinende Eingabe)."; exit 0; }
fi

# Zweite, getrennte Rückfrage nur für das Löschen der Daten.
if [ "${PURGE_DATA}" = "1" ] && [ "${ASSUME_YES}" != "1" ]; then
    echo ""
    warn "Letzte Warnung: alle Images, Container und Volumes werden gelöscht."
    read -rp "Zum Bestätigen 'LOESCHEN' eingeben: " CONFIRM_PURGE
    if [ "${CONFIRM_PURGE}" != "LOESCHEN" ]; then
        PURGE_DATA=0
        warn "Keine Bestätigung – die Daten bleiben erhalten, der Rest wird entfernt."
    fi
fi

# -----------------------------------------------------------------------------
# Schritt 2: Container stoppen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 2: Container stoppen${RESET}"
echo "------------------------------------------------------------"
CONTAINERS_STOPPED="0"
if [ "${DAEMON_RUNNING}" = "ja" ] && [ "${CONTAINERS_RUNNING}" -gt 0 ]; then
    info "Stoppe ${CONTAINERS_RUNNING} laufende(n) Container ..."
    # shellcheck disable=SC2046  # Container-IDs sollen hier absichtlich gesplittet werden
    ${SUDO} docker stop $(${SUDO} docker ps -q) >/dev/null 2>&1 || warn "Nicht alle Container konnten gestoppt werden."
    CONTAINERS_STOPPED="${CONTAINERS_RUNNING}"
    success "Container gestoppt."
else
    info "Keine laufenden Container."
fi

# -----------------------------------------------------------------------------
# Schritt 3: Netzwerk "shared_proxy" entfernen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 3: Netzwerk ${SHARED_NETWORK}${RESET}"
echo "------------------------------------------------------------"
NETWORK_RESULT="nicht vorhanden"
if [ "${NETWORK_PRESENT}" = "ja" ]; then
    if [ "${KEEP_NETWORK}" = "1" ]; then
        NETWORK_RESULT="behalten (KEEP_NETWORK=1)"
        info "KEEP_NETWORK=1 gesetzt, Netzwerk bleibt bestehen."
    else
        # Noch verbundene Endpunkte (z.B. Container, die nicht stoppen wollten) lösen,
        # sonst verweigert Docker das Entfernen mit "has active endpoints".
        # shellcheck disable=SC2016  # Go-Template für docker, darf nicht von der Shell expandiert werden
        REMAINING="$(${SUDO} docker network inspect "${SHARED_NETWORK}" \
            -f '{{range $k, $v := .Containers}}{{$v.Name}} {{end}}' 2>/dev/null || true)"
        for cname in ${REMAINING}; do
            warn "Trenne '${cname}' vom Netzwerk ..."
            ${SUDO} docker network disconnect -f "${SHARED_NETWORK}" "${cname}" >/dev/null 2>&1 || true
        done
        if ${SUDO} docker network rm "${SHARED_NETWORK}" >/dev/null 2>&1; then
            NETWORK_RESULT="entfernt"
            success "Netzwerk '${SHARED_NETWORK}' entfernt."
        else
            NETWORK_RESULT="konnte nicht entfernt werden"
            warn "Netzwerk '${SHARED_NETWORK}' konnte nicht entfernt werden."
            warn "Prüfe mit: docker network inspect ${SHARED_NETWORK}"
        fi
    fi
else
    info "Netzwerk '${SHARED_NETWORK}' ist nicht vorhanden."
fi

# -----------------------------------------------------------------------------
# Schritt 4: Dienst stoppen und deaktivieren
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 4: Dienst stoppen${RESET}"
echo "------------------------------------------------------------"
if command -v systemctl >/dev/null 2>&1; then
    for unit in docker.service docker.socket containerd.service; do
        if systemctl list-unit-files "${unit}" >/dev/null 2>&1 && systemctl is-enabled --quiet "${unit}" 2>/dev/null; then
            ${SUDO} systemctl disable "${unit}" >/dev/null 2>&1 || true
        fi
        ${SUDO} systemctl stop "${unit}" >/dev/null 2>&1 || true
    done
    success "Docker- und containerd-Dienste gestoppt und deaktiviert."
else
    ${SUDO} service docker stop >/dev/null 2>&1 || true
    warn "systemd nicht gefunden, 'service docker stop' wurde versucht."
fi

# -----------------------------------------------------------------------------
# Schritt 5: Pakete entfernen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 5: Pakete entfernen${RESET}"
echo "------------------------------------------------------------"
PACKAGE_RESULT="keine Pakete gefunden"
if [ "${#INSTALLED_PACKAGES[@]}" -gt 0 ]; then
    info "Purge: ${INSTALLED_PACKAGES[*]}"
    ${SUDO} apt-get purge -y "${INSTALLED_PACKAGES[@]}"
    info "Entferne nicht mehr benötigte Abhängigkeiten ..."
    ${SUDO} apt-get autoremove -y --purge
    PACKAGE_RESULT="entfernt: ${INSTALLED_PACKAGES[*]}"
    success "Docker-Pakete entfernt."
else
    info "Keine Docker-Pakete installiert, überspringe."
fi

# -----------------------------------------------------------------------------
# Schritt 6: Repository und GPG-Schlüssel entfernen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 6: Repository und Schlüssel${RESET}"
echo "------------------------------------------------------------"
REPO_RESULT="nichts gefunden"
REMOVED_ANY="nein"
if [ -f "${SOURCES_LIST_PATH}" ]; then
    ${SUDO} rm -f "${SOURCES_LIST_PATH}"
    success "Repository-Datei entfernt: ${SOURCES_LIST_PATH}"
    REMOVED_ANY="ja"
fi
for leftover in "${SOURCES_LIST_PATH}".bak-*; do
    [ -e "${leftover}" ] || continue
    ${SUDO} rm -f "${leftover}"
    info "Sicherungskopie entfernt: ${leftover}"
    REMOVED_ANY="ja"
done
if [ -f "${KEYRING_PATH}" ]; then
    ${SUDO} rm -f "${KEYRING_PATH}"
    success "GPG-Schlüssel entfernt: ${KEYRING_PATH}"
    REMOVED_ANY="ja"
fi
if [ "${REMOVED_ANY}" = "ja" ]; then
    REPO_RESULT="entfernt"
    info "Aktualisiere Paketlisten ..."
    ${SUDO} apt-get update -y || warn "apt-get update meldete einen Fehler – bitte manuell prüfen."
fi

# -----------------------------------------------------------------------------
# Schritt 7: Daten (optional)
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 7: Daten${RESET}"
echo "------------------------------------------------------------"
DATA_RESULT="behalten"
if [ "${PURGE_DATA}" = "1" ]; then
    for path in "${DATA_PATHS[@]}"; do
        if [ -e "${path}" ]; then
            ${SUDO} rm -rf "${path}"
            success "Gelöscht: ${path}"
        fi
    done
    if getent group docker >/dev/null 2>&1; then
        if ${SUDO} groupdel docker >/dev/null 2>&1; then
            success "Gruppe 'docker' entfernt."
        else
            warn "Gruppe 'docker' konnte nicht entfernt werden (evtl. noch Primärgruppe eines Benutzers)."
        fi
    fi
    DATA_RESULT="gelöscht (${DATA_PATHS[*]})"
else
    info "Daten bleiben erhalten:"
    for path in "${DATA_PATHS[@]}"; do
        if [ -e "${path}" ]; then
            echo "  - ${path}"
        fi
    done
    info "Später löschbar mit: sudo rm -rf ${DATA_PATHS[*]}"
fi

# -----------------------------------------------------------------------------
# Abschluss
# -----------------------------------------------------------------------------
echo ""
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"
printf '%b\n' "${GREEN}${BOLD}#        Deinstallation abgeschlossen       #${RESET}"
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"
echo ""
printf '%b\n' "${BOLD}Zusammenfassung${RESET}"
echo "------------------------------------------------------------"
printf 'System:              %s\n' "${PRETTY_NAME:-unbekannt}"
printf 'Container gestoppt:  %s\n' "${CONTAINERS_STOPPED}"
printf 'Netzwerk:            %s\n' "${SHARED_NETWORK} – ${NETWORK_RESULT}"
printf 'Pakete:              %s\n' "${PACKAGE_RESULT}"
printf 'Repository/Key:      %s\n' "${REPO_RESULT}"
printf 'Daten:               %s\n' "${DATA_RESULT}"
echo ""
if [ "${DATA_RESULT}" = "behalten" ]; then
    info "Docker ist entfernt, die Daten unter /var/lib/docker liegen weiterhin auf"
    info "der Platte. Eine Neuinstallation mit install-docker.sh findet Images und"
    info "Volumes unverändert wieder vor."
fi
if getent group docker >/dev/null 2>&1; then
    info "Die Gruppe 'docker' existiert noch. Benutzer daraus entfernen mit:"
    echo "  sudo gpasswd -d <benutzername> docker"
fi
info "Prüfen, ob wirklich alles weg ist:"
echo "  command -v docker || echo 'docker entfernt'"
echo "  dpkg -l | grep -i docker"
echo "  ls /var/lib/docker 2>/dev/null || echo 'keine Daten mehr'"
