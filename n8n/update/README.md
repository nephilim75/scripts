# 🔄 n8n Update Script

[🏠 Overview](../../) → [🔗 n8n](../) → Update

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-n8n-EA4B71?style=for-the-badge)](https://docs.n8n.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#)
[![Backup](https://img.shields.io/badge/Backup-before%20every%20run-2E7D32?style=flat-square)](#what-it-does)
[![Rollback](https://img.shields.io/badge/Rollback-automatic-2E7D32?style=flat-square)](#what-it-does)

Automated update script for a self-hosted [n8n](https://n8n.io) instance (including the `n8nio/runners` image), installed via [`install-n8n.sh`](../install/install-n8n.sh).

Updates an existing installation in place: version check, image pull, consistent backup, container restart, health check, and automatic rollback on failure — with no separate configuration step.

---

## Quick Update

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/update/update-n8n.sh)
```

Just like the installer, this can be run from anywhere — it no longer needs to
sit next to your `docker-compose.yml`. Asks for your installation folder
(default `/opt/n8n`), then for the target version, and walks through backup,
update, health check and automatic rollback on failure.

---

## Why this script?

- checks that `n8n` and `runners` images are version-synced before touching anything
- pulls the new images first, while n8n keeps running — a failed download changes nothing
- stops n8n before the backup, so the SQLite database is copied in a consistent state
- creates a full backup (data + `docker-compose.yml` + `.env`) that keeps file owners and permissions (`cp -a`)
- lets you pick any target version, including an older one, to downgrade
- checks health **inside the container** (`/healthz/readiness`) — independent of ports, reverse proxy, DNS or TLS
- rolls back automatically on failure: saves the logs of the failed version, stops the containers first, moves the failed data aside instead of deleting it, restores the backup with the correct owner, and verifies that n8n really runs again
- rotates old backups and removes old images only after a successful update; the previous version's image is kept for emergencies
- detects its configuration from your existing `docker-compose.yml` — nothing to set up first
- runs from anywhere via `bash <(curl ...)`, just like the installer — no need to download it into the install folder first

---

## What it does

1. Asks for your installation folder (`COMPOSE_DIR`, default `/opt/n8n`) and reads the current image versions from `docker-compose.yml`
2. Fetches the latest `n8n`/`runners` versions from Docker Hub – aborts if they're out of sync
3. Prompts for the target version (default: latest available) and confirms it exists for both images
4. Pulls the new images while n8n keeps running
5. Stops the containers and creates a backup (`n8n_data/`, `docker-compose.yml`, `.env`) with owners and permissions preserved – if the backup fails, n8n is started again unchanged
6. Updates `docker-compose.yml` and starts the containers with the new version
7. Runs a health check inside the n8n container (default: up to 3 minutes)
8. On failure: rollback (logs saved to the backup folder, failed data kept as `n8n_data.fehlgeschlagen-<timestamp>`, backup restored, health check of the old version)
9. On success: writes `current_version`, rotates old backups (`MAX_BACKUPS`), cleans up old images (keeps the new and the previous version)

---

## Requirements

- Bash ≥ 5
- `curl`
- `docker compose` (v2)
- An existing n8n installation with `docker-compose.yml` (e.g. via `install-n8n.sh`)

---

## Installation

The same thing step by step, if you prefer to look at the script before running it:

```bash
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/update/update-n8n.sh
chmod +x update-n8n.sh
./update-n8n.sh
```

Can be run from any directory — it will ask for the path to your installation.

---

## Configuration (optional)

No configuration file is required — every value is either asked for interactively, auto-detected, or defaulted:

| Value | Default | Description |
|---|---|---|
| `COMPOSE_DIR` | asked interactively, default `/opt/n8n` | Path to your n8n installation (docker-compose directory) |
| `BACKUP_DIR` | `${COMPOSE_DIR}/backups` | Backup target directory |
| `DATA_DIR` | `${COMPOSE_DIR}/n8n_data` | n8n data directory |
| `MAX_BACKUPS` | `5` | Maximum number of backups to keep |
| `N8N_IMAGE` / `RUNNERS_IMAGE` | `n8nio/n8n` / `n8nio/runners` | Docker images |
| `HEALTH_CHECK_RETRIES` / `HEALTH_CHECK_INTERVAL` | `36` / `5` | Health check attempts / seconds between them (3 minutes) |
| `N8N_INTERNAL_PORT` | `5678` | Port n8n listens on inside the container (`N8N_PORT`) |
| `N8N_UID` / `N8N_GID` | `1000` / `1000` | Owner of `n8n_data` (user `node` in the official image) |

The health check runs via `docker exec` inside the n8n container, so it does not need a public URL. The URL shown at the end is read from `N8N_WEBHOOK_URL` / `WEBHOOK_URL` in `docker-compose.yml`, if present.

To override any of these — e.g. for unattended/cron runs — export it as an environment variable before running the script:

```bash
COMPOSE_DIR=/opt/n8n MAX_BACKUPS=10 bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/update/update-n8n.sh)
```

---

## Useful Commands

```bash
cd /opt/n8n

# View service status
docker compose ps

# View live logs
docker compose logs -f

# Roll back manually to a specific backup
docker compose down
mv n8n_data n8n_data.alt-$(date +%Y%m%d_%H%M%S)
cp -a backups/n8n_backup_<version>_<timestamp>/n8n_data ./n8n_data
chown -R 1000:1000 n8n_data   # n8n runs as UID 1000 – without this it fails with EACCES
cp -a backups/n8n_backup_<version>_<timestamp>/docker-compose.yml .
docker compose up -d
```

---

## References

- [n8n](https://n8n.io)
- [n8n Docs](https://docs.n8n.io)
- [Docker Compose Docs](https://docs.docker.com/compose/)
- [pc-fee.com Blog](https://pc-fee.com/blog)

---

## Disclaimer

This script is provided "as is", without warranty of any kind. Use it at your
own risk. The author assumes no liability for damages, data loss, or other
consequences resulting from its use. Test it in a non-production environment
first.

---

## License

This project is licensed under the MIT License — see the
[LICENSE](../../LICENSE) file in the repository root.

<sub>This script was researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using it in production.</sub>

<sub>[← Back to the overview](../)</sub>
