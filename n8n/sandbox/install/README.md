# 🧪 n8n Sandbox Install Script

<a href="https://pc-fee.com/blog/" target="_blank" rel="noopener noreferrer">
  <img src="https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge" alt="Visit the pc-fee.com blog for additional resources and tutorials" />
</a>
<a href="https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/README.md" target="_blank" rel="noopener noreferrer">
  <img src="https://img.shields.io/badge/Docs-n8n--Sandbox-00B8D9?style=for-the-badge" alt="Read the official n8n Sandbox Service documentation" />
</a>
<a href="https://github.com/n8n-io/n8n-sandbox-service" target="_blank" rel="noopener noreferrer">
  <img src="https://img.shields.io/badge/GitHub-n8n--sandbox--service-181717?style=for-the-badge&logo=github" alt="n8n-sandbox-service on GitHub" />
</a>
<br><br>

Automated installer for the self-hosted [n8n Sandbox Service](https://github.com/n8n-io/n8n-sandbox-service) (isolated code execution for n8n), running behind [Nginx Proxy Manager](https://nginxproxymanager.com/) via Docker Compose — **no publicly bound ports**, all traffic routed through NPM.

Works whether n8n itself is already installed on the host or not. Sets up the sandbox from scratch: directories, `.env`, `docker-compose.yml`, and container start.

---

## 🚀 Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/install/install-n8n-sandbox.sh)
```

The installer checks prerequisites, prompts for the required values, generates secure secrets, and starts the stack automatically.

> **No leading `sudo` needed:** the script detects whether it's already running as root and, if not, automatically prefixes every privileged command with `sudo` internally. Don't add `sudo` yourself in front of this command — `sudo bash <(curl ...)` fails on most systems with `bash: /dev/fd/NN: No such file or directory`, because `sudo` closes inherited file descriptors above stderr by default, and that's exactly where process substitution hands off the downloaded script.

---

## ✨ What You Get

- ✅ n8n Sandbox Service (API + Runner) via Docker Compose
- ✅ Behind Nginx Proxy Manager (no exposed ports)
- ✅ mTLS between API and Runner, bootstrapped automatically
- ✅ Secure random secrets generated for you (no weak defaults)
- ✅ Runs alongside an existing n8n install, or completely standalone
- ✅ Safe re-run guard — refuses to install over an existing sandbox
- ✅ Production-ready `restart: unless-stopped` setup

---

## 💡 Why this script?

The [official quickstart](https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/quickstart-linux.md) is straightforward, but on fresh servers you want a repeatable installer that:

- checks prerequisites (Docker, Docker Compose, Nginx Proxy Manager, `shared_proxy`)
- refuses to install over an existing sandbox (would break registered runners / mTLS)
- generates strong, unique secrets automatically
- writes a known-good `docker-compose.yml` + `.env`
- starts the stack and waits for a healthy API
- tells you exactly what to configure in NPM afterwards

---

## ✅ What it does

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

## 📋 Requirements

- Linux server with Docker + Docker Compose (v2) installed
- Bash ≥ 5
- `curl`
- Docker network `shared_proxy` (created by the [Nginx Proxy Manager installer](https://github.com/nephilim75/scripts/tree/main/nginx-proxy-manager))
- Nginx Proxy Manager running in `shared_proxy`
- A DNS record for the domain you want to expose the sandbox API under

---

## 📥 Installation

Make the script executable and run it:

```bash
chmod +x install-n8n-sandbox.sh
./install-n8n-sandbox.sh
```

Or run it straight from GitHub without saving it first:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/install/install-n8n-sandbox.sh)
```

Neither form needs a leading `sudo` — see the note under [Quick Install](#-quick-install).

---

## ⚙️ Interactive Setup

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

## 🏗️ Architecture

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

## 🔒 Post-Install Setup

After successful installation:

1. **DNS:** point your sandbox domain (A-record) at your server's IP
2. **Nginx Proxy Manager:** create a new Proxy Host:
   - **Domain:** your sandbox domain (e.g. `n8n-sandbox.yourdomain.tld`)
   - **Forward Hostname:** `sandbox-api`
   - **Forward Port:** `8080`
   - **Websockets Support:** ✔ enabled
   - **Block Common Exploits:** ✔ enabled
   - **SSL:** Request a new Certificate with Let's Encrypt, Force SSL, HTTP/2, HSTS
3. **Verify:**

```bash
curl https://n8n-sandbox.yourdomain.tld/healthz
```

---

## 🔐 Security Notes

- `SANDBOX_API_KEYS` is an **admin key** with full access to every sandbox and to tenant management (`/admin/tenants`). Once the domain is publicly reachable through NPM, this key (plus mTLS between API and runner) is what protects it — treat `.env` like a root password.
- Consider adding an NPM **Access List** (IP allowlist) on the Proxy Host if the sandbox doesn't need to be reachable from the whole internet.

---

## 🔌 Connecting n8n to the Sandbox

This sandbox is used by n8n's **AI Assistant** ("n8n Assistant") — **not** by Code nodes. Enable it on the n8n side (n8n 2.x+) with these environment variables:

```bash
N8N_INSTANCE_AI_SANDBOX_ENABLED=true
N8N_INSTANCE_AI_SANDBOX_PROVIDER=n8n-sandbox
N8N_SANDBOX_SERVICE_URL=http://sandbox-api:8080   # if n8n runs in the same shared_proxy network — otherwise use the public NPM domain
N8N_SANDBOX_SERVICE_API_KEY=<your SANDBOX_API_KEYS value>
```

n8n's own docs describe this manually self-hosted sandbox setup as best suited to local development/testing, and officially recommend a Daytona-managed sandbox for production. That's not a blocker for running it yourself as described here, but worth knowing.

You can verify the sandbox works completely independently of n8n by calling its REST API directly (from the same host, since `sandbox-api` has no port published to the host):

```bash
# Create a sandbox
docker run --rm --network shared_proxy curlimages/curl -s -X POST \
  http://sandbox-api:8080/sandboxes -H "X-Api-Key: <your SANDBOX_API_KEYS value>"

# Run a real command in it (use the id returned above)
docker run --rm --network shared_proxy curlimages/curl -s -X POST \
  http://sandbox-api:8080/sandboxes/<id>/executions \
  -H "X-Api-Key: <your SANDBOX_API_KEYS value>" \
  -H "Content-Type: application/json" \
  -d '{"command": "echo hello", "timeout_ms": 10000}'
```

This exercises the full path (API → mTLS → Runner → inner Docker-in-Docker → sandbox container) without touching n8n at all — a good smoke test after installing or updating. Full API reference: [docs/API.md](https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/API.md).

---

## 🛠️ Useful Commands

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

## 🤖 AI Transparency

This script and its documentation were created by Claude (Anthropic), commissioned by [pc-fee.com](https://pc-fee.com).

**Model:** Claude Sonnet 5 (Anthropic)

All technical statements were checked against the [official n8n-sandbox-service documentation](https://github.com/n8n-io/n8n-sandbox-service/tree/main/docs) and the user's own working reference configuration. Review and test before production use.

---

## ⚖️ License

MIT License – Copyright (c) 2026 [pc-fee.com](https://pc-fee.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software to use, copy, modify, merge, publish, and/or distribute it, subject to the condition that this copyright notice is retained in all copies or substantial portions of the software.

**Disclaimer:** This script is provided without any warranty. Use at your own risk. pc-fee.com accepts no liability for any damages arising from the use of this script. Backups before planned changes are mandatory.

---

## 🔗 References

- [n8n Sandbox update script](../update/README.md)
- [n8n Sandbox uninstall script](../uninstall/README.md)
- [n8n Sandbox Service (GitHub)](https://github.com/n8n-io/n8n-sandbox-service)
- [Configuration Reference](https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/configuration.md)
- [Linux Quickstart](https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/quickstart-linux.md)
- [Nginx Proxy Manager](https://nginxproxymanager.com/)
- [Docker Compose Docs](https://docs.docker.com/compose/)
- [pc-fee.com Blog](https://pc-fee.com/blog)
