#!/bin/sh
# =============================================================================
# smtp-set.sh – Setzt die SMTP-Werte in der LibreChat-.env.
# Wird sowohl fuer "Neu anlegen" als auch "Ueberschreiben" genutzt (technisch
# identische Aktion: Werte in die .env schreiben). Der Kontext-Text
# unterscheidet sich je nach Aufrufmodus ($1: "create" oder "overwrite").
# =============================================================================

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
. "$PROJECT_ROOT/lib/common.sh"

modus="${1:-create}"

heading "== SMTP-Konfiguration =="
if [ "$modus" = "overwrite" ]; then
    info "Bestehende SMTP-Werte werden mit deinen neuen Angaben ueberschrieben."
else
    info "Es wird eine neue SMTP-Konfiguration angelegt."
fi
info "Danach ist Passwort-Reset ueber die Login-Seite moeglich (ALLOW_PASSWORD_RESET wird auf true gesetzt)."
echo ""

printf "%b" "${C_BLUE}SMTP-Host (z.B. smtp.strato.de): ${C_RESET}"
read -r smtp_host

printf "%b" "${C_BLUE}SMTP-Port (z.B. 587 fuer TLS, 465 fuer SSL): ${C_RESET}"
read -r smtp_port

printf "%b" "${C_BLUE}Verschluesselung [tls/ssl/keine]: ${C_RESET}"
read -r smtp_encryption
case "$smtp_encryption" in
    keine|Keine|"") smtp_encryption="" ;;
esac

printf "%b" "${C_BLUE}Benutzername (leer lassen, falls SMTP ohne Login): ${C_RESET}"
read -r smtp_user

printf "%b" "${C_BLUE}Passwort (leer lassen, falls SMTP ohne Login): ${C_RESET}"
read -r smtp_pass

printf "%b" "${C_BLUE}Absendername (z.B. LibreChat): ${C_RESET}"
read -r smtp_from_name

printf "%b" "${C_BLUE}Absender-Mailadresse (z.B. noreply@deine-domain.de): ${C_RESET}"
read -r smtp_from

if [ -z "$smtp_host" ] || [ -z "$smtp_from" ]; then
    error "SMTP-Host und Absender-Mailadresse sind Pflichtfelder. Abbruch."
    exit 1
fi

set_env_value EMAIL_HOST "$smtp_host"
set_env_value EMAIL_PORT "$smtp_port"
set_env_value EMAIL_ENCRYPTION "$smtp_encryption"
set_env_value EMAIL_USERNAME "$smtp_user"
set_env_value EMAIL_PASSWORD "$smtp_pass"
set_env_value EMAIL_FROM_NAME "$smtp_from_name"
set_env_value EMAIL_FROM "$smtp_from"
set_env_value ALLOW_PASSWORD_RESET "true"

echo ""
success "SMTP-Konfiguration wurde gespeichert. ALLOW_PASSWORD_RESET=true gesetzt."
echo ""
heading "-- Zusammenfassung (bitte pruefen) --"
show_smtp_summary
echo ""
warn "Damit die Aenderungen wirken, muss LibreChat neu gestartet werden: docker restart ${LIBRECHAT_CONTAINER}"
