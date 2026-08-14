#!/bin/sh
# =============================================================================
# delete.sh – Loescht einen LibreChat-User anhand seiner E-Mail-Adresse.
# Ruft die offizielle LibreChat-CLI im API-Container auf (npm run delete-user).
# Die E-Mail wird als Argument uebergeben, daher fragen WIR sie hier ab.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

heading "== User loeschen =="

printf "%b" "${C_BLUE}E-Mail-Adresse des zu loeschenden Users: ${C_RESET}"
read -r user_email

if [ -z "$user_email" ]; then
    error "Keine E-Mail-Adresse eingegeben. Abbruch."
    exit 1
fi

echo ""
warn "Dies loescht den User '${user_email}' unwiderruflich."
if ! confirm "Bist du sicher?"; then
    info "Abgebrochen. Es wurde nichts geloescht."
    exit 0
fi

echo ""
if run_librechat_cmd delete-user.js "$user_email"; then
    echo ""
    success "Befehl wurde ausgefuehrt (siehe Ausgabe oben zur Bestaetigung)."
else
    echo ""
    error "Loeschen ist fehlgeschlagen oder wurde abgebrochen."
fi
