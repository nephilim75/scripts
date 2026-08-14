#!/bin/sh
# =============================================================================
# reinstall.sh – Ruft das bestehende LibreChat-Installer-Skript live von
# GitHub auf. Keine lokale Kopie, damit immer die aktuelle Version genutzt
# wird. Das Installer-Skript bringt bereits eigene Sicherheitspruefungen mit
# (bricht ab, falls /opt/librechat oder LibreChat-Container bereits existieren).
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/install/install-librechat.sh"

heading_danger "== LibreChat neu einrichten =="
info "Holt das Install-Skript von GitHub und fuehrt es aus."
info "Falls unter /opt/librechat schon was liegt, bricht es von selbst ab."
echo ""

bash -c "$(curl -fsSL "$INSTALL_SCRIPT_URL")"
