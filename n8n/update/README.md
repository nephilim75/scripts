# 🔄 n8n Update Script

[🏠 Overview](../../) → [🔗 n8n](../) → Update

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-n8n-EA4B71?style=for-the-badge)](https://docs.n8n.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#)
[![Backup](https://img.shields.io/badge/Backup-before%20every%20run-2E7D32?style=flat-square)](#what-it-does)
[![Rollback](https://img.shields.io/badge/Rollback-automatic-2E7D32?style=flat-square)](#what-it-does)

Automated update script for a self-hosted [n8n](https://n8n.io) instance (including the `n8nio/runners` image), installed via [`install-n8n.sh`](../install/install-n8n.sh).

Updates an existing installation in place: version check, backup, image pull, container restart, health check, and automatic rollback on failure — with no separate configuration step.

---

## Quick Update

```bash
cd /opt/n8n && curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/update/update-n8n.sh && chmod +x update-n8n.sh && sudo ./update-n8n.sh
```

Unlike the installer, this script has to run **from the same folder as your
`docker-compose.yml`** — it uses its own location to find the installation, so it
can't be piped straight from `curl` into `bash` the way `install-n8n.sh` can. That
is why the one-liner changes into the install directory first; adjust the path if
yours differs from `/opt/n8n`.

---

## Why this script?

- checks that `n8n` and `runners` images are version-synced before touching anything
- creates a full backup (data + `docker-compose.yml` + `.env`) before updating, with automatic rotation
- lets you pick any target version, including an older one, to downgrade
- runs a post-update health check and rolls back automatically on failure
- detects its configuration from your existing `docker-compose.yml` — nothing to set up first

---

## What it does

1. Determines its own folder and reads `docker-compose.yml` from there (`COMPOSE_DIR`, current image versions, health-check URL)
2. Fetches the latest `n8n`/`runners` versions from Docker Hub – aborts if they're out of sync
3. Prompts for the target version (default: latest available)
4. Confirms the target version exists on Docker Hub for both images
5. Creates a backup (`n8n_data/`, `docker-compose.yml`, `.env`), rotating old backups (`MAX_BACKUPS`)
6. Updates `docker-compose.yml`, pulls the new images, restarts containers
7. Runs a health check against the detected URL, rolling back automatically on failure
8. Cleans up old images

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
cd /opt/n8n
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/update/update-n8n.sh
chmod +x update-n8n.sh
sudo ./update-n8n.sh
```

---

## Configuration (optional)

No configuration file is required — every value is auto-detected or defaulted:

| Value | Default | Description |
|---|---|---|
| `COMPOSE_DIR` | folder containing the script | Path to docker-compose directory |
| `BACKUP_DIR` | `${COMPOSE_DIR}/backups` | Backup target directory |
| `DATA_DIR` | `${COMPOSE_DIR}/n8n_data` | n8n data directory |
| `MAX_BACKUPS` | `5` | Maximum number of backups to keep |
| `N8N_IMAGE` / `RUNNERS_IMAGE` | `n8nio/n8n` / `n8nio/runners` | Docker images |
| `HEALTH_CHECK_URL` | read from `WEBHOOK_URL` in `docker-compose.yml` | URL for the post-update health check |
| `HEALTH_CHECK_RETRIES` / `HEALTH_CHECK_INTERVAL` | `12` / `5` | Health check attempts / seconds between them |

To override any of these, copy `.env.example` to `.env` in the same folder and adjust.

---

## Useful Commands

```bash
cd /opt/n8n

# View service status
docker compose ps

# View live logs
docker compose logs -f

# Roll back manually to a specific backup
cp -r backups/n8n_backup_<version>_<timestamp>/n8n_data ./n8n_data
cp backups/n8n_backup_<version>_<timestamp>/docker-compose.yml .
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

<sub>This script was created with the help of AI models (Claude, Anthropic),
commissioned by pc-fee.com. Please verify for yourself before using it in
production.</sub>

<sub>[← Back to the overview](../)</sub>
