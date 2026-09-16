# 🚀 Install LibreCodeInterpreter

[🏠 Overview](../../../../) → [💬 LibreChat](../../../) → [🧩 Code Interpreter](../../) → [🚀 usnavy13](../) → Install

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs) [![GitHub](https://img.shields.io/badge/GitHub-LibreCodeInterpreter-181717?style=for-the-badge&logo=github)](https://github.com/usnavy13/LibreCodeInterpreter) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements) [![Ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#security) [![Idempotent](https://img.shields.io/badge/Re--runnable-guarded-2E7D32?style=flat-square)](#what-it-does)

Installs [LibreCodeInterpreter](https://github.com/usnavy13/LibreCodeInterpreter) as an optional code-execution backend for LibreChat. The service runs behind an existing Nginx Proxy Manager, **no host port is bound**, and the `MASTER_API_KEY` is generated automatically.

> **Heads-up:** This is an add-on, not LibreChat itself. It needs a working LibreChat + Nginx Proxy Manager setup first.

---

## Quick Install

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/usnavy13/install/install-librecodeinterpreter.sh)"
```

This downloads and runs the installer interactively. It checks prerequisites, asks for the domain, and sets up the stack under `/opt/LibreCodeInterpreter`.

---

## What it does

1. **Checks prerequisites:** `git`, Docker daemon, Docker Compose plugin, and a running Nginx Proxy Manager container.
2. **Verifies** the shared Docker network (default: `shared_proxy`) exists.
3. **Detects** existing LibreCodeInterpreter installations and aborts if one is found.
4. **Asks for** the domain to use (e.g. `code.example.de`) and validates it.
5. **Clones** the upstream repository to `/opt/LibreCodeInterpreter`.
6. **Generates** a random `MASTER_API_KEY` and writes it to `.env`.
7. **Creates** a `docker-compose.override.yml` that removes host ports and attaches the stack to the NPM network.
8. **Starts** the stack and waits for all services to become ready.
9. **Displays** the `MASTER_API_KEY` and the exact Nginx Proxy Manager proxy-host settings needed.

---

## Requirements

- Debian 12+ (tested on Debian 12 and 13)
- root or `sudo`
- Docker + Docker Compose plugin
- `git` and `openssl`
- A running Nginx Proxy Manager with an existing `shared_proxy` Docker network
- A domain or subdomain pointing to this host

---

## Installation

### One-liner (interactive)

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/usnavy13/install/install-librecodeinterpreter.sh)"
```

### Local download

```bash
curl -fsSL -o install-librecodeinterpreter.sh \
  https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/usnavy13/install/install-librecodeinterpreter.sh
chmod +x install-librecodeinterpreter.sh
sudo ./install-librecodeinterpreter.sh
```

---

## Interactive Setup

The installer asks for:

| Prompt | Default | Purpose |
|--------|---------|---------|
| Docker network of Nginx Proxy Manager | `shared_proxy` | The external network the NPM container is attached to. |
| Domain for the Code Interpreter | — | The subdomain that will reach the service through NPM. |

After confirmation it proceeds automatically. At the end it prints:

- The public IPv4 to use for the DNS A-record
- The exact Nginx Proxy Manager proxy-host configuration
- The `MASTER_API_KEY` for the admin dashboard
- Instructions for creating a separate API key in LibreChat's dashboard and adding it to LibreChat's `.env`

---

## Connecting to LibreChat

The `MASTER_API_KEY` shown at the end is **only for logging into the dashboard**. Do not paste it into LibreChat.

1. Open `https://<your-domain>/admin-dashboard`.
2. Create a new API key in the dashboard (it is usually shown only once).
3. Add this line to LibreChat's `.env`:

```bash
LIBRECHAT_CODE_BASEURL=https://<NEW-API-KEY>@<your-domain>
```

4. **Stop and start** LibreChat — `docker restart` does **not** reload `.env`:

```bash
docker stop LibreChat && docker start LibreChat
```

5. Verify the variable is loaded:

```bash
docker exec LibreChat env | grep LIBRECHAT_CODE
```

---

## Security

- **No host ports are opened.** The service is reachable only through the `shared_proxy` Docker network used by Nginx Proxy Manager.
- The `MASTER_API_KEY` is generated with `openssl rand -hex 32` and stored in `/opt/LibreCodeInterpreter/.env` with `chmod 600`.
- Because the API key is embedded in the URL (`https://key@domain`), it may appear in Nginx Proxy Manager access logs. Rotate the key in the dashboard if it is ever exposed.
- The script runs as root and modifies `/opt`. Review it before execution.

---

## Known Pitfalls

- **Existing installation:** If `/opt/LibreCodeInterpreter` already exists or a LibreCodeInterpreter container is running, the script aborts. Remove the old stack manually first.
- **NPM network missing:** The script checks both that an NPM container is running **and** that the network exists. A network alone is not enough.
- **`.env` not reloaded:** LibreChat must be stopped and started, not restarted, after changing its `.env`.
- **Wrong key in LibreChat:** Using the `MASTER_API_KEY` in `LIBRECHAT_CODE_BASEURL` results in "Code execution is not authorized".

---

## Useful Commands

```bash
# View logs
cd /opt/LibreCodeInterpreter && docker compose logs -f api

# Check status
cd /opt/LibreCodeInterpreter && docker compose ps

# Update
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/usnavy13/update/update-librecodeinterpreter.sh)"

# Uninstall
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/usnavy13/uninstall/uninstall-librecodeinterpreter.sh)"
```

---

## References

- [LibreCodeInterpreter (GitHub)](https://github.com/usnavy13/LibreCodeInterpreter)
- [SECURITY.md](https://github.com/usnavy13/LibreCodeInterpreter/blob/main/docs/SECURITY.md)
- [Official LibreChat](https://www.librechat.ai/)
- [LibreChat Docs](https://www.librechat.ai/docs)
- [Nginx Proxy Manager](https://nginxproxymanager.com/)
- [Docker Compose Docs](https://docs.docker.com/compose/)
- [pc-fee.com Blog](https://pc-fee.com/blog)

---

## Disclaimer

This script is provided "as is", without warranty of any kind. Use it at your own risk. The author assumes no liability for damages, data loss, or other consequences resulting from its use. Test it in a non-production environment first.

---

## License

This project is licensed under the MIT License — see the [LICENSE](../../../../LICENSE) file in the repository root.

<sub>This script was researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using it in production.</sub>

<sub>[← Back to the overview](../)</sub>
