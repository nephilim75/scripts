#!/bin/sh
# =============================================================================
# link.sh – Verbindet LibreChat mit dem Code Interpreter (Variante usnavy13).
#
# Traegt in LibreChats .env die Zeile
#   LIBRECHAT_CODE_BASEURL=https://<API-KEY>@<domain>
# ein. Der Schluessel muss vorher im Admin-Dashboard des Code Interpreters
# erzeugt werden - der MASTER_API_KEY aus der .env taugt dafuer NICHT, er
# dient nur der Anmeldung am Dashboard selbst.
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

load_or_ask_librechat_path

breadcrumb "Hauptmenue > Code Interpreter > usnavy13 > Anbindung"
heading "== Anbindung an LibreChat (usnavy13) =="
echo ""

# --- Voraussetzungen ----------------------------------------------------------
if ! ci_installed "$CI_USNAVY_DIR"; then
    warn "Der Code Interpreter (usnavy13) ist nicht installiert."
    info "Zuerst den Menuepunkt 'Installieren' waehlen."
    exit 0
fi

env_file="$LIBRECHAT_DIR/.env"
if [ ! -f "$env_file" ]; then
    error "LibreChats .env wurde nicht gefunden: $env_file"
    exit 1
fi

# --- Domain -------------------------------------------------------------------
domain="$(ci_get_domain "$CI_USNAVY_DIR" 2>/dev/null)"
if [ -z "$domain" ]; then
    info "Unter welcher Domain ist der Code Interpreter erreichbar?"
    printf "%b" "${C_BLUE}Domain (z.B. code.example.de): ${C_RESET}"
    read -r domain
    if [ -z "$domain" ]; then
        error "Ohne Domain kann die Anbindung nicht eingetragen werden. Abbruch."
        exit 1
    fi
    ci_set_domain "$CI_USNAVY_DIR" "$domain" 2>/dev/null
fi
info "Domain: $domain"
echo ""

# --- Aktueller Zustand --------------------------------------------------------
aktuell="$(get_env_value LIBRECHAT_CODE_BASEURL 2>/dev/null)"
if [ -n "$aktuell" ]; then
    rest="${aktuell#*://}"
    if [ "$rest" != "${rest#*@}" ]; then
        warn "Es ist bereits eine Anbindung eingetragen:"
        echo "  Ziel:    ${rest#*@}"
        echo "  Key:     $(mask_secret "${rest%%@*}")"
    else
        warn "Es ist bereits ein Wert eingetragen: $aktuell"
    fi
    echo ""
    if ! confirm "Soll dieser Eintrag ueberschrieben werden?"; then
        info "Abgebrochen. Es wurde nichts veraendert."
        exit 0
    fi
    echo ""
fi

# --- Anleitung ----------------------------------------------------------------
echo "So kommst du an den benoetigten Schluessel:"
echo ""
echo "  1. Admin-Dashboard oeffnen:"
echo "     https://${domain}/admin-dashboard"
echo "  2. Dort mit dem MASTER_API_KEY anmelden"
echo "     (steht unter 'Status anzeigen')"
echo "  3. Einen neuen API-Key erzeugen und kopieren"
echo ""
warn "Der neue Key wird nur einmal angezeigt - jetzt gleich kopieren."
warn "Der MASTER_API_KEY selbst ist NICHT der richtige Schluessel."
echo ""

# --- Key abfragen -------------------------------------------------------------
printf "%b" "${C_BLUE}API-Key einfuegen (leer lassen zum Abbrechen): ${C_RESET}"
read -r api_key

if [ -z "$api_key" ]; then
    info "Abgebrochen. Es wurde nichts veraendert."
    exit 0
fi

# Bequemlichkeit: wer die komplette Adresse einfuegt, soll nicht scheitern.
# Aus "https://KEY@domain" wird der Key herausgeloest.
case "$api_key" in
    *://*)
        entpackt="${api_key#*://}"
        if [ "$entpackt" != "${entpackt#*@}" ]; then
            api_key="${entpackt%%@*}"
            info "Aus der eingefuegten Adresse wurde der Schluessel uebernommen."
        fi
        ;;
esac

# Leerzeichen deuten auf einen Kopierfehler hin - das waere in der .env fatal,
# weil der Wert dort abgeschnitten wuerde.
case "$api_key" in
    *" "*|*"	"*)
        error "Der Schluessel enthaelt Leerzeichen. Vermutlich ein Kopierfehler."
        info "Bitte erneut versuchen und nur den Schluessel selbst einfuegen."
        exit 1
        ;;
esac

# Haeufigste Verwechslung: der MASTER_API_KEY wurde eingefuegt.
master_key="$(ci_env_get MASTER_API_KEY "$CI_USNAVY_DIR/.env" 2>/dev/null)"
if [ -n "$master_key" ] && [ "$api_key" = "$master_key" ]; then
    error "Das ist der MASTER_API_KEY - er dient nur der Anmeldung am Dashboard."
    info "Im Dashboard einen eigenen Schluessel fuer LibreChat erzeugen und diesen"
    info "hier eintragen."
    exit 1
fi

# --- Bestaetigen und schreiben ------------------------------------------------
neue_url="https://${api_key}@${domain}"
echo ""
info "Eingetragen wird:"
echo "  LIBRECHAT_CODE_BASEURL=https://$(mask_secret "$api_key")@${domain}"
echo ""

if ! confirm "So eintragen?"; then
    info "Abgebrochen. Es wurde nichts veraendert."
    exit 0
fi

# Sicherheitskopie, bevor an der .env geschrieben wird.
sicherung="${env_file}.bak-$(date +%Y%m%d-%H%M%S)"
if cp "$env_file" "$sicherung" 2>/dev/null; then
    info "Sicherheitskopie: $sicherung"
else
    warn "Es konnte keine Sicherheitskopie angelegt werden."
fi

set_env_value LIBRECHAT_CODE_BASEURL "$neue_url"
success "Anbindung eingetragen."

# --- Aufraeumen: LIBRECHAT_CODE_API_KEY gehoert hier nicht hin ----------------
# In der .env gewinnt die letzte Zuweisung; eine zusaetzliche Key-Zeile fuehrt
# zu schwer auffindbaren Fehlern.
if [ -n "$(get_env_value LIBRECHAT_CODE_API_KEY 2>/dev/null)" ]; then
    echo ""
    warn "In der .env steht zusaetzlich LIBRECHAT_CODE_API_KEY."
    info "Diese Zeile ist bei dieser Variante nicht vorgesehen."
    if confirm "Zeile auskommentieren?"; then
        if awk '/^LIBRECHAT_CODE_API_KEY=/{print "#" $0; next} {print}' \
              "$env_file" > "${env_file}.tmp" 2>/dev/null \
           && mv "${env_file}.tmp" "$env_file"; then
            success "Zeile auskommentiert."
        else
            rm -f "${env_file}.tmp"
            warn "Zeile konnte nicht geaendert werden - bitte von Hand pruefen."
        fi
    fi
fi

# --- Abschluss: Neustart anbieten und Ergebnis pruefen ------------------------
if offer_librechat_restart; then
    # Kurz warten: unmittelbar nach dem Start nimmt der Container noch keine
    # exec-Aufrufe an.
    sleep 3
    echo ""
    info "Pruefe, ob der Wert angekommen ist ..."
    if docker exec "$LIBRECHAT_CONTAINER" env 2>/dev/null | grep -q '^LIBRECHAT_CODE_BASEURL='; then
        success "LibreChat kennt die Anbindung."
    else
        warn "Der Wert konnte nicht bestaetigt werden."
        info "Moeglicherweise laeuft der Container noch an. Spaeter pruefbar mit:"
        info "  docker exec ${LIBRECHAT_CONTAINER} env | grep LIBRECHAT_CODE"
    fi
else
    echo ""
    info "Spaeter pruefbar mit: docker exec ${LIBRECHAT_CONTAINER} env | grep LIBRECHAT_CODE"
fi
echo ""
