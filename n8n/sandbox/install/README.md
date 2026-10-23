# 🧪 n8n Sandbox Install Script

[🏠 Overview](../../../) → [🔗 n8n](../../) → [🧪 Sandbox](../) → Install

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-n8n--Sandbox-00B8D9?style=for-the-badge)](https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/README.md) [![GitHub](https://img.shields.io/badge/GitHub-n8n--sandbox--service-181717?style=for-the-badge&logo=github)](https://github.com/n8n-io/n8n-sandbox-service) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#) [![Ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#security-notes) [![Idempotent](https://img.shields.io/badge/Re--runnable-guarded-2E7D32?style=flat-square)](#what-it-does)

Automated installer for the self-hosted [n8n Sandbox Service](https://github.com/n8n-io/n8n-sandbox-service) (isolated code execution for n8n) via Docker Compose — **no publicly bound ports**. The privileged runner sits in a stack-internal network of its own; only the API joins the shared `shared_proxy` network.

Asks up front how n8n reaches the sandbox: **directly on the same host** (n8n in `shared_proxy`, internal URL `http://sandbox-api:8080`, no domain and no NPM) or **through a domain** behind [Nginx Proxy Manager](https://nginxproxymanager.com/). Sets up the sandbox from scratch: directories, `.env`, `docker-compose.yml`, and container start.

---

## Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/install/install-n8n-sandbox.sh)
```

The installer checks prerequisites, prompts for the required values, generates secure secrets, and starts the stack automatically.

> **No leading `sudo` needed:** the script detects whether it's already running as root and, if not, automatically prefixes every privileged command with `sudo` internally. Don't add `sudo` yourself in front of this command — `sudo bash <(curl ...)` fails on most systems with `bash: /dev/fd/NN: No such file or directory`, because `sudo` closes inherited file descriptors above stderr by default, and that's exactly where process substitution hands off the downloaded script.

---

## What You Get

- ✅ n8n Sandbox Service (API + Runner) via Docker Compose
- ✅ No exposed ports — reached either directly by n8n on the same host or through Nginx Proxy Manager
- ✅ Privileged runner isolated in its own `sandbox_intern` network, unreachable from other containers in `shared_proxy`
- ✅ mTLS between API and Runner, bootstrapped automatically
- ✅ Secure random secrets generated for you (no weak defaults)
- ✅ Runs alongside an existing n8n install, or completely standalone
- ✅ Safe re-run guard — refuses to install over an existing sandbox
- ✅ Production-ready `restart: unless-stopped` setup

---

## Why this script?

The [official quickstart](https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/quickstart-linux.md) is straightforward, but on fresh servers you want a repeatable installer that:

- checks prerequisites (Docker, Docker Compose, `shared_proxy`, and Nginx Proxy Manager when you use a domain)
- refuses to install over an existing sandbox (would break registered runners / mTLS)
- generates strong, unique secrets automatically
- writes a known-good `docker-compose.yml` + `.env`
- starts the stack and waits for a healthy API
- tells you exactly what to configure afterwards — in n8n only, or in NPM and n8n

---

## What it does

1. Detects whether it's already running as `root`; if not, transparently prefixes every privileged command with `sudo` (asks for your password once, same as any other `sudo` command)
2. Checks Docker + Docker Compose are installed and the Docker daemon is running
3. Asks whether n8n runs on this host in the `shared_proxy` network (suggests "yes" if a running `n8nio/n8n` container is attached to it)
4. Checks Nginx Proxy Manager is running — required only for domain access (dies with a guide link if missing); in same-host mode a missing NPM is just noted
5. Ensures the external Docker network `shared_proxy` exists (offers to create it)
6. Detects an existing sandbox installation and aborts safely instead of overwriting secrets/certificates
7. Prompts for install path, the domain you'll point at it via NPM (domain mode only), and the image tag
8. Generates three random 48-character secrets (`SANDBOX_API_KEYS`, `SANDBOX_API_RUNNER_REGISTRATION_TOKEN`, `SANDBOX_API_RUNNER_API_KEY`)
9. Writes `.env` (permissions `600`) and `docker-compose.yml` with two networks: `shared_proxy` (only `sandbox-api`) and the stack-internal `sandbox_intern`
10. Pulls images, starts the stack (`sandbox-certs` → `sandbox-api` → `sandbox-runner-1`), and waits for the API health check
11. Prints what to configure next: in same-host mode only the internal Service URL for n8n, otherwise DNS, the NPM Proxy Host and the n8n settings

---

## Requirements

- Linux server with Docker + Docker Compose (v2) installed
- Bash ≥ 5
- `curl`
- Docker network `shared_proxy` (created by the [Nginx Proxy Manager installer](https://github.com/nephilim75/scripts/tree/main/nginx-proxy-manager))
- **Same-host mode:** n8n running on this host and attached to `shared_proxy`
- **Domain mode:** Nginx Proxy Manager running in `shared_proxy`, plus a DNS record for the domain you want to expose the sandbox API under

---

## Installation

Make the script executable and run it:

```bash
chmod +x install-n8n-sandbox.sh
./install-n8n-sandbox.sh
```

Or run it straight from GitHub without saving it first:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/install/install-n8n-sandbox.sh)
```

Neither form needs a leading `sudo` — see the note under [Quick Install](#quick-install).

---

## Interactive Setup

The script will prompt for:

| Input | Default | Description |
|---|---|---|
| n8n on this host? | `j` if a running n8n container is found in `shared_proxy`, else `n` | `j` = same-host mode (no domain, NPM optional), `n` = domain mode behind NPM. Env var: `N8N_SAME_HOST=j\|n`; without a terminal and without the variable, `n` is used |
| Install path | `/opt/n8n-sandbox` | Directory for `.env` + `docker-compose.yml` |
| Domain | *(required in domain mode)* | Domain you'll point at the sandbox API via NPM (e.g. `n8n-sandbox.yourdomain.tld`) — documentation only, not consumed by any container. Not asked in same-host mode |
| Image tag | `latest` | Tag used for all three `ghcr.io/n8n-io/n8n-sandbox-service-*` images |

Every prompt can also be pre-set via environment variable to run unattended, e.g.:

```bash
# Domain mode behind NPM
N8N_SAME_HOST=n INSTALL_DIR=/opt/n8n-sandbox SANDBOX_DOMAIN=n8n-sandbox.yourdomain.tld \
  bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/install/install-n8n-sandbox.sh)

# Same-host mode (n8n on this host in shared_proxy)
N8N_SAME_HOST=j INSTALL_DIR=/opt/n8n-sandbox \
  bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/install/install-n8n-sandbox.sh)
```

---

## Architecture

```
            shared_proxy (external)          │      sandbox_intern (stack-internal)
                                             │
┌───────────────────┐         ┌──────────────┴──┐  gRPC   ┌────────────────────┐
│ n8n (same host)   │  :8080  │   sandbox-api   │ (mTLS)  │  sandbox-runner-1  │
│        or         │────────►│                 │◄───────►│  (privileged DinD, │
│ Nginx Proxy Mgr   │         │                 │         │   hosts the actual │
│ (80/443 public)   │         └──────────────┬──┘         │   sandboxes)       │
└───────────────────┘                        │            └────────────────────┘
                                             │            ┌────────────────────┐
                                             │            │   sandbox-certs    │
                                             │            │ (one-shot mTLS     │
                                             │            │  bootstrap)        │
                                             │            └────────────────────┘
```

No service in this stack binds a port on the host. Only `sandbox-api` is attached to both networks: `shared_proxy` (where n8n or NPM reach it at `sandbox-api:8080`) and `sandbox_intern`. `sandbox-runner-1` and `sandbox-certs` live **only** in `sandbox_intern` — the privileged Docker-in-Docker runner is not reachable from other containers in `shared_proxy`. API and runner talk to each other over `sandbox_intern`, secured with mutual TLS; `sandbox-certs` is a one-shot init container that bootstraps those certificates, then exits.

`sandbox_intern` is a regular bridge network (neither `external` nor `internal`) owned by the stack. Docker Compose names it `<project>_sandbox_intern` (e.g. `n8n-sandbox_sandbox_intern` for the default install path) and removes it again on `docker compose down`.

Only a single runner (`sandbox-runner-1`, `privileged: true` for Docker-in-Docker) is set up automatically. Scaling to multiple runners needs additional manual mTLS/SAN configuration — see the [upstream docs](https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/configuration.md).

---

## Post-Install Setup

### Same-host mode (n8n in `shared_proxy`)

Nothing to set up in DNS or NPM. Connect n8n to the sandbox **in the n8n UI** — not through environment variables or the CLI. When setting up the AI Assistant, n8n shows an **"Add a code sandbox"** dialog — pick **n8n Sandbox**, then enter:

- **Service URL:** `http://sandbox-api:8080`
- **API key:** the key printed at the end of the install script (stored as `SANDBOX_API_KEYS` in `.env`)

Note it's `http`, not `https` — there's no TLS on that internal port — and the host is the service name, not a domain. This only works while the n8n container is attached to `shared_proxy` on the same host.

### Domain mode (behind Nginx Proxy Manager)

1. **DNS:** point your sandbox domain (A-record) at your server's IP
2. **Nginx Proxy Manager:** create a new Proxy Host:
   - **Domain:** your sandbox domain (e.g. `n8n-sandbox.yourdomain.tld`)
   - **Scheme:** `http`
   - **Forward Hostname:** `sandbox-api`
   - **Forward Port:** `8080`
   - **Websockets Support:** ✔ enabled
   - **Block Common Exploits:** ✔ enabled
   - **SSL:** Request a new Certificate with Let's Encrypt, Force SSL, HTTP/2, HSTS
3. **Verify:**

```bash
curl https://n8n-sandbox.yourdomain.tld/healthz
```

4. **Connect n8n to the sandbox** in the n8n UI ("Add a code sandbox" → **n8n Sandbox**):
   - **Service URL:** `https://n8n-sandbox.yourdomain.tld`
   - **API key:** the key printed at the end of the install script (stored as `SANDBOX_API_KEYS` in `.env`)

   Assistant and Agents then use the sandbox to run code and work with files.

---

## Switching an existing installation

The installer never touches an existing sandbox (see [What it does](#what-it-does)), so installations made with an earlier version of this script still have all three containers in `shared_proxy`. To move the runner into its own network, edit the Compose file by hand. Secrets, the `sandbox-tls` volume and the mTLS certificates stay as they are: `sandbox-certs` runs again on recreate, but its bootstrap skips generation when the certificates already exist.

1. Back up the current Compose file:

```bash
cd /opt/n8n-sandbox && sudo cp docker-compose.yml "docker-compose.yml.bak-$(date +%Y%m%d-%H%M%S)"
```

2. Edit `docker-compose.yml` so the `networks:` entries look like this (only the network lines change):

```yaml
services:
  sandbox-certs:
    networks:
      - sandbox_intern          # was: shared_proxy

  sandbox-api:
    networks:
      - shared_proxy
      - sandbox_intern          # new

  sandbox-runner-1:
    networks:
      - sandbox_intern          # was: shared_proxy

networks:
  shared_proxy:
    external: true
  sandbox_intern: {}            # new
```

3. Validate the file, recreate the containers and check the result:

```bash
sudo docker compose config --quiet && sudo docker compose up -d --force-recreate && sudo docker compose ps
```

4. Confirm that only `sandbox-api` is left in `shared_proxy`:

```bash
sudo docker network inspect shared_proxy --format '{{range .Containers}}{{.Name}} {{end}}'
```

n8n or NPM keep using `sandbox-api:8080` — nothing changes on their side. To undo, restore the backup and run `sudo docker compose up -d --force-recreate` again.

---

## Security Notes

- `SANDBOX_API_KEYS` is an **admin key** with full access to every sandbox and to tenant management (`/admin/tenants`). Once the domain is publicly reachable through NPM, this key (plus mTLS between API and runner) is what protects it — treat `.env` like a root password.
- Consider adding an NPM **Access List** (IP allowlist) on the Proxy Host if the sandbox doesn't need to be reachable from the whole internet.
- The privileged runner (`sandbox-runner-1`, Docker-in-Docker) and the one-shot `sandbox-certs` container are attached only to the stack-internal `sandbox_intern` network. Other containers in `shared_proxy` can reach `sandbox-api:8080`, but not the runner.
- In same-host mode the API is not published through NPM at all, but every container in `shared_proxy` can still reach `sandbox-api:8080` — the API key is what protects it there.
- The API key is entered in the n8n UI, not in any config file on the n8n side — see [Post-Install Setup](#post-install-setup) above. Anyone who can reach the domain and holds the key controls every sandbox.

---

## Useful Commands

```bash
cd /opt/n8n-sandbox

# View service status
docker compose ps

# View live logs
docker compose logs -f

# Update to the latest images
docker compose pull
docker compose up -d

# Check the API health endpoint from the host
docker compose exec sandbox-api wget -qO- http://localhost:8080/healthz
```

---

## Troubleshooting

**The assistant reports `ETARGET` / `No matching version found for @n8n/workflow-sdk@…`**

The sandbox starts but its workspace setup fails, so the assistant can't run code or write files. This is a defect in the official sandbox image — it ships with an npm cache baked in at build time, and setup installs with `--prefer-offline`, so any SDK version published after the image was built is invisible. Reported upstream as [n8n-sandbox-service#178](https://github.com/n8n-io/n8n-sandbox-service/issues/178).

Not caused by your installation, and not avoidable by choosing a different image tag. Diagnose and repair it with the [fix-npm-cache script](../fix-npm-cache/README.md):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/fix-npm-cache/fix-n8n-sandbox-npm-cache.sh) --check-only
```

---

## References

- [n8n Sandbox update script](../update/README.md)
- [n8n Sandbox npm cache fix](../fix-npm-cache/README.md)
- [n8n Sandbox uninstall script](../uninstall/README.md)
- [n8n Sandbox Service (GitHub)](https://github.com/n8n-io/n8n-sandbox-service)
- [Configuration Reference](https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/configuration.md)
- [Linux Quickstart](https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/quickstart-linux.md)
- [Nginx Proxy Manager](https://nginxproxymanager.com/)
- [Docker Compose Docs](https://docs.docker.com/compose/)
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
[LICENSE](../../../LICENSE) file in the repository root.

<sub>This script was researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using it in production.</sub>

<sub>[← Back to the overview](../)</sub>
