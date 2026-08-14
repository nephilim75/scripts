#!/bin/sh
# =============================================================================
# smtp-show.sh – Zeigt die aktuell in der .env gesetzte SMTP-Konfiguration an.
# Rein lesend, keine Aenderungen.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

heading "== Aktuelle SMTP-Konfiguration =="
echo ""
show_smtp_summary
echo ""

if [ "$(get_env_value ALLOW_PASSWORD_RESET)" = "true" ] && [ -n "$(get_env_value EMAIL_HOST)" ]; then
    success "Konfiguration sieht vollstaendig aus."
else
    warn "Konfiguration ist unvollstaendig oder Passwort-Reset ist deaktiviert."
fi
