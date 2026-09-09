#!/usr/bin/env bash
# =============================================================================
# LibreChat Admin-Tool Installer
# - legt /opt/admin-lc an
# - klont nephilim75/scripts/librechat/maintenance direkt dorthin
# - macht alle .sh ausfuehrbar
# - prueft vorher, ob eine LibreChat-Installation existiert
# - fragt am Ende, ob das Admin-Tool gestartet werden soll
# -----------------------------------------------------------------------------
# Aufruf (Einzeiler):
#   bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/maintenance/install/install-admin-lc.sh)
#
# WICHTIG: bewusst "bash <(curl ...)", NICHT "curl ... | bash".
# Bei einer Pipe waere stdin durch den Skriptinhalt selbst belegt, die
# read-Abfragen unten (LibreChat-Pfad, "jetzt starten?") kaemen nie an.
# Mit Process Substitution bleibt stdin am Terminal, Eingaben funktionieren
# ganz normal - genau wie beim uebrigen Quick-Install in diesem Repo.
# -----------------------------------------------------------------------------
# AI-Transparenzhinweis:
# Dieses Skript wurde unter Einsatz von KI-Modellen (Claude Sonnet 5, Anthropic;
# MiniMax3, MiniMax) recherchiert, erstellt und iterativ ueberarbeitet.
# Vor produktivem Einsatz eigenverantwortlich pruefen.
# =============================================================================
set -Eeuo pipefail
trap 'rc=$?; printf "\033[0;31m[FEHLER]\033[0m Abbruch in Zeile %s (Exit %s).\n" "${LINENO}" "${rc}" >&2; exit "${rc}"' ERR

# ─────────────────────────────  Farben & Helpers  ─────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { printf '%b\n' "${CYAN}[INFO]${RESET}  $*"; }
success() { printf '%b\n' "${GREEN}[OK]${RESET}    $*"; }
warn()    { printf '%b\n' "${YELLOW}[WARN]${RESET}  $*"; }
error()   { printf '%b\n' "${RED}[FEHLER]${RESET} $*"; }
die()     { error "$*"; exit 1; }

# ─────────────────────────────  Konstanten  ─────────────────────────────
readonly REPO_URL="https://github.com/nephilim75/scripts.git"
readonly REPO_SUBDIR="librechat/maintenance"
readonly INSTALL_DIR="/opt/admin-lc"
readonly DEFAULT_LC_DIR="/opt/librechat"
readonly LC_DOC_URL="https://github.com/nephilim75/scripts/tree/main/librechat/install"

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "Bitte als root ausfuehren oder sudo installieren."
  SUDO="sudo"
fi

# ─────────────────────────────  Banner  ─────────────────────────────
clear
printf '%b' "${CYAN}"
cat <<'LOGO'
                  __
 _ __   ___      / _| ___  ___   _ __ ___
| '_ \ / __|____| |_ / _ \/ _ \ / _ \ '_ \
| |_) | (_|_____|  _|  __/  __/| (_) | | | |
| .__/ \___|    |_|  \___|\___| \___/|_| |_|
|_|
LOGO
printf '%b\n' "${RESET}"
printf '%b\n' "${BOLD} LibreChat Admin-Tool Installer – powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo ""
echo "Installiert das Admin-Tool (Backup, Update, User-Management, ...)"
echo "fuer eine bestehende LibreChat-Docker-Installation."
echo "------------------------------------------------------------"

# ─────────────────  Schritt 0: Voraussetzungen  ─────────────────
printf '\n%b\n' "${BOLD}Schritt 0: Voraussetzungen${RESET}"
echo "------------------------------------------------------------"
command -v git >/dev/null 2>&1 || die "git ist nicht installiert. Bitte vorher installieren: apt-get install git"
success "git gefunden: $(git --version)"

# ─────────────────  Schritt 1: LibreChat suchen  ─────────────────
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
  read -rp "$(printf '%b' "${BOLD}Liegt es in einem anderen Ordner? [y/N]:${RESET} ")" ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    while true; do
      read -rp "$(printf '%b' "${BOLD}Bitte absoluten Pfad zur LibreChat-Installation eingeben:${RESET} ")" LC_DIR
      if is_valid_lc_install "$LC_DIR"; then
        success "LibreChat-Installation gefunden unter: $LC_DIR"
        break
      else
        warn "Unter '$LC_DIR' wurde keine docker-compose.yml gefunden."
        read -rp "$(printf '%b' "${BOLD}Nochmal versuchen? [y/N]:${RESET} ")" retry
        [[ "$retry" =~ ^[Yy]$ ]] || { warn "Ueberspringe Pfaderkennung. Das Admin-Tool fragt beim ersten Start selbst danach."; LC_DIR=""; break; }
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

# ─────────────────  Schritt 2: Admin-Tool nach /opt/admin-lc klonen  ─────────────────
printf '\n%b\n' "${BOLD}Schritt 2: Admin-Tool installieren nach $INSTALL_DIR${RESET}"
echo "------------------------------------------------------------"

${SUDO} mkdir -p "$INSTALL_DIR"

# Rest eines vorherigen, abgebrochenen Laufs entfernen - sonst schlaegt der
# Clone beim erneuten Ausfuehren fehl ("destination path already exists").
${SUDO} rm -rf "$INSTALL_DIR/repo"

${SUDO} git clone --depth 1 "$REPO_URL" "$INSTALL_DIR/repo" || die "git clone fehlgeschlagen."

# Nur den maintenance-Ordner nach /opt/admin-lc kopieren, Rest weg.
# "cp -r quelle/. ziel" statt "mv": vorhandene Dateien wie config.sh (aus
# einem frueheren Lauf oder vom Tool selbst geschrieben) bleiben unangetastet,
# da die Quelle keine eigene config.sh mitbringt.
${SUDO} sh -c "cp -r '$INSTALL_DIR/repo/$REPO_SUBDIR/.' '$INSTALL_DIR/' && rm -rf '$INSTALL_DIR/repo'"

${SUDO} find "$INSTALL_DIR" -name '*.sh' -exec chmod +x {} +
success "Admin-Tool installiert unter: $INSTALL_DIR"

# Gefundenen (oder abgefragten) LibreChat-Pfad direkt in config.sh hinterlegen -
# genau das Format, das lib/common.sh selbst beim ersten Start schreiben wuerde.
# Robuster als den Pfad per Umgebungsvariable an "exec sudo ... menu.sh"
# durchzureichen: das haengt von der sudoers-env_reset/setenv-Konfiguration
# ab und kann dort je nach Haertung des Systems verloren gehen. So steht der
# Pfad zuverlaessig fest, egal ob/wann das Tool zum ersten Mal laeuft.
if [[ -n "$LC_DIR" ]]; then
  ${SUDO} sh -c "printf 'LIBRECHAT_DIR=\"%s\"\nLIBRECHAT_CONTAINER=\"LibreChat\"\n' '$LC_DIR' > '$INSTALL_DIR/config.sh'"
  success "LibreChat-Pfad in $INSTALL_DIR/config.sh hinterlegt: $LC_DIR"
fi

# ─────────────────  Schritt 3: Uebersicht  ─────────────────
printf '\n%b\n' "${BOLD}Schritt 3: Uebersicht${RESET}"
echo "------------------------------------------------------------"
info "LibreChat-Pfad:    ${LC_DIR:-<wird beim ersten Start abgefragt>}"
info "Admin-Tool-Pfad:   $INSTALL_DIR"
printf '\n%b\n' "${BOLD}Verfuegbare Admin-Skripte:${RESET}"
${SUDO} find "$INSTALL_DIR" -name '*.sh' -printf '  - %P\n' | sort
echo ""

# ─────────────────  Schritt 4: Admin-Tool starten?  ─────────────────
printf '\n%b\n' "${BOLD}Schritt 4: Admin-Tool starten?${RESET}"
echo "------------------------------------------------------------"
read -rp "$(printf '%b' "${BOLD}Admin-Tool jetzt starten? [y/N]:${RESET} ")" ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
  cd "$INSTALL_DIR"
  # Kein LIBRECHAT_DIR=... mehr noetig - steht (falls bekannt) in config.sh.
  exec ${SUDO} ./menu.sh
else
  printf '%b\n' "${CYAN}Uebersprungen. Manuelles Starten spaeter mit:${RESET}"
  echo "  cd $INSTALL_DIR && ${SUDO} ./menu.sh"
fi
