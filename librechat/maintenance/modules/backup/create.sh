#!/bin/sh
# =============================================================================
# create.sh – Erstellt ein Backup. Umfang per Parameter:
#   config      -> nur Konfigurationsdateien (.env, librechat.yaml, override)
#   config-db   -> zusaetzlich MongoDB-Rohdaten (Bind-Mount-Verzeichnis
#                  "data-node")
#   full        -> zusaetzlich alle weiteren erkannten Bind-Mount-
#                  Verzeichnisse (z.B. Meilisearch, Vector-DB)
# Fuer config-db/full wird kurz der betroffene Dienst (bzw. bei full der
# komplette Stack) gestoppt, damit die kopierten Rohdaten konsistent sind -
# laufende Datenbankdateien "heiss" zu kopieren ist nicht sicher.
# Jedes Archiv enthaelt eine manifest.txt (Typ/Zeitpunkt/Komponenten), damit
# restore.sh spaeter automatisch weiss, was wiederherzustellen ist.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

modus="${1:?Umfang (config|config-db|full) fehlt}"
case "$modus" in
    config|config-db|full) ;;
    *) error "Unbekannter Umfang: $modus"; exit 1 ;;
esac

ensure_backup_dir || exit 1

heading "== Backup erstellen ($modus) =="
echo ""

# --- Groesse schaetzen --------------------------------------------------
config_kb() {
    files=""
    [ -f "$LIBRECHAT_DIR/.env" ] && files="$files $LIBRECHAT_DIR/.env"
    [ -f "$LIBRECHAT_DIR/librechat.yaml" ] && files="$files $LIBRECHAT_DIR/librechat.yaml"
    [ -f "$LIBRECHAT_DIR/docker-compose.override.yml" ] && files="$files $LIBRECHAT_DIR/docker-compose.override.yml"
    [ -z "$files" ] && { echo 0; return; }
    du -ck $files 2>/dev/null | tail -1 | awk '{print $1}'
}
dir_kb() {
    [ -d "$1" ] || { echo 0; return; }
    du -sk "$1" 2>/dev/null | awk '{print $1}'
}

geschaetzt_kb=$(config_kb)
komponenten="Konfiguration (.env, librechat.yaml, docker-compose.override.yml)"

if [ "$modus" != "config" ]; then
    if [ ! -d "$LIBRECHAT_DIR/data-node" ]; then
        error "MongoDB-Datenverzeichnis '$LIBRECHAT_DIR/data-node' nicht gefunden."
        info "Falls MongoDB ueber ein Docker-Named-Volume statt Bind-Mount laeuft, wird das von diesem Backup-Modul aktuell nicht unterstuetzt."
        exit 1
    fi
    db_kb=$(dir_kb "$LIBRECHAT_DIR/data-node")
    geschaetzt_kb=$((geschaetzt_kb + db_kb))
    komponenten="$komponenten, MongoDB-Rohdaten (data-node)"
fi

BIND_DIRS=""
if [ "$modus" = "full" ]; then
    for d in $(detect_bind_mounts); do
        [ "$d" = "data-node" ] && continue
        [ -d "$LIBRECHAT_DIR/$d" ] || continue
        BIND_DIRS="$BIND_DIRS $d"
        d_kb=$(dir_kb "$LIBRECHAT_DIR/$d")
        geschaetzt_kb=$((geschaetzt_kb + d_kb))
        komponenten="$komponenten, $d"
    done
    [ -n "$BIND_DIRS" ] && info "Zusaetzlich erkannte Verzeichnisse:$BIND_DIRS"

    named_volumes="$(run_compose config --volumes 2>/dev/null)"
    if [ -n "$named_volumes" ]; then
        warn "Zusaetzlich gefundene Docker-Named-Volumes, die dieses Modul NICHT sichert:"
        echo "$named_volumes" | sed 's/^/    /'
    fi
fi

# Sicherheitsmarge: 20% Aufschlag, da kurzzeitig Rohdaten UND das fertige
# komprimierte Archiv gleichzeitig Platz brauchen.
benoetigt_kb=$((geschaetzt_kb * 12 / 10))
frei_kb=$(df -Pk "$BACKUP_DIR" | awk 'NR==2{print $4}')

echo ""
info "Komponenten: $komponenten"
info "Geschaetzte Rohgroesse: $((geschaetzt_kb / 1024)) MB"
info "Benoetigter freier Speicher (mit Sicherheitsmarge): $((benoetigt_kb / 1024)) MB"
info "Verfuegbar in $BACKUP_DIR: $((frei_kb / 1024)) MB"
echo ""

if [ "$frei_kb" -lt "$benoetigt_kb" ]; then
    error "Nicht genug freier Speicherplatz. Backup wird abgebrochen."
    exit 1
fi

if ! confirm "Backup jetzt erstellen?"; then
    info "Abgebrochen."
    exit 0
fi

zeitstempel="$(date +%Y-%m-%d_%H%M)"
archiv="$BACKUP_DIR/${modus}_${zeitstempel}.tar.gz"
arbeitsverzeichnis="$(mktemp -d "$BACKUP_DIR/.tmp-backup-XXXXXX")" || { error "Konnte kein temporaeres Verzeichnis anlegen."; exit 1; }
trap 'rm -rf "$arbeitsverzeichnis"' EXIT

echo ""
mkdir -p "$arbeitsverzeichnis/config"
[ -f "$LIBRECHAT_DIR/.env" ] && cp "$LIBRECHAT_DIR/.env" "$arbeitsverzeichnis/config/"
[ -f "$LIBRECHAT_DIR/librechat.yaml" ] && cp "$LIBRECHAT_DIR/librechat.yaml" "$arbeitsverzeichnis/config/"
[ -f "$LIBRECHAT_DIR/docker-compose.override.yml" ] && cp "$LIBRECHAT_DIR/docker-compose.override.yml" "$arbeitsverzeichnis/config/"
success "Konfiguration gesichert."

if [ "$modus" = "config-db" ]; then
    echo ""
    info "Stoppe MongoDB fuer ein konsistentes Backup ..."
    run_compose stop mongodb
    cp -a "$LIBRECHAT_DIR/data-node" "$arbeitsverzeichnis/data-node"
    info "Starte MongoDB wieder ..."
    run_compose start mongodb
    success "MongoDB-Rohdaten gesichert."
elif [ "$modus" = "full" ]; then
    echo ""
    info "Stoppe den gesamten Stack fuer ein konsistentes Backup ..."
    run_compose stop
    cp -a "$LIBRECHAT_DIR/data-node" "$arbeitsverzeichnis/data-node"
    for d in $BIND_DIRS; do
        cp -a "$LIBRECHAT_DIR/$d" "$arbeitsverzeichnis/$d"
    done
    info "Starte den Stack wieder ..."
    run_compose start
    success "Alle Rohdaten gesichert."
fi

{
    echo "TYP=$modus"
    echo "ERSTELLT=$zeitstempel"
    echo "HOST=$(hostname 2>/dev/null || echo unbekannt)"
    echo "LIBRECHAT_DIR=$LIBRECHAT_DIR"
    echo "KOMPONENTEN=$komponenten"
} > "$arbeitsverzeichnis/manifest.txt"

echo ""
info "Komprimiere Archiv ..."
if tar -czf "$archiv" -C "$arbeitsverzeichnis" .; then
    echo ""
    success "Backup erstellt: $archiv"
    info "Komprimierte Groesse: $(du -sh "$archiv" | awk '{print $1}')"
else
    error "Erstellen des Archivs ist fehlgeschlagen."
    exit 1
fi