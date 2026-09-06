#!/bin/sh
# =============================================================================
# remove.sh – Entfernt den Code Interpreter (Variante usnavy13).
#
# Aufbau in Stufen, damit niemand von einer Loeschung ueberrascht wird:
#   1. Vorschau - zeigt, was betroffen waere. Es passiert noch nichts.
#   2. Container, Volumes und Installationsverzeichnis (Kernvorgang)
#   3. Images (rund 9 GB) - eigene Rueckfrage
#   4. Eintrag in LibreChats .env - eigene Rueckfrage
#
# Schritt 4 ist wichtiger, als er aussieht: bleibt LIBRECHAT_CODE_BASEURL
# stehen, zeigt LibreChat weiter auf einen Dienst, den es nicht mehr gibt.
# Die Codeausfuehrung scheitert dann mit einer Meldung, aus der die Ursache
# nicht hervorgeht.
#
# Mit "--dry-run" endet das Skript nach der Vorschau.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

load_or_ask_librechat_path

DRY_RUN=0
[ "$1" = "--dry-run" ] && DRY_RUN=1

breadcrumb "Hauptmenue > Code Interpreter > usnavy13 > Entfernen"
heading_danger "== Code Interpreter entfernen (usnavy13) =="
echo ""

if ! ci_installed "$CI_USNAVY_DIR"; then
    warn "Der Code Interpreter (usnavy13) ist nicht installiert."
    info "Es gibt nichts zu entfernen."
    exit 0
fi

# --- Vorschau -----------------------------------------------------------------
# Alles einsammeln, bevor irgendetwas angefasst wird. Die Imageliste muss
# zwingend vor dem Loeschen des Verzeichnisses ermittelt werden - danach ist
# die docker-compose.yml weg und die Namen waeren nicht mehr feststellbar.
images="$(ci_compose "$CI_USNAVY_DIR" config --images 2>/dev/null)"
groesse="$(du -sh "$CI_USNAVY_DIR" 2>/dev/null | cut -f1)"
baseurl="$(get_env_value LIBRECHAT_CODE_BASEURL 2>/dev/null)"

heading "-- Betroffen waeren --"
echo ""
echo "1. Container und Datenvolumen des Code Interpreters"
ci_compose "$CI_USNAVY_DIR" ps --format '   {{.Name}} ({{.State}})' 2>/dev/null \
    || echo "   (Zustand nicht ermittelbar)"
echo ""
echo "2. Installationsverzeichnis"
echo "   $CI_USNAVY_DIR${groesse:+  (${groesse})}"
echo ""
echo "3. Images - nur auf Nachfrage"
if [ -n "$images" ]; then
    printf '   %s\n' $images
else
    echo "   (keine ermittelbar)"
fi
echo ""
echo "4. Eintrag in LibreChats .env - nur auf Nachfrage"
if [ -n "$baseurl" ]; then
    echo "   LIBRECHAT_CODE_BASEURL ist gesetzt"
else
    echo "   nicht gesetzt, nichts zu tun"
fi
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
    info "Testlauf - es wurde nichts veraendert."
    exit 0
fi

warn "Die Schritte 1 und 2 lassen sich nicht rueckgaengig machen."
info "Der Code Interpreter laesst sich jederzeit neu installieren."
echo ""

if ! confirm "Container, Volumen und Verzeichnis wirklich entfernen?"; then
    info "Abgebrochen. Es wurde nichts veraendert."
    exit 0
fi

# --- Schritt 1: Container, Netzwerk, Volumen ----------------------------------
echo ""
info "Entferne Container und Volumen ..."
if ci_compose "$CI_USNAVY_DIR" down --volumes --remove-orphans; then
    success "Container und Volumen entfernt."
else
    error "Das Entfernen der Container ist fehlgeschlagen."
    info "Das Verzeichnis bleibt vorerst bestehen. Bitte pruefen mit: docker ps -a"
    exit 1
fi

# --- Schritt 2: Verzeichnis ---------------------------------------------------
echo ""
info "Entferne $CI_USNAVY_DIR ..."
if rm -rf "$CI_USNAVY_DIR"; then
    success "Verzeichnis entfernt."
else
    error "Das Verzeichnis konnte nicht entfernt werden."
    info "Bitte von Hand pruefen: $CI_USNAVY_DIR"
fi

# --- Schritt 3: Images --------------------------------------------------------
if [ -n "$images" ]; then
    echo ""
    heading "-- Images --"
    printf '   %s\n' $images
    echo ""
    info "Sie belegen rund 9 GB. Ohne sie dauert eine Neuinstallation laenger,"
    info "weil alles erneut geladen werden muss."
    echo ""
    if confirm "Diese Images ebenfalls entfernen?"; then
        echo ""
        for img in $images; do
            if docker rmi "$img" >/dev/null 2>&1; then
                success "entfernt: $img"
            else
                # Kein Fehlerfall: das Image kann von einem anderen Dienst auf
                # diesem Server ebenfalls genutzt werden - dann bleibt es zu
                # Recht liegen.
                warn "nicht entfernt: $img (wird moeglicherweise noch genutzt)"
            fi
        done
    else
        info "Images bleiben liegen."
    fi
fi

# --- Schritt 4: Eintrag in LibreChats .env ------------------------------------
if [ -n "$baseurl" ]; then
    echo ""
    heading "-- Anbindung in LibreChat --"
    echo ""
    warn "In LibreChats .env zeigt LIBRECHAT_CODE_BASEURL weiterhin auf den"
    warn "soeben entfernten Dienst. Bleibt die Zeile stehen, scheitert die"
    warn "Codeausfuehrung mit einer wenig aussagekraeftigen Meldung."
    echo ""
    if confirm "Zeile auskommentieren?"; then
        env_file="$LIBRECHAT_DIR/.env"
        sicherung="${env_file}.bak-$(date +%Y%m%d-%H%M%S)"
        if cp "$env_file" "$sicherung" 2>/dev/null; then
            info "Sicherheitskopie: $sicherung"
        else
            warn "Es konnte keine Sicherheitskopie angelegt werden."
        fi

        if awk '/^LIBRECHAT_CODE_BASEURL=/{print "#" $0; next} {print}' \
              "$env_file" > "${env_file}.tmp" 2>/dev/null \
           && mv "${env_file}.tmp" "$env_file"; then
            success "Zeile auskommentiert."
            warn_restart_required
        else
            rm -f "${env_file}.tmp"
            error "Die Zeile konnte nicht geaendert werden."
            info "Bitte von Hand pruefen: $env_file"
        fi
    else
        info "Zeile bleibt stehen."
        warn "Die Codeausfuehrung in LibreChat wird damit fehlschlagen."
    fi
fi

echo ""
success "Fertig."
echo ""
