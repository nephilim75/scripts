# n8n Update Script

Automated update script for self-hosted [n8n](https://n8n.io) (including the `n8nio/runners` image).  
Handles version checking, backup, image pull, container restart, health check, automatic rollback on failure, and cleanup of old Docker images.

---

## Requirements

- Bash ≥ 5
- `curl`
- `docker compose` (v2)
- n8n deployed via `docker-compose.yml`

## Setup

1. Copy the example config and adjust it to your environment:

```bash
cp .env.example .env
nano .env
```

2. Make the script executable:

```bash
chmod +x update-n8n.sh
```

3. Run it:

```bash
sudo ./update-n8n.sh
```

## Configuration

All settings are managed via `.env` (never committed to Git). Copy `.env.example` to get started:

| Variable | Default | Description |
|---|---|---|
| `COMPOSE_DIR` | `/opt/n8n` | Path to docker-compose directory |
| `BACKUP_DIR` | `/opt/n8n/backups` | Backup target directory |
| `DATA_DIR` | `/opt/n8n/n8n_data` | n8n data directory |
| `MAX_BACKUPS` | `5` | Maximum number of backups to keep |
| `N8N_IMAGE` | `n8nio/n8n` | n8n Docker image |
| `RUNNERS_IMAGE` | `n8nio/runners` | n8n runners Docker image |
| `HEALTH_CHECK_URL` | *(your domain)* | URL used for health check after update |
| `HEALTH_CHECK_RETRIES` | `12` | Number of health check attempts |
| `HEALTH_CHECK_INTERVAL` | `5` | Seconds between attempts |

## What It Does

1. Fetches the latest version of both images (`n8nio/n8n`, `n8nio/runners`) from Docker Hub
2. Checks version sync between both images – aborts if they differ
3. Prompts for target version (default: latest)
4. Confirms target version exists on Docker Hub
5. Creates a data backup (rotation: max. 5 backups kept)
6. Updates `docker-compose.yml`
7. Pulls new images
8. Restarts containers
9. Runs health check against configured URL (up to 60 seconds)
10. Automatic rollback to previous version on failure
11. Cleans up old images

---

## AI Transparency

This script was created with AI assistance.  
**Models:** Claude Opus 4.6 / Claude Sonnet 4.6 (Anthropic)  
**Agent:** Nils Weber (n8n Automation Architect, pc-fee.com)

---

## License

MIT License – Copyright (c) 2026 pc-fee.com

Permission is hereby granted, free of charge, to any person obtaining a copy of this software to use, copy, modify, merge, publish, and/or distribute it, subject to the condition that this copyright notice is retained in all copies or substantial portions of the software.

**Disclaimer:** This script is provided without any warranty. Use at your own risk. pc-fee.com accepts no liability for any damages arising from the use of this script.
