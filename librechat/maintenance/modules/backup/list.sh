#!/bin/sh
# =============================================================================
# list.sh – Zeigt vorhandene Backups mit Typ/Zeitpunkt/Groesse (aus dem
# manifest.txt im jeweiligen Archiv) und erlaubt das Loeschen einzelner
# Backups.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

ensure_backup_dir || exit 1

heading "== Vorhandene Backups =="
echo ""

liste="$(find "$BACKUP_DIR" -maxdepth 1 -name '*.tar.gz' -type f 2>/dev/null | sort)"
if [ -z "$liste" ]; then
    warn "Keine Backups gefunden in $BACKUP_DIR."
    exit 0
fi

index_datei="$(mktemp)"
trap 'rm -f "$index_datei"' EXIT

index=0
echo "$liste" | while IFS= read -r datei; do
    index=$((index + 1))
    typ="$(tar -xOf "$datei" ./manifest.txt 2>/dev/null | grep '^TYP=' | cut -d= -f2-)"
    erstellt="$(tar -xOf "$datei" ./manifest.txt 2>/dev/null | grep '^ERSTELLT=' | cut -d= -f2-)"
    groesse="$(du -sh "$datei" 2>/dev/null | awk '{print $1}')"
    printf "%2d) %-11s %-17s %6s  %s\n" "$index" "${typ:-?}" "${erstellt:-?}" "${groesse:-?}" "$(basename "$datei")"
    echo "$datei" >> "$index_datei"
done

echo ""
printf "%b" "${C_BLUE}Nummer zum Loeschen eingeben, oder Enter zum Ueberspringen: ${C_RESET}"
read -r wahl
[ -z "$wahl" ] && exit 0

ziel="$(sed -n "${wahl}p" "$index_datei")"
if [ -z "$ziel" ]; then
    error "Ungueltige Nummer."
    exit 1
fi

echo ""
warn "Backup wird geloescht: $(basename "$ziel")"
if confirm "Wirklich loeschen?"; then
    rm -f "$ziel"
    success "Backup geloescht."
else
    info "Abgebrochen."
fi