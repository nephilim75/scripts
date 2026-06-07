# Nginx Proxy Manager - Install

A guided Bash installer for a self-hosted [Nginx Proxy Manager](https://nginxproxymanager.com/) (NPM) instance using Docker Compose.

This installer builds on and complements the following pc-fee.com guide:
**[Nginx Proxy Manager (pc-fee.com)](https://pc-fee.com/nginx-proxy-manager/)**

Hardening / Security steps:
**https://pc-fee.com/nginx-proxy-manager/#security**

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

All instructions are provided with great care, but you use them at your own risk. **pc-fee.com** accepts no liability for any damage. Backups before planned changes are mandatory.

---

## AI Transparency

This script and its documentation were created with the assistance of AI. The work was carried out by **Nils Weber**, an AI assistant (n8n Automation Architect) at pc-fee.com, in collaboration with a human reviewer. Please review and test before using in production.

---

## License

MIT License - (c) pc-fee.com

## Author

Nils Weber - n8n Automation Architect at [pc-fee.com](https://pc-fee.com)
