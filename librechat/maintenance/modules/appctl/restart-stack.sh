#!/bin/sh
# =============================================================================
# restart-stack.sh – Startet alle LibreChat-Dienste neu (ohne Datenverlust).
# Nutzt "docker compose restart" ohne Servicenamen: das betrifft NUR die in
# docker-compose.yml + docker-compose.override.yml definierten Dienste,
# keine fremden Container auf dem Host (n8n, calcom, jellyfin, ...).
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

heading "== Gesamten Stack neu starten =="
info "Betrifft alle LibreChat-Dienste (LibreChat, MongoDB, Meilisearch, RAG API, Vector-DB, Admin-Panel)."
info "Keine Daten gehen dabei verloren."
echo ""

if confirm "Jetzt alle Dienste neu starten?"; then
    if run_compose restart; then
        echo ""
        success "Alle Dienste wurden neu gestartet."
    else
        echo ""
        error "Neustart ist fehlgeschlagen. Bitte Ausgabe oben pruefen."
    fi
else
    info "Abgebrochen."
fi