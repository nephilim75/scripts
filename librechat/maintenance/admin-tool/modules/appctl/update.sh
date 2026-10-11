#!/bin/sh
# =============================================================================
# update.sh – Aktualisiert LibreChat: git pull im Installationsverzeichnis,
# neue Docker-Images ziehen, Stack neu hochfahren.
# WICHTIG: librechat.yaml und .env* stehen in LibreChats offizieller
# .gitignore (Stand geprueft) und werden durch "git pull" NICHT
# ueberschrieben. docker-compose.override.yml wird ebenfalls ignoriert.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

heading "== LibreChat aktualisieren =="
info "Fuehrt nacheinander aus: git pull, docker compose pull, docker compose up -d."
warn "Empfehlung: Vorher ein Backup erstellen (Menuepunkt Backup)."
echo ""

if [ ! -d "$LIBRECHAT_DIR/.git" ]; then
    error "Kein Git-Repository unter $LIBRECHAT_DIR gefunden. 'git pull' ist nicht moeglich."
    exit 1
fi

if ! confirm "Update jetzt durchfuehren?"; then
    info "Abgebrochen."
    exit 0
fi

echo ""
info "1/3  git pull ..."
if ! (cd "$LIBRECHAT_DIR" && git pull); then
    error "git pull fehlgeschlagen. Abbruch, um Inkonsistenzen zu vermeiden."
    exit 1
fi
success "Repository aktualisiert."

echo ""
info "2/3  Neue Images ziehen ..."
if ! run_compose pull; then
    error "docker compose pull fehlgeschlagen."
    exit 1
fi
success "Images aktualisiert."

echo ""
info "3/3  Stack neu hochfahren ..."
if ! run_compose up -d; then
    error "docker compose up -d fehlgeschlagen."
    exit 1
fi

echo ""
success "Update abgeschlossen."
warn "Falls sich .env.example geaendert hat: ggf. neue Variablen manuell in .env uebernehmen (siehe LibreChat-Changelog)."