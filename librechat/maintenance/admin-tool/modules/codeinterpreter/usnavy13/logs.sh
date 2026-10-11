#!/bin/sh
# =============================================================================
# logs.sh – Zeigt die Protokolle des Code Interpreters (Variante usnavy13).
#
# Bewusst knapp gehalten: standardmaessig 50 Zeilen. Vollstaendige Protokolle
# sind fuer Anfaenger unbrauchbar - man findet darin nichts und verliert die
# Uebersicht im Terminal. Wer mehr braucht, nimmt das Livemitlesen.
#
# Zum Abbrechen des Livemodus dient Strg+C. Der "trap ':' INT" in common.sh
# sorgt dafuer, dass dabei nur "docker compose logs" endet und nicht das
# ganze Menue.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

ZEILEN=50

pause() {
    echo ""
    printf "%b" "${C_BLUE}Enter druecken, um fortzufahren...${C_RESET}"
    read -r _dummy
}

if ! ci_installed "$CI_USNAVY_DIR"; then
    clear
    breadcrumb "Hauptmenue > Code Interpreter > usnavy13 > Logs"
    heading "== Logs (usnavy13) =="
    echo ""
    warn "Der Code Interpreter (usnavy13) ist nicht installiert."
    info "Zuerst den Menuepunkt 'Installieren' waehlen."
    pause
    exit 0
fi

while true; do
    clear
    breadcrumb "Hauptmenue > Code Interpreter > usnavy13 > Logs"
    heading "== Logs (usnavy13) =="
    echo ""
    echo "1) Letzte $ZEILEN Zeilen - nur die API"
    echo "2) Letzte $ZEILEN Zeilen - alle Dienste"
    echo "3) Live mitlesen - nur die API"
    echo "0) Zurueck"
    echo ""
    printf "%b" "${C_BLUE}Auswahl: ${C_RESET}"
    read -r wahl

    case "$wahl" in
        1)
            echo ""
            ci_compose "$CI_USNAVY_DIR" logs --tail="$ZEILEN" --no-color api \
                || error "Die Protokolle konnten nicht gelesen werden."
            pause
            ;;
        2)
            echo ""
            ci_compose "$CI_USNAVY_DIR" logs --tail="$ZEILEN" --no-color \
                || error "Die Protokolle konnten nicht gelesen werden."
            pause
            ;;
        3)
            echo ""
            info "Neue Zeilen erscheinen laufend. Mit Strg+C zurueck zu diesem Menue."
            echo ""
            ci_compose "$CI_USNAVY_DIR" logs --tail="$ZEILEN" -f --no-color api
            pause
            ;;
        0) exit 0 ;;
        *) warn "Ungueltige Auswahl."; pause ;;
    esac
done
