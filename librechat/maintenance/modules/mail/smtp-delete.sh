#!/bin/sh
# =============================================================================
# smtp-delete.sh – Entfernt die SMTP-Konfiguration aus der .env und
# deaktiviert damit automatisch auch den Passwort-Reset ueber die Login-Seite.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

breadcrumb "Hauptmenue > Mail & Passwort-Reset > Konfiguration loeschen"
heading "== SMTP-Konfiguration loeschen =="
echo ""
info "Aktuell gesetzte Werte:"
echo "  EMAIL_HOST:      $(get_env_value EMAIL_HOST)"
echo "  EMAIL_PORT:      $(get_env_value EMAIL_PORT)"
echo "  EMAIL_FROM:      $(get_env_value EMAIL_FROM)"
echo ""

warn "Dies leert alle SMTP-Felder und setzt ALLOW_PASSWORD_RESET wieder auf false."
warn "Der Passwort-Reset ueber die Login-Seite ist danach NICHT mehr moeglich."
if ! confirm "Bist du sicher?"; then
    info "Abgebrochen. Es wurde nichts geloescht."
    exit 0
fi

set_env_value EMAIL_HOST ""
set_env_value EMAIL_PORT ""
set_env_value EMAIL_ENCRYPTION ""
set_env_value EMAIL_USERNAME ""
set_env_value EMAIL_PASSWORD ""
set_env_value EMAIL_FROM_NAME ""
set_env_value EMAIL_FROM ""
set_env_value ALLOW_PASSWORD_RESET "false"

echo ""
success "SMTP-Konfiguration wurde geloescht. ALLOW_PASSWORD_RESET=false gesetzt."
warn "Damit die Aenderungen wirken, muss LibreChat neu gestartet werden: docker restart ${LIBRECHAT_CONTAINER}"
