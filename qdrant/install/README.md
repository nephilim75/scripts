# 🚀 Qdrant Install Script

[🏠 Overview](../../) → [🧮 Qdrant](../) → Install

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-Qdrant-DC244C?style=for-the-badge)](https://qdrant.tech/documentation/) [![GitHub](https://img.shields.io/badge/GitHub-qdrant-181717?style=for-the-badge&logo=github)](https://github.com/qdrant/qdrant) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements) [![Host-ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#what-it-does) [![Re-runnable](https://img.shields.io/badge/Re--runnable-guarded-2E7D32?style=flat-square)](#what-it-does)

A guided Bash installer for a self-hosted [Qdrant](https://qdrant.tech/) vector database using **Docker Compose**, behind **Nginx Proxy Manager** — built as the vector store for **n8n**. Qdrant is reachable internally as `http://qdrant:6333` and from outside through your domain, protected by a generated **admin API key**.

> **The API key is shown exactly once.** At the end of the run the script prints the generated admin API key. Store it in your password manager right away — afterwards it only lives in `<install path>/.env` (readable by root only).

---

## Quick Install

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/install/install-qdrant.sh)"
```

One command, in a root shell or with `sudo` — the script refuses to run without root. It checks the prerequisites, asks a few questions (domain, install path, backup path, proxy network, image tag, telemetry), then writes `.env` and `docker-compose.yml`, starts Qdrant and verifies that the API key is enforced. Step-by-step variant: see [Installation](#installation) below.

---

## Why this script?

Running Qdrant "by hand" behind a reverse proxy means deciding how to expose it without opening a port, remembering that a Qdrant without API key is wide open the moment it gets a public domain, and picking an image tag you can upgrade from later. This script does all of that consistently, pins a real release by default (so the [update script](../update/README.md) can plan clean upgrade steps), and refuses to run over an existing installation.

---

## What it does

1. Verifies you are running as `root` and switches to `/`, so a deleted working directory cannot break later calls
2. Checks Docker, a running Docker daemon, Docker Compose and `curl` (offers to install `curl` via `apt-get`, only after you agree)
3. Checks **separately** that a Nginx Proxy Manager container is running (image `jc21/nginx-proxy-manager`) — without it, it warns that Qdrant will only be reachable internally and asks whether to continue
4. Refuses to continue if any container with a `qdrant/qdrant` image exists (detected by image, not by name), or if a container named `qdrant` already exists
5. Asks for:
   - the **domain** — validated, e.g. `qdrant.example.com`
   - the **install path** — default `/opt/qdrant`, must be empty or not exist yet
   - the **backup path** — default `/opt/qdrant-backups`, must be outside the install path
   - the **proxy network** — default `shared_proxy`, must exist; warns if NPM is not attached to it
   - the **image tag** — the newest stable release is suggested (looked up via the GitHub releases, falling back to Docker Hub)
   - whether to **disable telemetry** — default yes
6. Generates a 256-bit admin API key (`openssl rand -hex 32`, with a `/dev/urandom` fallback)
7. Pulls the image **before** writing anything, so a wrong tag fails without leaving files behind
8. Writes `.env` (mode `600`) and a `docker-compose.yml` with `expose: "6333"` only — no published host ports, no gRPC — and the volumes `storage/` and `snapshots/`
9. Validates the Compose file (`docker compose config --quiet`), starts Qdrant and waits for `/readyz`
10. Checks that the API key is enforced (`/collections` answers `401` without and `200` with the key)
11. Prints the API key once, the DNS record, the Nginx Proxy Manager Proxy Host settings, the dashboard URL and the n8n credential values

---

## Requirements

- Linux server with Docker + Docker Compose installed ([pc-fee.com guide](https://pc-fee.com/docker-compose/))
- A running [Nginx Proxy Manager](../../nginx-proxy-manager/README.md) instance on the proxy network (default `shared_proxy`)
- `curl`; `openssl` is used for the API key if present (otherwise `/dev/urandom`)
- A domain (or subdomain) whose A record you can point at this server

---

## Installation

```bash
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/install/install-qdrant.sh
chmod +x install-qdrant.sh
sudo ./install-qdrant.sh
```

It does not matter where the file lives — the script works with absolute paths only and asks for the install path.

What ends up on disk:

| Path | Content |
|---|---|
| `/opt/qdrant/docker-compose.yml` | The Qdrant service, `expose: "6333"`, on the external proxy network |
| `/opt/qdrant/.env` | `QDRANT_API_KEY`, telemetry setting, domain and backup path (mode `600`) |
| `/opt/qdrant/storage/` | All collections — mounted at `/qdrant/storage` |
| `/opt/qdrant/snapshots/` | Qdrant's working folder for snapshots — mounted at `/qdrant/snapshots` |
| `/opt/qdrant-backups/` | Target of the [update](../update/README.md) and [backup](../backup/README.md) scripts (mode `700`) |

---

## Usage

**1. DNS** — point an A record for your domain at this server. The script prints the server's public IPv4 if it can determine it.

**2. Proxy Host in Nginx Proxy Manager** (*Hosts → Proxy Hosts → Add Proxy Host*):

| Setting | Value |
|---|---|
| Domain Names | your Qdrant domain |
| Scheme | `http` |
| Forward Hostname | `qdrant` |
| Forward Port | `6333` |
| Block Common Exploits | on |
| SSL | Request a new Let's Encrypt certificate, Force SSL, HTTP/2, HSTS |

**3. Dashboard** — open `https://<your-domain>/dashboard` and enter the API key.

**4. n8n** — *Credentials → Add Credential → Qdrant API*:

| Field | n8n on the same host (in `shared_proxy`) | n8n elsewhere |
|---|---|---|
| Qdrant URL | `http://qdrant:6333` | `https://<your-domain>` |
| API Key | the admin API key | the admin API key |

The internal URL is faster and does not depend on the proxy, but only works when the n8n container is attached to the same network.

---

## Known pitfalls

- **Changing `.env` needs a recreate, not a restart.** Environment values are fixed when the container is created. After editing `.env` (e.g. a new API key), run `docker compose -f /opt/qdrant/docker-compose.yml up -d` — a `docker restart qdrant` keeps the old values.
- **Pinned tag vs. `latest`.** You can enter `latest` at the tag prompt, but a fixed version (`vX.Y.Z`) is recommended: Qdrant must not skip minor versions when upgrading, and the update script plans the steps from the version that is actually running.
- **The dashboard itself loads without a key.** Its static files are public; every data request it makes needs the API key. Restrict the domain further with an NPM Access List if you do not want the dashboard reachable at all.
- **The internal URL is plain HTTP.** Traffic between n8n and Qdrant inside `shared_proxy` is unencrypted — fine on a single host, not across hosts.

---

## Security

The script requires root: it writes into `/opt`, generates a credential and starts a container on your proxy network. The Quick Install one-liner executes a remote script directly — review it first (see [Installation](#installation)) if you would rather not run it sight unseen.

- **No host port is published.** Qdrant is only reachable inside the proxy network and through the Nginx Proxy Manager Proxy Host you create.
- **The admin API key protects everything except the health endpoints.** `/`, `/healthz`, `/livez` and `/readyz` answer without a key (version and health only); collections, points, snapshots and telemetry require it.
- **The key is printed once and never logged.** It is stored in `.env` with mode `600`; the backup directory is created with mode `700`.
- **Telemetry** is disabled by default (`QDRANT__TELEMETRY_DISABLED=true`); you can keep it on at the prompt.

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
