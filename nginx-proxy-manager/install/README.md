# 🌐 Nginx Proxy Manager Install Script

[🏠 Overview](../../) → [🌐 Nginx Proxy Manager](../) → Install

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Guide](https://img.shields.io/badge/Guide-Nginx%20Proxy%20Manager-FE5200?style=for-the-badge)](https://pc-fee.com/nginx-proxy-manager/)
[![Docs](https://img.shields.io/badge/Docs-nginxproxymanager.com-2496ED?style=for-the-badge)](https://nginxproxymanager.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

A guided Bash installer for a self-hosted [Nginx Proxy Manager](https://nginxproxymanager.com/) (NPM) instance using Docker Compose.

This installer builds on and complements the following pc-fee.com guide:
**[Nginx Proxy Manager (pc-fee.com)](https://pc-fee.com/nginx-proxy-manager/)**

Hardening / Security steps:
**https://pc-fee.com/nginx-proxy-manager/#security**

---

## Installation

```bash
# Copy the script onto your server
cp install-npm.sh /root/

# Make it executable
chmod +x /root/install-npm.sh
```

---

## Usage

```bash
/root/install-npm.sh
```

After installation, access the admin UI at:

```
http://SERVER-IP:81
```

Default credentials (change immediately):

- Email: `admin@example.com`
- Password: `changeme`

---

## Why this script?

The guide is straightforward, but on fresh servers you often want a repeatable installer that:

- checks prerequisites (Docker / Docker Compose)
- creates the required folder structure under `/opt`
- creates/uses the `shared_proxy` Docker network
- starts NPM with a known-good `docker-compose.yml`

---

## What it does

1. Verifies you are running as `root`
2. Checks Docker + Docker Compose are installed and the Docker daemon is running
3. Ensures the external Docker network `shared_proxy` exists (can create it)
4. Creates the NPM directory structure (data, letsencrypt, backups)
5. Writes a `docker-compose.yml` (matching the blog guide)
6. Starts NPM via Docker Compose
7. Prints a short post-install hardening hint + link

---

## Requirements

- Linux server (tested conceptually on Debian/Ubuntu)
- Docker + Docker Compose installed
- Open ports 80 and 443 (TCP) at your provider/firewall (see security section in the guide)

---

## Security / Hardening (important)

During initial setup, port 81 is intentionally exposed so you can access the admin panel.

After completing initial configuration, follow the guide here:

**https://pc-fee.com/nginx-proxy-manager/#security**

Then bind the admin UI to localhost by changing the port mapping from:

```
- '81:81'
```

to:

```
- '127.0.0.1:81:81'
```

and restart:

```bash
cd /opt/nginx-proxy-manager
docker compose up -d
```

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

<sub>This script and its documentation were created with the help of AI models,
carried out by Nils Weber (AI assistant, n8n Automation Architect at pc-fee.com)
in collaboration with a human reviewer. Please verify for yourself before using it
in production.</sub>

<sub>[← Back to the overview](../)</sub>
