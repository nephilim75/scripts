#!/bin/bash

# =============================================================================
# n8n Update Script
# =============================================================================
# Projekt:      pc-fee.com | https://pc-fee.com
# Repository:   https://github.com/nephilim75/scripts/tree/main/n8n-update
# Lizenz:       MIT License
#
# KI-Transparenz:
#   Erstellt von Claude (Anthropic) im Auftrag von pc-fee.com.
#
# Haftungsausschluss:
#   Dieses Skript wird ohne jegliche Gewährleistung bereitgestellt.
#   Die Nutzung erfolgt auf eigene Gefahr. pc-fee.com übernimmt keine
#   Haftung für Schäden, die durch die Verwendung dieses Skripts entstehen.
#
# MIT License – Copyright (c) 2026 pc-fee.com
#   Permission is hereby granted, free of charge, to any person obtaining
#   a copy of this software to use, copy, modify, merge, publish, and/or
#   distribute it, subject to the condition that this copyright notice
#   is retained in all copies or substantial portions of the software.
# =============================================================================

# -E: ERR-Trap greift auch innerhalb von Funktionen (sonst kein Rollback,
#     wenn z.B. "docker compose up" in einer Funktion fehlschlaegt)
set -Eeuo pipefail

# --- Referenz-URL dieses Skripts (fuer Fehlermeldungen/Copy-Paste) -----------
UPDATE_SCRIPT_URL="https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/update/update-n8n.sh"

# --- Defaults setzen (greifen, wenn nicht per Umgebungsvariable ueberschrieben) --
# Hinweis: COMPOSE_DIR wird bewusst NICHT aus dem Speicherort dieses Skripts
# abgeleitet, damit es per "bash <(curl -fsSL ...)" von ueberall aus laeuft.
# Der Pfad wird interaktiv abgefragt (Default /opt/n8n) bzw. kann vorab per
# COMPOSE_DIR gesetzt werden:
#   COMPOSE_DIR=/opt/n8n bash <(curl -fsSL <UPDATE_SCRIPT_URL>)
: "${MAX_BACKUPS:=5}"
: "${N8N_IMAGE:=n8nio/n8n}"
: "${RUNNERS_IMAGE:=n8nio/runners}"
# 36 x 5s = 3 Minuten: Versionen mit DB-Migrationen brauchen beim ersten
# Start oft deutlich laenger als 60s
: "${HEALTH_CHECK_RETRIES:=36}"
: "${HEALTH_CHECK_INTERVAL:=5}"
# Port, auf dem n8n INNERHALB des Containers lauscht (N8N_PORT, Default 5678)
: "${N8N_INTERNAL_PORT:=5678}"
# UID/GID des Users "node" im offiziellen n8n-Image
: "${N8N_UID:=1000}"
: "${N8N_GID:=1000}"

# --- Farben ------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Globale Variablen (COMPOSE_FILE/VERSION_FILE/DATA_DIR/BACKUP_DIR werden in
# resolve_compose_dir() befuellt, sobald der Installationsordner feststeht)
COMPOSE_DIR="${COMPOSE_DIR:-}"
COMPOSE_FILE=""
VERSION_FILE=""
DATA_DIR="${DATA_DIR:-}"
BACKUP_DIR="${BACKUP_DIR:-}"
N8N_URL=""
BACKUP_PATH=""
CURRENT_VERSION=""
TARGET_VERSION=""
LATEST_VERSION=""
FAILED_LOG=""

# --- Hilfsfunktionen ---------------------------------------------------------
print_header() {
    clear
    echo -e "${CYAN}"
    cat <<'LOGO'
               __
 _ __  __ ___ / _|___ ___   __ ___ _ __
| '_ \/ _|___|  _/ -_) -_)_/ _/ _ \ '  \
| .__/\__|   |_| \___\___(_)__\___/_|_|_|
|_|
LOGO
    echo -e "${NC}"
    echo -e "${BOLD}  n8n Update Script – powered by pc-fee.com${NC}"
    echo -e "  ${CYAN}https://pc-fee.com${NC} | ${CYAN}https://github.com/nephilim75/scripts${NC}"
    echo ""
    echo -e "  Aktualisiert eine bestehende ${BOLD}n8n${NC}-Installation auf eine neue"
    echo -e "  Version, inkl. Backup, Health Check und automatischem Rollback bei Fehlern."
    echo ""
    echo -e "────────────────────────────────────────────────────────────"
}

print_step() {
    echo ""
    echo -e "${CYAN}${BOLD}▶ $1${NC}"
}

print_ok() {
    echo -e "${GREEN}  ✔ $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}  ⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}  ✘ $1${NC}"
}

print_info() {
    echo -e "  $1"
}

print_config() {
    print_step "Konfiguration"
    print_info "COMPOSE_DIR:           ${COMPOSE_DIR}"
    print_info "DATA_DIR:              ${DATA_DIR}"
    print_info "BACKUP_DIR:            ${BACKUP_DIR}"
    print_info "MAX_BACKUPS:           ${MAX_BACKUPS}"
    print_info "N8N_IMAGE:             ${N8N_IMAGE}"
    print_info "RUNNERS_IMAGE:         ${RUNNERS_IMAGE}"
    print_info "Health Check:          im Container, Port ${N8N_INTERNAL_PORT} (/healthz/readiness)"
    print_info "HEALTH_CHECK_RETRIES:  ${HEALTH_CHECK_RETRIES}"
    print_info "HEALTH_CHECK_INTERVAL: ${HEALTH_CHECK_INTERVAL}s"
    print_info "Daten-Besitzer:        ${N8N_UID}:${N8N_GID}"
}

# --- Installationsordner ermitteln --------------------------------------------
resolve_compose_dir() {
    if [[ -z "${COMPOSE_DIR}" ]]; then
        echo ""
        echo -ne "  ${BOLD}Installationsordner deiner n8n-Installation${NC} (mit docker-compose.yml) [${CYAN}/opt/n8n${NC}]: "
        read -r compose_dir_input
        COMPOSE_DIR="${compose_dir_input:-/opt/n8n}"
    fi

    : "${DATA_DIR:=${COMPOSE_DIR}/n8n_data}"
    : "${BACKUP_DIR:=${COMPOSE_DIR}/backups}"

    COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
    VERSION_FILE="${COMPOSE_DIR}/current_version"

    if [[ ! -f "${COMPOSE_FILE}" ]]; then
        print_error "docker-compose.yml nicht gefunden unter ${COMPOSE_FILE}"
        print_info "Ist '${COMPOSE_DIR}' wirklich der Ordner deiner n8n-Installation?"
        print_info "Der Pfad laesst sich auch vorab per COMPOSE_DIR setzen, z.B.:"
        print_info "  COMPOSE_DIR=/pfad/zu/n8n bash <(curl -fsSL ${UPDATE_SCRIPT_URL})"
        exit 1
    fi

    if [[ ! -d "${DATA_DIR}" ]]; then
        print_error "Datenverzeichnis nicht gefunden: ${DATA_DIR}"
        print_info "Bitte DATA_DIR als Umgebungsvariable setzen."
        exit 1
    fi

    # Oeffentliche URL nur zur Anzeige am Ende (N8N_WEBHOOK_URL oder WEBHOOK_URL,
    # egal ob "- KEY=wert" oder "KEY: wert"). Der Health Check braucht sie nicht.
    N8N_URL="$(sed -nE "s/.*WEBHOOK_URL[[:space:]]*[=:][[:space:]]*[\"']?([^\"'[:space:]]+).*/\1/p" "${COMPOSE_FILE}" | head -1 || true)"
}

# --- Docker Hub: neueste Version ermitteln -----------------------------------
get_latest_version() {
    local image=$1
    curl -s --max-time 10 \
        "https://hub.docker.com/v2/repositories/${image}/tags?page_size=100&ordering=last_updated" \
        | grep -o '"name":"[0-9]*\.[0-9]*\.[0-9]*"' \
        | grep -o '[0-9]*\.[0-9]*\.[0-9]*' \
        | awk -F. '$1 >= 2' \
        | sort -t. -k1,1n -k2,2n -k3,3n \
        | tail -1
}

# --- Docker Hub: prüfen ob Version existiert ---------------------------------
check_image_version_exists() {
    local image=$1
    local version=$2
    curl -s --max-time 10 \
        "https://hub.docker.com/v2/repositories/${image}/tags/${version}/" \
        | grep -c '"name"' || true
}

# --- Voraussetzung: Versions-Prüfung -----------------------------------------
check_versions() {
    print_step "Prüfe verfügbare Versionen auf Docker Hub..."

    local n8n_latest runners_latest
    n8n_latest=$(get_latest_version "${N8N_IMAGE}")
    runners_latest=$(get_latest_version "${RUNNERS_IMAGE}")

    if [[ -z "${n8n_latest}" ]]; then
        print_error "Konnte neueste Version von ${N8N_IMAGE} nicht ermitteln."
        exit 1
    fi

    if [[ -z "${runners_latest}" ]]; then
        print_error "Konnte neueste Version von ${RUNNERS_IMAGE} nicht ermitteln."
        exit 1
    fi

    print_info "Neueste ${N8N_IMAGE}:     ${BOLD}${n8n_latest}${NC}"
    print_info "Neueste ${RUNNERS_IMAGE}: ${BOLD}${runners_latest}${NC}"

    if [[ "${n8n_latest}" != "${runners_latest}" ]]; then
        print_error "Versionen sind NICHT synchron (n8n: ${n8n_latest} / runners: ${runners_latest})."
        print_error "Update abgebrochen – bitte warten bis beide Images synchron sind."
        exit 1
    fi

    print_ok "Beide Images sind synchron auf Version ${n8n_latest}."
    LATEST_VERSION="${n8n_latest}"
}

# --- Aktuelle Version aus docker-compose.yml lesen ---------------------------
get_current_version() {
    grep "${N8N_IMAGE}:" "${COMPOSE_FILE}" | grep -o '[0-9]*\.[0-9]*\.[0-9]*' | head -1
}

# --- Versionseingabe ---------------------------------------------------------
ask_version() {
    local current_version
    current_version=$(get_current_version)

    if [[ -z "${current_version}" ]]; then
        print_error "Konnte die aktuelle Version nicht aus ${COMPOSE_FILE} lesen."
        print_info "Erwartet wird eine Zeile wie: image: ${N8N_IMAGE}:2.44.3"
        exit 1
    fi

    echo ""
    print_info "Aktuell installierte Version: ${BOLD}${current_version}${NC}"
    print_info "Neueste verfügbare Version:   ${BOLD}${LATEST_VERSION}${NC}"
    echo ""

    if [[ "${current_version}" == "${LATEST_VERSION}" ]]; then
        print_warn "Du bist bereits auf der neuesten Version (${current_version})."
        read -rp "  Trotzdem fortfahren? (j/N): " confirm
        if [[ ! "${confirm}" =~ ^[jJ]$ ]]; then
            print_info "Abgebrochen."
            exit 0
        fi
    fi

    echo ""
    read -rp "  Auf welche Version updaten? [${LATEST_VERSION}]: " TARGET_VERSION
    TARGET_VERSION="${TARGET_VERSION:-${LATEST_VERSION}}"

    if [[ ! "${TARGET_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_error "Ungültige Version '${TARGET_VERSION}' (erwartet z.B. 2.45.3)."
        exit 1
    fi

    print_step "Prüfe ob Version ${TARGET_VERSION} auf Docker Hub existiert..."

    local n8n_check runners_check
    n8n_check=$(check_image_version_exists "${N8N_IMAGE}" "${TARGET_VERSION}")
    runners_check=$(check_image_version_exists "${RUNNERS_IMAGE}" "${TARGET_VERSION}")

    if [[ "${n8n_check}" -eq 0 ]]; then
        print_error "${N8N_IMAGE}:${TARGET_VERSION} existiert nicht auf Docker Hub."
        exit 1
    fi

    if [[ "${runners_check}" -eq 0 ]]; then
        print_error "${RUNNERS_IMAGE}:${TARGET_VERSION} existiert nicht auf Docker Hub."
        exit 1
    fi

    print_ok "Version ${TARGET_VERSION} ist für beide Images verfügbar."
    CURRENT_VERSION="${current_version}"
}

# --- Bestätigung -------------------------------------------------------------
confirm_update() {
    echo ""
    echo -e "${YELLOW}${BOLD}  Zusammenfassung:${NC}"
    print_info "  Von Version:  ${BOLD}${CURRENT_VERSION}${NC}"
    print_info "  Auf Version:  ${BOLD}${TARGET_VERSION}${NC}"
    print_info "  Backup:       ${BACKUP_DIR}"
    print_info "  Health Check: max. $((HEALTH_CHECK_RETRIES * HEALTH_CHECK_INTERVAL))s"
    print_info "  Hinweis:      n8n ist während Backup und Update kurz nicht erreichbar."
    echo ""
    read -rp "  Update jetzt starten? (j/N): " confirm
    if [[ ! "${confirm}" =~ ^[jJ]$ ]]; then
        print_info "Abgebrochen."
        exit 0
    fi
}

# --- Images vorab laden (n8n laeuft waehrenddessen weiter) --------------------
# Wird VOR jeder Aenderung ausgefuehrt: scheitert der Download, ist noch nichts
# veraendert und n8n laeuft unbeeinflusst weiter.
pull_images() {
    print_step "Lade neue Images von Docker Hub (n8n läuft währenddessen weiter)..."
    docker pull "${N8N_IMAGE}:${TARGET_VERSION}"
    docker pull "${RUNNERS_IMAGE}:${TARGET_VERSION}"
    print_ok "Images erfolgreich geladen."
}

# --- Container stoppen (fuer ein konsistentes Backup) ------------------------
# SQLite im WAL-Modus darf nicht im laufenden Betrieb kopiert werden, sonst
# kann das Backup einen halb geschriebenen Stand enthalten.
stop_containers() {
    print_step "Stoppe n8n für ein konsistentes Backup..."
    cd "${COMPOSE_DIR}"
    docker compose stop
    print_ok "Container gestoppt."
}

# --- Fehler beim Backup: nichts veraendert, n8n wieder starten ----------------
on_backup_error() {
    trap - ERR
    set +e
    echo ""
    print_error "Backup fehlgeschlagen – an der Installation wurde nichts geändert."
    print_info "Starte n8n wieder mit Version ${CURRENT_VERSION}..."
    cd "${COMPOSE_DIR}" && docker compose start
    print_info "Bitte freien Speicherplatz prüfen: df -h ${BACKUP_DIR}"
    exit 1
}

# --- Backup ------------------------------------------------------------------
create_backup() {
    print_step "Erstelle Backup..."

    mkdir -p "${BACKUP_DIR}"
    local backup_name="n8n_backup_${CURRENT_VERSION}_$(date +%Y%m%d_%H%M%S)"
    local backup_path="${BACKUP_DIR}/${backup_name}"

    mkdir -p "${backup_path}"

    # cp -a statt cp -r: erhaelt Besitzer (UID 1000), Rechte und Zeitstempel.
    # Mit cp -r gehoert die Kopie root und n8n startet nach einem Restore
    # nicht mehr (EACCES auf /home/node/.n8n/config).
    cp -a "${DATA_DIR}" "${backup_path}/n8n_data"
    print_ok "n8n_data gesichert."

    cp -a "${COMPOSE_FILE}" "${backup_path}/docker-compose.yml"
    print_ok "docker-compose.yml gesichert."

    if [[ -f "${COMPOSE_DIR}/.env" ]]; then
        cp -a "${COMPOSE_DIR}/.env" "${backup_path}/.env"
        print_ok ".env gesichert."
    fi

    BACKUP_PATH="${backup_path}"
    print_ok "Backup erstellt: ${backup_path}"
}

# --- Alte Backups rotieren (erst NACH erfolgreichem Update) ------------------
rotate_backups() {
    local backups=()
    mapfile -t backups < <(ls -1dt "${BACKUP_DIR}"/n8n_backup_* 2>/dev/null || true)

    if (( ${#backups[@]} > MAX_BACKUPS )); then
        print_step "Rotiere alte Backups (behalte ${MAX_BACKUPS})..."
        local old
        for old in "${backups[@]:MAX_BACKUPS}"; do
            rm -rf -- "${old}"
            print_ok "Gelöscht: ${old}"
        done
    fi
}

# --- docker-compose.yml aktualisieren ----------------------------------------
update_compose_file() {
    print_step "Aktualisiere docker-compose.yml..."

    sed -i "s|${N8N_IMAGE}:${CURRENT_VERSION}|${N8N_IMAGE}:${TARGET_VERSION}|g" "${COMPOSE_FILE}"
    sed -i "s|${RUNNERS_IMAGE}:${CURRENT_VERSION}|${RUNNERS_IMAGE}:${TARGET_VERSION}|g" "${COMPOSE_FILE}"

    print_ok "docker-compose.yml aktualisiert auf Version ${TARGET_VERSION}."
}

# --- Container mit neuer Version starten -------------------------------------
start_containers() {
    print_step "Starte Container mit Version ${TARGET_VERSION}..."
    cd "${COMPOSE_DIR}"
    docker compose up -d
    print_ok "Container gestartet."
}

# --- Name des n8n-Containers ermitteln ---------------------------------------
# Sucht im Compose-Projekt den Container, der das n8n-Image nutzt
# (unabhaengig von container_name / Service-Name).
get_n8n_container() {
    (cd "${COMPOSE_DIR}" && docker compose ps -a --format '{{.Name}} {{.Image}}' 2>/dev/null) \
        | awk -v img="${N8N_IMAGE}:" 'index($2, img) == 1 { print $1; exit }' \
        || true
}

# --- Health Check (direkt im Container) --------------------------------------
# Prueft n8n innerhalb des Containers ueber 127.0.0.1 – unabhaengig von
# veroeffentlichten Ports, Reverse Proxy, DNS oder TLS. /healthz/readiness ist
# erst OK, wenn die Datenbank verbunden und migriert ist (Fallback: /healthz).
health_check() {
    print_step "Warte auf n8n Health Check (max. $((HEALTH_CHECK_RETRIES * HEALTH_CHECK_INTERVAL))s)..."

    local base="http://127.0.0.1:${N8N_INTERNAL_PORT}"
    local js="const t=()=>AbortSignal.timeout(4000);fetch('${base}/healthz/readiness',{signal:t()}).then(r=>r.status===404?fetch('${base}/healthz',{signal:t()}):r).then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

    local attempt=0 container state
    while [[ ${attempt} -lt ${HEALTH_CHECK_RETRIES} ]]; do
        attempt=$(( attempt + 1 ))

        container="$(get_n8n_container)"
        if [[ -n "${container}" ]] && docker exec "${container}" node -e "${js}" >/dev/null 2>&1; then
            print_ok "n8n ist bereit (Container: ${container})."
            return 0
        fi

        if [[ -n "${container}" ]]; then
            state="$(docker inspect -f '{{.State.Status}}' "${container}" 2>/dev/null || echo "unbekannt")"
        else
            state="nicht gefunden"
        fi
        print_info "  Versuch ${attempt}/${HEALTH_CHECK_RETRIES} – noch nicht bereit (Container: ${state}), warte ${HEALTH_CHECK_INTERVAL}s..."
        sleep "${HEALTH_CHECK_INTERVAL}"
    done

    print_error "n8n ist nach $((HEALTH_CHECK_RETRIES * HEALTH_CHECK_INTERVAL))s nicht bereit."
    return 1
}

# --- Logs der fehlgeschlagenen Version sichern -------------------------------
save_failed_logs() {
    local target_dir="${BACKUP_PATH:-${BACKUP_DIR}}"
    mkdir -p "${target_dir}"
    FAILED_LOG="${target_dir}/fehlgeschlagen_${TARGET_VERSION}_$(date +%Y%m%d_%H%M%S).log"
    (cd "${COMPOSE_DIR}" && docker compose logs --no-color --tail 1000) > "${FAILED_LOG}" 2>&1
    print_warn "Logs der fehlgeschlagenen Version gesichert: ${FAILED_LOG}"
}

# --- Rollback ----------------------------------------------------------------
rollback() {
    trap - ERR
    set +e

    echo ""
    print_error "Fehler aufgetreten – starte Rollback auf Version ${CURRENT_VERSION}..."

    # 1. Logs sichern, solange die Container noch existieren
    save_failed_logs

    # 2. Container ZUERST stoppen, damit nichts mehr in die Daten schreibt
    cd "${COMPOSE_DIR}"
    docker compose down
    print_warn "Container der Version ${TARGET_VERSION} gestoppt."

    # 3. Compose-Datei zuruecksetzen
    sed -i "s|${N8N_IMAGE}:${TARGET_VERSION}|${N8N_IMAGE}:${CURRENT_VERSION}|g" "${COMPOSE_FILE}"
    sed -i "s|${RUNNERS_IMAGE}:${TARGET_VERSION}|${RUNNERS_IMAGE}:${CURRENT_VERSION}|g" "${COMPOSE_FILE}"
    print_warn "docker-compose.yml zurückgesetzt auf ${CURRENT_VERSION}."

    # 4. Daten wiederherstellen: fehlgeschlagenen Stand beiseitelegen (nicht
    #    loeschen), Backup mit Rechten zurueckkopieren, Besitzer absichern
    local aside=""
    if [[ -n "${BACKUP_PATH}" && -d "${BACKUP_PATH}/n8n_data" ]]; then
        aside="${DATA_DIR}.fehlgeschlagen-$(date +%Y%m%d_%H%M%S)"
        if [[ -e "${DATA_DIR}" ]]; then
            mv "${DATA_DIR}" "${aside}"
            print_warn "Daten der fehlgeschlagenen Version beiseitegelegt: ${aside}"
        fi

        if cp -a "${BACKUP_PATH}/n8n_data" "${DATA_DIR}" \
            && chown -R "${N8N_UID}:${N8N_GID}" "${DATA_DIR}"; then
            print_warn "Datensicherung wiederhergestellt (Besitzer ${N8N_UID}:${N8N_GID})."
        else
            print_error "Wiederherstellen der Daten ist fehlgeschlagen!"
            print_info "  Backup:  ${BACKUP_PATH}/n8n_data"
            print_info "  Bitte manuell prüfen, bevor n8n gestartet wird."
            print_info "  Grund für den Fehlschlag: ${FAILED_LOG}"
            exit 1
        fi
    else
        print_error "Kein Backup gefunden – Daten wurden NICHT zurückgespielt."
    fi

    # 5. Alte Version starten und pruefen, ob sie wirklich laeuft
    docker compose up -d

    echo ""
    if health_check; then
        print_warn "Rollback erfolgreich – n8n läuft wieder mit Version ${CURRENT_VERSION}."
        [[ -n "${aside}" ]] && print_info "  Nach Prüfung löschbar: ${aside}"
    else
        print_error "n8n startet auch nach dem Rollback nicht! Bitte prüfen:"
        print_info "  cd ${COMPOSE_DIR} && docker compose logs --tail 100"
    fi
    print_info "  Grund für den Fehlschlag: ${FAILED_LOG}"
    echo ""
    exit 1
}

# --- Aufräumen: alte Images (Vorversion bleibt fuer Notfaelle) ---------------
cleanup_images() {
    print_step "Räume alte Docker Images auf (behalte ${TARGET_VERSION} und ${CURRENT_VERSION})..."

    local cleaned=0 image tag

    for image in "${N8N_IMAGE}" "${RUNNERS_IMAGE}"; do
        while IFS= read -r tag; do
            [[ -z "${tag}" || "${tag}" == "${TARGET_VERSION}" || "${tag}" == "${CURRENT_VERSION}" ]] && continue
            if docker rmi "${image}:${tag}" >/dev/null 2>&1; then
                print_ok "Gelöscht: ${image}:${tag}"
                cleaned=$(( cleaned + 1 ))
            fi
        done < <(docker images "${image}" --format "{{.Tag}}")
    done

    if [[ ${cleaned} -eq 0 ]]; then
        print_info "Keine alten Images gefunden."
    fi
}

# --- Abschlussbericht --------------------------------------------------------
print_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}=============================================${NC}"
    echo -e "${BOLD}${GREEN}  Update erfolgreich abgeschlossen! ✓${NC}"
    echo -e "${BOLD}${GREEN}=============================================${NC}"
    print_info "  Version:  ${CURRENT_VERSION} → ${TARGET_VERSION}"
    print_info "  Backup:   ${BACKUP_PATH}"
    [[ -n "${N8N_URL}" ]] && print_info "  URL:      ${N8N_URL}"
    echo ""
}

# --- Hauptprogramm -----------------------------------------------------------
main() {
    print_header
    resolve_compose_dir
    print_config
    check_versions
    ask_version
    confirm_update

    # Bis hier ist nichts veraendert, n8n laeuft weiter
    pull_images

    # Backup bei gestopptem n8n; bei Fehler n8n unveraendert wieder starten
    trap 'on_backup_error' ERR
    stop_containers
    create_backup

    # Ab hier fuehrt jeder Fehler zum Rollback
    trap 'rollback' ERR

    update_compose_file
    start_containers

    if ! health_check; then
        rollback
    fi

    trap - ERR

    echo "${TARGET_VERSION}" > "${VERSION_FILE}"
    rotate_backups
    cleanup_images
    print_summary
}

main "$@"
