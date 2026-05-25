# n8n Install Script

Automated install script for self-hosted [n8n](https://n8n.io) (including the `n8nio/runners` image), running behind [Nginx Proxy Manager](https://nginxproxymanager.com) via Docker Compose.

Sets up n8n from scratch: directories, `.env`, `docker-compose.yml`, and container start.

---

## Requirements

- Bash ≥ 5
- `curl`
- `docker compose` (v2)
- Docker network `shared_proxy` (created by Nginx Proxy Manager)
- Nginx Proxy Manager running in `shared_proxy` network

---

## Setup

1. Make the script executable and run it:

```bash
chmod +x install-n8n.sh
sudo ./install-n8n.sh
```

The script will interactively ask for:

| Input | Default | Description |
|---|---|---|
| Domain | *(required)* | Your n8n domain (e.g. `n8n.yourdomain.com`) |
| Install path | `/opt/n8n` | Directory for all n8n files |
| n8n version | `2.22.2` | Version to install |
| Timezone | `Europe/Berlin` | Container timezone |
| Encryption Key | *(auto-generated)* | Protects stored credentials |

2. After installation, set up a Proxy Host in Nginx Proxy Manager:

- **Domain:** your n8n domain
- **Forward Hostname:** `n8n`
- **Forward Port:** `5678`
- **Websockets Support:** ✔ enabled
- **SSL:** Let's Encrypt + Force SSL

---

## What It Does

1. Checks prerequisites (Docker, Docker Compose, Nginx Proxy Manager, `shared_proxy` network)
2. Prompts for configuration interactively
3. Creates directories (`n8n_data/`, `backups/`) with correct permissions (UID 1000)
4. Writes `.env` (permissions: 600) and `docker-compose.yml`
5. Pulls images and starts containers (`n8n` + `n8n-task-runners`)

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
