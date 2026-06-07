#!/bin/bash
#
# ==============================================================================
#  Nginx Proxy Manager - Automatisches Update mit Backup
# ==============================================================================
#  Autor:    Nils Weber (n8n Automation Architect)
#  Firma:    pc-fee.com (https://pc-fee.com)
#  Lizenz:   MIT
#
#  Dieses Script baut auf dem folgenden Blogartikel auf und ergaenzt ihn um
#  ein automatisiertes Update inkl. Backup und Major-Version-Sprung:
#  https://pc-fee.com/nginx-proxy-manager/
#
#  Was es tut:
#    1. Erstellt ein Backup von data/ (inkl. SQLite-DB) und letsencrypt/
#    2. Behaelt nur die 5 neuesten Backups
#    3. Zieht das aktuellste Image und erkennt auch Major-Spruenge (z.B. v14->v15)
#    4. Erstellt den Container nur bei tatsaechlich neuem Image neu
#    5. Raeumt alte (dangling) Images auf
#
#  HINWEIS: Nachmachen auf eigene Gefahr. Backups vor Aenderungen sind Pflicht.
# ==============================================================================

set -euo pipefail

DIR=/opt/nginx-proxy-manager
BACKUP=/opt/nginx-proxy-manager/backups
TS=$(date +%F_%H-%M-%S)
LOG=/var/log/npm-update.log

exec > >(tee -a "$LOG") 2>&1
echo "=== $(date) NPM update start ==="

mkdir -p "$BACKUP"
cd "$DIR"

# 1) Backup data + letsencrypt (SQLite-DB liegt in data/)
tar czf "$BACKUP/npm_$TS.tar.gz" data letsencrypt
echo "Backup erstellt: npm_$TS.tar.gz"

# 2) Nur 5 letzte Backups behalten
ls -1t "$BACKUP"/npm_*.tar.gz | tail -n +6 | xargs -r rm -f

# 3) Image-ID vor Pull merken
OLD=$(docker compose images -q app || true)

# 4) Neuestes latest holen
docker compose pull

NEW=$(docker image inspect jc21/nginx-proxy-manager:latest -f '{{.Id}}')

# 5) Nur bei neuem Image sauber neu erstellen (erzwingt v14->v15)
if [ "$OLD" != "$NEW" ]; then
  docker compose up -d --force-recreate
  docker image prune -f
  echo "UPDATED: ${OLD} -> ${NEW}"
else
  echo "NOCHANGE: bereits aktuell"
fi

echo "=== $(date) NPM update done ==="
