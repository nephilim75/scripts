#!/bin/sh
# =============================================================================
# registration-set.sh – Setzt ALLOW_REGISTRATION in der .env.
# Nutzung: registration-set.sh an | registration-set.sh aus
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

modus="${1:?Modus (an/aus) fehlt}"

case "$modus" in
    an)
        heading "== Registrierung aktivieren =="
        echo ""
        if [ -z "$(get_env_value EMAIL_HOST)" ]; then
            warn "Kein SMTP eingerichtet (siehe Mail & Passwort-Reset)."
            warn "Neue User werden dann nicht per Mail verifiziert."
            echo ""
        fi
        set_env_value ALLOW_REGISTRATION "true"
        success "Registrierung wurde aktiviert."
        ;;
    aus)
        heading "== Registrierung deaktivieren =="
        echo ""
        set_env_value ALLOW_REGISTRATION "false"
        success "Registrierung wurde deaktiviert."
        ;;
    *)
        error "Unbekannter Modus: $modus (erwartet: an|aus)"
        exit 1
        ;;
esac

echo ""
warn_restart_required