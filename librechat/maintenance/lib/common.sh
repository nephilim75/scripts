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
C_BLUE="\033[0;94m"
C_BOLD="\033[1m"

# --- Ausgabe-Funktionen -------------------------------------------------------
info()    { printf "%b\n" "${C_BLUE}i  $*${C_RESET}"; }
success() { printf "%b\n" "${C_GREEN}✓  $*${C_RESET}"; }
error()   { printf "%b\n" "${C_RED}✗  $*${C_RESET}"; }
warn()    { printf "%b\n" "${C_YELLOW}!  $*${C_RESET}"; }
heading() { printf "%b\n" "${C_BOLD}${C_BLUE}$*${C_RESET}"; }
# Fuer destruktive/gefaehrliche Bereiche (z.B. Loeschen/Neu-Einrichten) -
# rot statt blau, damit sofort auffaellt: hier kann was Ernstes passieren.
heading_danger() { printf "%b\n" "${C_BOLD}${C_RED}$*${C_RESET}"; }

# --- Strg+C soll das Menue NICHT beenden -------------------------------------
# Ohne diesen Trap wuerde Strg+C (SIGINT) waehrend eines laufenden Befehls
# (z.B. "Logs anzeigen", docker compose logs -f) das komplette Menue inkl.
# aller Elternskripte beenden, da alle Prozesse in derselben Terminal-
# Vordergrundgruppe haengen. "trap ':' INT" faengt SIGINT im Skript selbst ab
# (Skript laeuft weiter) - gestartete Kindprozesse wie "docker" bekommen beim
# Ausfuehren trotzdem das normale SIGINT-Verhalten (POSIX: nur wirklich
# ignorierte Signale ueber "trap '' SIG" vererben sich an exec'te
# Kindprozesse, abgefangene wie hier nicht - Ctrl+C beendet also weiterhin
# z.B. "docker compose logs -f", nicht aber unser Menue).
trap ':' INT

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

# --- Standardwerte fuer die Ziel-Installation --------------------------------
DEFAULT_LIBRECHAT_DIR="/opt/librechat"
DEFAULT_LIBRECHAT_CONTAINER="LibreChat"

# --- LibreChat-Pfad laden oder einmalig abfragen -----------------------------
# Setzt am Ende: LIBRECHAT_DIR, LIBRECHAT_CONTAINER
load_or_ask_librechat_path() {
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    fi

    # Fallback auf Default, falls Config leer/nicht vorhanden
    LIBRECHAT_DIR="${LIBRECHAT_DIR:-$DEFAULT_LIBRECHAT_DIR}"
    LIBRECHAT_CONTAINER="${LIBRECHAT_CONTAINER:-$DEFAULT_LIBRECHAT_CONTAINER}"

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
            echo "LIBRECHAT_CONTAINER=\"$LIBRECHAT_CONTAINER\""
        } > "$CONFIG_FILE"
        success "Pfad gespeichert in $CONFIG_FILE"
    fi
}

# --- CLI-Skript direkt im Container ausfuehren --------------------------------
# WICHTIG: bewusst NICHT "npm run ...", sondern direkt "node config/<script>".
# npm leitet Signale (z.B. Strg+C) unzuverlaessig weiter, was zu haengenden,
# nicht abbrechbaren Sessions fuehren kann.
# Nutzung: run_librechat_cmd create-user.js
run_librechat_cmd() {
    node_script="$1"
    shift

    if ! docker ps --format '{{.Names}}' | grep -q "^${LIBRECHAT_CONTAINER}$"; then
        error "Der Container '${LIBRECHAT_CONTAINER}' laeuft nicht. Bitte pruefen: docker ps"
        return 1
    fi

    docker exec -it "$LIBRECHAT_CONTAINER" node "config/${node_script}" "$@"
}

# --- Docker-Compose-Befehl im LibreChat-Projektverzeichnis ausfuehren -------
# Nutzung: run_compose restart | run_compose up -d <service> | run_compose ps
# Per "cd" statt "-f <pfad>", damit docker-compose.override.yml (liegt im
# selben Verzeichnis) automatisch mit eingelesen wird, wie beim normalen
# "docker compose"-Aufruf im Projektordner ueblich. Betrifft ausschliesslich
# die in docker-compose.yml + override definierten Dienste, keine fremden
# Container auf dem Host.
run_compose() {
    (cd "$LIBRECHAT_DIR" && docker compose "$@")
}

# --- Sensiblen Wert teilweise maskiert anzeigen -------------------------------
# Zeigt Anfang/Ende, damit Tippfehler auffallen, ohne den Wert komplett offenzulegen.
# Nutzung: mask_secret "$passwort"
mask_secret() {
    wert="$1"
    laenge=${#wert}
    if [ "$laenge" -le 4 ]; then
        printf '%s' "****"
        return
    fi
    anfang=$(printf '%s' "$wert" | cut -c1-2)
    ende=$(printf '%s' "$wert" | cut -c$((laenge - 1))-"$laenge")
    printf '%s***%s (Laenge: %d)' "$anfang" "$ende" "$laenge"
}

# --- .env-Werte lesen und schreiben ------------------------------------------
# Nutzung: get_env_value EMAIL_HOST
get_env_value() {
    key="$1"
    env_file="$LIBRECHAT_DIR/.env"
    [ -f "$env_file" ] || return 1
    grep -E "^${key}=" "$env_file" | head -n1 | cut -d '=' -f2-
}

# Nutzung: set_env_value EMAIL_HOST smtp.example.com
# Ersetzt die Zeile falls vorhanden, haengt sie sonst an. Robust gegenueber
# Sonderzeichen im Wert (kein sed, um Escaping-Probleme zu vermeiden).
set_env_value() {
    key="$1"
    value="$2"
    env_file="$LIBRECHAT_DIR/.env"

    if grep -q "^${key}=" "$env_file" 2>/dev/null; then
        awk -F= -v k="$key" -v v="$value" 'BEGIN{OFS="="} $1==k{$0=k"="v} {print}' "$env_file" > "${env_file}.tmp" && mv "${env_file}.tmp" "$env_file"
    else
        echo "${key}=${value}" >> "$env_file"
    fi
}
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

# --- Aktuelle SMTP-Konfiguration uebersichtlich anzeigen ---------------------
show_smtp_summary() {
    echo "  EMAIL_HOST:           $(get_env_value EMAIL_HOST)"
    echo "  EMAIL_PORT:           $(get_env_value EMAIL_PORT)"
    echo "  EMAIL_ENCRYPTION:     $(get_env_value EMAIL_ENCRYPTION)"
    echo "  EMAIL_USERNAME:       $(get_env_value EMAIL_USERNAME)"
    echo "  EMAIL_PASSWORD:       $(mask_secret "$(get_env_value EMAIL_PASSWORD)")"
    echo "  EMAIL_FROM_NAME:      $(get_env_value EMAIL_FROM_NAME)"
    echo "  EMAIL_FROM:           $(get_env_value EMAIL_FROM)"
    echo "  ALLOW_PASSWORD_RESET: $(get_env_value ALLOW_PASSWORD_RESET)"
}

# --- Willkommensnachricht (librechat.yaml: interface.customWelcome) ---------
# Bewusst spezifisch statt generischer YAML-Editor, da nur dieser eine
# Schluessel benoetigt wird und echtes YAML-Parsing in POSIX-sh zu fehleranfaellig waere.

get_welcome_message() {
    yaml_file="$LIBRECHAT_DIR/librechat.yaml"
    [ -f "$yaml_file" ] || return 1
    grep "customWelcome:" "$yaml_file" | head -n1 | sed -E "s/^[[:space:]]*customWelcome:[[:space:]]*//; s/^'//; s/'$//; s/^\"//; s/\"$//" | sed "s/''/'/g"
}

# Nutzung: set_welcome_message "Neuer Text"
set_welcome_message() {
    neuer_text="$1"
    yaml_file="$LIBRECHAT_DIR/librechat.yaml"
    [ -f "$yaml_file" ] || { error "librechat.yaml nicht gefunden unter $LIBRECHAT_DIR"; return 1; }

    if ! grep -q "customWelcome:" "$yaml_file"; then
        error "Kein 'customWelcome'-Eintrag in librechat.yaml gefunden. Bitte manuell pruefen."
        return 1
    fi

    # Einfache Anfuehrungszeichen im Text verdoppeln (YAML-Escaping fuer single-quoted strings)
    escaped=$(printf '%s' "$neuer_text" | sed "s/'/''/g")

    awk -v val="$escaped" '
        /^[[:space:]]*customWelcome:/ {
            match($0, /^[[:space:]]*/)
            indent = substr($0, RSTART, RLENGTH)
            print indent "customWelcome: '"'"'" val "'"'"'"
            next
        }
        { print }
    ' "$yaml_file" > "${yaml_file}.tmp" && mv "${yaml_file}.tmp" "$yaml_file"
}

# --- Initialisierung, die jedes Modul beim Einbinden ausfuehren soll --------
load_or_ask_librechat_path