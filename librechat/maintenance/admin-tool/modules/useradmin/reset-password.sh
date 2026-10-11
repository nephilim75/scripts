#!/bin/sh
# =============================================================================
# reset-password.sh – Setzt das Passwort eines Users direkt neu.
# Ruft die offizielle LibreChat-CLI im API-Container auf (npm run reset-password).
# Das CLI-Skript fragt selbst interaktiv nach E-Mail und neuem Passwort.
# Hinweis: Es wird KEINE E-Mail an den User verschickt, das Passwort wird
# direkt in der Datenbank gesetzt.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

breadcrumb "Hauptmenue > User-Verwaltung > Passwort zuruecksetzen"
heading "== Passwort zuruecksetzen =="
info "Gleich fragt LibreChat nach E-Mail und neuem Passwort."
info "Der User wird NICHT per Mail benachrichtigt - das Passwort wird direkt gesetzt."
echo ""

if run_librechat_cmd reset-password.js; then
    echo ""
    success "Befehl wurde ausgefuehrt (siehe Ausgabe oben zur Bestaetigung)."
else
    echo ""
    error "Zuruecksetzen ist fehlgeschlagen oder wurde abgebrochen."
fi
