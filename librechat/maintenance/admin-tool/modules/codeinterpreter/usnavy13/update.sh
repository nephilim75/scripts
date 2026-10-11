#!/bin/sh
# =============================================================================
# update.sh – Aktualisiert den Code Interpreter (Variante usnavy13).
#
# Ablauf: "pull" holt die neuen Images, "up -d" legt genau die Container neu
# an, deren Image sich geaendert hat.
#
# Bewusst KEIN "restart": das startet die vorhandenen Container mitsamt dem
# alten Image neu - das frisch geladene Image bliebe ungenutzt, und der
# Fehler faellt nicht auf, weil scheinbar alles funktioniert.
# Bewusst auch kein "down" davor: das entfernt alle Container samt
# Compose-Netzwerk und haengt den Stack kurz vom Proxy-Netzwerk ab. Laengere
# Ausfallzeit ohne jeden Gewinn.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

breadcrumb "Hauptmenue > Code Interpreter > usnavy13 > Aktualisieren"
heading "== Code Interpreter aktualisieren (usnavy13) =="
echo ""

if ! ci_installed "$CI_USNAVY_DIR"; then
    warn "Der Code Interpreter (usnavy13) ist nicht installiert."
    info "Zuerst den Menuepunkt 'Installieren' waehlen."
    exit 0
fi

info "Pfad: $CI_USNAVY_DIR"
echo ""
echo "Es werden die aktuellen Images geladen und die betroffenen Container"
echo "neu angelegt. Die eigene Konfiguration (.env, docker-compose.override.yml)"
echo "bleibt unangetastet."
echo ""
warn "Waehrend des Vorgangs ist der Code Interpreter kurz nicht erreichbar."
info "Der Download kann je nach Umfang einige Minuten dauern."
echo ""

if ! confirm "Update jetzt durchfuehren?"; then
    info "Abgebrochen. Es wurde nichts veraendert."
    exit 0
fi

# --- Images laden -------------------------------------------------------------
echo ""
info "Lade aktuelle Images ..."
if ! ci_compose "$CI_USNAVY_DIR" pull; then
    echo ""
    error "Die Images konnten nicht geladen werden."
    info "Besteht eine Internetverbindung? Es wurde nichts veraendert -"
    info "die bisherige Fassung laeuft unveraendert weiter."
    exit 1
fi
success "Images geladen."

# --- Container erneuern -------------------------------------------------------
echo ""
info "Erneuere die Container ..."
if ! ci_compose "$CI_USNAVY_DIR" up -d; then
    echo ""
    error "Die Container konnten nicht erneuert werden."
    info "Zustand pruefen unter 'Starten / Stoppen / Neustarten' und in den Logs."
    exit 1
fi

echo ""
success "Update abgeschlossen."
info "Bis alle Dienste als 'healthy' gelten, vergeht knapp eine Minute."
echo ""

# --- Zustand zeigen -----------------------------------------------------------
heading "-- Dienste --"
ci_compose "$CI_USNAVY_DIR" ps 2>/dev/null \
    || warn "Der Zustand konnte nicht ermittelt werden."
echo ""

# Alte, nun ungenutzte Images bleiben liegen und belegen Platz. Nicht selbst
# aufraeumen: "docker image prune" wuerde auch Images anderer Dienste auf
# diesem Server treffen.
info "Die abgeloesten Images bleiben auf der Platte liegen."
info "Aufraeumen bei Bedarf von Hand mit: docker image prune"
echo ""
