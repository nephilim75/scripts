#!/bin/sh
# =============================================================================
# registration-show.sh – Zeigt, ob Selbst-Registrierung aktiviert ist
# (ALLOW_REGISTRATION in .env). Rein lesend, keine Aenderungen.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

heading "== Registrierung: Status =="
echo ""

wert="$(get_env_value ALLOW_REGISTRATION)"
echo "  ALLOW_REGISTRATION: $wert"
echo ""

if [ "$wert" = "true" ]; then
    success "Registrierung ist aktuell aktiviert."
else
    warn "Registrierung ist aktuell deaktiviert."
fi

if [ -z "$(get_env_value EMAIL_HOST)" ]; then
    echo ""
    warn "Kein SMTP eingerichtet (siehe Mail & Passwort-Reset)."
    info "Falls Registrierung aktiv ist: neue User werden dann nicht per Mail verifiziert."
fi