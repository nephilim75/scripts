#!/bin/sh
# =============================================================================
# common.sh – Gemeinsame Basisbibliothek fuer LibreChat-Admin-Tool
# Wird von jedem Modul per ". lib/common.sh" eingebunden.
# =============================================================================

# --- Farben (ANSI, POSIX-kompatibel) ---------------------------------------
C_RESET="\033[0m"
C_GREEN="\033[0;32m"
C_RED="\033[0;31m"
C_YELLOW="\033[0;33m"
C_BLUE="\033[0;34m"
C_BOLD="\033[1m"

# --- Ausgabe-Funktionen -------------------------------------------------------
info()    { printf "%b\n" "${C_BLUE}i  $*${C_RESET}"; }
success() { printf "%b\n" "${C_GREEN}✓  $*${C_RESET}"; }
error()   { printf "%b\n" "${C_RED}✗  $*${C_RESET}"; }
warn()    { printf "%b\n" "${C_YELLOW}!  $*${C_RESET}"; }
heading() { printf "%b\n" "${C_BOLD}${C_BLUE}$*${C_RESET}"; }

# --- Ja/Nein-Abfrage fuer kritische Aktionen ---------------------------------
# Nutzung: confirm "Wirklich loeschen?" && <aktion>
confirm() {
    prompt="$1"
    printf "%b" "${C_YELLOW}? ${prompt} [j/N]: ${C_RESET}"
    read -r antwort
    case "$antwort" in
        j|J|ja|Ja|JA) return 0 ;;
        *) return 1 ;;
    esac
}

# --- Projekt-Root ermitteln ---------------------------------------------------
# WICHTIG: POSIX-sh kennt keinen verlaesslichen Weg, den eigenen Pfad einer
# per "." eingebundenen Datei zu ermitteln ($0 zeigt auf das aufrufende Skript).
# Konvention: Jedes Modul berechnet PROJECT_ROOT SELBST und exportiert es,
# bevor es common.sh einbindet, z.B.:
#   PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
#   . "$PROJECT_ROOT/lib/common.sh"
# Falls PROJECT_ROOT nicht gesetzt ist (z.B. common.sh wird direkt getestet),
# gilt das aktuelle Arbeitsverzeichnis als Fallback.
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
CONFIG_FILE="$PROJECT_ROOT/config.sh"

# --- Standardwert fuer deinen Kosmos -----------------------------------------
DEFAULT_LIBRECHAT_DIR="/opt/librechat"
DEFAULT_API_SERVICE="api"

# --- LibreChat-Pfad laden oder einmalig abfragen -----------------------------
# Setzt am Ende: LIBRECHAT_DIR, API_SERVICE
load_or_ask_librechat_path() {
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    fi

    # Fallback auf Default, falls Config leer/nicht vorhanden
    LIBRECHAT_DIR="${LIBRECHAT_DIR:-$DEFAULT_LIBRECHAT_DIR}"
    API_SERVICE="${API_SERVICE:-$DEFAULT_API_SERVICE}"

    # Validierung: existiert der Pfad und liegt dort eine docker-compose.yml?
    if [ ! -d "$LIBRECHAT_DIR" ] || [ ! -f "$LIBRECHAT_DIR/docker-compose.yml" ]; then
        warn "LibreChat wurde unter '$LIBRECHAT_DIR' nicht gefunden."
        printf "%b" "${C_BLUE}Bitte den korrekten Installationspfad angeben: ${C_RESET}"
        read -r eingabe
        if [ -z "$eingabe" ] || [ ! -f "$eingabe/docker-compose.yml" ]; then
            error "Kein gueltiger LibreChat-Pfad (docker-compose.yml fehlt). Abbruch."
            exit 1
        fi
        LIBRECHAT_DIR="$eingabe"
        {
            echo "LIBRECHAT_DIR=\"$LIBRECHAT_DIR\""
            echo "API_SERVICE=\"$API_SERVICE\""
        } > "$CONFIG_FILE"
        success "Pfad gespeichert in $CONFIG_FILE"
    fi
}

# --- Befehl im API-Container ausfuehren --------------------------------------
# Nutzung: run_librechat_cmd create-user
run_librechat_cmd() {
    npm_script="$1"
    shift

    if ! docker compose -f "$LIBRECHAT_DIR/docker-compose.yml" ps --services --status running 2>/dev/null | grep -q "^${API_SERVICE}$"; then
        error "Der Service '${API_SERVICE}' laeuft nicht. Bitte pruefen: docker compose ps (in $LIBRECHAT_DIR)"
        return 1
    fi

    docker compose -f "$LIBRECHAT_DIR/docker-compose.yml" exec "$API_SERVICE" npm run "$npm_script" "$@"
}

# --- Pruefen, ob Mailversand (SMTP) konfiguriert ist -------------------------
# Nutzung: check_mailer_configured || return 1
check_mailer_configured() {
    env_file="$LIBRECHAT_DIR/.env"
    if [ ! -f "$env_file" ]; then
        error "Konnte .env unter $LIBRECHAT_DIR nicht finden."
        return 1
    fi

    host_wert="$(grep -E '^MAILER_HOST=' "$env_file" | cut -d '=' -f2-)"
    if [ -z "$host_wert" ]; then
        warn "Mailversand ist noch nicht eingerichtet."
        info "Bitte zuerst das Mail-Setup ausfuehren, bevor du Passwoerter zuruecksetzt."
        return 1
    fi
    return 0
}

# --- Initialisierung, die jedes Modul beim Einbinden ausfuehren soll --------
load_or_ask_librechat_path
