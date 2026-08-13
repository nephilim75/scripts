#!/bin/sh
# =============================================================================
# create.sh – Legt einen neuen LibreChat-User an.
# Ruft die offizielle LibreChat-CLI im API-Container auf (npm run create-user).
# Das CLI-Skript fragt selbst interaktiv nach E-Mail und Passwort.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

heading "== Neuen User anlegen =="
info "Gleich fragt LibreChat selbst nach E-Mail, Name und Passwort."
echo ""

if run_librechat_cmd create-user; then
    echo ""
    success "User wurde angelegt (siehe Ausgabe oben zur Bestaetigung)."
else
    echo ""
    error "Anlegen ist fehlgeschlagen oder wurde abgebrochen."
fi
