#!/bin/sh
# =============================================================================
# menu.sh – Startseite des LibreChat-Admin-Tools.
# Zeigt Themenfelder, bei Auswahl folgen Unteroptionen (Entscheidungsbaum).
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

# --- Platzhalter fuer noch nicht gebaute Themenfelder ------------------------
not_yet_built() {
    echo ""
    warn "Dieses Modul ist noch nicht fertig gebaut."
    info "Kommt in einem der naechsten Schritte."
}

pause() {
    echo ""
    printf "%b" "${C_BLUE}Enter druecken, um fortzufahren...${C_RESET}"
    read -r _dummy
}

# --- Untermenue: User-Verwaltung ---------------------------------------------
menu_useradmin() {
    while true; do
        clear
        heading "== User-Verwaltung =="
        echo "1) User anlegen"
        echo "2) User loeschen"
        echo "3) Alle User auflisten"
        echo "4) User bannen"
        echo "5) Passwort zuruecksetzen"
        echo "0) Zurueck zum Hauptmenue"
        echo ""
        printf "%b" "${C_BLUE}Auswahl: ${C_RESET}"
        read -r wahl
        case "$wahl" in
            1) "$PROJECT_ROOT/modules/useradmin/create.sh"; pause ;;
            2) "$PROJECT_ROOT/modules/useradmin/delete.sh"; pause ;;
            3) "$PROJECT_ROOT/modules/useradmin/list.sh"; pause ;;
            4) "$PROJECT_ROOT/modules/useradmin/ban.sh"; pause ;;
            5) "$PROJECT_ROOT/modules/useradmin/reset-password.sh"; pause ;;
            0) return ;;
            *) warn "Ungueltige Auswahl."; pause ;;
        esac
    done
}

# --- Hauptmenue ---------------------------------------------------------------
while true; do
    clear
    heading "=================================="
    heading "  LibreChat Admin-Tool"
    heading "=================================="
    echo ""
    echo "1) User-Verwaltung"
    echo "2) Mail-Setup"
    echo "3) Code Interpreter"
    echo "4) LibreChat loeschen/neu einrichten"
    echo "5) Registrierung an/aus"
    echo "6) API-Key-Verwaltung"
    echo "0) Beenden"
    echo ""
    printf "%b" "${C_BLUE}Auswahl: ${C_RESET}"
    read -r wahl
    case "$wahl" in
        1) menu_useradmin ;;
        2) not_yet_built; pause ;;
        3) not_yet_built; pause ;;
        4) not_yet_built; pause ;;
        5) not_yet_built; pause ;;
        6) not_yet_built; pause ;;
        0) echo ""; info "Bis zum naechsten Mal."; exit 0 ;;
        *) warn "Ungueltige Auswahl."; pause ;;
    esac
done
