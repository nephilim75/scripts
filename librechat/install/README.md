# 🚀 LibreChat Install Script

<a href="https://pc-fee.com/blog/" target="_blank" rel="noopener noreferrer">
  <img src="https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge" alt="Visit the pc-fee.com blog for additional resources and tutorials" />
</a>
<a href="https://www.librechat.ai/docs" target="_blank" rel="noopener noreferrer">
  <img src="https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge" alt="Read the official LibreChat documentation" />
</a>
<br><br>

Automated installer for self-hosted [LibreChat](https://www.librechat.ai/) instance (API, Admin Panel, MongoDB, Meilisearch, RAG), running behind [Nginx Proxy Manager](https://nginxproxymanager.com/) via Docker Compose.

This installer builds on and complements the official [LibreChat Docker guide](https://www.librechat.ai/docs/local/docker).

Sets up LibreChat from scratch: directories, `.env`, `docker-compose.yml`, containers and admin user.

---

## 🚀 Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/install/install-librechat.sh)
```

---

## 💡 Why this script?

The official docs are comprehensive, but you want a repeatable, automated installer that:

- checks prerequisites (Docker, Docker Compose, Nginx Proxy Manager)
- creates required folder structure under `/opt`
- generates secure `.env` values automatically
- creates `docker-compose.override.yml` for your NPM network
- starts the full LibreChat stack
- creates admin user via CLI (no web registration)
- guides you through DNS and NPM proxy setup

---

## ✅ What it does

1. Verifies you have `sudo` or run as `root`
2. Checks Docker + Docker Compose installed and daemon running
3. Ensures `shared_proxy` Docker network exists
4. Checks Nginx Proxy Manager container is running
5. Detects existing LibreChat installation (prevents overwrite)
6. Prompts for configuration (paths, domains, admin credentials)
7. Clones official [LibreChat repository](https://github.com/danny-avila/LibreChat)
8. Generates secure `.env` (random keys/secrets)
9. Creates `docker-compose.override.yml` for NPM network
10. Pulls Docker images and starts all services
11. Creates admin user automatically
12. Prints remaining setup steps (DNS, NPM proxy hosts)

---

## 📋 Requirements

- Linux server (Debian 12+)
- Bash ≥ 5
- `curl`, `git`
- `docker compose` (v2+)
- Docker network `shared_proxy` (created by [Nginx Proxy Manager](https://nginxproxymanager.com/))
- [Nginx Proxy Manager](https://nginxproxymanager.com/) running in `shared_proxy` network
- Two valid domains (chat + admin panel)
- Internet connection (pull Docker images, clone repository)

---

## 📥 Installation

1. Make the script executable and run it:

```bash
chmod +x install-librechat.sh
sudo ./install-librechat.sh
```

Or download and run directly:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/install/install-librechat.sh)
```

---

## ⚙️ Interactive Setup

The script will prompt for:

| Input | Default | Description |
|---|---|---|
| Install path | `/opt/librechat` | Directory for all LibreChat files |
| NPM network | `shared_proxy` | Docker network name |
| Chat domain | *(required)* | Public domain for chat (e.g. `chat.example.com`) |
| Admin domain | *(required)* | Public domain for admin panel (e.g. `chat-admin.example.com`) |
| Admin email | *(required)* | Admin account email |
| Admin username | *(derived from email)* | Admin login username |
| Admin name | *(from username)* | Admin display name |
| Admin password | *(required, min 12 chars)* | Admin password |

Both domains must be different. Password must be at least 12 characters.

---

## 🔒 Post-Install Setup

After successful installation, the script guides you through:

1. **DNS Configuration:** Set two A-records with your domain provider pointing to your server IP
2. **Nginx Proxy Manager:** Create two proxy hosts:
   - **Chat:** Domain → `api:3080` (enable WebSockets, SSL via Let's Encrypt)
   - **Admin Panel:** Domain → `admin-panel:3000` (enable WebSockets, SSL via Let's Encrypt)
3. **Access:** Login to LibreChat and Admin Panel via HTTPS

---

## 🌐 Access After Install

- **LibreChat Chat:** `https://<CHAT_DOMAIN>`
- **Admin Panel:** `https://<ADMIN_DOMAIN>`
- **Username:** Admin email or custom username
- **Password:** As configured during installation

---

## 🛠️ Useful Commands

```bash
cd /opt/librechat

# View service status
docker compose ps

# View live logs
docker compose logs -f

# Update LibreChat to latest
git pull
docker compose pull
docker compose up -d

# Create additional user
docker compose exec api node config/create-user.js \
  user@example.com username "Display Name" "password" --email-verified=True

# Backup database
docker compose exec -T mongodb mongodump --archive | gzip > backup.tar.gz
```

---

## 🤖 AI Transparency

This script was created with AI assistance.

**Models:** Claude Sonnet 5 (Anthropic), MiniMax3 / MiniMax (MiniMax)  
**Agent:** Cody (Senior AI Software Engineer, [pc-fee.com](https://pc-fee.com))

All technical statements verified against [official LibreChat docs](https://www.librechat.ai/docs) and [source code](https://github.com/danny-avila/LibreChat). Review and test before production use.

---

## ⚖️ License

MIT License – Copyright (c) 2026 [pc-fee.com](https://pc-fee.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software to use, copy, modify, merge, publish, and/or distribute it, subject to the condition that this copyright notice is retained in all copies or substantial portions of the software.

**Disclaimer:** This script is provided without any warranty. Use at your own risk.

---

## 🔗 References

- [Official LibreChat](https://www.librechat.ai/)
- [LibreChat Docs](https://www.librechat.ai/docs)
- [LibreChat GitHub](https://github.com/danny-avila/LibreChat)
- [Docker Compose Docs](https://docs.docker.com/compose/)
- [Nginx Proxy Manager](https://nginxproxymanager.com/)
- [pc-fee.com Blog](https://pc-fee.com/blog)
