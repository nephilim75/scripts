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


# --- Untermenue: LibreChat loeschen/neu einrichten (GEFAHRENBEREICH) ---------
menu_lifecycle() {
    while true; do
        clear
        heading_danger "== LibreChat loeschen/neu einrichten =="
        printf "%b\n" "${C_RED}Achtung: Dieser Bereich enthaelt destruktive Aktionen.${C_RESET}"
        echo ""
        echo "1) Testlauf: zeigen, was geloescht wuerde (Dry-Run, ungefaehrlich)"
        printf "%b\n" "${C_RED}2) Wirklich loeschen${C_RESET}"
        echo "3) Neu einrichten (frische Installation)"
        echo "0) Zurueck zum Hauptmenue"
        echo ""
        printf "%b" "${C_BLUE}Auswahl: ${C_RESET}"
        read -r wahl
        case "$wahl" in
            1) bash "$PROJECT_ROOT/modules/lifecycle/purge-librechat.sh" --dry-run; pause ;;
            2) bash "$PROJECT_ROOT/modules/lifecycle/purge-librechat.sh"; pause ;;
            3) "$PROJECT_ROOT/modules/lifecycle/reinstall.sh"; pause ;;
            0) return ;;
            *) warn "Ungueltige Auswahl."; pause ;;
        esac
    done
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

# --- Untermenue: Mail & Passwort-Reset ---------------------------------------
menu_mail() {
    while true; do
        clear
        heading "== Mail & Passwort-Reset (SMTP) =="
        echo "1) Aktuelle Konfiguration anzeigen"
        echo "2) Neue Konfiguration anlegen"
        echo "3) Konfiguration ueberschreiben"
        echo "4) Konfiguration loeschen"
        echo "0) Zurueck zum Hauptmenue"
        echo ""
        printf "%b" "${C_BLUE}Auswahl: ${C_RESET}"
        read -r wahl
        case "$wahl" in
            1) "$PROJECT_ROOT/modules/mail/smtp-show.sh"; pause ;;
            2) "$PROJECT_ROOT/modules/mail/smtp-set.sh" create; pause ;;
            3) "$PROJECT_ROOT/modules/mail/smtp-set.sh" overwrite; pause ;;
            4) "$PROJECT_ROOT/modules/mail/smtp-delete.sh"; pause ;;
            0) return ;;
            *) warn "Ungueltige Auswahl."; pause ;;
        esac
    done
}
while true; do
    clear
    heading "=================================="
    heading "  LibreChat Admin-Tool"
    heading "=================================="
    echo ""
    echo "1) User-Verwaltung"
    echo "2) Mail & Passwort-Reset (SMTP)"
    echo "3) Code Interpreter"
    echo "4) Registrierung an/aus"
    echo "5) API-Key-Verwaltung"
    echo "6) Willkommensnachricht"
    echo "7) Anwendungssteuerung"
    printf "%b\n" "${C_RED}8) LibreChat loeschen/neu einrichten${C_RESET}"
    echo "0) Beenden"
    echo ""
    printf "%b" "${C_BLUE}Auswahl: ${C_RESET}"
    read -r wahl
    case "$wahl" in
        1) menu_useradmin ;;
        2) menu_mail ;;
        3) not_yet_built; pause ;;
        4) not_yet_built; pause ;;
        5) not_yet_built; pause ;;
        6) not_yet_built; pause ;;
        7) not_yet_built; pause ;;
        8) menu_lifecycle ;;
        0) echo ""; info "Bis zum naechsten Mal."; exit 0 ;;
        *) warn "Ungueltige Auswahl."; pause ;;
    esac
done
