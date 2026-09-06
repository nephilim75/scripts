#!/bin/sh
# =============================================================================
# install.sh – Installiert den Code Interpreter (Variante usnavy13).
#
# Das eigentliche Installationsskript liegt im Repo und wird bei jedem Aufruf
# frisch geladen. So bekommt man immer die aktuelle Fassung, ohne dass eine
# Kopie im Admin-Tool mitgepflegt werden muss.
#
# Bewusst NICHT "curl ... | bash": das Installationsskript stellt waehrend des
# Laufs Fragen (Domain, Docker-Netzwerk). Bei einer Pipe waere stdin durch das
# Skript selbst belegt, die Eingaben kaemen nie an. Darum: erst in eine
# temporaere Datei laden, dann ausfuehren.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

INSTALLER_URL="https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/usnavy13/install/install-librecodeinterpreter.sh"

heading "== Code Interpreter installieren (usnavy13) =="
echo ""

# --- Schon installiert? -------------------------------------------------------
if ci_installed "$CI_USNAVY_DIR"; then
    warn "Unter $CI_USNAVY_DIR ist bereits eine Installation vorhanden."
    info "Zum Aktualisieren: Menuepunkt 'Aktualisieren'."
    info "Fuer eine komplett neue Installation zuerst 'Entfernen' waehlen."
    exit 0
fi

# Ordner da, aber ohne Override-Datei: Rest einer abgebrochenen Installation.
# Nicht selbst aufraeumen - das koennte fremde Daten treffen.
if [ -e "$CI_USNAVY_DIR" ]; then
    error "$CI_USNAVY_DIR existiert bereits, sieht aber nicht nach einer"
    error "vollstaendigen Installation aus (docker-compose.override.yml fehlt)."
    info "Vermutlich Rest eines abgebrochenen Versuchs. Bitte den Ordner pruefen"
    info "und von Hand entfernen, bevor neu installiert wird."
    exit 1
fi

# --- Werkzeuge pruefen --------------------------------------------------------
if ! command -v curl >/dev/null 2>&1; then
    error "curl ist nicht installiert, das Installationsskript kann nicht geladen werden."
    info "Nachinstallieren mit: sudo apt-get install -y curl"
    exit 1
fi

# Das Installationsskript ist in bash geschrieben (nutzt set -o pipefail u.a.)
# und laeuft daher nicht unter reinem sh.
if ! command -v bash >/dev/null 2>&1; then
    error "bash ist nicht installiert, das Installationsskript kann nicht ausgefuehrt werden."
    info "Nachinstallieren mit: sudo apt-get install -y bash"
    exit 1
fi

# --- Was gleich passiert ------------------------------------------------------
info "Installiert wird nach: $CI_USNAVY_DIR"
echo ""
echo "Das Installationsskript wird vorher pruefen, ob alles Noetige da ist:"
echo "  - Docker und das Docker-Compose-Plugin"
echo "  - ein laufender Nginx Proxy Manager mit dem Netzwerk 'shared_proxy'"
echo "  - git und openssl"
echo ""
echo "Bereithalten solltest du:"
echo "  - eine Domain, die auf diesen Server zeigt (z.B. code.deine-domain.de)"
echo "  - den Namen des Docker-Netzwerks des Proxy Managers (meist shared_proxy)"
echo ""
warn "Der Download der Images braucht einige Minuten und rund 9 GB Speicherplatz."
echo ""

if ! confirm "Installation jetzt starten?"; then
    info "Abgebrochen. Es wurde nichts veraendert."
    exit 0
fi

# --- Installationsskript laden ------------------------------------------------
tmp_installer="$(mktemp /tmp/lci-install.XXXXXX)" || {
    error "Temporaere Datei konnte nicht angelegt werden."
    exit 1
}
# Aufraeumen in jedem Fall - auch bei Abbruch mitten im Lauf.
trap 'rm -f "$tmp_installer"' EXIT

echo ""
info "Lade Installationsskript..."
if ! curl -fsSL "$INSTALLER_URL" -o "$tmp_installer"; then
    error "Download fehlgeschlagen."
    info "Besteht eine Internetverbindung? Quelle: $INSTALLER_URL"
    exit 1
fi

# Plausibilitaetspruefung: bei Fehlerseiten oder abgeschnittenen Downloads
# waere die Datei kein Shell-Skript. Lieber hier abbrechen als etwas
# Unvollstaendiges ausfuehren.
if ! head -n1 "$tmp_installer" | grep -q '^#!'; then
    error "Die geladene Datei ist kein ausfuehrbares Skript."
    info "Moeglicherweise war die Quelle voruebergehend nicht erreichbar."
    exit 1
fi
success "Installationsskript geladen."
echo ""

# --- Ausfuehren ---------------------------------------------------------------
# Das Skript regelt root/sudo selbst und stellt seine Fragen direkt am Terminal.
bash "$tmp_installer"
rc=$?

echo ""
if [ "$rc" -eq 0 ] && ci_installed "$CI_USNAVY_DIR"; then
    success "Installation abgeschlossen."
    echo ""

    # Das Installationsskript zeigt die Domain nur an, speichert sie aber nicht.
    # Hier einmal nachfragen und merken - dann steht sie spaeter jederzeit unter
    # 'Status anzeigen', auch wenn dieses Fenster laengst geschlossen ist.
    info "Zum Merken: unter welcher Domain hast du den Code Interpreter"
    info "eingerichtet? Sie erscheint dann kuenftig im Status."
    printf "%b" "${C_BLUE}Domain (leer lassen zum Ueberspringen): ${C_RESET}"
    read -r ci_domain
    if [ -n "$ci_domain" ]; then
        if ci_set_domain "$CI_USNAVY_DIR" "$ci_domain"; then
            success "Domain gemerkt."
        else
            warn "Domain konnte nicht gespeichert werden - halb so wild,"
            warn "der Status fragt bei Bedarf noch einmal nach."
        fi
    fi

    echo ""
    info "Naechster Schritt: im Menue 'Anbindung an LibreChat' - dort wird der"
    info "API-Key eingetragen, damit LibreChat den Code Interpreter nutzen kann."
else
    error "Die Installation wurde nicht erfolgreich abgeschlossen."
    info "Die Meldungen oben nennen den Grund."
fi

exit "$rc"
