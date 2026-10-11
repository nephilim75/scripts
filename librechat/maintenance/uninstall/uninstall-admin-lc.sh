#!/usr/bin/env bash
# =============================================================================
# LibreChat Admin-Tool Uninstaller
# -----------------------------------------------------------------------------
# SCOPE - entfernt ausschliesslich das Admin-Tool (Standard: /opt/admin-lc):
#   - das Installationsverzeichnis des Admin-Tools inkl. dessen config.sh
#   - die vom Admin-Tool angelegte Datei .admin-lc-info im Code-Interpreter-
#     Ordner /opt/LibreCodeInterpreter (nur diese eine Datei)
#   - optional: Reste des Selbst-Updates in /tmp
#       (admin-lc-update.*, admin-lc-repo.*, admin-lc-vor-update-*.tgz)
#
# NICHT angefasst werden:
#   - LibreChat (Verzeichnis, Container, Volumes, Daten, Backups)
#   - das gemeinsame Docker-Netzwerk (shared_proxy), Nginx Proxy Manager
#   - Code-Interpreter-Installationen (bis auf die oben genannte Datei)
#   - git, Docker und sonstige Pakete
#
# ACHTUNG: Das Loeschen des Admin-Tool-Verzeichnisses ist unwiderruflich.
#   Eine dort liegende config.sh (hinterlegter LibreChat-Pfad) geht verloren.
#   Empfehlung: zuerst mit --dry-run ansehen, was entfernt wuerde.
#   Das Admin-Tool (menu.sh) vorher beenden.
# -----------------------------------------------------------------------------
# Aufruf:
#   bash uninstall-admin-lc.sh [--dir <pfad>] [--dry-run] [--yes]
#
#   --dir <pfad>   Verzeichnis des Admin-Tools (Default-Vorschlag: /opt/admin-lc)
#   --dry-run      Nur anzeigen, was entfernt wuerde - nichts wird veraendert
#   --yes, -y      Rueckfragen automatisch bestaetigen (auch: ASSUME_YES=1)
#   --help, -h     Hilfe
#
# Eingaben kommen von /dev/tty, nicht von stdin. Ohne Terminal und ohne --yes
# wird nichts geloescht.
# -----------------------------------------------------------------------------
# AI-Transparenzhinweis:
# Dieses Skript wurde unter Einsatz von KI-Modellen (Claude Sonnet 5.5,
# Anthropic) erstellt. Vor produktivem Einsatz eigenverantwortlich pruefen.
# =============================================================================

set -Eeuo pipefail
trap 'rc=$?; printf "\033[0;31m[FEHLER]\033[0m Abbruch in Zeile %s (Exit %s).\n" "${LINENO}" "${rc}" >&2; exit "${rc}"' ERR

# ───────────────────────────── Farben & Helpers ─────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { printf '%b\n' "${CYAN}[INFO]${RESET} $*"; }
success() { printf '%b\n' "${GREEN}[OK]${RESET} $*"; }
warn()    { printf '%b\n' "${YELLOW}[WARN]${RESET} $*"; }
error()   { printf '%b\n' "${RED}[FEHLER]${RESET} $*"; }
die()     { error "$*"; exit 1; }

# ───────────────────────────── Konstanten ─────────────────────────────
readonly DEFAULT_ADMIN_DIR="/opt/admin-lc"
readonly DEFAULT_LC_DIR="/opt/librechat"
readonly CI_DIRS=("/opt/LibreCodeInterpreter" "/opt/avila-code-interpreter")
readonly CI_INFO_FILE=".admin-lc-info"
readonly CI_USNAVY_DIR="/opt/LibreCodeInterpreter"   # wie in lib/common.sh des Admin-Tools
readonly CI_INFO_PATH="${CI_USNAVY_DIR}/${CI_INFO_FILE}"
readonly INSTALL_ONELINER='bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/maintenance/install/install-admin-lc.sh)'
readonly SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"

ASSUME_YES="${ASSUME_YES:-0}"
DRY_RUN=0
ADMIN_DIR_ARG=""
ADMIN_DIR=""

usage() {
  cat <<EOF
Aufruf: $0 [--dir <pfad>] [--dry-run] [--yes]

  --dir <pfad>   Verzeichnis des Admin-Tools (Default-Vorschlag: ${DEFAULT_ADMIN_DIR})
  --dry-run      Nur anzeigen, was entfernt wuerde - nichts wird veraendert
  --yes, -y      Rueckfragen automatisch bestaetigen (auch ASSUME_YES=1)
  --help, -h     Diese Hilfe

Entfernt NUR das Admin-Tool. LibreChat, Docker-Netzwerke und Code-Interpreter
bleiben unangetastet.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)     [[ $# -ge 2 ]] || die "--dir benoetigt einen Pfad."; ADMIN_DIR_ARG="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y)  ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         die "Unbekannte Option: $1 (siehe --help)" ;;
  esac
done

# ───────────────────────────── Eingabe (immer von /dev/tty) ─────────────────────────────
HAVE_TTY=0
if [[ -r /dev/tty ]] && { : </dev/tty; } 2>/dev/null; then HAVE_TTY=1; fi

if [[ "$HAVE_TTY" -ne 1 && "$ASSUME_YES" != "1" && "$DRY_RUN" -ne 1 ]]; then
  die "Kein Terminal fuer Rueckfragen verfuegbar. Interaktiv starten, mit --dry-run ansehen oder mit --yes bestaetigen. Es wurde nichts geloescht."
fi

# ask "Frage" "Default" -> Ergebnis in $REPLY_VAL
ask() {
  local prompt="$1" def="${2:-}" a=""
  if [[ "$HAVE_TTY" -ne 1 ]]; then REPLY_VAL="$def"; return 0; fi
  if [[ -n "$def" ]]; then
    read -rp "$(printf '%b' "${BOLD}${prompt} [${def}]:${RESET} ")" a </dev/tty || a=""
  else
    read -rp "$(printf '%b' "${BOLD}${prompt}:${RESET} ")" a </dev/tty || a=""
  fi
  REPLY_VAL="${a:-$def}"
}

# ask_yn "Frage" -> 0 = Ja, 1 = Nein (Default: Nein)
ask_yn() {
  local a=""
  if [[ "$ASSUME_YES" == "1" ]]; then return 0; fi
  read -rp "$(printf '%b' "${BOLD}$1 [j/N]:${RESET} ")" a </dev/tty || a=""
  [[ "$a" =~ ^[JjYy]$ ]]
}

# ───────────────────────────── sudo-Erkennung (ruft sudo noch NICHT auf) ─────────────────────────────
SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  elif [[ "$DRY_RUN" -ne 1 ]]; then
    die "Bitte als root ausfuehren oder sudo installieren."
  fi
fi

is_safe_path() { [[ "$1" =~ ^/[A-Za-z0-9._@+/-]+$ ]]; }

# Prueft, ob $1 wirklich ein Admin-Tool-Verzeichnis ist. Setzt ADMIN_DIR.
# Erkennung ueber Marker (menu.sh + lib/common.sh), nicht ueber den Ordnernamen.
check_admin_dir() {
  local c="${1%/}" r
  if [[ -z "$c" ]] || ! is_safe_path "$c"; then
    warn "Bitte einen absoluten Pfad ohne Leer- und Sonderzeichen angeben."
    return 1
  fi
  if [[ ! -d "$c" ]]; then warn "'$c' existiert nicht."; return 1; fi
  if [[ -L "$c" ]]; then warn "'$c' ist ein Symlink - wird aus Sicherheitsgruenden nicht unterstuetzt."; return 1; fi
  r="$(readlink -f -- "$c")"
  if [[ ! "$r" =~ ^/[^/]+/[^/]+ ]]; then
    warn "'$r' ist zu weit oben im Dateisystem, um ein Admin-Tool-Ordner zu sein."
    return 1
  fi
  if [[ ! -f "$r/menu.sh" || ! -f "$r/lib/common.sh" ]] || ! grep -q "LibreChat-Admin-Tool" "$r/menu.sh" 2>/dev/null; then
    warn "In '$r' wurde kein LibreChat-Admin-Tool erkannt (menu.sh/lib/common.sh fehlen oder passen nicht)."
    return 1
  fi
  if [[ -f "$r/docker-compose.yml" ]]; then
    warn "In '$r' liegt eine docker-compose.yml - das sieht nach einer LibreChat-Installation aus. Es wird nichts geloescht."
    return 1
  fi
  case "$(readlink -f -- "$SCRIPT_PATH" 2>/dev/null || true)" in
    "$r"/*)
      warn "Dieses Skript liegt selbst in '$r'. Bitte von ausserhalb starten (z. B. Kopie nach /root)."
      return 1 ;;
  esac
  ADMIN_DIR="$r"
  return 0
}

# ───────────────────────────── Banner ─────────────────────────────
# 'clear' scheitert ohne brauchbares TERM (z.B. im Cron) - darf nicht abbrechen.
clear 2>/dev/null || true
printf '%b' "${CYAN}"
cat <<'LOGO'
                  __
 _ __   ___      / _| ___  ___   ___ ___  _ __ ___
| '_ \ / __|____| |_ / _ \/ _ \ / __/ _ \| '_ ` _ \
| |_) | (_|_____|  _|  __/  __/| (_| (_) | | | | | |
| .__/ \___|    |_|  \___|\___(_)___\___/|_| |_| |_|
|_|
LOGO
printf '%b\n' "${RESET}"
printf '%b\n' "${BOLD} LibreChat Admin-Tool Uninstall – powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo "Macht die Installation aus install-admin-lc.sh rueckgaengig:"
echo "entfernt NUR das Admin-Tool. LibreChat, Docker-Netzwerke und"
echo "Code-Interpreter bleiben unangetastet."
[[ "$DRY_RUN" -eq 1 ]] && printf '%b\n' "${YELLOW}Testlauf (--dry-run): Es wird nichts veraendert.${RESET}"
echo "------------------------------------------------------------"

# ───────────────── Schritt 1: Admin-Tool finden ─────────────────
printf '\n%b\n' "${BOLD}Schritt 1: Admin-Tool suchen${RESET}"
echo "------------------------------------------------------------"

CANDIDATE="${ADMIN_DIR_ARG:-$DEFAULT_ADMIN_DIR}"
while true; do
  if [[ -d "$CANDIDATE" || -n "$ADMIN_DIR_ARG" ]] && check_admin_dir "$CANDIDATE"; then
    success "Admin-Tool gefunden unter: $ADMIN_DIR"
    break
  fi
  [[ "$HAVE_TTY" -eq 1 ]] || die "Kein Admin-Tool unter '$CANDIDATE' gefunden. Es wurde nichts geloescht."
  warn "Unter '$CANDIDATE' wurde kein Admin-Tool gefunden."
  ask_yn "Anderen Pfad eingeben?" || die "Abbruch auf Wunsch. Es wurde nichts geloescht."
  ask "Pfad zum Admin-Tool" ""
  CANDIDATE="$REPLY_VAL"
  ADMIN_DIR_ARG="$CANDIDATE"
done

# ───────────────── Schritt 2: Inventar ─────────────────
printf '\n%b\n' "${BOLD}Schritt 2: Was wuerde entfernt?${RESET}"
echo "------------------------------------------------------------"

SIZE="$(du -sh -- "$ADMIN_DIR" 2>/dev/null | cut -f1 || true)"
FILES="$(find "$ADMIN_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')"
info "Verzeichnis: $ADMIN_DIR  (${SIZE:-?}, ${FILES} Dateien)"
echo "Inhalt (oberste Ebene):"
find "$ADMIN_DIR" -mindepth 1 -maxdepth 1 -printf '  - %f\n' 2>/dev/null | sort

# config.sh NICHT sourcen (wuerde Code ausfuehren), nur den Wert auslesen
LC_FROM_CONFIG=""
if [[ -f "$ADMIN_DIR/config.sh" ]]; then
  LC_FROM_CONFIG="$(grep -m1 '^LIBRECHAT_DIR=' "$ADMIN_DIR/config.sh" 2>/dev/null | sed 's/^[^=]*=//; s/^"//; s/"$//' || true)"
  warn "config.sh liegt dort und geht mit verloren (LibreChat-Pfad darin: ${LC_FROM_CONFIG:-<leer>})."
fi

INFO_FILE_FOUND=0
if [[ -f "$CI_INFO_PATH" && ! -L "$CI_INFO_PATH" ]]; then
  INFO_FILE_FOUND=1
  echo ""
  echo "Vom Admin-Tool im Code-Interpreter-Ordner angelegte Datei (wird mit entfernt):"
  echo "  - $CI_INFO_PATH"
fi

TMP_LEFTOVERS=()
while IFS= read -r -d '' f; do TMP_LEFTOVERS+=("$f"); done < <(
  find /tmp -maxdepth 1 ! -type l \( -name 'admin-lc-update.*' -o -name 'admin-lc-repo.*' -o -name 'admin-lc-vor-update-*.tgz' \) -print0 2>/dev/null
)
if [[ ${#TMP_LEFTOVERS[@]} -gt 0 ]]; then
  echo ""
  echo "Reste des Selbst-Updates in /tmp (separat bestaetigt):"
  printf '  - %s\n' "${TMP_LEFTOVERS[@]}"
fi

echo ""
echo "Bleibt unangetastet:"
LC_SHOW="${LC_FROM_CONFIG:-$DEFAULT_LC_DIR}"
if [[ -f "$LC_SHOW/docker-compose.yml" ]]; then
  echo "  - LibreChat unter $LC_SHOW (Container, Daten, Backups)"
else
  echo "  - LibreChat (nicht beruehrt)"
fi
echo "  - Docker-Netzwerk shared_proxy und Nginx Proxy Manager"
for d in "${CI_DIRS[@]}"; do
  [[ -d "$d" ]] && echo "  - Code-Interpreter unter $d"
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo ""
  echo "------------------------------------------------------------"
  echo -e "${YELLOW}${BOLD} DRY-RUN beendet - es wurde NICHTS geloescht.${RESET}"
  echo "------------------------------------------------------------"
  echo ""
  exit 0
fi

# ───────────────── Schritt 3: Bestaetigungen (einzeln) ─────────────────
printf '\n%b\n' "${BOLD}Schritt 3: Bestaetigung${RESET}"
echo "------------------------------------------------------------"
echo "Das Loeschen ist unwiderruflich. LibreChat selbst bleibt unberuehrt."
[[ -n "$SUDO" ]] && echo "Dafuer wird sudo verwendet (Passwortabfrage moeglich)."

if ! ask_yn "Admin-Tool unter '$ADMIN_DIR' jetzt entfernen?"; then
  info "Abgebrochen. Es wurde nichts geloescht."
  exit 0
fi

DELETE_TMP=0
if [[ ${#TMP_LEFTOVERS[@]} -gt 0 ]]; then
  if ask_yn "Zusaetzlich die ${#TMP_LEFTOVERS[@]} Selbst-Update-Rest(e) in /tmp loeschen?"; then DELETE_TMP=1; fi
fi

# ───────────────── Schritt 4: Entfernen ─────────────────
printf '\n%b\n' "${BOLD}Schritt 4: Entfernen${RESET}"
echo "------------------------------------------------------------"

# Nicht im zu loeschenden Verzeichnis stehen bleiben
cd /

# Letzte Sicherheitspruefung unmittelbar vor dem Loeschen
check_admin_dir "$ADMIN_DIR" || die "Sicherheitspruefung vor dem Loeschen fehlgeschlagen. Es wurde nichts geloescht."
${SUDO} rm -rf -- "$ADMIN_DIR"
if [[ -e "$ADMIN_DIR" ]]; then
  die "'$ADMIN_DIR' konnte nicht vollstaendig entfernt werden."
fi
success "Admin-Tool entfernt: $ADMIN_DIR"

if [[ $INFO_FILE_FOUND -eq 1 && -f "$CI_INFO_PATH" && ! -L "$CI_INFO_PATH" ]]; then
  ${SUDO} rm -f -- "$CI_INFO_PATH"
  if [[ -e "$CI_INFO_PATH" ]]; then
    warn "$CI_INFO_PATH konnte nicht entfernt werden."
  else
    success "Datei entfernt: $CI_INFO_PATH"
  fi
fi

if [[ $DELETE_TMP -eq 1 ]]; then
  for f in "${TMP_LEFTOVERS[@]}"; do
    [[ -e "$f" && ! -L "$f" ]] && ${SUDO} rm -rf -- "$f"
  done
  success "Selbst-Update-Reste in /tmp entfernt."
fi

# ───────────────── Abschluss ─────────────────
echo ""
echo "------------------------------------------------------------"
echo -e "${GREEN}${BOLD} Admin-Tool vollstaendig entfernt.${RESET}"
echo "------------------------------------------------------------"
echo ""
echo -e " Neuinstallation jederzeit moeglich mit:"
echo -e " ${CYAN}${INSTALL_ONELINER}${RESET}"
echo ""
echo -e " Mehr Tipps & Tutorials: ${CYAN}https://pc-fee.com/blog${RESET}"
echo -e " GitHub:                 ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
