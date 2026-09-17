# 🌐 Nginx Proxy Manager Install Script

[🏠 Overview](../../) → [🌐 Nginx Proxy Manager](../) → Install

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Guide](https://img.shields.io/badge/Guide-Nginx%20Proxy%20Manager-FE5200?style=for-the-badge)](https://pc-fee.com/nginx-proxy-manager/) [![Docs](https://img.shields.io/badge/Docs-nginxproxymanager.com-2496ED?style=for-the-badge)](https://nginxproxymanager.com/) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements) [![Host-ports](https://img.shields.io/badge/Host--ports-80%2C%20443%20%2B%2081%20local-E67E22?style=flat-square)](#security) [![Re-runnable](https://img.shields.io/badge/Re--runnable-guarded-2E7D32?style=flat-square)](#reinstalling-over-an-existing-instance)

A guided Bash installer that sets up a self-hosted [Nginx Proxy Manager](https://nginxproxymanager.com/) (NPM) **fully configured in one run**: it starts NPM via Docker Compose, **creates the admin account itself**, publishes the admin panel on **its own domain with a Let's Encrypt certificate**, and finally binds the admin port 81 to **localhost only**.

> The admin domain needs a DNS **A record pointing to this server before you start**, and ports 80 and 443 must be reachable from the internet. Without both, Let's Encrypt cannot issue the certificate.

---

## Quick Install

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/install/install-npm.sh)"
```

One command, in a root shell or with `sudo`. The script asks for the admin domain and a real email address, checks DNS and ports, installs NPM under `/opt/nginx-proxy-manager` and prints the generated admin credentials **once** at the end. Step-by-step variant: see [Installation](#installation).

---

## Why this script?

Installing NPM by hand leaves a window in which the admin panel is open on `http://SERVER-IP:81` and its **Welcome!** setup screen is not protected — whoever reaches it first becomes the admin. After that, SSL for the panel and closing port 81 are manual steps that are easy to postpone.

This installer closes that window:

- the admin account is created from a random 32-character password before the panel is ever reachable from outside
- the panel is served via HTTPS on its own domain, with Force SSL, HSTS and HTTP/2
- port 81 ends up on `127.0.0.1` only, and the initial credentials are removed from the Compose file again
- the NPM version is pinned, so the API calls it makes are known to work

---

## What it does

1. Verifies root, Docker, Docker Compose, `curl`, `openssl`, `tar`
2. Asks for install path, admin domain, admin email and Docker network (default `shared_proxy`)
3. Determines the public IPv4 and checks that the domain resolves to it; asks before continuing otherwise
4. Detects an existing NPM container or an old database in the install path and offers backup + reinstall (see [below](#reinstalling-over-an-existing-instance))
5. Checks that ports 80, 81 and 443 are free and names the process that blocks them
6. Shows a summary and asks for confirmation (default: no)
7. Writes `docker-compose.yml` (mode `600`) with the pinned image and `INITIAL_ADMIN_EMAIL` / `INITIAL_ADMIN_PASSWORD`, then starts NPM
8. Logs in via the NPM API and creates a Proxy Host `admin domain → http://localhost:81`
9. Requests a Let's Encrypt certificate and enables SSL, Force SSL, HSTS and HTTP/2 on that host
10. Checks that `https://<domain>/api/` answers with a valid certificate
11. Rewrites the Compose file: port 81 bound to `127.0.0.1`, initial credentials removed — then restarts NPM
12. Prints the credentials once, plus an SSH tunnel command as emergency access

---

## Requirements

- Linux server with Bash ≥ 4 (tested conceptually on Debian/Ubuntu)
- Docker + Docker Compose (v2 plugin or the legacy `docker-compose` binary)
- `curl`, `openssl`, `tar`; optional `ss` (port check), `getent` (DNS check), `python3` or `jq` (JSON parsing)
- A subdomain for the admin panel (e.g. `npm.example.com`) with an **A record** pointing to the server's public IPv4
- A **real email address** — it becomes the admin login and the Let's Encrypt account address; placeholders such as `admin@example.com` are rejected
- Ports **80 and 443** free on the host and open in the provider firewall; port **81** free locally
- An interactive terminal — the script reads its answers from `/dev/tty` and aborts without one

---

## Installation

The same thing step by step, if you prefer to read the script before running it:

```bash
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/install/install-npm.sh
chmod +x install-npm.sh
sudo ./install-npm.sh
```

It does not matter where the file lives — the script works with absolute paths only.

---

## Options

| Variable | Effect |
|---|---|
| `NPM_VERSION` | NPM image tag to install (default: the version pinned in the script). The API calls are tested against that default; test other versions first |

```bash
sudo NPM_VERSION=2.15.1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/install/install-npm.sh)"
```

The installed version stays pinned in `docker-compose.yml`. The [update script](../update/README.md) detects newer releases and moves the pin forward after a backup.

---

## After the installation

1. Open `https://<your admin domain>` and log in with the credentials printed at the end. They are shown **only once** and stored nowhere on the server — save them in a password manager right away.
2. Change the password in the user menu (top right).
3. Enable two-factor authentication in the same menu.
4. Point your other stacks at the `shared_proxy` network — the installers for [n8n](../../n8n/README.md), [SearXNG](../../searxng/README.md) and [LibreChat](../../librechat/README.md) expect it.

Emergency access to the admin panel, e.g. while the domain is unreachable:

```bash
ssh -L 8181:127.0.0.1:81 root@SERVER-IP
```

Then open `http://localhost:8181` in your local browser.

---

## Reinstalling over an existing instance

NPM only creates the admin account from `INITIAL_ADMIN_*` on an **empty** database. If the script finds an existing NPM container or data in `<install path>/data`, it therefore stops and offers two choices:

- **a** — abort (recommended), nothing is changed
- **b** — back up and reinstall: the old container is removed, its `data/` and `letsencrypt/` are archived to `backups/npm_<timestamp>_*.tar.gz` and then deleted

The old installation is located through the container itself (Compose working directory and mounts), so it is found even if it lived in a different path. Removal happens only after you have confirmed the summary. The archives use the same layout as the update script's backups and can be restored with `tar xzf <backup> -C <install path>`.

---

## Known pitfalls

- **Let's Encrypt fails** — almost always one of: the A record does not (yet) point to this server, port 80 is blocked by a provider firewall or security group, or the rate limit for this domain is exhausted. In that case the script keeps port 81 **open** and prints the credentials, so you can fix the cause and request the certificate in the UI.
- **HTTPS check fails although the certificate exists** — the script then asks before binding port 81 locally. If you decline, bind it later by changing `- '81:81'` to `- '127.0.0.1:81:81'` in `docker-compose.yml` and running `docker compose up -d`.
- **Cloudflare proxy (orange cloud)** — the DNS check shows Cloudflare IPs instead of the server IP. Continue only if HTTP on port 80 is passed through to the origin.
- **Custom network name** — the n8n, n8n Sandbox and SearXNG installers use `shared_proxy` unconditionally. The script warns and asks before accepting any other name.
- **Non-interactive runs are not supported** — without a terminal the script aborts at the first question.

---

## Uninstalling

Updates are handled by the [update script](../update/README.md). To remove the instance again — containers, `data/`, `letsencrypt/`, optionally backups and images — use the [uninstall script](../uninstall/README.md).

---

## Security

The script requires root: it writes to `/opt`, creates a Docker network and starts a container that publishes ports 80 and 443 and, after setup, port 81 on `127.0.0.1` only. During the run, port 81 is briefly reachable from outside while the admin account already exists with a random password. The Quick Install one-liner executes a remote script directly — review it first (see [Installation](#installation)) if you would rather not run it sight unseen.

Credentials are handled carefully: the password is generated with `openssl rand`, written to the Compose file only for the first start (file mode `600`, directory mode `700`) and removed from it afterwards; API login data and the token are passed to `curl` via files in a private temporary directory that is deleted on exit, never on the command line. Outbound connections go to `api.ipify.org` / `ifconfig.me` / `icanhazip.com` (public IP), Docker Hub (image) and, through NPM, Let's Encrypt.

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
