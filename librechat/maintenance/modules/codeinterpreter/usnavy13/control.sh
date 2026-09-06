#!/bin/sh
# =============================================================================
# control.sh – Startet, stoppt und startet den Code Interpreter neu
# (Variante usnavy13).
#
# Bewusst alle Dienste gemeinsam statt einzeln: api, garage und redis gehoeren
# zusammen, einzeln gestartet ergeben sie keinen brauchbaren Zustand. Wer
# doch einzelne Container braucht, findet sie in der Containerverwaltung des
# Docker-Hosts.
#
# Eigenes Untermenue mit eigener Schleife - das Skript laeuft als eigener
# Prozess, darum ist pause() hier neu definiert.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

pause() {
    echo ""
    printf "%b" "${C_BLUE}Enter druecken, um fortzufahren...${C_RESET}"
    read -r _dummy
}

if ! ci_installed "$CI_USNAVY_DIR"; then
    clear
    breadcrumb "Hauptmenue > Code Interpreter > usnavy13 > Starten/Stoppen"
    heading "== Dienste steuern (usnavy13) =="
    echo ""
    warn "Der Code Interpreter (usnavy13) ist nicht installiert."
    info "Zuerst den Menuepunkt 'Installieren' waehlen."
    pause
    exit 0
fi

while true; do
    clear
    breadcrumb "Hauptmenue > Code Interpreter > usnavy13 > Starten/Stoppen"
    heading "== Dienste steuern (usnavy13) =="
    echo "Pfad: $CI_USNAVY_DIR"
    echo ""
    echo "1) Starten"
    echo "2) Stoppen"
    echo "3) Neustarten"
    echo "4) Kurzer Zustandsbericht"
    echo "0) Zurueck"
    echo ""
    printf "%b" "${C_BLUE}Auswahl: ${C_RESET}"
    read -r wahl

    case "$wahl" in
        1)
            echo ""
            info "Starte die Dienste ..."
            # "up -d" statt "start": legt fehlende Container auch neu an,
            # etwa nachdem sie entfernt wurden.
            if ci_compose "$CI_USNAVY_DIR" up -d; then
                echo ""
                success "Die Dienste wurden gestartet."
                info "Bis alle als 'healthy' gelten, vergeht knapp eine Minute."
            else
                echo ""
                error "Starten ist fehlgeschlagen."
                info "Mehr dazu im Menuepunkt 'Logs anzeigen'."
            fi
            pause
            ;;
        2)
            echo ""
            warn "Waehrend die Dienste gestoppt sind, kann LibreChat keinen Code"
            warn "ausfuehren. Die Daten bleiben erhalten."
            echo ""
            if confirm "Dienste wirklich stoppen?"; then
                echo ""
                info "Stoppe die Dienste ..."
                if ci_compose "$CI_USNAVY_DIR" stop; then
                    echo ""
                    success "Die Dienste wurden gestoppt."
                else
                    echo ""
                    error "Stoppen ist fehlgeschlagen."
                fi
            else
                info "Abgebrochen. Es wurde nichts veraendert."
            fi
            pause
            ;;
        3)
            echo ""
            info "Starte die Dienste neu ..."
            if ci_compose "$CI_USNAVY_DIR" restart; then
                echo ""
                success "Die Dienste wurden neu gestartet."
            else
                echo ""
                error "Neustart ist fehlgeschlagen."
                info "Mehr dazu im Menuepunkt 'Logs anzeigen'."
            fi
            pause
            ;;
        4)
            echo ""
            if ! ci_compose "$CI_USNAVY_DIR" ps; then
                error "Der Zustand konnte nicht ermittelt werden."
                info "Laeuft Docker? Pruefen mit: docker ps"
            fi
            pause
            ;;
        0) exit 0 ;;
        *) warn "Ungueltige Auswahl."; pause ;;
    esac
done
