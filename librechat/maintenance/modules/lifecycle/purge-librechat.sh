root@my-vps:/opt/admin-lc/modules/lifecycle# cat purge-librechat.sh
#!/usr/bin/env bash
# purge-librechat.sh
# Entfernt ausschließlich das LibreChat-Compose-Projekt unter /opt/librechat.
# Andere Container/Images auf dem Host bleiben unangetastet.

set -euo pipefail

# --- Farben -----------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${CYAN}[i]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
step() { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }

START_DIR="$(pwd)"
PROJECT_DIR="/opt/librechat"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# Schreib-/löschender Befehl: im Dry-Run nur anzeigen, sonst ausführen.
run() {
    if (( DRY_RUN )); then
        echo -e "${YELLOW}   [DRY-RUN]${NC} $*"
    else
        "$@"
    fi
}
# Reine Reads immer real ausführen (Image-Erkennung, cd).
fetch() { "$@"; }

trap 'err "Abbruch in Zeile $LINENO – Aufräumen nicht vollständig."' ERR

step "LibreChat wird vollständig entfernt ${DRY_RUN:+(DRY-RUN)}"
echo -e "${YELLOW}Gestartet in:${NC} ${START_DIR}"
echo -e "${YELLOW}Modus:        ${NC} $( (( DRY_RUN )) && echo "DRY-RUN (nichts wird gelöscht)" || echo "LIVE" )"

[[ -d "${PROJECT_DIR}" ]] || { err "Verzeichnis ${PROJECT_DIR} existiert nicht – Abbruch."; exit 1; }
fetch cd "${PROJECT_DIR}"

# --- 1) Image-Referenzen aus der Compose-Config ziehen ---------------------
# 'docker compose images -q' listet nur laufende Container → nach 'down' oder
# ohne je gestartetes Projekt leer. 'docker compose config --images' liefert
# die Referenzen unabhängig vom Container-Status.
step "1/5  Erfasse Image-Referenzen aus der Compose-Config"
mapfile -t IMAGE_REFS < <(fetch docker compose config --images 2>/dev/null | sort -u || true)

# Parallele Arrays: IMAGE_NAMES[i] ↔ IMAGE_IDS[i] (sortiert nach ID).
IMAGE_NAMES=()
IMAGE_IDS=()
if (( ${#IMAGE_REFS[@]} > 0 )); then
    for ref in "${IMAGE_REFS[@]}"; do
        while IFS=$'\t' read -r id repo tag; do
            [[ -z "$id" ]] && continue
            if [[ "$repo" == "<none>" ]]; then
                name="<dangling:${id:0:12}>"
            else
                name="${repo}:${tag}"
            fi
            if [[ " ${IMAGE_IDS[*]} " != *" $id "* ]]; then
                IMAGE_NAMES+=("$name")
                IMAGE_IDS+=("$id")
            fi
        done < <(fetch docker images --format $'\t''{{.ID}}\t{{.Repository}}\t{{.Tag}}' "$ref" 2>/dev/null || true)
    done
fi

# --- 2) Aktive User-Bestätigung --------------------------------------------
step "2/5  Bestätigung zur Image-Löschung"
if (( ${#IMAGE_IDS[@]} == 0 )); then
    warn "Keine projekt-eigenen, lokal vorhandenen Images gefunden."
else
    info "Diese ${#IMAGE_IDS[@]} Image(s) sind lokal vorhanden und würden entfernt werden:"
    echo
    printf '   %-70s  %s\n' "REPO:TAG" "IMAGE ID"
    printf '   %-70s  %s\n' "$(printf '%.0s-' {1..70})" "$(printf '%.0s-' {1..12})"
    for i in "${!IMAGE_IDS[@]}"; do
        printf '   %-70s  %s\n' "${IMAGE_NAMES[$i]}" "${IMAGE_IDS[$i]:0:12}"
    done
    echo
    echo -e "${YELLOW}${BOLD}ACHTUNG:${NC} Sollten Tags außerhalb dieses Projekts referenziert werden"
    echo -e "         (z. B. gemeinsam genutzte Basis-Images), wirkt die Löschung im"
    echo -e "         Image-Cache des Hosts – Container, die diese Images halten, sind"
    echo -e "         allerdings bereits durch 'down -v' entfernt."
    echo
    if (( DRY_RUN )); then
        warn "DRY-RUN: keine Bestätigung erforderlich – weiter als ob 'j' gewählt."
    else
        read -r -p "$(echo -e "${YELLOW}[?]${NC} Wirklich diese ${#IMAGE_IDS[@]} Image(s) löschen? [j/N]: ")" ANSWER
        case "${ANSWER,,}" in
            j|ja|y|yes) : ;;
            *)
                warn "Image-Löschung übersprungen – es werden nur Container/Volumes/Ordner entfernt."
                IMAGE_NAMES=()
                IMAGE_IDS=()
                ;;
        esac
    fi
fi

# --- 3) Compose stoppen (separate Aktion) ----------------------------------
step "3/5  docker compose down -v"
run docker compose down -v
(( DRY_RUN )) || ok "Container & Volumes dieses Projekts entfernt"

# --- 4) Images entfernen (separate Aktion) --------------------------------
step "4/5  Images entfernen"
if (( ${#IMAGE_IDS[@]} > 0 )); then
    run docker rmi "${IMAGE_IDS[@]}"
    (( DRY_RUN )) || ok "Images entfernt"
else
    warn "Keine Images zum Löschen – übersprungen."
fi

# --- 5) Projektordner löschen ---------------------------------------------
step "5/5  ${PROJECT_DIR} wird gelöscht"
fetch cd /opt
run rm -rf "${PROJECT_DIR}"
(( DRY_RUN )) || ok "Ordner entfernt"

# --- 6) Zurück nach ~ ------------------------------------------------------
fetch cd ~
(( DRY_RUN )) || ok "Wechsel zurück nach ~"

echo
if (( DRY_RUN )); then
    echo -e "${YELLOW}${BOLD}✓ DRY-RUN beendet – es wurde NICHTS gelöscht.${NC}"
else
    echo -e "${GREEN}${BOLD}✔ Aufräumen erfolgreich abgeschlossen.${NC}"
fi
echo -e "${CYAN}Gestartet in:${NC} ${START_DIR}"
echo -e "${CYAN}Beendet in:  ${NC} $(pwd)"
