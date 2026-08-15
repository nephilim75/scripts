#!/bin/sh
# =============================================================================
# container-menu.sh – Generisches Untermenue fuer Start/Stop/Neustart/Status/
# Logs/Loeschen EINES LibreChat-Compose-Dienstes. Wird von menu.sh mit
# Anzeigename und Compose-Servicename aufgerufen, z.B.:
#   container-menu.sh "LibreChat" "api"
# So gibt es nur EIN Skript fuer alle Dienste (Wartung an einer Stelle statt
# in sechs Kopien).
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

ANZEIGENAME="${1:?Anzeigename fehlt}"
SERVICE="${2:?Compose-Servicename fehlt}"

pause() {
    echo ""
    printf "%b" "${C_BLUE}Enter druecken, um fortzufahren...${C_RESET}"
    read -r _dummy
}

while true; do
    clear
    heading "== $ANZEIGENAME =="
    echo "1) Status anzeigen"
    echo "2) Logs anzeigen"
    echo "3) Starten"
    echo "4) Stoppen"
    echo "5) Neustarten"
    printf "%b\n" "${C_RED}6) Loeschen (mit Datenverlust)${C_RESET}"
    echo "0) Zurueck"
    echo ""
    printf "%b" "${C_BLUE}Auswahl: ${C_RESET}"
    read -r wahl
    case "$wahl" in
        1)
            echo ""
            run_compose ps "$SERVICE"
            pause
            ;;
        2)
            echo ""
            info "Letzte 100 Zeilen, danach live. Mit Strg+C beenden (zurueck zu diesem Menue)."
            run_compose logs --tail=100 -f "$SERVICE"
            pause
            ;;
        3)
            echo ""
            info "Starte $ANZEIGENAME ..."
            # "up -d" statt "start": legt den Dienst auch neu an, falls er
            # zuvor per "Loeschen" entfernt wurde (fuer Anfaenger robuster).
            if run_compose up -d "$SERVICE"; then
                success "$ANZEIGENAME wurde gestartet."
            else
                error "Starten ist fehlgeschlagen."
            fi
            pause
            ;;
        4)
            echo ""
            info "Stoppe $ANZEIGENAME ..."
            if run_compose stop "$SERVICE"; then
                success "$ANZEIGENAME wurde gestoppt."
            else
                error "Stoppen ist fehlgeschlagen."
            fi
            pause
            ;;
        5)
            echo ""
            info "Starte $ANZEIGENAME neu ..."
            if run_compose restart "$SERVICE"; then
                success "$ANZEIGENAME wurde neu gestartet."
            else
                error "Neustart ist fehlgeschlagen."
            fi
            pause
            ;;
        6)
            echo ""
            warn "Dies entfernt den Container UND das zugehoerige Datenvolumen von '$ANZEIGENAME'."
            warn "Alle darin gespeicherten Daten gehen unwiderruflich verloren!"
            info "Tipp: Vorher ein Backup erstellen (Menuepunkt Backup)."
            if confirm "Wirklich '$ANZEIGENAME' inkl. Daten loeschen?"; then
                if run_compose rm --stop --force --volumes "$SERVICE"; then
                    success "'$ANZEIGENAME' wurde inkl. Daten entfernt."
                    info "Mit 'Starten' kannst du den Dienst mit frischen Daten neu anlegen."
                else
                    error "Loeschen ist fehlgeschlagen."
                fi
            else
                info "Abgebrochen. Es wurde nichts geloescht."
            fi
            pause
            ;;
        0) exit 0 ;;
        *) warn "Ungueltige Auswahl."; pause ;;
    esac
done