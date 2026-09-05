#!/usr/bin/env bash
# =============================================================================
# Docker & Docker Compose Installer für Debian
# - folgt der offiziellen Docker-Installationsanleitung:
#   https://docs.docker.com/engine/install/debian/
# - erkennt automatisch die laufende Debian-Version (buster/bullseye/bookworm/
#   trixie/...) und CPU-Architektur und richtet das dazu passende offizielle
#   Docker-apt-Repository ein
# - entfernt zuerst konfligierende Alt-Pakete (docker.io, docker-compose, ...)
# - installiert Docker Engine, CLI, containerd sowie die Plugins Buildx und
#   Compose (also "docker compose", nicht das alte Python-docker-compose)
# - aktiviert den Docker-Dienst per systemd und fügt optional einen Benutzer
#   zur Gruppe "docker" hinzu
# - zeigt vor dem eigentlichen Start eine Zusammenfassung und fragt explizit
#   nach Bestätigung; danach begleitet das Skript jeden Schritt mit Ausgaben
# - schliesst mit einer farbigen Zusammenfassung ab (docker --version, docker
#   compose version, testweiser hello-world-Container)
#
# -----------------------------------------------------------------------------
# AI-Transparenzhinweis:
# Dieses Skript wurde unter Einsatz von KI-Modellen (Claude Sonnet 5, Anthropic)
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

# Optionen (Umgebungsvariablen):
#   ADD_USER=<name>    Benutzer, der zur Gruppe "docker" hinzugefügt werden
#                       soll (Standard: der aufrufende, nicht-root Benutzer)
#   SKIP_USER_ADD=1     Überspringt das Hinzufügen zur docker-Gruppe
#   ASSUME_YES=1        Überspringt die Bestätigungsabfrage vor der Installation
#                       (z.B. für automatisierte/unbeaufsichtigte Läufe)

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "Bitte als root ausführen oder sudo installieren."
  SUDO="sudo"
fi

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
printf '%b\n' "${BOLD} Docker & Docker Compose Installer – powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET}"
echo ""
echo "Erkennt die laufende Debian-Version automatisch und installiert Docker"
echo "Engine + Docker Compose Plugin darauf abgestimmt über das offizielle"
echo "Docker-apt-Repository. Siehe auch: ${OFFICIAL_GUIDE}"
echo "------------------------------------------------------------"

# -----------------------------------------------------------------------------
# Schritt 1: Betriebssystem erkennen
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
        warn "Dieses Skript ist für reines Debian gedacht. Für Ubuntu/Raspbian/etc."
        warn "wird das offizielle Docker-Repo hier NICHT automatisch korrekt gewählt."
        die "Abbruch, da kein reines Debian erkannt wurde. Bitte das passende Docker-Setup-Skript für '$OS_ID' verwenden."
    else
        die "Dieses Skript unterstützt nur Debian. Erkanntes System: '$OS_ID'."
    fi
fi

# Bekannte / unterstützte Debian-Codenames und deren Docker-Support-Status.
# (Stand: Docker unterstützt offiziell aktuelle Debian-Stable- und -Oldstable-
# Releases. Ältere Codenames werden hier nur als "eingeschränkt getestet"
# markiert, das Skript versucht die Installation trotzdem.)
declare -A KNOWN_CODENAMES=(
    [buster]="10 (oldoldstable, ggf. EOL – Docker-Support kann eingeschränkt sein)"
    [bullseye]="11 (oldstable)"
    [bookworm]="12 (stable)"
    [trixie]="13 (testing/stable, je nach Release-Stand)"
    [forky]="14 (testing/unstable)"
    [sid]="unstable (rolling)"
)

if [ -z "$OS_CODENAME" ]; then
    die "Konnte VERSION_CODENAME nicht aus /etc/os-release ermitteln. Abbruch."
fi

if [ -n "${KNOWN_CODENAMES[$OS_CODENAME]:-}" ]; then
    success "Debian-Version erkannt: $OS_CODENAME -> ${KNOWN_CODENAMES[$OS_CODENAME]}"
else
    warn "Unbekannter/neuer Debian-Codename '$OS_CODENAME'. Es wird trotzdem versucht,"
    warn "das offizielle Docker-Repository für '$OS_CODENAME' einzurichten."
fi

ARCH="$(dpkg --print-architecture)"
info "Erkannte CPU-Architektur: $ARCH"

case "$ARCH" in
    amd64|arm64|armhf) : ;;
    *)
        warn "Architektur '$ARCH' wird von Docker offiziell evtl. nicht (voll) unterstützt."
        warn "Die Installation wird trotzdem versucht."
        ;;
esac

DOCKER_ALREADY_INSTALLED="nein"
if command -v docker >/dev/null 2>&1; then
    DOCKER_ALREADY_INSTALLED="ja"
    warn "Docker ist bereits installiert: $(docker --version)"
    warn "Das Skript fährt fort und aktualisiert/vervollständigt ggf. die Installation."
fi

# Zielbenutzer für die docker-Gruppe schon jetzt ermitteln, damit er in der
# Zusammenfassung auftaucht statt erst mitten in der Installation.
TARGET_USER=""
if [ "${SKIP_USER_ADD:-0}" != "1" ]; then
    TARGET_USER="${ADD_USER:-${SUDO_USER:-}}"
    if [ -z "$TARGET_USER" ] && [ -n "${SUDO:-}" ]; then
        TARGET_USER="$(logname 2>/dev/null || true)"
    fi
    [ "$TARGET_USER" = "root" ] && TARGET_USER=""
fi

# -----------------------------------------------------------------------------
# Zusammenfassung vor dem Start
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Zusammenfassung${RESET}"
echo "------------------------------------------------------------"
printf 'System:              %s\n' "${PRETTY_NAME:-unbekannt}"
printf 'Architektur:         %s\n' "$ARCH"
printf 'Docker bereits da:   %s\n' "$DOCKER_ALREADY_INSTALLED"
echo ""
echo "Folgendes wird gleich passieren:"
echo "  1) Alte/konfligierende Pakete entfernen (docker.io, docker-compose, ...)"
echo "  2) Voraussetzungen installieren (ca-certificates, curl, gnupg)"
echo "  3) Offiziellen Docker-GPG-Schlüssel einrichten"
echo "  4) Docker-apt-Repository für '${OS_CODENAME}' (${ARCH}) einrichten"
echo "  5) docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin,"
echo "     docker-compose-plugin installieren"
echo "  6) Docker-Dienst aktivieren und starten (systemd)"
if [ -n "$TARGET_USER" ]; then
    echo "  7) Benutzer '${TARGET_USER}' zur Gruppe 'docker' hinzufügen"
else
    echo "  7) Gruppenzuweisung überspringen (kein Zielbenutzer erkannt oder SKIP_USER_ADD=1)"
fi
echo "  8) Installation verifizieren (docker --version, docker compose version,"
echo "     Testcontainer hello-world)"
echo ""
warn "Dabei werden Systempakete installiert/entfernt und eine neue apt-Quelle"
warn "(${SOURCES_LIST_PATH}) angelegt. Das ist mit den offiziellen Docker-"
warn "Anweisungen identisch, verändert aber dein System."

if [ "${ASSUME_YES:-0}" = "1" ]; then
    info "ASSUME_YES=1 gesetzt, überspringe die Bestätigungsabfrage."
else
    echo ""
    read -rp "Installation jetzt starten? [j/N]: " CONFIRM
    [[ "${CONFIRM,,}" == "j" ]] || { warn "Abgebrochen (keine oder verneinende Eingabe)."; exit 0; }
fi

# -----------------------------------------------------------------------------
# Schritt 2: Alte/konfligierende Pakete entfernen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 2: Alte Pakete entfernen${RESET}"
echo "------------------------------------------------------------"
info "Entferne alte/konfligierende Docker-Pakete (falls vorhanden) ..."
OLD_PACKAGES=(
    docker.io
    docker-doc
    docker-compose
    docker-compose-v2
    podman-docker
    containerd
    runc
)
${SUDO} apt-get remove -y "${OLD_PACKAGES[@]}" >/dev/null 2>&1 || true
success "Bereinigung alter Pakete abgeschlossen."

# -----------------------------------------------------------------------------
# Schritt 3: Systempakete aktualisieren und Voraussetzungen installieren
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 3: Voraussetzungen${RESET}"
echo "------------------------------------------------------------"
info "Aktualisiere Paketlisten ..."
export DEBIAN_FRONTEND=noninteractive
${SUDO} apt-get update -y

info "Installiere Voraussetzungen (ca-certificates, curl, gnupg) ..."
${SUDO} apt-get install -y ca-certificates curl gnupg
success "Voraussetzungen installiert."

# -----------------------------------------------------------------------------
# Schritt 4: Offiziellen Docker-GPG-Signaturschlüssel einrichten
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 4: Docker GPG-Schlüssel${RESET}"
echo "------------------------------------------------------------"
info "Richte Docker GPG-Schlüssel ein ..."
${SUDO} install -m 0755 -d "${KEYRING_DIR}"

if [ -f "${KEYRING_PATH}" ]; then
    warn "GPG-Schlüssel existiert bereits, wird neu heruntergeladen und überschrieben."
fi

curl -fsSL "${DOCKER_GPG_URL}" | ${SUDO} tee "${KEYRING_PATH}" >/dev/null
${SUDO} chmod a+r "${KEYRING_PATH}"
success "GPG-Schlüssel unter ${KEYRING_PATH} abgelegt."

# -----------------------------------------------------------------------------
# Schritt 5: Docker apt-Repository passend zur erkannten Debian-Version einrichten
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 5: Docker apt-Repository${RESET}"
echo "------------------------------------------------------------"
info "Richte Docker apt-Repository für '$OS_CODENAME' ($ARCH) ein ..."

REPO_LINE="deb [arch=${ARCH} signed-by=${KEYRING_PATH}] ${DOCKER_APT_REPO_BASE} ${OS_CODENAME} stable"
echo "$REPO_LINE" | ${SUDO} tee "${SOURCES_LIST_PATH}" >/dev/null
success "Repository-Eintrag geschrieben: ${SOURCES_LIST_PATH}"
info "  -> $REPO_LINE"

info "Aktualisiere Paketlisten mit neuem Docker-Repository ..."
if ! ${SUDO} apt-get update -y; then
    error "apt-get update ist fehlgeschlagen. Möglicherweise stellt Docker für"
    error "die Codename '$OS_CODENAME' (noch) kein Repository bereit."
    error "Prüfe ${DOCKER_APT_REPO_BASE}/dists/ auf verfügbare Versionen."
    exit 1
fi

# -----------------------------------------------------------------------------
# Schritt 6: Docker Engine, CLI, containerd und Compose-Plugin installieren
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 6: Docker-Pakete installieren${RESET}"
echo "------------------------------------------------------------"
info "Installiere Docker Engine, CLI, containerd und Compose-Plugin ..."
warn "Je nach Internetverbindung und Serverleistung kann das ein paar Minuten"
warn "dauern - bitte nicht abbrechen."
${SUDO} apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
success "Docker-Pakete installiert."

# -----------------------------------------------------------------------------
# Schritt 7: Dienst aktivieren und starten
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 7: Dienst aktivieren${RESET}"
echo "------------------------------------------------------------"
info "Aktiviere und starte den Docker-Dienst ..."
if command -v systemctl >/dev/null 2>&1; then
    ${SUDO} systemctl enable --now docker
    success "Docker-Dienst über systemd aktiviert und gestartet."
else
    ${SUDO} service docker start || true
    warn "systemd nicht gefunden, 'service docker start' wurde versucht."
fi

# -----------------------------------------------------------------------------
# Schritt 8: Optional: Benutzer zur docker-Gruppe hinzufügen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 8: Benutzer zur docker-Gruppe hinzufügen${RESET}"
echo "------------------------------------------------------------"
GROUP_ADD_DONE="nein"
if [ -n "$TARGET_USER" ]; then
    if id "$TARGET_USER" >/dev/null 2>&1; then
        ${SUDO} usermod -aG docker "$TARGET_USER"
        success "Benutzer '$TARGET_USER' wurde der Gruppe 'docker' hinzugefügt."
        warn "'$TARGET_USER' muss sich ab- und wieder anmelden (oder 'newgrp docker'"
        warn "ausführen), damit die Gruppenmitgliedschaft wirksam wird."
        GROUP_ADD_DONE="ja (${TARGET_USER})"
    else
        warn "Benutzer '$TARGET_USER' existiert nicht, überspringe Gruppenzuweisung."
    fi
elif [ "${SKIP_USER_ADD:-0}" = "1" ]; then
    info "SKIP_USER_ADD=1 gesetzt, Gruppenzuweisung übersprungen."
else
    info "Kein nicht-root-Benutzer erkannt. Gruppenzuweisung übersprungen."
    info "Manuell möglich mit: sudo usermod -aG docker <benutzername>"
fi

# -----------------------------------------------------------------------------
# Schritt 9: Installation verifizieren
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 9: Verifikation${RESET}"
echo "------------------------------------------------------------"
info "Verifiziere Installation ..."

DOCKER_VERSION_OUTPUT="$(docker --version 2>/dev/null || true)"
COMPOSE_VERSION_OUTPUT="$(docker compose version 2>/dev/null || true)"

if [ -z "$DOCKER_VERSION_OUTPUT" ]; then
    die "Verifikation fehlgeschlagen: 'docker --version' liefert keine Ausgabe."
fi
success "Docker Engine: $DOCKER_VERSION_OUTPUT"

if [ -z "$COMPOSE_VERSION_OUTPUT" ]; then
    die "Verifikation fehlgeschlagen: 'docker compose version' liefert keine Ausgabe."
fi
success "Docker Compose: $COMPOSE_VERSION_OUTPUT"

HELLO_WORLD_OK="nein"
if ${SUDO} docker run --rm hello-world >/dev/null 2>&1; then
    success "Testcontainer 'hello-world' erfolgreich ausgeführt."
    HELLO_WORLD_OK="ja"
else
    warn "Testcontainer 'hello-world' konnte nicht ausgeführt werden (evtl. kein"
    warn "Internetzugriff im Container, oder aktueller Benutzer ist noch nicht in"
    warn "der docker-Gruppe aktiv). Docker/Compose selbst wurden dennoch installiert."
fi

# -----------------------------------------------------------------------------
# Abschluss
# -----------------------------------------------------------------------------
echo ""
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"
printf '%b\n' "${GREEN}${BOLD}#         Installation erfolgreich          #${RESET}"
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"
echo ""
printf '%b\n' "${BOLD}Zusammenfassung${RESET}"
echo "------------------------------------------------------------"
printf 'System:              %s\n' "${PRETTY_NAME:-unbekannt}"
printf 'Docker Engine:       %s\n' "$DOCKER_VERSION_OUTPUT"
printf 'Docker Compose:      %s\n' "$COMPOSE_VERSION_OUTPUT"
printf 'Benutzer zur Gruppe: %s\n' "$GROUP_ADD_DONE"
printf 'Testcontainer:       %s\n' "$HELLO_WORLD_OK"
echo ""
if [ "$GROUP_ADD_DONE" != "nein" ]; then
    warn "Nicht vergessen: '$TARGET_USER' muss sich neu anmelden (oder 'newgrp"
    warn "docker' ausführen), bevor docker-Befehle ohne sudo funktionieren."
fi
if [ "$HELLO_WORLD_OK" != "ja" ]; then
    warn "Der hello-world-Test ist fehlgeschlagen bzw. wurde übersprungen -"
    warn "Docker selbst läuft trotzdem. Prüfe ggf. Internetzugriff/Gruppenrechte."
fi
echo ""
info "Wichtige Befehle:"
echo "  Status:  systemctl status docker"
echo "  Version: docker --version && docker compose version"
echo "  Test:    docker run --rm hello-world"
echo "  Logs:    journalctl -u docker -f"
