# 🔍 SearXNG Install Script

[🏠 Overview](../../) → [🔍 SearXNG](../) → Install

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Guide](https://img.shields.io/badge/Guide-SearXNG-FE5200?style=for-the-badge)](https://pc-fee.com/searxng/)
[![Docs](https://img.shields.io/badge/Docs-docs.searxng.org-2496ED?style=for-the-badge)](https://docs.searxng.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements)
[![Host-ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#what-it-does)
[![Re-runnable](https://img.shields.io/badge/Re--runnable-guarded-2E7D32?style=flat-square)](#what-it-does)

A guided Bash installer for a self-hosted [SearXNG](https://docs.searxng.org/) metasearch instance using Docker Compose, behind Nginx Proxy Manager.

This installer builds on and complements the following pc-fee.com guide:
**[SearXNG (pc-fee.com)](https://pc-fee.com/searxng/)**

> **A deliberate choice: no rate-limiter.** SearXNG ships a built-in rate-limiter/bot-detection that needs a cache backend (Valkey/Redis) to work. This installer turns it **off**, so automations such as an n8n agent calling the JSON API can never be throttled or blocked by SearXNG itself. The trade-off is that the instance then has **no built-in protection** against abuse from the public internet — see [Security](#security) for the recommended mitigation (an NPM Access List) and [Known pitfalls](#known-pitfalls) for the reasoning.

---

## Quick Install

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/searxng/install/install-searxng.sh)"
```

One command, in a root shell or with `sudo` — the script refuses to run without
root. It checks Docker, Docker Compose and the `shared_proxy` network, asks a
few questions (domain, install path, image tag, time zone, whether to enable
the JSON format), then writes `settings.yml` and `docker-compose.yml` and
starts SearXNG. Step-by-step variant: see [Installation](#installation) below.

---

## Why this script?

Running SearXNG "by hand" means hand-writing a `settings.yml` with a random
`secret_key`, deciding what the JSON-API and rate-limiter settings should be,
and wiring the container into your existing reverse-proxy network — easy to
get subtly wrong (a default `secret_key`, or a limiter that quietly throttles
your own automation). This script does all of that consistently and refuses
to run over an existing installation.

---

## What it does

1. Verifies you are running as `root`
2. Checks Docker + Docker Compose are installed and the Docker daemon is running
3. Checks that the external Docker network `shared_proxy` exists (created by [the Nginx Proxy Manager installer](../../nginx-proxy-manager/install/README.md)) and warns (with an opt-out) if no NPM container is running
4. Refuses to continue if a SearXNG container already exists, instead of installing over it
5. Asks for domain, install path, image tag, time zone and whether to enable the JSON output format
6. Generates a random 256-bit `secret_key` (`openssl rand -hex 32`, with a `/dev/urandom` fallback)
7. Writes `config/settings.yml` — `use_default_settings: true`, the generated `secret_key`, `server.base_url`, `server.limiter: false`, and `search.formats` including `json` if you opted in
8. Writes a `docker-compose.yml` with no published host ports (`expose: "8080"` only) on the `shared_proxy` network
9. Starts the container and prints the Nginx Proxy Manager Proxy Host settings to use, plus the rate-limiter/Access-List note below

---

## Requirements

- Linux server with Docker + Docker Compose installed
- A running [Nginx Proxy Manager](../../nginx-proxy-manager/README.md) instance on the `shared_proxy` network
- `openssl` (or `/dev/urandom`, always present) to generate the `secret_key`

---

## Installation

```bash
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/searxng/install/install-searxng.sh
chmod +x install-searxng.sh
sudo ./install-searxng.sh
```

It does not matter where the file lives — the script works with absolute paths only and asks for the install path (default `/opt/searxng`).

---

## Usage

After installation, create the Proxy Host in Nginx Proxy Manager (Forward
Hostname `searxng`, Forward Port `8080`) as printed at the end of the run,
request a Let's Encrypt certificate, then open your domain in the browser.

For programmatic access (e.g. an n8n HTTP Request node), and if you enabled
the JSON format during install:

```
GET https://<your-domain>/search?q=<query>&format=json
```

Calling it from inside the `shared_proxy` network (e.g. from n8n) works the
same way against the internal hostname, without going through the reverse
proxy: `http://searxng:8080/search?q=<query>&format=json`.

---

## Known pitfalls

- **No rate-limiter means no bot-protection.** This is intentional (see the callout above), but it means a public, unauthenticated SearXNG instance can be scraped, and heavy scraping can get *your* server's outgoing IP temporarily blocked by the search engines SearXNG queries (Google, Bing, DuckDuckGo, …). Restrict access — see [Security](#security).
- **The JSON format widens the attack surface.** It is what makes n8n/API access possible at all, but it also makes the instance more attractive to scrapers than the HTML-only default. Combine it with the Access List recommendation below if the instance is reachable from the public internet.
- **`secret_key` lives in `config/settings.yml`.** Treat that file like a credential; the [update](../update/README.md) and [uninstall](../uninstall/README.md) scripts back it up / warn about it accordingly.
- **The `latest` image tag can change under you.** Pin a specific tag during install if you need reproducible upgrades, and use the [update script](../update/README.md) rather than a bare `docker compose pull`.

---

## Security

The script requires root: it writes into `/opt`, creates a Docker network dependency check, and starts a container reachable from your `shared_proxy` network. The Quick Install one-liner executes a remote script directly — review it first (see [Installation](#installation)) if you would rather not run it sight unseen.

Because the built-in rate-limiter is disabled by design (see the callout above), the **recommended way to protect the public web UI** is an Nginx Proxy Manager **Access List**:

1. In NPM: **Access Lists** → **Add Access List** — add HTTP Basic Auth credentials and/or an IP allowlist (`Satisfy Any` for "either/or").
2. Open the Proxy Host for your SearXNG domain → **Details** tab → select that Access List.

This protects the public-facing domain without touching internal traffic: containers on the `shared_proxy` network calling `http://searxng:8080` directly (bypassing NPM) are unaffected by an NPM Access List, so n8n and other internal automation keep working exactly as before.

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
