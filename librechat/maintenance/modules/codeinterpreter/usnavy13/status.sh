#!/bin/sh
# =============================================================================
# status.sh – Zeigt den Zustand des Code Interpreters (Variante usnavy13).
#
# Ersetzt die Abschlussanzeige des Installationsskripts, die nach dem
# Schliessen des Terminals nicht mehr erreichbar ist: Domain, Adressen,
# MASTER_API_KEY und der Zustand der Anbindung an LibreChat.
# Rein lesend - mit einer Ausnahme: ist die Domain unbekannt, wird einmalig
# danach gefragt und sie wird gemerkt.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

load_or_ask_librechat_path

breadcrumb "Hauptmenue > Code Interpreter > usnavy13 > Status"
heading "== Code Interpreter: Status (usnavy13) =="
echo ""

# --- Installiert? -------------------------------------------------------------
if ! ci_installed "$CI_USNAVY_DIR"; then
    warn "Der Code Interpreter (usnavy13) ist nicht installiert."
    info "Installationspfad waere: $CI_USNAVY_DIR"
    info "Zum Einrichten den Menuepunkt 'Installieren' waehlen."
    exit 0
fi

success "Installiert unter: $CI_USNAVY_DIR"
echo ""

# --- Container ----------------------------------------------------------------
heading "-- Dienste --"
if ! ci_compose "$CI_USNAVY_DIR" ps 2>/dev/null; then
    error "Der Zustand der Container konnte nicht ermittelt werden."
    info "Laeuft Docker? Pruefen mit: docker ps"
fi
echo ""

# --- Domain -------------------------------------------------------------------
heading "-- Adressen --"
domain="$(ci_get_domain "$CI_USNAVY_DIR" 2>/dev/null)"

if [ -z "$domain" ]; then
    # Die Domain wird vom Installationsskript nur angezeigt, nicht gespeichert.
    # Einmalig nachfragen und merken, damit sie kuenftig hier steht.
    warn "Die Domain ist nicht bekannt."
    echo "Sie wurde bei der Installation angegeben, aber nirgends gespeichert."
    echo "Wenn du sie eintraegst, merkt sich das Tool sie ab jetzt."
    echo ""
    printf "%b" "${C_BLUE}Domain (z.B. code.example.de, leer lassen zum Ueberspringen): ${C_RESET}"
    read -r eingabe
    if [ -n "$eingabe" ]; then
        if ci_set_domain "$CI_USNAVY_DIR" "$eingabe"; then
            domain="$eingabe"
            success "Domain gemerkt."
        else
            warn "Domain konnte nicht gespeichert werden (Schreibrechte pruefen)."
            domain="$eingabe"
        fi
    fi
    echo ""
fi

if [ -n "$domain" ]; then
    echo "Domain:           $domain"
    echo "Admin-Dashboard:  https://${domain}/admin-dashboard"
    echo "Health-Check:     https://${domain}/health"
else
    info "Ohne Domain koennen die Adressen nicht angezeigt werden."
fi
echo ""

# --- MASTER_API_KEY -----------------------------------------------------------
heading "-- Zugang zum Admin-Dashboard --"
master_key="$(ci_env_get MASTER_API_KEY "$CI_USNAVY_DIR/.env" 2>/dev/null)"

if [ -n "$master_key" ]; then
    echo "MASTER_API_KEY:   $(mask_secret "$master_key")"
    echo "Steht in:         $CI_USNAVY_DIR/.env"
    echo ""
    info "Damit meldet man sich am Admin-Dashboard an."
    warn "Das ist NICHT der Schluessel fuer LibreChat - den legt man im"
    warn "Dashboard separat an."
    echo ""
    if confirm "Den MASTER_API_KEY vollstaendig anzeigen?"; then
        echo ""
        printf "%b\n" "${C_BOLD}${master_key}${C_RESET}"
    fi
else
    warn "MASTER_API_KEY konnte nicht gelesen werden."
    info "Erwartet in: $CI_USNAVY_DIR/.env (nur fuer root lesbar)"
fi
echo ""

# --- Anbindung an LibreChat ---------------------------------------------------
heading "-- Anbindung an LibreChat --"
baseurl="$(get_env_value LIBRECHAT_CODE_BASEURL 2>/dev/null)"

if [ -z "$baseurl" ]; then
    warn "Nicht eingerichtet - LibreChat nutzt den Code Interpreter noch nicht."
    info "Menuepunkt 'Anbindung an LibreChat' erledigt das."
else
    # Form: https://<KEY>@domain - den Key nicht im Klartext ausgeben.
    rest="${baseurl#*://}"
    if [ "$rest" != "${rest#*@}" ]; then
        lc_key="${rest%%@*}"
        lc_host="${rest#*@}"
        success "Eingerichtet."
        echo "Ziel:             $lc_host"
        echo "API-Key:          $(mask_secret "$lc_key")"
    else
        warn "Eingetragen, aber ohne API-Key im Format https://<KEY>@domain:"
        echo "$baseurl"
        info "In dieser Form wird die Verbindung vermutlich abgelehnt."
    fi

    # Haeufige Stolperstelle: ein angehaengtes /v1 gehoert hier nicht hin.
    case "$baseurl" in
        */v1|*/v1/)
            echo ""
            warn "Die Adresse endet auf /v1 - das gehoert hier nicht hin."
            ;;
    esac

    # Zweite Stolperstelle: eine zusaetzliche Key-Zeile, die es nicht geben soll.
    if [ -n "$(get_env_value LIBRECHAT_CODE_API_KEY 2>/dev/null)" ]; then
        echo ""
        warn "In LibreChats .env steht zusaetzlich LIBRECHAT_CODE_API_KEY."
        info "Diese Zeile ist hier nicht vorgesehen und sollte entfernt werden."
    fi
fi
echo ""
