#!/bin/sh
# =============================================================================
# ban.sh – Bannt einen LibreChat-User fuer eine bestimmte Dauer.
# Ruft die offizielle LibreChat-CLI im API-Container auf (npm run ban-user).
# Das CLI-Skript fragt selbst interaktiv nach E-Mail und Dauer.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

breadcrumb "Hauptmenue > User-Verwaltung > User bannen"
heading "== User bannen =="
info "Gleich fragt LibreChat nach E-Mail und der Dauer des Banns."
echo ""

if run_librechat_cmd ban-user.js; then
    echo ""
    success "Befehl wurde ausgefuehrt (siehe Ausgabe oben zur Bestaetigung)."
else
    echo ""
    error "Bannen ist fehlgeschlagen oder wurde abgebrochen."
fi
