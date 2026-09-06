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
        breadcrumb "Hauptmenue > LibreChat loeschen/neu einrichten"
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
        breadcrumb "Hauptmenue > User-Verwaltung"
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
        breadcrumb "Hauptmenue > Mail & Passwort-Reset"
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
        breadcrumb "Hauptmenue > Instanz-Einstellungen > Willkommensnachricht"
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

# --- Untermenue: Containerverwaltung (Docker) --------------------------------
# Punkte 1-6 rufen das generische container-menu.sh mit Anzeigename und
# Compose-Servicename auf (ein Skript fuer alle Dienste statt sechs Kopien).
# Kein "pause" danach, da container-menu.sh bereits selbst vor der Rueckkehr
# pausiert.
menu_appctl() {
    while true; do
        clear
        breadcrumb "Hauptmenue > Containerverwaltung (Docker)"
        heading "== Containerverwaltung (Docker) =="
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

# --- Untermenue: Registrierung an/aus -----------------------------------------
menu_registration() {
    while true; do
        clear
        breadcrumb "Hauptmenue > Instanz-Einstellungen > Registrierung"
        heading "== Registrierung an/aus =="
        echo "1) Status anzeigen"
        echo "2) Registrierung aktivieren"
        echo "3) Registrierung deaktivieren"
        echo "0) Zurueck"
        echo ""
        printf "%b" "${C_BLUE}Auswahl: ${C_RESET}"
        read -r wahl
        case "$wahl" in
            1) "$PROJECT_ROOT/modules/instance/registration-show.sh"; pause ;;
            2) "$PROJECT_ROOT/modules/instance/registration-set.sh" an; pause ;;
            3) "$PROJECT_ROOT/modules/instance/registration-set.sh" aus; pause ;;
            0) return ;;
            *) warn "Ungueltige Auswahl."; pause ;;
        esac
    done
}

# --- Untermenue: Instanz-Einstellungen ---------------------------------------
# Fasst Konfigurationspunkte zusammen, die man einmalig einrichtet und danach
# selten anfasst - im Gegensatz zu Themenfeldern wie User-Verwaltung, die man
# haeufig braucht. Willkommensnachricht bleibt technisch eigenstaendig
# (eigene menu_welcome-Funktion), wird hier nur als Unterpunkt eingehaengt.
menu_instance() {
    while true; do
        clear
        breadcrumb "Hauptmenue > Instanz-Einstellungen"
        heading "== Instanz-Einstellungen =="
        echo "1) Willkommensnachricht"
        echo "2) Registrierung an/aus"
        echo "3) API-Key-Verwaltung"
        echo "0) Zurueck zum Hauptmenue"
        echo ""
        printf "%b" "${C_BLUE}Auswahl: ${C_RESET}"
        read -r wahl
        case "$wahl" in
            1) menu_welcome ;;
            2) menu_registration ;;
            3) not_yet_built; pause ;;
            0) return ;;
            *) warn "Ungueltige Auswahl."; pause ;;
        esac
    done
}

# --- Untermenue: Backup -------------------------------------------------------
menu_backup() {
    while true; do
        clear
        breadcrumb "Hauptmenue > Backup"
        heading "== Backup =="
        echo "1) Backup erstellen - Konfiguration"
        echo "2) Backup erstellen - Konfiguration + Datenbank"
        echo "3) Backup erstellen - Alles"
        printf "%b\n" "${C_RED}4) Backup wiederherstellen${C_RESET}"
        echo "5) Vorhandene Backups anzeigen/verwalten"
        echo "0) Zurueck zum Hauptmenue"
        echo ""
        printf "%b" "${C_BLUE}Auswahl: ${C_RESET}"
        read -r wahl
        case "$wahl" in
            1) "$PROJECT_ROOT/modules/backup/create.sh" config; pause ;;
            2) "$PROJECT_ROOT/modules/backup/create.sh" config-db; pause ;;
            3) "$PROJECT_ROOT/modules/backup/create.sh" full; pause ;;
            4) "$PROJECT_ROOT/modules/backup/restore.sh"; pause ;;
            5) "$PROJECT_ROOT/modules/backup/list.sh"; pause ;;
            0) return ;;
            *) warn "Ungueltige Auswahl."; pause ;;
        esac
    done
}

# --- Untermenue: Code Interpreter (Variantenauswahl) -------------------------
# Erste Ebene: welche der beiden Varianten. Da ein Server ueblicherweise nur
# eine davon betreibt, steht hinter jedem Eintrag der Installationsstatus -
# sonst wuerde man leicht im falschen Zweig landen.
menu_codeinterpreter() {
    while true; do
        clear
        breadcrumb "Hauptmenue > Code Interpreter"
        heading "== Code Interpreter =="
        echo "Fuehrt Programmcode aus, den die KI im Chat schreibt - z.B. um"
        echo "eine Tabelle auszuwerten oder ein Diagramm zu erzeugen."
        echo ""
        printf "%b\n" "1) usnavy13     $(ci_status_label "$CI_USNAVY_DIR")"
        printf "%b\n" "2) LibreChat-AI $(ci_status_label "$CI_LIBREAI_DIR")"
        echo "0) Zurueck zum Hauptmenue"
        echo ""
        printf "%b" "${C_BLUE}Auswahl: ${C_RESET}"
        read -r wahl
        case "$wahl" in
            1) menu_ci_usnavy ;;
            2) not_yet_built; pause ;;
            0) return ;;
            *) warn "Ungueltige Auswahl."; pause ;;
        esac
    done
}

# --- Untermenue: Code Interpreter - Variante usnavy13 ------------------------
menu_ci_usnavy() {
    while true; do
        clear
        breadcrumb "Hauptmenue > Code Interpreter > usnavy13"
        heading "== Code Interpreter: usnavy13 =="
        printf "%b\n" "Status: $(ci_status_label "$CI_USNAVY_DIR")   Pfad: $CI_USNAVY_DIR"
        echo ""
        echo "1) Installieren"
        echo "2) Anbindung an LibreChat"
        echo "3) Status anzeigen"
        echo "4) Starten / Stoppen / Neustarten"
        echo "5) Logs anzeigen"
        echo "6) Aktualisieren"
        printf "%b\n" "${C_RED}7) Entfernen${C_RESET}"
        echo "0) Zurueck"
        echo ""
        printf "%b" "${C_BLUE}Auswahl: ${C_RESET}"
        read -r wahl
        case "$wahl" in
            1) "$PROJECT_ROOT/modules/codeinterpreter/usnavy13/install.sh"; pause ;;
            2) "$PROJECT_ROOT/modules/codeinterpreter/usnavy13/link.sh"; pause ;;
            3) "$PROJECT_ROOT/modules/codeinterpreter/usnavy13/status.sh"; pause ;;
            4) "$PROJECT_ROOT/modules/codeinterpreter/usnavy13/control.sh" ;;
            5) "$PROJECT_ROOT/modules/codeinterpreter/usnavy13/logs.sh" ;;
            6) "$PROJECT_ROOT/modules/codeinterpreter/usnavy13/update.sh"; pause ;;
            7) "$PROJECT_ROOT/modules/codeinterpreter/usnavy13/remove.sh"; pause ;;
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
    echo "2) Containerverwaltung (Docker)"
    echo "3) Mail & Passwort-Reset (SMTP)"
    echo "4) Instanz-Einstellungen"
    echo "5) Code Interpreter"
    echo "6) Backup"
    printf "%b\n" "${C_RED}7) LibreChat loeschen/neu einrichten${C_RESET}"
    echo "8) Admin-Tool aktualisieren"
    echo "0) Beenden"
    echo ""
    printf "%b" "${C_BLUE}Auswahl: ${C_RESET}"
    read -r wahl
    case "$wahl" in
        1) menu_useradmin ;;
        2) menu_appctl ;;
        3) menu_mail ;;
        4) menu_instance ;;
        5) menu_codeinterpreter ;;
        6) menu_backup ;;
        7) menu_lifecycle ;;
        # "exec": das Menue endet hier sauber. Das Update-Skript ersetzt die
        # Dateien und startet menu.sh danach selbst wieder.
        8) exec "$PROJECT_ROOT/modules/selfupdate/update-tool.sh" ;;
        0) echo ""; info "Bis zum naechsten Mal."; exit 0 ;;
        *) warn "Ungueltige Auswahl."; pause ;;
    esac
done
