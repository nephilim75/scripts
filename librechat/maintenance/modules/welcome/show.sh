#!/bin/sh
# =============================================================================
# show.sh – Zeigt die aktuell gesetzte Willkommensnachricht an.
# Rein lesend, keine Aenderungen.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

heading "== Aktuelle Willkommensnachricht =="
echo ""

aktueller_text="$(get_welcome_message)"
if [ -z "$aktueller_text" ]; then
    warn "Konnte keine Willkommensnachricht finden (librechat.yaml pruefen)."
else
    echo "  \"$aktueller_text\""
fi