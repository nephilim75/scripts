#!/bin/sh
# =============================================================================
# update-tool.sh – Aktualisiert das Admin-Tool selbst aus dem GitHub-Repo.
#
# Besonderheit: Das Skript ueberschreibt Dateien, die gerade in Benutzung sind -
# darunter menu.sh und dieses Skript. POSIX-Shells lesen ein Skript waehrend
# des Laufs nach; wird die Datei unter ihnen ausgetauscht, fuehrt das zu
# unvorhersehbarem Verhalten.
#
# Darum in zwei Stufen:
#   1. Aufruf aus dem Installationsverzeichnis: kopiert sich nach /tmp und
#      startet die Kopie per "exec" (der urspruengliche Prozess endet dabei).
#   2. Die Kopie in /tmp fuehrt das Update durch - sie liegt ausserhalb des
#      Verzeichnisses, das gerade ersetzt wird - und startet danach das Menue
#      wieder per "exec".
#
# Aufruf aus dem Menue daher ebenfalls mit "exec", damit das Menue vorher
# sauber endet und nicht im Hintergrund auf die Rueckkehr wartet.
# =============================================================================

REPO_URL="https://github.com/nephilim75/scripts.git"
REPO_SUBDIR="librechat/maintenance"

# --- Stufe 1: nach /tmp ausweichen -------------------------------------------
# Die Stufe wird ueber einen ausdruecklichen Schalter erkannt, nicht ueber den
# eigenen Pfad: Eine Pfadpruefung wuerde fehlschlagen, sobald das Tool selbst
# unterhalb von /tmp liegt - das Original haette sich dann fuer die Kopie
# gehalten und sich am Ende geloescht.
if [ "$1" = "--stufe2" ]; then
    PROJECT_ROOT="$2"
    if [ -z "$PROJECT_ROOT" ]; then
        echo "Stufe 2 ohne Installationspfad aufgerufen." >&2
        exit 1
    fi
else
    PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"

    kopie="$(mktemp /tmp/admin-lc-update.XXXXXX)" || {
        echo "Temporaere Datei konnte nicht angelegt werden." >&2
        exit 1
    }
    cp "$0" "$kopie" && chmod +x "$kopie" || {
        echo "Update-Skript konnte nicht nach /tmp kopiert werden." >&2
        rm -f "$kopie"
        exit 1
    }
    # Ab hier laeuft die Kopie in /tmp weiter, dieser Prozess endet.
    exec "$kopie" --stufe2 "$PROJECT_ROOT"
fi

. "$PROJECT_ROOT/lib/common.sh"

# Die Kopie in /tmp raeumt sich selbst weg - auch bei Abbruch.
trap 'aufraeumen' EXIT

# Aufraeumen der temporaeren Dateien. Muss vor jedem "exec" von Hand gerufen
# werden: "exec" ersetzt den Prozess, der EXIT-Trap kaeme dann nie zum Zug.
aufraeumen() {
    [ -n "${klon:-}" ] && rm -rf "$klon" 2>/dev/null
    rm -f "$0" 2>/dev/null
    return 0
}

clear
breadcrumb "Hauptmenue > Admin-Tool aktualisieren"
heading "== Admin-Tool aktualisieren =="
echo ""

echo "Holt die aktuelle Fassung des Admin-Tools aus dem Repo und ersetzt"
echo "die Dateien unter:"
echo "  $PROJECT_ROOT"
echo ""
echo "Quelle: $REPO_URL ($REPO_SUBDIR)"
echo ""
info "Die eigene Konfiguration (config.sh) bleibt erhalten."
info "Vom bisherigen Stand wird vorher eine Sicherung unter /tmp abgelegt."
echo ""

if ! command -v git >/dev/null 2>&1; then
    error "git ist nicht installiert, das Update kann nicht geladen werden."
    info "Nachinstallieren mit: sudo apt-get install -y git"
    echo ""
    printf "%b" "${C_BLUE}Enter druecken, um zum Menue zurueckzukehren...${C_RESET}"
    read -r _dummy
    aufraeumen
    exec "$PROJECT_ROOT/menu.sh"
fi

if ! confirm "Update jetzt durchfuehren?"; then
    info "Abgebrochen. Es wurde nichts veraendert."
    echo ""
    printf "%b" "${C_BLUE}Enter druecken, um zum Menue zurueckzukehren...${C_RESET}"
    read -r _dummy
    aufraeumen
    exec "$PROJECT_ROOT/menu.sh"
fi

# --- Sicherung des bisherigen Stands -----------------------------------------
echo ""
sicherung="/tmp/admin-lc-vor-update-$(date +%Y%m%d-%H%M%S).tgz"
if (cd "$PROJECT_ROOT" && tar czf "$sicherung" . 2>/dev/null); then
    success "Sicherung angelegt: $sicherung"
else
    warn "Sicherung konnte nicht angelegt werden."
    if ! confirm "Trotzdem fortfahren?"; then
        info "Abgebrochen. Es wurde nichts veraendert."
        echo ""
        printf "%b" "${C_BLUE}Enter druecken, um zum Menue zurueckzukehren...${C_RESET}"
        read -r _dummy
        aufraeumen
        exec "$PROJECT_ROOT/menu.sh"
    fi
fi

# --- Repo holen ---------------------------------------------------------------
klon="$(mktemp -d /tmp/admin-lc-repo.XXXXXX)" || {
    error "Temporaeres Verzeichnis konnte nicht angelegt werden."
    exit 1
}
echo ""
info "Lade aktuelle Fassung..."
if ! git clone --depth 1 "$REPO_URL" "$klon" >/dev/null 2>&1; then
    error "Das Repo konnte nicht geladen werden."
    info "Besteht eine Internetverbindung? Quelle: $REPO_URL"
    echo ""
    printf "%b" "${C_BLUE}Enter druecken, um zum Menue zurueckzukehren...${C_RESET}"
    read -r _dummy
    aufraeumen
    exec "$PROJECT_ROOT/menu.sh"
fi

# Plausibilitaetspruefung, bevor irgendetwas ersetzt wird: liegt im Klon
# ueberhaupt das erwartete Verzeichnis samt menu.sh?
if [ ! -f "$klon/$REPO_SUBDIR/menu.sh" ]; then
    error "Im geladenen Repo fehlt $REPO_SUBDIR/menu.sh."
    info "Es wurde nichts ersetzt."
    echo ""
    printf "%b" "${C_BLUE}Enter druecken, um zum Menue zurueckzukehren...${C_RESET}"
    read -r _dummy
    aufraeumen
    exec "$PROJECT_ROOT/menu.sh"
fi
success "Aktuelle Fassung geladen."

# --- Dateien ersetzen ---------------------------------------------------------
# "cp -r <quelle>/. <ziel>" statt "mv": so kommen auch neu hinzugekommene
# Unterordner zuverlaessig mit, und vorhandene Dateien wie config.sh bleiben
# unangetastet.
info "Ersetze Dateien..."
if ! cp -r "$klon/$REPO_SUBDIR/." "$PROJECT_ROOT/"; then
    error "Die Dateien konnten nicht kopiert werden."
    info "Der bisherige Stand liegt als Sicherung unter: $sicherung"
    echo ""
    printf "%b" "${C_BLUE}Enter druecken, um zum Menue zurueckzukehren...${C_RESET}"
    read -r _dummy
    aufraeumen
    exec "$PROJECT_ROOT/menu.sh"
fi

# Ausfuehrungsrechte tiefenunabhaengig setzen - "modules/*/*.sh" wuerde
# tiefer liegende Skripte wie modules/codeinterpreter/usnavy13/*.sh verfehlen.
find "$PROJECT_ROOT" -name '*.sh' -exec chmod +x {} + 2>/dev/null

# Windows-Zeilenenden entfernen. Ueber die GitHub-Weboberfläche gespeicherte
# Dateien tragen sie gelegentlich; die Shell sucht dann nach einem Interpreter
# namens "/bin/sh<CR>" und meldet "not found".
find "$PROJECT_ROOT" -name '*.sh' -exec sed -i 's/\r$//' {} + 2>/dev/null

success "Update abgeschlossen."
echo ""
info "Sicherung des vorherigen Stands: $sicherung"
echo ""

# --- Menue neu starten --------------------------------------------------------
printf "%b" "${C_BLUE}Enter druecken, um das Menue neu zu starten...${C_RESET}"
read -r _dummy

if [ ! -x "$PROJECT_ROOT/menu.sh" ]; then
    error "menu.sh ist nach dem Update nicht ausfuehrbar."
    info "Von Hand starten mit: sh $PROJECT_ROOT/menu.sh"
    exit 1
fi

aufraeumen
exec "$PROJECT_ROOT/menu.sh"
