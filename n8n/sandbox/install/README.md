# 🧪 n8n Sandbox Install Script

[🏠 Overview](../../../) → [🔗 n8n](../../) → [🧪 Sandbox](../) → Install

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-n8n--Sandbox-00B8D9?style=for-the-badge)](https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/README.md)
[![GitHub](https://img.shields.io/badge/GitHub-n8n--sandbox--service-181717?style=for-the-badge&logo=github)](https://github.com/n8n-io/n8n-sandbox-service)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../LICENSE)

Automated installer for the self-hosted [n8n Sandbox Service](https://github.com/n8n-io/n8n-sandbox-service) (isolated code execution for n8n), running behind [Nginx Proxy Manager](https://nginxproxymanager.com/) via Docker Compose — **no publicly bound ports**, all traffic routed through NPM.

Works whether n8n itself is already installed on the host or not. Sets up the sandbox from scratch: directories, `.env`, `docker-compose.yml`, and container start.

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
- ✅ Behind Nginx Proxy Manager (no exposed ports)
- ✅ mTLS between API and Runner, bootstrapped automatically
- ✅ Secure random secrets generated for you (no weak defaults)
- ✅ Runs alongside an existing n8n install, or completely standalone
- ✅ Safe re-run guard — refuses to install over an existing sandbox
- ✅ Production-ready `restart: unless-stopped` setup

---

## Why this script?

The [official quickstart](https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/quickstart-linux.md) is straightforward, but on fresh servers you want a repeatable installer that:

- checks prerequisites (Docker, Docker Compose, Nginx Proxy Manager, `shared_proxy`)
- refuses to install over an existing sandbox (would break registered runners / mTLS)
- generates strong, unique secrets automatically
- writes a known-good `docker-compose.yml` + `.env`
- starts the stack and waits for a healthy API
- tells you exactly what to configure in NPM afterwards

---

## What it does

1. Detects whether it's already running as `root`; if not, transparently prefixes every privileged command with `sudo` (asks for your password once, same as any other `sudo` command)
2. Checks Docker + Docker Compose are installed and the Docker daemon is running
3. Checks Nginx Proxy Manager is running (dies with a guide link if not — this stack has no public ports of its own)
4. Ensures the external Docker network `shared_proxy` exists (offers to create it)
5. Detects — informationally only — whether n8n itself is already running on the host
6. Detects an existing sandbox installation and aborts safely instead of overwriting secrets/certificates
7. Prompts for install path, the domain you'll point at it via NPM, and the image tag
8. Generates three random 48-character secrets (`SANDBOX_API_KEYS`, `SANDBOX_API_RUNNER_REGISTRATION_TOKEN`, `SANDBOX_API_RUNNER_API_KEY`)
9. Writes `.env` (permissions `600`) and `docker-compose.yml`
10. Pulls images, starts the stack (`sandbox-certs` → `sandbox-api` → `sandbox-runner-1`), and waits for the API health check
11. Prints the exact NPM Proxy Host settings to add next

---

## Requirements

- Linux server with Docker + Docker Compose (v2) installed
- Bash ≥ 5
- `curl`
- Docker network `shared_proxy` (created by the [Nginx Proxy Manager installer](https://github.com/nephilim75/scripts/tree/main/nginx-proxy-manager))
- Nginx Proxy Manager running in `shared_proxy`
- A DNS record for the domain you want to expose the sandbox API under

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
| Install path | `/opt/n8n-sandbox` | Directory for `.env` + `docker-compose.yml` |
| Domain | *(required)* | Domain you'll point at the sandbox API via NPM (e.g. `n8n-sandbox.yourdomain.tld`) — documentation only, not consumed by any container |
| Image tag | `latest` | Tag used for all three `ghcr.io/n8n-io/n8n-sandbox-service-*` images |

Every prompt can also be pre-set via environment variable to run unattended, e.g.:

```bash
INSTALL_DIR=/opt/n8n-sandbox SANDBOX_DOMAIN=n8n-sandbox.yourdomain.tld \
  bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/install/install-n8n-sandbox.sh)
```

---

## Architecture

```
                 shared_proxy (external Docker network)
┌──────────────┐        ┌───────────────┐        ┌───────────────────┐
│   Nginx      │ :8080  │  sandbox-api  │  gRPC  │ sandbox-runner-1   │
│ Proxy Manager│◄──────►│  (mTLS certs  │◄──────►│ (privileged DinD,  │
│  (80/443     │        │  bootstrapped │        │  hosts the actual  │
│   public)    │        │  by           │        │  sandbox           │
│              │        │  sandbox-certs│        │  containers)       │
└──────────────┘        └───────────────┘        └───────────────────┘
```

No service in this stack binds a port on the host. `sandbox-api` and `sandbox-runner-1` are reachable only from other containers on `shared_proxy` — which is exactly how NPM reaches `sandbox-api:8080`. `sandbox-certs` is a one-shot init container that bootstraps the mutual-TLS certificates used between the API and the runner, then exits.

Only a single runner (`sandbox-runner-1`, `privileged: true` for Docker-in-Docker) is set up automatically. Scaling to multiple runners needs additional manual mTLS/SAN configuration — see the [upstream docs](https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/configuration.md).

---

## Post-Install Setup

After successful installation:

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

4. **Connect n8n to the sandbox:** this happens **in the n8n UI**, not through environment variables or the CLI. When setting up the AI Assistant, n8n shows an **"Add a code sandbox"** dialog — pick **n8n Sandbox**, then enter:
   - **Service URL:** `https://n8n-sandbox.yourdomain.tld`
   - **API key:** the key printed at the end of the install script (stored as `SANDBOX_API_KEYS` in `.env`)

   Assistant and Agents then use the sandbox to run code and work with files.

---

## Security Notes

- `SANDBOX_API_KEYS` is an **admin key** with full access to every sandbox and to tenant management (`/admin/tenants`). Once the domain is publicly reachable through NPM, this key (plus mTLS between API and runner) is what protects it — treat `.env` like a root password.
- Consider adding an NPM **Access List** (IP allowlist) on the Proxy Host if the sandbox doesn't need to be reachable from the whole internet.
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

<sub>This script and its documentation were created with the help of AI models
(Claude Sonnet 5, Anthropic), commissioned by pc-fee.com. All technical statements
were checked against the official n8n-sandbox-service documentation and the user's
own working configuration. Please verify for yourself before using it in
production.</sub>

<sub>[← Back to the overview](../)</sub>
