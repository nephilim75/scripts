#!/usr/bin/env bash
# =============================================================================
# LibreChat Admin-Tool Installer
# - fragt ZUERST, ob und wohin das Admin-Tool installiert werden soll
#   (Vorschlag: /opt/admin-lc - nur ein Default, keine Annahme)
# - prueft vorher, ob eine LibreChat-Installation existiert
# - zeigt vor jeder Aenderung eine Zusammenfassung; ohne Bestaetigung wird
#   NICHTS veraendert
# - klont nephilim75/scripts/librechat/maintenance/admin-tool ins gewaehlte Verzeichnis
# - macht alle .sh ausfuehrbar
# - fragt am Ende, ob das Admin-Tool gestartet werden soll
# -----------------------------------------------------------------------------
# Aufruf (Einzeiler):
#   bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/maintenance/install/install-admin-lc.sh)
#
# Optionen:
#   --dir <pfad>   Zielverzeichnis vorgeben (wird trotzdem bestaetigt)
#   --yes, -y      Alle Rueckfragen mit Default/Ja beantworten (auch: ASSUME_YES=1)
#   --help, -h     Hilfe
#
# Eingaben werden von /dev/tty gelesen, nicht von stdin. Ohne Terminal und
# ohne --yes bricht das Skript ab, bevor etwas veraendert wird.
# -----------------------------------------------------------------------------
# AI-Transparenzhinweis:
# Dieses Skript wurde unter Einsatz von KI-Modellen (Claude Sonnet 5, Anthropic;
# MiniMax3, MiniMax) recherchiert, erstellt und iterativ ueberarbeitet.
# Vor produktivem Einsatz eigenverantwortlich pruefen.
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
readonly REPO_URL="https://github.com/nephilim75/scripts.git"
readonly REPO_SUBDIR="librechat/maintenance/admin-tool"
readonly DEFAULT_INSTALL_DIR="/opt/admin-lc"
readonly DEFAULT_LC_DIR="/opt/librechat"
readonly LC_DOC_URL="https://github.com/nephilim75/scripts/tree/main/librechat/install"

ASSUME_YES="${ASSUME_YES:-0}"
INSTALL_DIR_ARG=""
TMP_DIR=""

usage() {
  cat <<EOF
Aufruf: $0 [--dir <pfad>] [--yes]

  --dir <pfad>   Zielverzeichnis fuer das Admin-Tool (Default-Vorschlag: ${DEFAULT_INSTALL_DIR})
  --yes, -y      Rueckfragen automatisch bestaetigen (auch ASSUME_YES=1)
  --help, -h     Diese Hilfe
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)     [[ $# -ge 2 ]] || die "--dir benoetigt einen Pfad."; INSTALL_DIR_ARG="$2"; shift 2 ;;
    --yes|-y)  ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         die "Unbekannte Option: $1 (siehe --help)" ;;
  esac
done

cleanup() { [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"; return 0; }
trap cleanup EXIT

# ───────────────────────────── Eingabe (immer von /dev/tty) ─────────────────────────────
HAVE_TTY=0
if [[ -r /dev/tty ]] && { : </dev/tty; } 2>/dev/null; then HAVE_TTY=1; fi

if [[ "$HAVE_TTY" -ne 1 && "$ASSUME_YES" != "1" ]]; then
  die "Kein Terminal fuer Rueckfragen verfuegbar. Interaktiv starten oder mit --yes (und ggf. --dir) aufrufen. Es wurde nichts veraendert."
fi

# ask "Frage" "Default"  -> Ergebnis in $REPLY_VAL
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

# ask_yn "Frage" -> Return 0 = Ja, 1 = Nein (Default: Nein)
ask_yn() {
  local a=""
  if [[ "$ASSUME_YES" == "1" ]]; then return 0; fi
  read -rp "$(printf '%b' "${BOLD}$1 [j/N]:${RESET} ")" a </dev/tty || a=""
  [[ "$a" =~ ^[JjYy]$ ]]
}

# ───────────────────────────── sudo-Erkennung (ruft sudo noch NICHT auf) ─────────────────────────────
SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "Bitte als root ausfuehren oder sudo installieren."
  SUDO="sudo"
fi

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
printf '%b\n' "${BOLD} LibreChat Admin-Tool Installer – powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo "Installiert das Admin-Tool (Backup, Update, User-Management, ...)"
echo "fuer eine bestehende LibreChat-Docker-Installation."
echo "Es wird nichts veraendert, bevor Sie die Zusammenfassung bestaetigt haben."
echo "------------------------------------------------------------"

# Gueltiger Pfad: absolut, nur unkritische Zeichen (kommt spaeter in config.sh)
is_safe_path() { [[ "$1" =~ ^/[A-Za-z0-9._@+/-]+$ ]]; }

# ───────────────── Schritt 0: Voraussetzungen ─────────────────
printf '\n%b\n' "${BOLD}Schritt 0: Voraussetzungen${RESET}"
echo "------------------------------------------------------------"

if ! command -v git >/dev/null 2>&1; then
  warn "git ist nicht installiert."
  if command -v apt-get >/dev/null 2>&1; then
    if ask_yn "git jetzt per apt-get installieren?"; then
      ${SUDO} apt-get install -y git || die "Installation von git fehlgeschlagen."
    else
      die "Ohne git nicht moeglich. Abbruch - es wurde nichts veraendert."
    fi
  else
    die "Bitte git manuell installieren und das Skript erneut starten."
  fi
fi
success "git gefunden: $(git --version)"

# ───────────────── Schritt 1: LibreChat suchen ─────────────────
printf '\n%b\n' "${BOLD}Schritt 1: LibreChat-Installation suchen${RESET}"
echo "------------------------------------------------------------"

is_valid_lc_install() {
  local p="$1"
  [[ -d "$p" ]] && [[ -f "$p/docker-compose.yml" ]]
}

LC_DIR=""
if is_valid_lc_install "$DEFAULT_LC_DIR"; then
  LC_DIR="$DEFAULT_LC_DIR"
  success "LibreChat-Installation gefunden unter: $LC_DIR"
else
  warn "LibreChat wurde unter '$DEFAULT_LC_DIR' nicht gefunden."
  if [[ "$ASSUME_YES" != "1" ]] && ask_yn "Liegt es in einem anderen Ordner?"; then
    while true; do
      ask "Bitte absoluten Pfad zur LibreChat-Installation eingeben" ""
      LC_DIR="$REPLY_VAL"
      if is_safe_path "$LC_DIR" && is_valid_lc_install "$LC_DIR"; then
        success "LibreChat-Installation gefunden unter: $LC_DIR"
        break
      fi
      warn "Unter '$LC_DIR' wurde keine gueltige Installation (docker-compose.yml) gefunden."
      if ! ask_yn "Nochmal versuchen?"; then
        warn "Ueberspringe Pfaderkennung. Das Admin-Tool fragt beim ersten Start selbst danach."
        LC_DIR=""
        break
      fi
    done
  else
    warn "Ueberspringe Pfaderkennung. Das Admin-Tool fragt beim ersten Start selbst danach."
  fi
fi
if [[ -z "$LC_DIR" ]]; then
  info "Noch keine LibreChat-Installation gefunden? Anleitung: $LC_DOC_URL"
fi
info "LC_DIR: ${LC_DIR:-<noch offen, wird beim ersten Start abgefragt>}"

# ───────────────── Schritt 2: Zielverzeichnis waehlen ─────────────────
printf '\n%b\n' "${BOLD}Schritt 2: Wohin soll das Admin-Tool installiert werden?${RESET}"
echo "------------------------------------------------------------"

INSTALL_DIR=""
UPDATE_MODE=0
CANDIDATE="${INSTALL_DIR_ARG:-$DEFAULT_INSTALL_DIR}"

while true; do
  ask "Installationsverzeichnis" "$CANDIDATE"
  CAND="${REPLY_VAL%/}"

  if [[ -z "$CAND" ]] || ! is_safe_path "$CAND"; then
    warn "Bitte einen absoluten Pfad ohne Leer- und Sonderzeichen angeben (erlaubt: A-Z a-z 0-9 . _ @ + - /)."
  elif [[ "$CAND" =~ ^/(bin|boot|dev|etc|home|lib|lib32|lib64|opt|proc|root|run|sbin|srv|sys|tmp|usr|var)$ ]]; then
    warn "'$CAND' ist ein Systemverzeichnis. Bitte einen eigenen Unterordner waehlen (z. B. ${DEFAULT_INSTALL_DIR})."
  elif [[ -n "$LC_DIR" && ( "$CAND" == "$LC_DIR" || "$CAND" == "$LC_DIR"/* || "$LC_DIR" == "$CAND"/* ) ]]; then
    warn "Das Zielverzeichnis darf nicht mit der LibreChat-Installation ($LC_DIR) ueberlappen."
  elif [[ -e "$CAND" && ! -d "$CAND" ]]; then
    warn "'$CAND' existiert, ist aber kein Verzeichnis."
  elif [[ -d "$CAND" && -n "$(find "$CAND" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    if [[ -f "$CAND/menu.sh" ]]; then
      info "Dort liegt bereits ein Admin-Tool (menu.sh gefunden)."
      if ask_yn "Dort aktualisieren? (vorhandene config.sh bleibt erhalten)"; then
        INSTALL_DIR="$CAND"; UPDATE_MODE=1; break
      fi
    else
      warn "'$CAND' ist nicht leer und enthaelt kein Admin-Tool. Es wird nichts hineinkopiert - bitte anderen Pfad waehlen."
    fi
  else
    INSTALL_DIR="$CAND"; break
  fi

  # Bei --yes ohne gueltigen Pfad nicht endlos fragen
  if [[ "$HAVE_TTY" -ne 1 ]]; then die "Zielverzeichnis '$CAND' ist nicht verwendbar. Es wurde nichts veraendert."; fi
  CANDIDATE="$DEFAULT_INSTALL_DIR"
  ask_yn "Anderen Pfad eingeben?" || die "Abbruch auf Wunsch. Es wurde nichts veraendert."
done

# Bereits vorhandene config.sh nur nach Rueckfrage anfassen
WRITE_CONFIG=0
if [[ -n "$LC_DIR" ]]; then
  if [[ -f "$INSTALL_DIR/config.sh" ]]; then
    warn "$INSTALL_DIR/config.sh existiert bereits."
    if ask_yn "LibreChat-Pfad dort auf '$LC_DIR' setzen (ueberschreibt die Datei)?"; then WRITE_CONFIG=1; fi
  else
    WRITE_CONFIG=1
  fi
fi

# ───────────────── Schritt 3: Zusammenfassung & Bestaetigung ─────────────────
printf '\n%b\n' "${BOLD}Schritt 3: Zusammenfassung${RESET}"
echo "------------------------------------------------------------"
info "Zielverzeichnis:  $INSTALL_DIR $([[ $UPDATE_MODE -eq 1 ]] && echo '(bestehendes Admin-Tool wird aktualisiert)' || echo '(wird angelegt bzw. verwendet)')"
info "LibreChat-Pfad:   ${LC_DIR:-<wird beim ersten Start abgefragt>}"
info "Quelle:           $REPO_URL ($REPO_SUBDIR)"
echo ""
echo "Geplant:"
echo "  - Repository temporaer klonen (in ein temporaeres Verzeichnis, wird danach geloescht)"
echo "  - Inhalt von '$REPO_SUBDIR' nach '$INSTALL_DIR' kopieren"
echo "  - alle .sh-Dateien dort ausfuehrbar machen"
[[ $WRITE_CONFIG -eq 1 ]] && echo "  - $INSTALL_DIR/config.sh mit dem LibreChat-Pfad schreiben"
[[ -n "$SUDO" ]] && echo "  - dafuer wird sudo verwendet (Passwortabfrage moeglich)"
echo ""
echo "Ohne Bestaetigung wird nichts veraendert."
if ! ask_yn "Jetzt so installieren?"; then
  info "Abgebrochen. Es wurde nichts veraendert."
  exit 0
fi

# ───────────────── Schritt 4: Installation ─────────────────
printf '\n%b\n' "${BOLD}Schritt 4: Admin-Tool installieren nach $INSTALL_DIR${RESET}"
echo "------------------------------------------------------------"

TMP_DIR="$(mktemp -d)"
git clone --depth 1 "$REPO_URL" "$TMP_DIR/repo" || die "git clone fehlgeschlagen."
[[ -d "$TMP_DIR/repo/$REPO_SUBDIR" ]] || die "Unterordner '$REPO_SUBDIR' im Repository nicht gefunden."

${SUDO} mkdir -p "$INSTALL_DIR"
# "cp -r quelle/. ziel": vorhandene Dateien wie config.sh bleiben unangetastet,
# da die Quelle keine eigene config.sh mitbringt.
${SUDO} cp -r "$TMP_DIR/repo/$REPO_SUBDIR/." "$INSTALL_DIR/"
${SUDO} find "$INSTALL_DIR" -name '*.sh' -exec chmod +x {} +
success "Admin-Tool installiert unter: $INSTALL_DIR"

# LibreChat-Pfad direkt in config.sh hinterlegen (Format wie lib/common.sh beim ersten Start)
if [[ $WRITE_CONFIG -eq 1 ]]; then
  printf 'LIBRECHAT_DIR="%s"\nLIBRECHAT_CONTAINER="LibreChat"\n' "$LC_DIR" | ${SUDO} tee "$INSTALL_DIR/config.sh" >/dev/null
  success "LibreChat-Pfad in $INSTALL_DIR/config.sh hinterlegt: $LC_DIR"
fi

# ───────────────── Schritt 5: Uebersicht ─────────────────
printf '\n%b\n' "${BOLD}Schritt 5: Uebersicht${RESET}"
echo "------------------------------------------------------------"
info "LibreChat-Pfad:  ${LC_DIR:-<wird beim ersten Start abgefragt>}"
info "Admin-Tool-Pfad: $INSTALL_DIR"
printf '\n%b\n' "${BOLD}Verfuegbare Admin-Skripte:${RESET}"
${SUDO} find "$INSTALL_DIR" -name '*.sh' -printf '  - %P\n' | sort
echo ""

# ───────────────── Schritt 6: Admin-Tool starten? ─────────────────
printf '\n%b\n' "${BOLD}Schritt 6: Admin-Tool starten?${RESET}"
echo "------------------------------------------------------------"
START=0
if [[ "$ASSUME_YES" != "1" ]] && ask_yn "Admin-Tool jetzt starten?"; then START=1; fi

if [[ $START -eq 1 ]]; then
  cd "$INSTALL_DIR"
  exec ${SUDO} ./menu.sh
else
  printf '%b\n' "${CYAN}Uebersprungen. Manuelles Starten spaeter mit:${RESET}"
  echo "  cd $INSTALL_DIR && ${SUDO:+$SUDO }./menu.sh"
fi
