# 🔄 n8n Update Script

<a href="https://pc-fee.com/blog/" target="_blank" rel="noopener noreferrer">
  <img src="https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge" alt="Visit the pc-fee.com blog for additional resources and tutorials" />
</a>
<a href="https://docs.n8n.io" target="_blank" rel="noopener noreferrer">
  <img src="https://img.shields.io/badge/Docs-n8n-EA4B71?style=for-the-badge" alt="Read the official n8n documentation" />
</a>
<br><br>

Automated update script for a self-hosted [n8n](https://n8n.io) instance (including the `n8nio/runners` image), installed via [`install-n8n.sh`](../install/install-n8n.sh).

Updates an existing installation in place: version check, backup, image pull, container restart, health check, and automatic rollback on failure — with no separate configuration step.

---

## 💡 Why this script?

- checks that `n8n` and `runners` images are version-synced before touching anything
- creates a full backup (data + `docker-compose.yml` + `.env`) before updating, with automatic rotation
- lets you pick any target version, including an older one, to downgrade
- runs a post-update health check and rolls back automatically on failure
- detects its configuration from your existing `docker-compose.yml` — nothing to set up first

---

## ✅ What it does

1. Determines its own folder and reads `docker-compose.yml` from there (`COMPOSE_DIR`, current image versions, health-check URL)
2. Fetches the latest `n8n`/`runners` versions from Docker Hub – aborts if they're out of sync
3. Prompts for the target version (default: latest available)
4. Confirms the target version exists on Docker Hub for both images
5. Creates a backup (`n8n_data/`, `docker-compose.yml`, `.env`), rotating old backups (`MAX_BACKUPS`)
6. Updates `docker-compose.yml`, pulls the new images, restarts containers
7. Runs a health check against the detected URL, rolling back automatically on failure
8. Cleans up old images

---

## 📋 Requirements

- Bash ≥ 5
- `curl`
- `docker compose` (v2)
- An existing n8n installation with `docker-compose.yml` (e.g. via `install-n8n.sh`)

---

## 📥 Installation

Unlike the installer, this script has to run **from the same folder as your `docker-compose.yml`** — it uses its own location to find the installation, so it can't be piped straight from `curl` into `bash` the way `install-n8n.sh` can.

```bash
cd /opt/n8n
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/update/update-n8n.sh
chmod +x update-n8n.sh
sudo ./update-n8n.sh
```

---

## ⚙️ Configuration (optional)

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

## 🛠️ Useful Commands

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

## 🤖 AI Transparency

Erstellt von Claude (Anthropic) im Auftrag von pc-fee.com.

---

## ⚖️ License

MIT License – Copyright (c) 2026 [pc-fee.com](https://pc-fee.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software to use, copy, modify, merge, publish, and/or distribute it, subject to the condition that this copyright notice is retained in all copies or substantial portions of the software.

**Disclaimer:** This script is provided without any warranty. Use at your own risk. pc-fee.com accepts no liability for any damages arising from the use of this script.

---

## 🔗 References

- [n8n](https://n8n.io)
- [n8n Docs](https://docs.n8n.io)
- [Docker Compose Docs](https://docs.docker.com/compose/)
- [pc-fee.com Blog](https://pc-fee.com/blog)
