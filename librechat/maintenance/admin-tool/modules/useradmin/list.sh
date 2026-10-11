#!/bin/sh
# =============================================================================
# list.sh – Zeigt alle registrierten LibreChat-User an.
# Ruft die offizielle LibreChat-CLI im API-Container auf (npm run list-users).
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

breadcrumb "Hauptmenue > User-Verwaltung > Alle User auflisten"
heading "== Alle User auflisten =="
echo ""

if ! run_librechat_cmd list-users.js; then
    echo ""
    error "Auflisten ist fehlgeschlagen."
fi
