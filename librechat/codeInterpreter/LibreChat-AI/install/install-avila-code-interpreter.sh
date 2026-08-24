#!/usr/bin/env bash
# =============================================================================
# avila-code-interpreter Installer
# - installiert https://github.com/LibreChat-AI/code-interpreter (Fork von
#   ClickHouse/code-interpreter) unter /opt/avila-code-interpreter
# - volle gehaertete Konfiguration: MicroVM (libkrun) + NsJail im Gast,
#   Egress-Gateway, signierte Execution-Manifeste, Hardened Mode
# - Voraussetzung: laufender Nginx Proxy Manager (NPM) + Docker-Netzwerk
#   "shared_proxy" (unabhaengig vom gewaehlten Modus, siehe Schritt 0)
# - zwei Modi:
#     lokal  -> kein NPM-Host, kein Domain-Zugriff. LibreChat und der
#               Interpreter laufen auf demselben Docker-Host und sprechen
#               sich direkt ueber den Container-Namen im shared_proxy-Netz an.
#     extern -> zusaetzlicher NPM-Proxy-Host mit eigener Domain, da LibreChat
#               auf einem anderen Host laeuft. Kein Auth-Mechanismus fuer die
#               Codeausfuehrung selbst (siehe Warnhinweis am Ende) - dafuer
#               Empfehlung fuer eine IP-beschraenkte Access List in NPM.
# - Kein Port wird jemals oeffentlich an den Host gebunden, unabhaengig vom
#   Modus. Aller Traffic laeuft ueber Docker-Netzwerke bzw. NPM.
# =============================================================================
set -Eeuo pipefail
trap 'rc=$?; echo "[FEHLER] Abbruch in Zeile ${LINENO} (Exit ${rc})." >&2; exit ${rc}' ERR
 
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { printf '%b\n' "${CYAN}[INFO]${RESET}  $*"; }
success() { printf '%b\n' "${GREEN}[OK]${RESET}    $*"; }
warn()    { printf '%b\n' "${YELLOW}[WARN]${RESET}  $*"; }
error()   { printf '%b\n' "${RED}[FEHLER]${RESET} $*"; }
die()     { error "$*"; exit 1; }
 
readonly REPO_URL="https://github.com/LibreChat-AI/code-interpreter.git"
readonly DEFAULT_INSTALL_DIR="/opt/avila-code-interpreter"
readonly DEFAULT_LIBRECHAT_DIR="/opt/librechat"
readonly DEFAULT_NPM_NETWORK="shared_proxy"
readonly MIN_FREE_MB=15000   # 15 GB Sicherheitsschwelle fuer den lokalen Image-Build
# Im NsJail-Modus kommt der Bauvorgang fuer die Laufzeitumgebungen hinzu.
# Gemessen auf einem Testsystem: ~3,1 GB unter data/pkgs plus ~1,4 GB fuer das
# dabei erzeugte package-init-Image. Aufgerundet auf 5 GB Aufschlag, da die
# Daten waehrend des Entpackens kurzzeitig doppelt vorliegen.
readonly MIN_FREE_NSJAIL_MB=20000
readonly SWAP_FILE="/swapfile-avila-code-interpreter"
readonly SWAP_SIZE_MB=4096
 
SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "Bitte als root ausfuehren oder sudo installieren."
  SUDO="sudo"
fi
 
clear
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
printf '%b\n' "${BOLD} Code Interpreter Installer – powered by pc-fee.com${RESET}"
printf '%b\n' " ${CYAN}https://pc-fee.com${RESET} | ${CYAN}https://github.com/nephilim75/scripts${RESET}"
echo "Installiert den LibreChat Code Interpreter (gehaertete Konfiguration:"
echo "MicroVM + NsJail + Egress-Gateway + signierte Manifeste) hinter einem"
echo "Nginx Proxy Manager. Kein Port wird jemals oeffentlich an den Host"
echo "gebunden."
echo "------------------------------------------------------------"
 
# -----------------------------------------------------------------------------
# Schritt 0: Voraussetzungen pruefen (immer, unabhaengig vom Modus)
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 0: Voraussetzungen${RESET}"
echo "------------------------------------------------------------"
 
command -v git >/dev/null 2>&1 || die "git ist nicht installiert. Bitte zuerst installieren (z.B. apt-get install -y git)."
success "git gefunden: $(git --version)"
 
command -v docker >/dev/null 2>&1 || die "Docker ist nicht installiert."
success "Docker gefunden: $(docker --version)"
 
${SUDO} docker info >/dev/null 2>&1 || die "Docker-Daemon laeuft nicht oder ist nicht erreichbar."
success "Docker-Daemon laeuft."
 
${SUDO} docker compose version >/dev/null 2>&1 || die "Docker Compose Plugin nicht gefunden."
COMPOSE_CMD="${SUDO} docker compose"
success "Docker Compose Plugin gefunden: $(${COMPOSE_CMD} version --short 2>/dev/null || ${COMPOSE_CMD} version)"
 
command -v openssl >/dev/null 2>&1 || die "openssl ist nicht installiert (wird fuer Secrets und Schluessel gebraucht)."
success "openssl gefunden."
 
# curl wird nur fuer die Anzeige der oeffentlichen IP am Ende gebraucht (siehe
# detect_public_ipv4). Fehlt es, laeuft die Installation vollstaendig durch -
# nur der A-Record muesste dann von Hand ermittelt werden. Deshalb Hinweis
# statt Abbruch.
if command -v curl >/dev/null 2>&1; then
  success "curl gefunden."
else
  warn "curl ist nicht installiert. Die Installation laeuft trotzdem durch,"
  warn "nur die oeffentliche IP fuer den A-Record kann am Ende nicht"
  warn "automatisch ermittelt werden (nachinstallieren: apt-get install -y curl)."
fi
 
# NPM + shared_proxy sind unabhaengig vom Modus Pflicht-Voraussetzung: im
# lokalen Modus, weil LibreChat und der Interpreter darueber den Container-
# Namen des jeweils anderen aufloesen; im externen Modus zusaetzlich, weil
# NPM den Domain-Traffic dorthin weiterleitet.
if ${SUDO} docker ps --format '{{.Image}}' | grep -qi 'nginx-proxy-manager'; then
  success "Nginx Proxy Manager Container laeuft."
else
  die "Kein laufender Nginx Proxy Manager Container gefunden. Das ist fuer dieses Skript in jedem Modus Voraussetzung."
fi
 
if ${SUDO} docker network inspect "${DEFAULT_NPM_NETWORK}" >/dev/null 2>&1; then
  success "Docker-Netzwerk '${DEFAULT_NPM_NETWORK}' gefunden."
else
  die "Docker-Netzwerk '${DEFAULT_NPM_NETWORK}' existiert nicht. Bitte zuerst in NPM/Docker anlegen."
fi
 
# -----------------------------------------------------------------------------
# Schritt 1: Installationspfad + Modus abfragen
# -----------------------------------------------------------------------------
is_domain() { [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; }
canon_dir() { local d="${1:-}"; d="${d/#\~/$HOME}"; printf '%s' "${d%/}"; }
detect_public_ipv4() {
  local ip
  ip="$(curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  [[ -z "${ip}" ]] && ip="$(curl -fsS4 --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  printf '%s' "${ip}"
}
 
printf '%b\n' "\n${BOLD}Schritt 1: Installationspfad und Modus${RESET}"
echo "------------------------------------------------------------"
read -rp "Installationspfad [${DEFAULT_INSTALL_DIR}]: " INSTALL_DIR
INSTALL_DIR="$(canon_dir "${INSTALL_DIR:-${DEFAULT_INSTALL_DIR}}")"
[[ ! -e "${INSTALL_DIR}" ]] || die "${INSTALL_DIR} existiert bereits. Bitte pruefen/entfernen oder einen anderen Pfad waehlen."
success "Installationspfad: ${INSTALL_DIR}"
echo ""
echo "1) Lokal  - LibreChat laeuft auf DIESEM Server. Kein Domain-Zugriff,"
echo "            direkte Container-zu-Container-Kommunikation."
echo "            Voraussetzung: LibreChat ist hier bereits installiert."
echo "2) Extern - LibreChat laeuft auf einem ANDEREN Server. Zugriff ueber"
echo "            eine eigene Domain via NPM."
echo "            Voraussetzung: eine Domain, die auf diesen Server zeigt."
echo ""
while :; do
  read -rp "Auswahl [1/2]: " MODE_CHOICE
  case "${MODE_CHOICE}" in
    1) MODE="lokal"; break ;;
    2) MODE="extern"; break ;;
    *) warn "Bitte 1 oder 2 eingeben." ;;
  esac
done
success "Modus: ${MODE}"
 
# Im lokalen Modus muss LibreChat auf DIESEM Host bereits installiert sein -
# der Interpreter wird spaeter dort in der .env eingetragen und ueber den
# Container-Namen im gemeinsamen Docker-Netz angesprochen. Ohne bestehende
# LibreChat-Installation gibt es nichts anzubinden, daher harter Abbruch mit
# klarer Handlungsanweisung statt einer halbfertigen Installation.
# Im externen Modus entfaellt diese Pruefung bewusst: dort laeuft LibreChat
# per Definition auf einem ANDEREN Server.
LIBRECHAT_DIR=""
if [[ "${MODE}" == "lokal" ]]; then
  echo ""
  info "Der Code-Interpreter ist eine Erweiterung fuer LibreChat und wird dort"
  info "in die Konfiguration (.env) eingetragen. Deshalb muss LibreChat auf"
  info "diesem Server bereits installiert sein - der Pfad wird jetzt abgefragt."
  echo ""
  read -rp "Installationspfad von LibreChat [${DEFAULT_LIBRECHAT_DIR}]: " LIBRECHAT_DIR
  LIBRECHAT_DIR="$(canon_dir "${LIBRECHAT_DIR:-${DEFAULT_LIBRECHAT_DIR}}")"
  if [[ ! -f "${LIBRECHAT_DIR}/.env" ]]; then
    error "Unter ${LIBRECHAT_DIR} wurde keine LibreChat-Installation gefunden (.env fehlt)."
    echo ""
    echo "  Der lokale Modus setzt voraus, dass LibreChat auf DIESEM Server bereits"
    echo "  installiert ist - der Code-Interpreter wird dort in die .env eingetragen."
    echo ""
    echo "  Moegliche naechste Schritte:"
    echo "    - LibreChat zuerst installieren, danach dieses Skript erneut ausfuehren"
    echo "    - oder das Skript neu starten und Modus 2 (extern) waehlen, falls"
    echo "      LibreChat auf einem anderen Server laeuft"
    echo ""
    die "Abbruch: keine LibreChat-Installation vorhanden."
  fi
  success "LibreChat gefunden: ${LIBRECHAT_DIR}"
fi
 
DOMAIN=""
if [[ "${MODE}" == "extern" ]]; then
  echo ""
  while :; do
    read -rp "Domain fuer den Code-Interpreter (z.B. code.example.de): " DOMAIN
    is_domain "${DOMAIN}" && break || warn "Ungueltige Domain."
  done
  success "Domain: ${DOMAIN}"
fi
 
# -----------------------------------------------------------------------------
# Absicherung der Codeausfuehrung (JWT) abfragen
# -----------------------------------------------------------------------------
# Ohne JWT nimmt der Interpreter JEDEN Auftrag an, der ihn erreicht. Im
# lokalen Modus heisst das: jeder andere Container im gemeinsamen Docker-Netz
# koennte Code ausfuehren. Im externen Modus haengt der Dienst an einer
# oeffentlichen Domain - dort ist ohne JWT eine NPM-Access-List die einzige
# Zugangskontrolle.
# Mit JWT unterschreibt LibreChat jeden Auftrag mit einem privaten Schluessel,
# der Interpreter prueft die Unterschrift mit dem passenden oeffentlichen
# Schluessel. Das Schluesselpaar wird hier automatisch erzeugt.
printf '%b\n' "\n${BOLD}Absicherung der Codeausfuehrung${RESET}"
echo "------------------------------------------------------------"
echo "Empfohlen: Auftraege per JWT signieren. LibreChat unterschreibt jeden"
echo "Auftrag, der Interpreter nimmt nur korrekt unterschriebene an."
echo "Ohne JWT fuehrt der Interpreter Code von jedem aus, der ihn erreicht."
echo ""
read -rp "Codeausfuehrung per JWT absichern? [J/n]: " JWT_CONFIRM
if [[ "${JWT_CONFIRM,,}" == "n" ]]; then
  JWT_AUTH="false"
  warn "Ohne JWT-Absicherung - Zugriffsschutz nur ueber Netzwerk-Isolation."
else
  JWT_AUTH="true"
  success "JWT-Absicherung wird eingerichtet."
fi
 
# -----------------------------------------------------------------------------
# Schritt 2: Speicherplatz pruefen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 2: Speicherplatz${RESET}"
echo "------------------------------------------------------------"
info "Dieser Stack baut mehrere Docker-Images lokal aus dem Quellcode (kein"
info "fertiges Image von einer Registry). Besonders das Sandbox-Image baut"
info "dabei Python-, Node- und Bun-Laufzeiten mit ein - das braucht deutlich"
info "mehr Platz und Zeit als ein normaler 'docker compose pull'."
 
# Ohne /dev/kvm laeuft die Installation spaeter im NsJail-Modus, und dort
# kommt ein zweiter Bauvorgang fuer die Laufzeitumgebungen der Sandbox hinzu
# (siehe Schritt 8). Gemessen: rund 3 GB unter data/pkgs plus ~1,4 GB fuer das
# dabei erzeugte Image - zusammen etwa 5 GB, die im MicroVM-Modus nicht
# anfallen. Die Schwelle wird deshalb hier schon passend gewaehlt; die
# eigentliche Modus-Entscheidung faellt erst in Schritt 4, aber sie haengt an
# genau derselben Bedingung.
REQUIRED_FREE_MB="${MIN_FREE_MB}"
if [[ ! -e /dev/kvm || ! -r /dev/kvm || ! -w /dev/kvm ]]; then
  REQUIRED_FREE_MB="${MIN_FREE_NSJAIL_MB}"
  info "Kein nutzbares /dev/kvm gefunden - es wird mit dem NsJail-Modus"
  info "gerechnet, der zusaetzlich etwa 5 GB fuer die Laufzeitumgebungen braucht."
fi
 
# Gemessen wird dort, wo Docker seine Images tatsaechlich ablegt - nicht auf
# "/". Bei manchen Hostern liegt /var/lib/docker auf einer eigenen Partition;
# eine Pruefung von "/" wuerde dann den falschen Wert melden und einen Build
# zulassen, der spaeter am vollen Speicher scheitert. Den echten Pfad kennt
# Docker selbst; faellt die Abfrage aus, bleibt /var/lib/docker als Rueckfall.
DOCKER_ROOT="$(${SUDO} docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
[[ -d "${DOCKER_ROOT}" ]] || DOCKER_ROOT="/var/lib/docker"
[[ -d "${DOCKER_ROOT}" ]] || DOCKER_ROOT="/"
 
FREE_MB="$(df -Pm "${DOCKER_ROOT}" | awk 'NR==2{print $4}')"
info "Verfuegbarer Speicherplatz auf ${DOCKER_ROOT}: ${FREE_MB} MB"
info "Benoetigt (mit Reserve):          ${REQUIRED_FREE_MB} MB"
if (( FREE_MB < REQUIRED_FREE_MB )); then
  die "Weniger als ${REQUIRED_FREE_MB} MB frei. Der Build wuerde vermutlich mitten drin abbrechen. Bitte zuerst Platz schaffen."
fi
success "Genug Speicherplatz vorhanden."
 
# -----------------------------------------------------------------------------
# Schritt 3: Swap pruefen / anlegen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 3: Swap-Speicher${RESET}"
echo "------------------------------------------------------------"
info "Der lokale Build mehrerer Images gleichzeitig kann kurzzeitig viel RAM"
info "brauchen. Ohne Swap als Sicherheitsnetz kann der Build-Prozess vom"
info "Betriebssystem abgeschossen werden (OOM-Kill) - meist ohne verstaendliche"
info "Fehlermeldung."
 
CURRENT_SWAP_MB="$(free -m | awk '/^Swap:/{print $2}')"
if (( CURRENT_SWAP_MB > 0 )); then
  success "Swap bereits vorhanden: ${CURRENT_SWAP_MB} MB. Kein Handlungsbedarf."
else
  warn "Kein Swap vorhanden."
  read -rp "Jetzt eine ${SWAP_SIZE_MB} MB Swap-Datei anlegen (${SWAP_FILE})? [j/N]: " SWAP_CONFIRM
  if [[ "${SWAP_CONFIRM,,}" == "j" ]]; then
    ${SUDO} fallocate -l "${SWAP_SIZE_MB}M" "${SWAP_FILE}" || ${SUDO} dd if=/dev/zero of="${SWAP_FILE}" bs=1M count="${SWAP_SIZE_MB}"
    ${SUDO} chmod 600 "${SWAP_FILE}"
    ${SUDO} mkswap "${SWAP_FILE}" >/dev/null
    ${SUDO} swapon "${SWAP_FILE}"
    if ! grep -q "^${SWAP_FILE} " /etc/fstab 2>/dev/null; then
      echo "${SWAP_FILE} none swap sw 0 0" | ${SUDO} tee -a /etc/fstab >/dev/null
    fi
    success "Swap-Datei angelegt und aktiviert (bleibt auch nach einem Neustart bestehen)."
  else
    warn "Kein Swap angelegt - Build laeuft ohne Sicherheitsnetz weiter."
  fi
fi
 
# -----------------------------------------------------------------------------
# Schritt 4: Sandbox-Isolationsmodus (MicroVM oder NsJail-only)
# -----------------------------------------------------------------------------
# Beide Modi sind im Repository offiziell dokumentiert und unterstuetzt
# (README, Abschnitt "Sandbox Isolation"):
#   MicroVM mode (kvmEnabled: true)  - eigener Gast-Kernel, volle Haertung
#   NsJail mode  (kvmEnabled: false) - teilt sich den Host-Kernel
printf '%b\n' "\n${BOLD}Schritt 4: Sandbox-Isolationsmodus${RESET}"
echo "------------------------------------------------------------"
KVM_ENABLED="true"
if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
  success "/dev/kvm vorhanden und zugreifbar. MicroVM-Modus wird verwendet."
else
  warn "/dev/kvm nicht gefunden oder nicht zugreifbar - MicroVM-Modus nicht moeglich."
  echo ""
  echo "Aus der offiziellen Projekt-Doku (README, Abschnitt 'Security disclaimer',"
  echo "https://github.com/LibreChat-AI/code-interpreter#security-disclaimer):"
  echo "  Im vollen gehaerteten Modus (MicroVM, eigener Gast-Kernel) gilt der"
  echo "  Interpreter als angemessen abgesichert. Der reine NsJail-Modus teilt"
  echo "  sich dagegen den Kernel mit dem Host und bietet spuerbar schwaechere"
  echo "  Isolation - passend fuer lokale Tests, NICHT fuer die Ausfuehrung von"
  echo "  Code aus nicht vertrauenswuerdigen Quellen."
  echo ""
  read -rp "Trotzdem mit dem NsJail-only-Modus fortfahren? [j/N]: " KVM_SKIP_CONFIRM
  if [[ "${KVM_SKIP_CONFIRM,,}" != "j" ]]; then
    die "Abgebrochen. Fuer den vollen MicroVM-Schutz wird ein Server mit /dev/kvm benoetigt."
  fi
  KVM_ENABLED="false"
  warn "NsJail-only-Modus gewaehlt - fuer Tests ok, nicht empfohlen fuer produktive Systeme mit unbekannten Nutzern."
fi
 
# -----------------------------------------------------------------------------
# Zusammenfassung vor dem Start
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Zusammenfassung${RESET}"
echo "------------------------------------------------------------"
printf 'Installationspfad: %s\nModus:             %s\n' "${INSTALL_DIR}" "${MODE}"
[[ -n "${LIBRECHAT_DIR}" ]] && printf 'LibreChat:         %s\n' "${LIBRECHAT_DIR}"
[[ -n "${DOMAIN}" ]] && printf 'Domain:            %s\n' "${DOMAIN}"
printf 'NPM-Netzwerk:      %s\n' "${DEFAULT_NPM_NETWORK}"
printf 'JWT-Absicherung:   %s\n' "$( [[ "${JWT_AUTH}" == "true" ]] && echo "ja" || echo "nein" )"
read -rp "Installation starten? [j/N]: " CONFIRM
[[ "${CONFIRM,,}" == "j" ]] || { warn "Abgebrochen (keine oder verneinende Eingabe)."; exit 0; }
 
# -----------------------------------------------------------------------------
# Schritt 5: Repository holen
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 5: Repository${RESET}"
echo "------------------------------------------------------------"
${SUDO} git clone --depth=1 "${REPO_URL}" "${INSTALL_DIR}"
cd "${INSTALL_DIR}"
[[ -f docker-compose.yaml ]] || die "docker-compose.yaml fehlt im Repository - hat sich die Struktur geaendert?"
success "Repository bereit."
 
# -----------------------------------------------------------------------------
# Schritt 6: Secrets + Ed25519-Schluesselpaar erzeugen, .env schreiben
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 6: .env erzeugen${RESET}"
echo "------------------------------------------------------------"
info "Erzeuge Secrets fuer den internen Dienst-zu-Dienst-Verkehr und ein"
info "Ed25519-Schluesselpaar, mit dem Ausfuehrungs-Auftraege signiert und"
info "geprueft werden (schuetzt vor manipulierten Auftraegen zwischen den"
info "einzelnen Komponenten)."
 
CODEAPI_INTERNAL_SERVICE_TOKEN="$(openssl rand -hex 32)"
CODEAPI_EGRESS_GRANT_SECRET="$(openssl rand -hex 32)"
 
PRIV_DER_B64="$(openssl genpkey -algorithm ed25519 -outform DER 2>/dev/null | base64 -w0)"
PUB_DER_B64="$(printf '%s' "${PRIV_DER_B64}" | base64 -d | openssl pkey -inform DER -pubout -outform DER 2>/dev/null | base64 -w0)"
[[ -n "${PRIV_DER_B64}" && -n "${PUB_DER_B64}" ]] || die "Ed25519-Schluesselpaar konnte nicht erzeugt werden."
 
# --- JWT-Schluesselpaar (getrennt vom Manifest-Schluessel oben) -------------
# Der Verifier (service/src/auth/librechat-jwt.ts) akzeptiert den oeffentlichen
# Schluessel als JWK-JSON oder PEM. JWK ist hier die bessere Wahl, weil es in
# eine einzige .env-Zeile passt (PEM enthaelt Zeilenumbrueche).
# Ableitung ohne Zusatzwerkzeug: Bei Ed25519 sind die DER-Strukturen fester
# Laenge - die letzten 32 Byte des PKCS8-DER sind der private Seed ("d"), die
# letzten 32 Byte des SPKI-DER der oeffentliche Punkt ("x"). Beides
# base64url-kodiert ergibt ein gueltiges OKP-JWK.
JWT_KID=""
JWT_PUBLIC_JWK=""
JWT_PRIVATE_JWK=""
readonly JWT_ISSUER="librechat"
readonly JWT_AUDIENCE="codeapi"
readonly JWT_TENANT_ID="legacy"
if [[ "${JWT_AUTH}" == "true" ]]; then
  b64url() { base64 -w0 | tr '+/' '-_' | tr -d '='; }
  JWT_PRIV_PEM="$(openssl genpkey -algorithm ed25519 2>/dev/null)"
  [[ -n "${JWT_PRIV_PEM}" ]] || die "JWT-Schluesselpaar konnte nicht erzeugt werden."
  JWT_D="$(printf '%s' "${JWT_PRIV_PEM}" | openssl pkey -outform DER 2>/dev/null | tail -c 32 | b64url)"
  JWT_X="$(printf '%s' "${JWT_PRIV_PEM}" | openssl pkey -pubout -outform DER 2>/dev/null | tail -c 32 | b64url)"
  [[ -n "${JWT_D}" && -n "${JWT_X}" ]] || die "JWT-Schluessel konnten nicht in das JWK-Format umgewandelt werden."
  JWT_KID="lc-codeapi-$(date +%Y-%m)-$(openssl rand -hex 3)"
  JWT_PUBLIC_JWK="{\"crv\":\"Ed25519\",\"x\":\"${JWT_X}\",\"kty\":\"OKP\",\"kid\":\"${JWT_KID}\",\"alg\":\"EdDSA\"}"
  JWT_PRIVATE_JWK="{\"crv\":\"Ed25519\",\"d\":\"${JWT_D}\",\"x\":\"${JWT_X}\",\"kty\":\"OKP\",\"kid\":\"${JWT_KID}\",\"alg\":\"EdDSA\"}"
  unset JWT_PRIV_PEM JWT_D
  success "JWT-Schluesselpaar erzeugt (Kennung: ${JWT_KID})."
fi
 
{
  echo "# Automatisch erzeugt von install-avila-code-interpreter.sh"
  echo "LOCAL_MODE=false"
  echo "CODEAPI_HARDENED_SANDBOX_MODE=true"
  # Mit LOCAL_MODE=false verlangt die API entweder eine vollstaendige JWT-
  # Verifier-Konfiguration oder die ausdrueckliche Freigabe des Modus "none"
  # (siehe service/src/auth/startup.ts). Fehlt beides, startet der
  # API-Container gar nicht erst ("CODEAPI_JWT_ALLOWED_ALGS must include
  # EdDSA, RS256, or HS256" - die Meldung ist irrefuehrend, tatsaechlich
  # fehlt jede Schluesselquelle).
  if [[ "${JWT_AUTH}" == "true" ]]; then
    # Issuer/Audience entsprechen den Defaults des Verifiers, werden aber
    # bewusst explizit gesetzt: LibreChat muss exakt dieselben Werte
    # verwenden, sonst schlaegt die Pruefung fehl.
    echo "CODEAPI_AUTH_PROVIDER=librechat-jwt"
    echo "CODEAPI_JWT_ALLOWED_ALGS=EdDSA"
    echo "CODEAPI_JWT_ISSUER=${JWT_ISSUER}"
    echo "CODEAPI_JWT_AUDIENCE=${JWT_AUDIENCE}"
    echo "CODEAPI_JWT_KID=${JWT_KID}"
    echo "CODEAPI_JWT_PUBLIC_KEY=${JWT_PUBLIC_JWK}"
    echo "CODEAPI_JWT_SINGLE_TENANT_ID=${JWT_TENANT_ID}"
  else
    echo "CODEAPI_AUTH_PROVIDER=none"
    echo "CODEAPI_ALLOW_AUTH_PROVIDER_NONE=true"
  fi
  echo "KVM_ENABLED=${KVM_ENABLED}"
  echo "CODEAPI_INTERNAL_SERVICE_TOKEN=${CODEAPI_INTERNAL_SERVICE_TOKEN}"
  echo "CODEAPI_EGRESS_GRANT_SECRET=${CODEAPI_EGRESS_GRANT_SECRET}"
  echo "CODEAPI_EXECUTION_MANIFEST_PRIVATE_KEY=${PRIV_DER_B64}"
  echo "SANDBOX_EXECUTION_MANIFEST_PUBLIC_KEY=${PUB_DER_B64}"
  echo "SANDBOX_REQUIRE_EGRESS_MANIFEST=true"
  # MinIO- und Redis-Zugangsdaten bleiben bewusst auf den Repo-Standardwerten:
  # beide Dienste haengen NICHT im shared_proxy-Netz, sind also weder von
  # aussen noch von LibreChat aus erreichbar, nur containerintern im
  # Projekt-eigenen Netz.
} | ${SUDO} tee .env >/dev/null
${SUDO} chmod 600 .env
success ".env geschrieben."
 
# -----------------------------------------------------------------------------
# LibreChat-Konfigurationsblock erzeugen (nur bei JWT-Absicherung)
# -----------------------------------------------------------------------------
# Der private Schluessel gehoert ausschliesslich auf die LibreChat-Seite - er
# wird hier NICHT in die .env des Interpreters geschrieben. Die Datei wird als
# Vorlage abgelegt (chmod 600), damit sie auch spaeter noch verfuegbar ist.
LIBRECHAT_BLOCK_FILE=""
if [[ "${JWT_AUTH}" == "true" ]]; then
  if [[ "${MODE}" == "lokal" ]]; then
    LC_BASEURL="http://avila-api:3112/v1"
  else
    LC_BASEURL="https://${DOMAIN}/v1"
  fi
  LIBRECHAT_BLOCK_FILE="${INSTALL_DIR}/librechat-jwt-block.txt"
  ${SUDO} tee "${LIBRECHAT_BLOCK_FILE}" >/dev/null <<EOF
# ===========================================================================
# Code-Interpreter-Anbindung fuer LibreChat
# Erzeugt von install-avila-code-interpreter.sh am $(date '+%Y-%m-%d %H:%M')
# Diese Zeilen gehoeren in die .env von LibreChat.
# Der private Schluessel darf NUR dort liegen, nirgends sonst.
#
# WICHTIG - vorher pruefen:
# Falls in der .env bereits Zeilen mit LIBRECHAT_CODE_BASEURL= oder CODEAPI_
# stehen (z.B. von einem frueheren Code-Interpreter), muessen diese ENTFERNT
# oder auskommentiert werden. Sonst gewinnt die jeweils LETZTE Zuweisung in
# der Datei - stehen die alten Zeilen weiter unten, ueberschreiben sie die
# Werte hier, und die Anbindung schlaegt fehl (typisch: "unknown_kid", weil
# noch die alte Schluessel-Kennung gilt).
#
# Wo einfuegen: in den Abschnitt, in dem die uebrigen LIBRECHAT_CODE_-Werte
# stehen (in LibreChats .env meist unter einer Ueberschrift wie "Code
# Interpreter API"). Gibt es keinen solchen Abschnitt, kann der Block auch
# ans Dateiende angehaengt werden - Hauptsache, es bleiben keine aelteren
# Zeilen mit denselben Namen weiter unten stehen.
# ===========================================================================
LIBRECHAT_CODE_BASEURL=${LC_BASEURL}
CODEAPI_AUTH_PROVIDER=librechat-jwt
CODEAPI_JWT_ALGORITHM=EdDSA
CODEAPI_JWT_KID=${JWT_KID}
CODEAPI_JWT_ISSUER=${JWT_ISSUER}
CODEAPI_JWT_AUDIENCE=${JWT_AUDIENCE}
CODEAPI_JWT_TTL_SECONDS=300
CODEAPI_JWT_MINT_CACHE_SECONDS=30
CODEAPI_JWT_SINGLE_TENANT_ID=${JWT_TENANT_ID}
CODEAPI_JWT_PRIVATE_JWK_JSON=${JWT_PRIVATE_JWK}
EOF
  ${SUDO} chmod 600 "${LIBRECHAT_BLOCK_FILE}"
  success "LibreChat-Konfigurationsblock abgelegt: ${LIBRECHAT_BLOCK_FILE}"
 
  # Im lokalen Modus ist der Pfad bekannt und geprueft - dort kann der Block
  # auf Wunsch direkt angehaengt werden. Vorher wird die bestehende .env
  # gesichert, damit ein Rueckweg bleibt.
  if [[ "${MODE}" == "lokal" ]]; then
    echo ""
    read -rp "Block jetzt automatisch in ${LIBRECHAT_DIR}/.env eintragen? [J/n]: " LC_WRITE
    if [[ "${LC_WRITE,,}" != "n" ]]; then
      LC_BACKUP="${LIBRECHAT_DIR}/.env.vor-code-interpreter-$(date +%Y%m%d-%H%M%S)"
      ${SUDO} cp "${LIBRECHAT_DIR}/.env" "${LC_BACKUP}"
      # Vorhandene Eintraege auskommentieren, damit es keine Doppelungen gibt
      # (die letzte Zuweisung gewinnt zwar, aber doppelte Zeilen verwirren
      # beim spaeteren Nachsehen).
      ${SUDO} sed -i -E 's~^(LIBRECHAT_CODE_BASEURL=|CODEAPI_)~#&~' "${LIBRECHAT_DIR}/.env" 2>/dev/null || true
      ${SUDO} tee -a "${LIBRECHAT_DIR}/.env" >/dev/null < "${LIBRECHAT_BLOCK_FILE}"
      success "In LibreChats .env eingetragen (Sicherung: $(basename "${LC_BACKUP}"))."
      # Die Vorlagendatei enthaelt den privaten Signierschluessel. Nach dem
      # Eintragen steht er bereits in LibreChats .env - eine zweite Kopie
      # bringt keinen Nutzen mehr und koennte beim Aufraeumen uebersehen
      # werden (z.B. in einem Backup des Interpreter-Verzeichnisses).
      ${SUDO} rm -f "${LIBRECHAT_BLOCK_FILE}"
      LIBRECHAT_BLOCK_FILE=""
      info "Vorlagendatei mit dem privaten Schluessel wurde entfernt."
      LC_ENV_WRITTEN="true"
    else
      info "Nicht eingetragen - der Block liegt in ${LIBRECHAT_BLOCK_FILE}."
      LC_ENV_WRITTEN="false"
    fi
  fi
fi
 
# -----------------------------------------------------------------------------
# Schritt 7: docker-compose.override.yml (Namen, Netzwerk, keine Host-Ports)
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 7: Compose Override${RESET}"
echo "------------------------------------------------------------"
 
# Ohne /dev/kvm auf dem Host wuerde Docker beim Start versuchen, das nicht
# existierende Geraet in den Container zu mounten und abstuerzen - daher muss
# das devices-Mapping in diesem Fall explizit entfernt werden. Zusaetzlich
# braucht der NsJail-only-Modus selbst (laut Docker/Moby-Dokumentation zu
# "unshare: Operation not permitted") die Faehigkeit CAP_SYS_ADMIN sowie ein
# freigegebenes AppArmor-Profil, um Cgroups und Namespaces fuer die Sandbox
# einzurichten - ohne KVM uebernimmt NsJail diese Aufgabe direkt am Host.
#
# Drei bekannte, voneinander unabhaengige Upstream-Bugs im NsJail-only-
# Start-Skript (docker/start-direct-sandbox.sh):
#
# Bug 1 (fehlender Export): Das Skript setzt vor dem "exec unshare --mount
# bash -c '...'"-Block nur "export SANDBOX_ROOTFS=...", nicht aber ROOTFS
# selbst. Da "unshare" einen komplett neuen Bash-Prozess startet, der nur
# exportierte Umgebungsvariablen erbt (keine gewoehnlichen Shell-Variablen
# des Elternskripts), ist $ROOTFS innerhalb dieses Blocks leer.
# Fix: zusaetzlich "export ROOTFS=..." vor dem unshare-Aufruf ergaenzen.
#
# Bug 2 (Symlink-Bind-Falle, die eigentliche Ursache des "mount: command not
# found"-Fehlers): Im Basis-Image ist /usr/sbin nur ein Symlink auf
# /usr/bin ("merged-usr"-Layout). Ein "mount --bind ... /usr/sbin" mountet
# dabei nicht auf den Symlink selbst, sondern auf dessen AUFGELOESTES Ziel -
# also /usr/bin. Dadurch wird das komplette /usr/bin (inkl. "mount", "ls",
# "which", ...) sofort durch den Inhalt von $ROOTFS/usr/sbin ersetzt, der
# diese Programme nicht enthaelt (z.B. liegt "mount" im Sandbox-Rootfs nur
# unter usr/bin, nicht unter usr/sbin - dafuer aber der fuer die Sandbox
# unverzichtbare "nsjail"-Binary nur unter usr/sbin). Jeder folgende
# mount-Aufruf schlaegt darum mit "command not found" fehl.
# Fix: unmittelbar vor diesem einen Bind den Symlink /usr/sbin entfernen und
# durch ein echtes, leeres Verzeichnis ersetzen - dann bekommt der Bind sein
# eigenes Ziel, statt versehentlich /usr/bin zu ueberschreiben. Betrifft nur
# diesen Mount-Namespace des Sandbox-Runners, nicht den Host.
#
# Bug 3 (Bash-Pfad-Cache, Restrisiko): Selbst mit korrektem Bind-Ziel koennte
# Bashs interner Befehls-Cache theoretisch noch auf einen veralteten Pfad
# zeigen. Fix: "hash -r" nach dem sbin-Bind, leert den Cache zur Sicherheit.
#
# Alle drei Fixes werden ausschliesslich per schreibgeschuetztem Volume-Mount
# eingespielt, das geklonte Repo bleibt unveraendert. Bei einem spaeteren
# Update des Upstream-Images bleibt diese lokale Kopie wirkungslos-aber-
# harmlos, falls die Bugs dort inzwischen behoben wurden - es aendert sich
# nichts an ihrem Verhalten zum Schlechteren.
SANDBOX_DEVICES_OVERRIDE=""
SANDBOX_VOLUMES_OVERRIDE=""
if [[ "${KVM_ENABLED}" == "false" ]]; then
  SANDBOX_DEVICES_OVERRIDE='    devices: !reset []
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
'
  ${SUDO} mkdir -p ./nsjail-fix
  ${SUDO} sed \
    -e '/mount -o bind,ro "\$ROOTFS\/usr\/sbin"/i\    rm -f /usr/sbin \&\& mkdir -p /usr/sbin' \
    -e '/mount -o bind,ro "\$ROOTFS\/usr\/sbin"/a\    hash -r' \
    -e '/^export SANDBOX_ROOTFS="\$ROOTFS"$/a\export ROOTFS="$ROOTFS"' \
    docker/start-direct-sandbox.sh | ${SUDO} tee ./nsjail-fix/start-direct-sandbox.sh >/dev/null
  ${SUDO} chmod +x ./nsjail-fix/start-direct-sandbox.sh
  if ! grep -q '^    rm -f /usr/sbin && mkdir -p /usr/sbin$' ./nsjail-fix/start-direct-sandbox.sh; then
    die "Patch fuer start-direct-sandbox.sh (sbin-Symlink-Fix) konnte nicht angewendet werden - hat sich das Upstream-Skript geaendert?"
  fi
  if ! grep -q '^    hash -r$' ./nsjail-fix/start-direct-sandbox.sh; then
    die "Patch fuer start-direct-sandbox.sh (hash -r) konnte nicht angewendet werden - hat sich das Upstream-Skript geaendert?"
  fi
  if ! grep -q '^export ROOTFS="\$ROOTFS"$' ./nsjail-fix/start-direct-sandbox.sh; then
    die "Patch fuer start-direct-sandbox.sh (ROOTFS-Export) konnte nicht angewendet werden - hat sich das Upstream-Skript geaendert?"
  fi
  success "Korrigierte Kopie von start-direct-sandbox.sh erzeugt (sbin-Symlink-Fix + hash -r + ROOTFS-Export)."
 
  # Eigenes Healthcheck-Skript (siehe Bug 4 weiter unten): bewusst nur mit
  # Bash-Bordmitteln (/dev/tcp, read, printf) geschrieben, ohne curl/wget/
  # grep - denn nach den Bind-Mounts zeigt /usr/bin auf das Sandbox-Rootfs,
  # in dem diese Programme nicht enthalten sind.
  ${SUDO} tee ./nsjail-fix/avila-healthcheck.sh >/dev/null <<'HEALTHEOF'
#!/bin/bash
# Prueft die Sandbox-API auf 127.0.0.1:2000 - ausschliesslich mit
# Bash-Builtins, damit der Check auch nach den Bind-Mounts funktioniert.
# Bewusst der Wurzelpfad "/": auf diesem Port beantwortet der Sandbox-Runner
# ausschliesslich "/" mit 200; /health, /healthz, /ready und /v1/health
# liefern hier 404 (live gegen den laufenden Container verifiziert).
exec 3<>/dev/tcp/127.0.0.1/2000 || exit 1
printf 'GET / HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n' >&3 || exit 1
read -r statuszeile <&3 || exit 1
exec 3<&-
case "$statuszeile" in
    *" 200"*) exit 0 ;;
    *) exit 1 ;;
esac
HEALTHEOF
  ${SUDO} chmod +x ./nsjail-fix/avila-healthcheck.sh
  success "Eigenes Healthcheck-Skript erzeugt (ohne curl-Abhaengigkeit)."
 
  SANDBOX_VOLUMES_OVERRIDE='    volumes:
      - ./nsjail-fix/start-direct-sandbox.sh:/usr/local/bin/start-direct-sandbox.sh:ro
      - ./nsjail-fix/avila-healthcheck.sh:/avila-healthcheck.sh:ro
'
fi
 
# Bug 4 (Healthcheck laeuft ins Leere): Die Bind-Mounts ersetzen /usr/local
# und /usr/bin durch die Verzeichnisse des Sandbox-Rootfs. Damit verschwinden
# aus Sicht des Containers sowohl das vom Image mitgelieferte Skript
# /usr/local/bin/sandbox-runner-healthcheck.sh als auch die von ihm benutzten
# Programme (curl). Der Sandbox-Betrieb selbst ist davon NICHT betroffen (die
# API laeuft einwandfrei auf Port 2000) - aber Dockers Health-Status bleibt
# dauerhaft auf "starting" haengen, weshalb abhaengige Dienste wie
# service-worker ewig warten.
# Fix: Ein eigenes, minimales Healthcheck-Skript (oben erzeugt) wird an einen
# Pfad im Wurzelverzeichnis gemountet, den keiner der Binds beruehrt, und
# fragt die API ausschliesslich mit Bash-Bordmitteln ab (/dev/tcp statt
# curl). Zeitwerte identisch zum Original-Image (Interval 5s, Timeout 3s,
# Start-Period 20s, 60 Versuche).
SANDBOX_HEALTHCHECK_OVERRIDE=""
if [[ "${KVM_ENABLED}" == "false" ]]; then
  SANDBOX_HEALTHCHECK_OVERRIDE='    healthcheck:
      test: ["CMD", "/bin/bash", "/avila-healthcheck.sh"]
      interval: 5s
      timeout: 3s
      start_period: 20s
      retries: 60
'
fi
 
${SUDO} tee docker-compose.override.yml >/dev/null <<EOF
services:
  api:
    container_name: avila-api
    ports: !reset []
    networks:
      - default
      - ${DEFAULT_NPM_NETWORK}
 
  service-worker:
    container_name: avila-service-worker
 
  egress_gateway:
    container_name: avila-egress-gateway
    ports: !reset []
 
  tool_call_server:
    container_name: avila-tool-call-server
 
  sandbox-runner:
    container_name: avila-sandbox-runner
    ports: !reset []
${SANDBOX_DEVICES_OVERRIDE}${SANDBOX_VOLUMES_OVERRIDE}${SANDBOX_HEALTHCHECK_OVERRIDE}
 
  file_server:
    container_name: avila-file-server
    ports: !reset []
 
  redis:
    container_name: avila-redis
    ports: !reset []
 
  minio:
    container_name: avila-minio
    ports: !reset []
 
networks:
  ${DEFAULT_NPM_NETWORK}:
    external: true
EOF
 
${COMPOSE_CMD} config --quiet
success "docker-compose.override.yml ok. Kein Port ist oeffentlich am Host gebunden."
 
# -----------------------------------------------------------------------------
# Schritt 8: Stack bauen und starten
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 8: Stack bauen und starten${RESET}"
echo "------------------------------------------------------------"
warn "Der erste Build kann je nach Server-Leistung 10-30+ Minuten dauern -"
warn "das ist normal, es werden mehrere Images inkl. Laufzeitumgebungen"
warn "lokal kompiliert. Bitte nicht abbrechen."
if [[ "${KVM_ENABLED}" == "false" ]]; then
  warn "Im NsJail-Modus kommt danach noch ein zweiter Bauvorgang fuer die"
  warn "Laufzeitumgebungen der Sandbox hinzu - ebenfalls normal."
fi
${COMPOSE_CMD} build
 
# --- Laufzeitumgebungen fuer die Sandbox bereitstellen (nur NsJail) --------
# Im MicroVM-Modus (KVM_ENABLED=true) sind Python/Node/Bun/Bash fest in das
# Block-Root-Image eingebacken - dort ist nichts weiter zu tun.
# Im NsJail-Modus dagegen mountet der sandbox-runner die Laufzeiten zur
# Startzeit vom Host: "./data/pkgs" wird als "/host-packages" eingehaengt und
# im Container nach "/pkgs" gebunden (siehe docker-compose.yaml). Docker legt
# das Verzeichnis beim Start zwar automatisch an, befuellt es aber nicht.
# Bleibt es leer, startet der Stack zwar fehlerfrei und meldet "healthy", aber
# JEDE Codeausfuehrung scheitert mit "[bad_request] <runtime> is unknown" -
# ein Fehlerbild, das nach einem Problem der Anfrage aussieht, tatsaechlich
# aber schlicht fehlende Laufzeitumgebungen sind.
# Das Repo liefert dafuer ein eigenes Image (docker/Dockerfile.package-init),
# das in Kubernetes als Init-Job laeuft; fuer Docker Compose gibt es keinen
# Automatismus, deshalb wird es hier einmalig gebaut und ausgefuehrt.
if [[ "${KVM_ENABLED}" == "false" ]]; then
  printf '%b\n' "\n${BOLD}Laufzeitumgebungen der Sandbox erzeugen${RESET}"
  echo "------------------------------------------------------------"
  info "Im NsJail-Modus werden Python, Node, Bun und Bash einmalig gebaut und"
  info "unter ${INSTALL_DIR}/data/pkgs abgelegt. Python wird dabei aus dem"
  info "Quellcode kompiliert - das dauert erneut einige Minuten."
  ${SUDO} mkdir -p "${INSTALL_DIR}/data/pkgs"
  ${SUDO} docker build -f docker/Dockerfile.package-init -t avila-package-init . \
    || die "Image fuer die Laufzeitumgebungen konnte nicht gebaut werden."
  ${SUDO} docker run --rm -v "${INSTALL_DIR}/data/pkgs:/pkgs" avila-package-init \
    || die "Laufzeitumgebungen konnten nicht erzeugt werden."
  # Gegenpruefung: ohne diese vier Verzeichnisse waere jede spaetere
  # Codeausfuehrung wirkungslos, das faellt sonst erst beim ersten echten
  # Nutzer-Aufruf auf.
  for runtime in python node bun bash; do
    [[ -e "${INSTALL_DIR}/data/pkgs/${runtime}" ]] \
      || die "Laufzeitumgebung '${runtime}' fehlt unter ${INSTALL_DIR}/data/pkgs - Abbruch."
  done
  success "Laufzeitumgebungen bereit: python, node, bun, bash."
fi
 
${COMPOSE_CMD} up -d
 
wait_running() {
  local service="$1" cid state health
  info "Warte auf Service ${service}..."
  for _ in {1..80}; do
    cid="$(${COMPOSE_CMD} ps -q "${service}" 2>/dev/null || true)"
    if [[ -n "${cid}" ]]; then
      state="$(${SUDO} docker inspect --format '{{.State.Status}}' "${cid}" 2>/dev/null || true)"
      health="$(${SUDO} docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${cid}" 2>/dev/null || true)"
      if [[ "${health}" == "healthy" || ( "${health}" == "none" && "${state}" == "running" ) ]]; then
        success "${service} ist bereit (${state}, health=${health})."
        return 0
      fi
      [[ "${state}" == "exited" || "${state}" == "dead" ]] && break
    fi
    sleep 3
  done
  ${COMPOSE_CMD} ps || true
  ${COMPOSE_CMD} logs --tail=80 "${service}" || true
  die "Service ${service} wurde nicht bereit."
}
 
wait_running redis
wait_running minio
wait_running tool_call_server
wait_running egress_gateway
wait_running sandbox-runner
wait_running file_server
wait_running api
wait_running service-worker
 
# -----------------------------------------------------------------------------
# Schritt 9: Verifikation - kein Port oeffentlich
# -----------------------------------------------------------------------------
printf '%b\n' "\n${BOLD}Schritt 9: Sicherheits-Check${RESET}"
echo "------------------------------------------------------------"
PUBLIC_PORT_FOUND=0
for c in avila-api avila-egress-gateway avila-sandbox-runner avila-file-server avila-redis avila-minio; do
  if ${SUDO} docker port "${c}" 2>/dev/null | grep -q '0\.0\.0\.0\|\[::\]'; then
    warn "Container ${c} hat einen oeffentlich gebundenen Port - bitte pruefen: docker port ${c}"
    PUBLIC_PORT_FOUND=1
  fi
done
(( PUBLIC_PORT_FOUND == 0 )) && success "Kein Container hat einen oeffentlich gebundenen Port."
 
# -----------------------------------------------------------------------------
# Schritt 10: Abschluss
# -----------------------------------------------------------------------------
echo ""
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"
printf '%b\n' "${GREEN}${BOLD}#         Installation erfolgreich          #${RESET}"
printf '%b\n' "${GREEN}${BOLD}#############################################${RESET}"
 
if [[ "${MODE}" == "lokal" ]]; then
  echo ""
  info "Lokaler Modus: LibreChat erreicht den Interpreter direkt ueber den"
  info "Container-Namen im gemeinsamen Docker-Netzwerk '${DEFAULT_NPM_NETWORK}' -"
  info "es ist keine Domain und kein NPM-Proxy-Host noetig."
  echo ""
  if [[ "${JWT_AUTH}" == "true" && "${LC_ENV_WRITTEN:-false}" == "true" ]]; then
    success "Die Anbindung wurde bereits in LibreChats .env eingetragen."
    echo ""
    echo "Es fehlt nur noch ein echter Stop+Start von LibreChat, damit die neuen"
    echo "Werte gelesen werden (ein reines 'docker restart' genuegt NICHT):"
    echo ""
    echo "  docker stop LibreChat && docker start LibreChat"
  elif [[ "${JWT_AUTH}" == "true" ]]; then
    printf '%b\n' "${YELLOW}${BOLD}>>> Das ist der letzte offene Schritt - ohne ihn laeuft nichts. <<<${RESET}"
    echo ""
    echo "Der fertige Block liegt hier:"
    echo ""
    printf '%b\n' "  ${BOLD}${LIBRECHAT_BLOCK_FILE}${RESET}"
    echo ""
    printf '%b\n' "Vor dem Einfuegen ${BOLD}pruefen${RESET}, ob in ${LIBRECHAT_DIR}/.env schon"
    echo "Zeilen mit LIBRECHAT_CODE_BASEURL= oder CODEAPI_ stehen - falls ja,"
    echo "diese entfernen oder auskommentieren."
    printf '%b\n' "${YELLOW}Grund: In der .env gewinnt die LETZTE Zuweisung. Alte Zeilen weiter${RESET}"
    printf '%b\n' "${YELLOW}unten wuerden die neuen Werte ueberschreiben.${RESET}"
    echo ""
    echo "Danach LibreChat stoppen und starten (kein reines 'docker restart'):"
    echo ""
    echo "  docker stop LibreChat && docker start LibreChat"
  else
    echo "In der .env von LibreChat einzutragen (danach LibreChat stoppen und"
    echo "starten - ein reines 'docker restart' liest die .env NICHT neu):"
    echo ""
    echo "  LIBRECHAT_CODE_BASEURL=http://avila-api:3112/v1"
    echo ""
    warn "Hinweis: Ein Auth-Mechanismus fuer diese Verbindung ist nicht"
    warn "eingerichtet (offener Zugriff, abgesichert nur durch Netzwerk-Isolation -"
    warn "ausserhalb des Docker-Netzes ist der Dienst gar nicht erreichbar)."
  fi
else
  HOST_IPV4="$(detect_public_ipv4)"
  echo ""
  info "Externer Modus: Domain ${DOMAIN} muss auf diesen Server zeigen und in"
  info "NPM als Proxy Host angelegt werden."
  echo ""
  if [[ -n "${HOST_IPV4}" ]]; then
    cat <<DNS
1) Beim Domain-Provider einen A-Record auf diesen Host setzen:
 
   ${HOST_IPV4}   A   (TTL 300)   ${DOMAIN}
DNS
  else
    warn "Oeffentliche IPv4 konnte nicht automatisch ermittelt werden."
    echo "   Bitte die Server-IP manuell ermitteln und einen A-Record fuer"
    echo "   ${DOMAIN} beim Domain-Provider anlegen."
  fi
  cat <<NEXT
 
2) Proxy Host im Nginx Proxy Manager anlegen:
 
   Reiter Details:
     Domain:             ${DOMAIN}
     Scheme:             http
     Forward Hostname:   avila-api
     Forward Port:       3112
     Websockets Support: an
 
   Reiter SSL:
     SSL Certificate:    Request a new SSL Certificate (Let's Encrypt)
     Force SSL:          an
     HTTP/2 Support:     an
     HSTS Enabled:       an
 
3) In der .env von LibreChat einzutragen:
 
NEXT
  if [[ "${JWT_AUTH}" == "true" ]]; then
    printf '%b\n' "${YELLOW}${BOLD}   >>> Das ist der letzte offene Schritt - ohne ihn laeuft nichts. <<<${RESET}"
    echo ""
    echo "   Der fertige Block (inkl. privatem Signierschluessel) liegt hier:"
    echo ""
    printf '%b\n' "     ${BOLD}${LIBRECHAT_BLOCK_FILE}${RESET}"
    echo ""
    echo "   a) Inhalt dieser Datei auf den LibreChat-Server uebertragen."
    echo ""
    printf '%b\n' "   b) ${BOLD}Dort zuerst pruefen${RESET}, ob in der .env schon Zeilen mit"
    echo "      LIBRECHAT_CODE_BASEURL= oder CODEAPI_ stehen (z.B. von einem"
    echo "      frueheren Code-Interpreter). Falls ja: entfernen oder"
    echo "      auskommentieren."
    printf '%b\n' "      ${YELLOW}Grund: In der .env gewinnt die LETZTE Zuweisung. Bleiben alte${RESET}"
    printf '%b\n' "      ${YELLOW}Zeilen weiter unten stehen, ueberschreiben sie die neuen Werte${RESET}"
    printf '%b\n' "      ${YELLOW}und die Anbindung schlaegt fehl.${RESET}"
    echo ""
    echo "   c) Block in die .env von LibreChat einfuegen - dorthin, wo die"
    echo "      uebrigen LIBRECHAT_CODE_-Werte stehen (meist unter einer"
    echo "      Ueberschrift wie 'Code Interpreter API'). Gibt es keinen"
    echo "      solchen Abschnitt, geht auch das Dateiende."
    echo ""
    echo "   d) LibreChat stoppen und starten (ein reines 'docker restart'"
    echo "      liest die .env NICHT neu):"
    echo ""
    echo "        docker stop LibreChat && docker start LibreChat"
    echo ""
    warn "Der private Schluessel in dieser Datei gehoert ausschliesslich auf den"
    warn "LibreChat-Server. Nach dem Uebertragen hier loeschen:"
    warn "  rm ${LIBRECHAT_BLOCK_FILE}"
    echo ""
    info "Zusaetzlich empfohlen: In NPM eine 'Access List' anlegen und dem Proxy"
    info "Host zuweisen (nur die IP des LibreChat-Servers erlauben). Die JWT-"
    info "Pruefung schuetzt bereits vor fremden Auftraegen - die Access List haelt"
    info "unerwuenschten Traffic schon vor dem Interpreter ab."
  else
    echo "   LIBRECHAT_CODE_BASEURL=https://${DOMAIN}/v1"
    echo ""
    warn "WICHTIG: Der Dienst ist ueber diese Domain aktuell OHNE Passwort/Token"
    warn "erreichbar - jeder, der die Domain kennt, koennte Code ausfuehren."
    warn "Empfehlung: In NPM eine 'Access List' anlegen (Menuepunkt 'Access"
    warn "Lists' -> 'Add Access List' -> unter 'Access' eine Regel mit der"
    warn "IP-Adresse deines LibreChat-Servers als 'Allow', danach 'Deny' fuer"
    warn "alle uebrigen), und diese Access List dem Proxy Host oben im Reiter"
    warn "'Details' zuweisen. Damit nimmt NPM nur noch Traffic von dieser einen"
    warn "IP an, bevor er ueberhaupt den Interpreter erreicht."
  fi
fi
 
echo ""
if [[ "${KVM_ENABLED}" == "true" ]]; then
  success "Isolation: MicroVM-Modus (voll gehaertet, laut Projekt-Doku angemessen abgesichert)."
else
  warn "Isolation: NsJail-only-Modus (teilt sich den Host-Kernel, laut Projekt-Doku"
  warn "geeignet fuer lokale Tests, nicht fuer produktive Systeme mit unbekannten Nutzern)."
fi
echo ""
if [[ "${JWT_AUTH}" == "true" ]]; then
  success "Authentifizierung: Auftraege werden per JWT signiert und geprueft (EdDSA)."
else
  warn "Authentifizierung: nicht eingerichtet - der Interpreter fuehrt Code von"
  warn "jedem aus, der ihn erreicht. Absicherung nur ueber Netzwerk-Isolation."
fi
echo ""
info "Wichtige Befehle:"
echo "  Logs:    cd ${INSTALL_DIR} && ${COMPOSE_CMD} logs -f"
echo "  Status:  cd ${INSTALL_DIR} && ${COMPOSE_CMD} ps"
echo "  Update:  cd ${INSTALL_DIR} && git pull && ${COMPOSE_CMD} build && ${COMPOSE_CMD} up -d"
