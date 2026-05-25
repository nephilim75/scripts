#!/bin/bash

# =============================================================================
# n8n Update Script
# =============================================================================
# Projekt:      pc-fee.com | https://pc-fee.com
# Repository:   https://github.com/nephilim75/scripts/tree/main/n8n-update
# Lizenz:       MIT License
#
# KI-Transparenz:
#   Dieses Skript wurde mit Unterstützung von KI erstellt.
#   Modelle: Claude Opus 4.6 / Claude Sonnet 4.6 (Anthropic)
#   Agent:   Nils Weber (n8n Automation Architect, pc-fee.com)
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

set -euo pipefail

# --- Konfiguration aus .env laden --------------------------------------------
ENV_FILE="$(dirname "$0")/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
    echo "Fehler: .env nicht gefunden unter ${ENV_FILE}"
    echo "Bitte .env.example kopieren und anpassen: cp .env.example .env"
    exit 1
fi
source "${ENV_FILE}"

# --- Farben ------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Abgeleitete Variablen ---------------------------------------------------
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
VERSION_FILE="${COMPOSE_DIR}/current_version"

# Globale Variablen
BACKUP_PATH=""
CURRENT_VERSION=""
TARGET_VERSION=""
LATEST_VERSION=""

# --- Hilfsfunktionen ---------------------------------------------------------
print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}=============================================${NC}"
    echo -e "${BOLD}${BLUE}  n8n Update Script | pc-fee.com${NC}"
    echo -e "${BOLD}${BLUE}=============================================${NC}"
    echo ""
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
    grep "n8nio/n8n:" "${COMPOSE_FILE}" | grep -o '[0-9]*\.[0-9]*\.[0-9]*' | head -1
}

# --- Versionseingabe ---------------------------------------------------------
ask_version() {
    local current_version
    current_version=$(get_current_version)

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
    print_info "  Von Version: ${BOLD}${CURRENT_VERSION}${NC}"
    print_info "  Auf Version: ${BOLD}${TARGET_VERSION}${NC}"
    print_info "  Backup:      ${BACKUP_DIR}"
    echo ""
    read -rp "  Update jetzt starten? (j/N): " confirm
    if [[ ! "${confirm}" =~ ^[jJ]$ ]]; then
        print_info "Abgebrochen."
        exit 0
    fi
}

# --- Backup ------------------------------------------------------------------
create_backup() {
    print_step "Erstelle Backup..."

    mkdir -p "${BACKUP_DIR}"
    local backup_name="n8n_backup_${CURRENT_VERSION}_$(date +%Y%m%d_%H%M%S)"
    local backup_path="${BACKUP_DIR}/${backup_name}"

    mkdir -p "${backup_path}"

    # n8n Daten sichern
    cp -r "${DATA_DIR}" "${backup_path}/n8n_data"
    print_ok "n8n_data gesichert."

    # docker-compose.yml sichern
    cp "${COMPOSE_FILE}" "${backup_path}/docker-compose.yml"
    print_ok "docker-compose.yml gesichert."

    # .env sichern
    if [[ -f "${COMPOSE_DIR}/.env" ]]; then
        cp "${COMPOSE_DIR}/.env" "${backup_path}/.env"
        print_ok ".env gesichert."
    fi

    print_ok "Backup erstellt: ${backup_path}"

    local backup_count
    backup_count=$(ls -d "${BACKUP_DIR}"/n8n_backup_* 2>/dev/null | wc -l)

    if [[ "${backup_count}" -gt "${MAX_BACKUPS}" ]]; then
        local to_delete=$(( backup_count - MAX_BACKUPS ))
        print_info "Rotiere alte Backups (behalte ${MAX_BACKUPS}, lösche ${to_delete})..."
        ls -dt "${BACKUP_DIR}"/n8n_backup_* | tail -"${to_delete}" | xargs rm -rf
        print_ok "Alte Backups bereinigt."
    fi

    BACKUP_PATH="${backup_path}"
}

# --- docker-compose.yml aktualisieren ----------------------------------------
update_compose_file() {
    print_step "Aktualisiere docker-compose.yml..."

    sed -i "s|${N8N_IMAGE}:${CURRENT_VERSION}|${N8N_IMAGE}:${TARGET_VERSION}|g" "${COMPOSE_FILE}"
    sed -i "s|${RUNNERS_IMAGE}:${CURRENT_VERSION}|${RUNNERS_IMAGE}:${TARGET_VERSION}|g" "${COMPOSE_FILE}"

    print_ok "docker-compose.yml aktualisiert auf Version ${TARGET_VERSION}."
}

# --- Images pullen -----------------------------------------------------------
pull_images() {
    print_step "Lade neue Images von Docker Hub..."
    cd "${COMPOSE_DIR}"
    docker compose pull
    print_ok "Images erfolgreich geladen."
}

# --- Container neu starten ---------------------------------------------------
restart_containers() {
    print_step "Starte Container neu..."
    cd "${COMPOSE_DIR}"
    docker compose down
    docker compose up -d
    print_ok "Container gestartet."
}

# --- Health Check ------------------------------------------------------------
health_check() {
    print_step "Warte auf n8n Health Check (max. $((HEALTH_CHECK_RETRIES * HEALTH_CHECK_INTERVAL))s)..."

    local attempt=0
    while [[ ${attempt} -lt ${HEALTH_CHECK_RETRIES} ]]; do
        attempt=$(( attempt + 1 ))
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${HEALTH_CHECK_URL}" || echo "000")

        if [[ "${http_code}" == "200" || "${http_code}" == "302" || "${http_code}" == "301" ]]; then
            print_ok "n8n antwortet (HTTP ${http_code}) – läuft!"
            return 0
        fi

        print_info "  Versuch ${attempt}/${HEALTH_CHECK_RETRIES} – HTTP ${http_code}, warte ${HEALTH_CHECK_INTERVAL}s..."
        sleep "${HEALTH_CHECK_INTERVAL}"
    done

    print_error "n8n antwortet nicht nach $((HEALTH_CHECK_RETRIES * HEALTH_CHECK_INTERVAL))s."
    return 1
}

# --- Rollback ----------------------------------------------------------------
rollback() {
    echo ""
    print_error "Fehler aufgetreten – starte Rollback auf Version ${CURRENT_VERSION}..."

    sed -i "s|${N8N_IMAGE}:${TARGET_VERSION}|${N8N_IMAGE}:${CURRENT_VERSION}|g" "${COMPOSE_FILE}"
    sed -i "s|${RUNNERS_IMAGE}:${TARGET_VERSION}|${RUNNERS_IMAGE}:${CURRENT_VERSION}|g" "${COMPOSE_FILE}"
    print_warn "docker-compose.yml zurückgesetzt auf ${CURRENT_VERSION}."

    if [[ -n "${BACKUP_PATH}" && -d "${BACKUP_PATH}" ]]; then
        rm -rf "${DATA_DIR}"
        cp -r "${BACKUP_PATH}/n8n_data" "${DATA_DIR}"
        print_warn "Datensicherung wiederhergestellt."
    fi

    cd "${COMPOSE_DIR}"
    docker compose down
    docker compose up -d
    print_warn "Container mit Version ${CURRENT_VERSION} gestartet."

    echo ""
    print_error "Rollback abgeschlossen. Bitte Status manuell prüfen:"
    print_info "  docker compose -f ${COMPOSE_FILE} logs -f"
    echo ""
}

# --- Aufräumen: alte Images --------------------------------------------------
cleanup_images() {
    print_step "Räume alte Docker Images auf..."

    local cleaned=0

    while IFS= read -r tag; do
        [[ -z "${tag}" || "${tag}" == "${TARGET_VERSION}" ]] && continue
        if docker rmi "${N8N_IMAGE}:${tag}" 2>/dev/null; then
            print_ok "Gelöscht: ${N8N_IMAGE}:${tag}"
            cleaned=$(( cleaned + 1 ))
        fi
    done < <(docker images "${N8N_IMAGE}" --format "{{.Tag}}")

    while IFS= read -r tag; do
        [[ -z "${tag}" || "${tag}" == "${TARGET_VERSION}" ]] && continue
        if docker rmi "${RUNNERS_IMAGE}:${tag}" 2>/dev/null; then
            print_ok "Gelöscht: ${RUNNERS_IMAGE}:${tag}"
            cleaned=$(( cleaned + 1 ))
        fi
    done < <(docker images "${RUNNERS_IMAGE}" --format "{{.Tag}}")

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
    print_info "  URL:      ${HEALTH_CHECK_URL}"
    echo ""
}

# --- Hauptprogramm -----------------------------------------------------------
main() {
    print_header
    check_versions
    ask_version
    confirm_update
    create_backup

    trap 'rollback' ERR

    update_compose_file
    pull_images
    restart_containers

    if ! health_check; then
        rollback
        exit 1
    fi

    trap - ERR

    cleanup_images
    echo "${TARGET_VERSION}" > "${VERSION_FILE}"
    print_summary
}

main "$@"
