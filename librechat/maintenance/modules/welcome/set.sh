#!/bin/sh
# =============================================================================
# set.sh – Aendert die Willkommensnachricht (interface.customWelcome in
# librechat.yaml). Zeigt vorher den aktuellen Stand als Ueberblick.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

heading "== Willkommensnachricht aendern =="
echo ""

aktueller_text="$(get_welcome_message)"
if [ -n "$aktueller_text" ]; then
    info "Aktuell gesetzt ist:"
    echo "  \"$aktueller_text\""
else
    warn "Aktuell ist keine Willkommensnachricht auslesbar (librechat.yaml pruefen)."
fi
echo ""
info "Tipp: {{user.name}} im Text fuegt automatisch den Namen des jeweiligen Users ein."
echo ""

printf "%b" "${C_BLUE}Neuer Text: ${C_RESET}"
read -r neuer_text

if [ -z "$neuer_text" ]; then
    error "Kein Text eingegeben. Abbruch."
    exit 1
fi

if set_welcome_message "$neuer_text"; then
    echo ""
    success "Willkommensnachricht wurde geaendert."
    echo "  \"$(get_welcome_message)\""
    warn_restart_required
else
    error "Aendern ist fehlgeschlagen."
fi