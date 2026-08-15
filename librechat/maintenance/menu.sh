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
# --- Untermenue: Willkommensnachricht -----------------------------------------
menu_welcome() {
    while true; do
        clear
        heading "== Willkommensnachricht =="
        echo "1) Aktuelle Nachricht anzeigen"
        echo "2) Nachricht aendern"
        echo "0) Zurueck zum Hauptmenue"
        echo ""
        printf "%b" "${C_BLUE}Auswahl: ${C_RESET}"
        read -r wahl
        case "$wahl" in
            1) "$PROJECT_ROOT/modules/welcome/show.sh"; pause ;;
            2) "$PROJECT_ROOT/modules/welcome/set.sh"; pause ;;
            0) return ;;
            *) warn "Ungueltige Auswahl."; pause ;;
        esac
    done
}

# --- Untermenue: Anwendungssteuerung -----------------------------------------
# Punkte 1-6 rufen das generische container-menu.sh mit Anzeigename und
# Compose-Servicename auf (ein Skript fuer alle Dienste statt sechs Kopien).
# Kein "pause" danach, da container-menu.sh bereits selbst vor der Rueckkehr
# pausiert.
menu_appctl() {
    while true; do
        clear
        heading "== Anwendungssteuerung =="
        echo "1) LibreChat"
        echo "2) MongoDB"
        echo "3) Meilisearch"
        echo "4) RAG API"
        echo "5) Vector-DB"
        echo "6) Admin-Panel"
        echo "7) Gesamten Stack neu starten (ohne Datenverlust)"
        echo "8) LibreChat aktualisieren (Update)"
        echo "0) Zurueck zum Hauptmenue"
        echo ""
        printf "%b" "${C_BLUE}Auswahl: ${C_RESET}"
        read -r wahl
        case "$wahl" in
            1) "$PROJECT_ROOT/modules/appctl/container-menu.sh" "LibreChat" "api" ;;
            2) "$PROJECT_ROOT/modules/appctl/container-menu.sh" "MongoDB" "mongodb" ;;
            3) "$PROJECT_ROOT/modules/appctl/container-menu.sh" "Meilisearch" "meilisearch" ;;
            4) "$PROJECT_ROOT/modules/appctl/container-menu.sh" "RAG API" "rag_api" ;;
            5) "$PROJECT_ROOT/modules/appctl/container-menu.sh" "Vector-DB" "vectordb" ;;
            6) "$PROJECT_ROOT/modules/appctl/container-menu.sh" "Admin-Panel" "admin-panel" ;;
            7) "$PROJECT_ROOT/modules/appctl/restart-stack.sh"; pause ;;
            8) "$PROJECT_ROOT/modules/appctl/update.sh"; pause ;;
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
        6) menu_welcome ;;
        7) menu_appctl ;;
        8) menu_lifecycle ;;
        0) echo ""; info "Bis zum naechsten Mal."; exit 0 ;;
        *) warn "Ungueltige Auswahl."; pause ;;
    esac
done