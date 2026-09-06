#!/bin/sh
# =============================================================================
# restore.sh – Stellt ein vorhandenes Backup wieder her. Ueberschreibt dabei
# die AKTUELLEN Live-Daten (Konfiguration bzw. Datenbank) - daher rot markiert
# und mit Sicherheitsabfrage. Der Umfang (config/config-db/full) wird
# automatisch aus dem manifest.txt im gewaehlten Backup gelesen, nicht vom
# User erfragt (Fehlerquelle vermeiden).
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

ensure_backup_dir || exit 1

breadcrumb "Hauptmenue > Backup > Wiederherstellen"
heading_danger "== Backup wiederherstellen =="
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
    printf "%2d) %-11s %-17s %s\n" "$index" "${typ:-?}" "${erstellt:-?}" "$(basename "$datei")"
    echo "$datei" >> "$index_datei"
done

echo ""
printf "%b" "${C_BLUE}Welches Backup wiederherstellen (Nummer)? ${C_RESET}"
read -r wahl
quelle="$(sed -n "${wahl}p" "$index_datei")"
if [ -z "$quelle" ] || [ ! -f "$quelle" ]; then
    error "Ungueltige Auswahl."
    exit 1
fi

typ="$(tar -xOf "$quelle" ./manifest.txt 2>/dev/null | grep '^TYP=' | cut -d= -f2-)"
erstellt="$(tar -xOf "$quelle" ./manifest.txt 2>/dev/null | grep '^ERSTELLT=' | cut -d= -f2-)"
komponenten="$(tar -xOf "$quelle" ./manifest.txt 2>/dev/null | grep '^KOMPONENTEN=' | cut -d= -f2-)"

if [ -z "$typ" ]; then
    error "Konnte kein Manifest in diesem Archiv finden. Abbruch (evtl. beschaedigtes oder fremdes Archiv)."
    exit 1
fi

echo ""
info "Ausgewaehlt: $(basename "$quelle")"
info "Typ:       $typ"
info "Erstellt:  $erstellt"
info "Enthaelt:  $komponenten"
echo ""
warn "Dies ueberschreibt die AKTUELLEN Live-Daten mit dem Stand von '$erstellt'."
warn "Alles, was seitdem passiert ist, geht dabei unwiderruflich verloren!"
if ! confirm "Wirklich wiederherstellen?"; then
    info "Abgebrochen."
    exit 0
fi

arbeitsverzeichnis="$(mktemp -d)"
trap 'rm -rf "$arbeitsverzeichnis"; rm -f "$index_datei"' EXIT
tar -xzf "$quelle" -C "$arbeitsverzeichnis"

# --- Aktuelle Konfiguration vorsichtshalber sichern, bevor sie ueberschrieben wird
sicherungszeit="$(date +%Y%m%d-%H%M%S)"
[ -f "$LIBRECHAT_DIR/.env" ] && cp "$LIBRECHAT_DIR/.env" "$LIBRECHAT_DIR/.env.vor-restore-$sicherungszeit"
[ -f "$LIBRECHAT_DIR/librechat.yaml" ] && cp "$LIBRECHAT_DIR/librechat.yaml" "$LIBRECHAT_DIR/librechat.yaml.vor-restore-$sicherungszeit"

echo ""
info "Stelle Konfiguration wieder her ..."
[ -f "$arbeitsverzeichnis/config/.env" ] && cp "$arbeitsverzeichnis/config/.env" "$LIBRECHAT_DIR/.env"
[ -f "$arbeitsverzeichnis/config/librechat.yaml" ] && cp "$arbeitsverzeichnis/config/librechat.yaml" "$LIBRECHAT_DIR/librechat.yaml"
[ -f "$arbeitsverzeichnis/config/docker-compose.override.yml" ] && cp "$arbeitsverzeichnis/config/docker-compose.override.yml" "$LIBRECHAT_DIR/docker-compose.override.yml"
success "Konfiguration wiederhergestellt."

if [ "$typ" = "config-db" ]; then
    echo ""
    info "Stoppe MongoDB, um die Datenbank zu ersetzen ..."
    run_compose stop mongodb
    rm -rf "${LIBRECHAT_DIR:?}/data-node"
    cp -a "$arbeitsverzeichnis/data-node" "$LIBRECHAT_DIR/data-node"
    info "Starte MongoDB wieder ..."
    run_compose start mongodb
    success "MongoDB-Daten wiederhergestellt."
elif [ "$typ" = "full" ]; then
    echo ""
    info "Stoppe den gesamten Stack, um alle Daten zu ersetzen ..."
    run_compose stop
    rm -rf "${LIBRECHAT_DIR:?}/data-node"
    cp -a "$arbeitsverzeichnis/data-node" "$LIBRECHAT_DIR/data-node"
    for eintrag in "$arbeitsverzeichnis"/*/; do
        name="$(basename "$eintrag")"
        [ "$name" = "config" ] && continue
        [ "$name" = "data-node" ] && continue
        rm -rf "${LIBRECHAT_DIR:?}/$name"
        cp -a "$eintrag" "$LIBRECHAT_DIR/$name"
    done
    info "Starte den Stack wieder ..."
    run_compose start
    success "Alle Daten wiederhergestellt."
fi

echo ""
success "Wiederherstellung abgeschlossen."
if [ "$typ" = "full" ]; then
    info "Der gesamte Stack (inkl. LibreChat) wurde bereits neu gestartet - keine weitere Aktion noetig."
else
    warn_restart_required
fi
