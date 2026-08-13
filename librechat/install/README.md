# LibreChat Docker Installer

<a href="https://pc-fee.com/blog/" target="_blank" rel="noopener noreferrer">
  <img src="https://img.shields.io/badge/Blog-pc--fee.com-0A84FF?style=for-the-badge" alt="Visit the pc-fee.com blog for additional resources and tutorials" />
</a>
<a href="https://www.librechat.ai/docs" target="_blank" rel="noopener noreferrer">
  <img src="https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge" alt="Read the official LibreChat documentation" />
</a>

This installer is the practical companion to the step-by-step LibreChat setup described on the <a href="https://pc-fee.com/blog/" target="_blank" rel="noopener noreferrer">pc-fee.com blog</a>. It turns the blog walkthrough into a repeatable, scripted installation for a Docker-based environment behind Nginx Proxy Manager.

A ready-to-use installation script for LibreChat behind an existing Nginx Proxy Manager (NPM) setup.

---

## 🚀 Quickstart

Download and run directly from GitHub:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/install/install-librechat.sh)
```

Or run it locally after cloning this repo:

```bash
cd /path/to/scripts/librechat
bash install-librechat.sh
```

---

## 📦 What this script does

This installer:

- clones the official LibreChat repository
- creates the required environment configuration
- generates secure `.env` values automatically
- configures a Docker Compose override for your NPM network
- starts the full LibreChat stack with MongoDB, Meilisearch, RAG API, API and admin panel
- creates the admin user automatically
- prints the remaining DNS and NPM setup steps for you

> The setup intentionally does not expose LibreChat directly to a host port. It is meant to run behind an existing Docker network managed by Nginx Proxy Manager.

---

## 🧩 Components

| Component | Purpose |
|-----------|---------|
| LibreChat | Main chat application |
| MongoDB | Database |
| Meilisearch | Search backend |
| RAG API | Retrieval / AI context support |
| Admin Panel | Admin interface |

---

## ✅ Requirements

Before running the installer, make sure you have:

- a Debian-based Linux server
- root privileges or `sudo`
- `git` installed
- `docker` and it's Compose plugin installed/ enabled - :link: [![Badge linking to blog post about Docker Compose setup](https://img.shields.io/badge/Blogpost-Docker%20Compose-fe5200
)](https://pc-fee.com/docker-compose/)
- an existing Nginx Proxy Manager container with network called `shared_proxy` - :link: [![Badge linking to blog post about Nginx Proxy Manager setup](https://img.shields.io/badge/Blogpost-Nginx%20Proxy%20Manager-fe5200
)](https://pc-fee.com/nginx-proxy-manager/)

- valid domains for the chat and admin frontend
- an admin email address

---

## ⚙️ Default settings

The script uses these default values unless you override them:

- install directory: `/opt/librechat`
- NPM network: `shared_proxy`
- LibreChat branch: `main`

---

## 📝 Interactive prompts

The installer asks for:

- installation path
- Docker network name
- chat domain, e.g. `chat.example.de`
- admin domain, e.g. `chat-admin.example.de`
- admin email
- admin username
- admin display name
- admin password

The two domains must be different, and the password must be at least 12 characters long.

---

## 📁 Files created by the installer

In the target directory, the script creates or updates:

- `.env`
- `docker-compose.override.yml`
- `librechat.yaml` if it does not exist yet
- the LibreChat application files from the upstream repo

---

## 🌐 NPM and DNS setup

After installation, the script guides you through the remaining setup:

1. identification of server's public IPv4 to become able to
2. add two A-records for your domains at your domain provider
3. create two proxy hosts in Nginx Proxy Manager
   - chat domain → `api:3080`
   - admin domain → `admin-panel:3000`
4. enable SSL via Let's Encrypt
5. enable WebSockets and Force SSL

---

## 🔐 Admin user

The installer creates the admin user automatically without relying on the public registration form.

You can log in via:

- LibreChat: `https://<CHAT_DOMAIN>`
- Admin Panel: `https://<ADMIN_DOMAIN>`

---

## 🛠️ Useful commands

After installation:

```bash
cd /opt/librechat
docker compose ps
docker compose logs -f
```

If a service is not ready, the log output is usually the fastest way to identify the problem.

---

## ⚠️ Notes

- the script does not overwrite an existing installation
- existing LibreChat containers or images must be removed manually first
- always review the output and environment before using it in a production setup
- this script was assembled from the official LibreChat docs and project code, with iterative review and validation

---

## 🔗 References

- LibreChat: https://www.librechat.ai/
- LibreChat Docker docs: https://www.librechat.ai/docs/local/docker
- Nginx Proxy Manager guide: https://pc-fee.com/2026/05/03/nginx-proxy-manager/
- Docker Compose guide: https://pc-fee.com/2026/05/03/docker-compose/

---

## 📄 License

This script is part of this repository and follows the project license.
