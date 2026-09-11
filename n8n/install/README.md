# 🚀 n8n Install Script

[🏠 Overview](../../) → [🔗 n8n](../) → Install

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-n8n-EA4B71?style=for-the-badge)](https://docs.n8n.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

Automated install script for a self-hosted [n8n](https://n8n.io) instance (including the `n8nio/runners` task-runner image), running behind [Nginx Proxy Manager](https://nginxproxymanager.com) via Docker Compose (SQLite, external runner, `shared_proxy` network).

Sets up n8n from scratch: directories, `.env`, `docker-compose.yml`, and container start.

---

## Why this script?

- checks all prerequisites first (Docker, Docker Compose, Nginx Proxy Manager, `shared_proxy` network)
- refuses to install over an existing installation — protects you from an `N8N_ENCRYPTION_KEY` mismatch that would break your existing credentials
- picks up the latest version where `n8n` and `runners` images are in sync automatically, with a safe fallback
- generates a secure runner auth token for you — no manual secret handling
- prints the exact Nginx Proxy Manager settings you need afterwards

---

## What it does

1. Checks prerequisites (Docker installed & running, Docker Compose available, Nginx Proxy Manager container running)
2. Ensures the `shared_proxy` Docker network exists (offers to create it if missing)
3. Detects an existing n8n installation and aborts instead of overwriting it
4. Determines the latest synced `n8n`/`runners` version from Docker Hub as a default
5. Prompts for domain, install path, n8n version, timezone, and an optional custom encryption key
6. Generates a secure runner auth token automatically
7. Creates `n8n_data/` and `backups/` with correct permissions (UID 1000)
8. Writes `.env` (mode 600) and `docker-compose.yml`
9. Pulls images and starts the stack (`n8n` + `task-runners`)
10. Prints the Nginx Proxy Manager settings and remaining setup steps

---

## Requirements

- Bash ≥ 5
- `curl`
- `docker compose` (v2)
- Docker network `shared_proxy` (created by [Nginx Proxy Manager](https://nginxproxymanager.com), or by this script on request)
- Nginx Proxy Manager running in the `shared_proxy` network
- A domain pointing at your server

---

## Installation

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/install/install-n8n.sh)
```

Or download and run it locally:

```bash
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/install/install-n8n.sh
chmod +x install-n8n.sh
./install-n8n.sh
```

---

## Interactive Setup

The script will prompt for:

| Input | Default | Description |
|---|---|---|
| Domain | *(required)* | Your n8n domain (e.g. `n8n.yourdomain.com`) |
| Install path | `/opt/n8n` | Directory for all n8n files |
| n8n version | latest synced version on Docker Hub (fallback: `2.30.3`) | Version to install |
| Timezone | `Europe/Berlin` | Container timezone |
| Encryption Key | *(auto-generated)* | Protects stored credentials |

The runner auth token is always generated automatically — you won't be asked for it.

---

## Updating an Existing Installation

This script will **not** install over an existing n8n setup — it detects one and aborts to avoid an encryption-key mismatch. To update an installation this script created, use the companion **[n8n Update Script](../update/README.md)** instead: it handles version checks, backups, image pulls, health checks and rollback for you.

---

## Post-Install Setup

After installation, set up a Proxy Host in Nginx Proxy Manager:

1. **Details tab:**
   - **Domain:** your n8n domain
   - **Scheme:** `http`
   - **Forward Hostname:** `n8n`
   - **Forward Port:** `5678`
   - Enable **Block Common Exploits** and **Websockets**
2. **SSL tab:**
   - Request a new certificate with **Let's Encrypt**
   - Enable **Force SSL**, **HTTP/2 Support**, and **HSTS**

---

## Access After Install

- **n8n:** `https://<YOUR_DOMAIN>`
- **Login:** create your admin account on first visit (no CLI step — n8n handles this in the browser)

---

## Useful Commands

```bash
cd /opt/n8n

# View service status
docker compose ps

# View live logs
docker compose logs -f

# Update to a new version
# → use the n8n Update Script instead of doing this by hand:
# https://github.com/nephilim75/scripts/tree/main/n8n/update
```

---

## References

- [n8n](https://n8n.io)
- [n8n Docs](https://docs.n8n.io)
- [Docker Compose Docs](https://docs.docker.com/compose/)
- [Nginx Proxy Manager](https://nginxproxymanager.com)
- [n8n Update Script](../update/README.md)
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
