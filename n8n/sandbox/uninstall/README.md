# 🧹 n8n Sandbox Uninstall Script

<a href="https://pc-fee.com/blog/" target="_blank" rel="noopener noreferrer">
  <img src="https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge" alt="Visit the pc-fee.com blog for additional resources and tutorials" />
</a>
<a href="https://github.com/n8n-io/n8n-sandbox-service" target="_blank" rel="noopener noreferrer">
  <img src="https://img.shields.io/badge/GitHub-n8n--sandbox--service-181717?style=for-the-badge&logo=github" alt="n8n-sandbox-service on GitHub" />
</a>
<br><br>

Companion script to the [n8n Sandbox install script](../install/README.md) — removes a sandbox installation completely: containers, the mTLS volume, optionally the Docker images, and the install directory (including `.env` with all secrets).

The `shared_proxy` Docker network and any n8n installation on the same host are **never touched** — they're shared with other services.

---

## 🚀 Quick Uninstall

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/uninstall/uninstall-n8n-sandbox.sh)
```

No leading `sudo` needed — same self-elevation behavior as the install script (see its README for why `sudo bash <(curl ...)` should never be used).

Want to see what would happen without touching anything first?

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/uninstall/uninstall-n8n-sandbox.sh) --dry-run
```

---

## ✅ What it does

1. Detects whether it's already running as `root`; if not, transparently prefixes every privileged command with `sudo`
2. Checks Docker + Docker Compose are available
3. Asks for the install path (default `/opt/n8n-sandbox`)
4. Shows exactly what it found: containers, the `sandbox-tls` volume, matching local images, and the install directory
5. Asks for explicit confirmation before deleting anything (default answer is **no**)
6. Runs `docker compose down -v --remove-orphans` to stop and remove the containers and the mTLS volume
7. Optionally removes the `n8n-sandbox-service-api` / `-runner-dind` images (asked separately, also defaults to no)
8. Removes the install directory (`.env` and all)
9. Reminds you to delete the matching Proxy Host in Nginx Proxy Manager

---

## 📋 Requirements

- The same host (or install path) where `install-n8n-sandbox.sh` was run
- Docker + Docker Compose still installed (used to tear the stack down cleanly)

---

## 📥 Usage

Make the script executable and run it:

```bash
chmod +x uninstall-n8n-sandbox.sh
./uninstall-n8n-sandbox.sh
```

Or run it straight from GitHub:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/uninstall/uninstall-n8n-sandbox.sh)
```

### Options & environment variables

| Flag / Variable | Effect |
|---|---|
| `--dry-run` | Shows every step and what would be deleted, but changes nothing |
| `INSTALL_DIR` | Pre-sets the install path, skipping that prompt |
| `ASSUME_YES=1` | Skips all confirmations (containers/volume **and** images are removed without asking) — use with care, ideally combined with `--dry-run` first |

Example, fully unattended:

```bash
INSTALL_DIR=/opt/n8n-sandbox ASSUME_YES=1 \
  bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/uninstall/uninstall-n8n-sandbox.sh)
```

---

## 🔍 What's left alone, on purpose

- **`shared_proxy` Docker network** — shared with Nginx Proxy Manager and possibly other services; never removed by this script
- **Nginx Proxy Manager itself** — untouched; you still need to delete the Proxy Host you created for the sandbox domain manually
- **n8n itself**, if installed on the same host — completely unrelated stack, untouched
- **`ghcr.io/n8n-io/n8n-sandbox-service-sandbox` image** — this one lives inside the runner's internal Docker-in-Docker daemon, not on the host, so it isn't independently visible or removable here; it disappears automatically once the `sandbox-runner-1` container is removed

---

## 🤖 AI Transparency

This script and its documentation were created by Claude (Anthropic), commissioned by [pc-fee.com](https://pc-fee.com).

**Model:** Claude Sonnet 5 (Anthropic)

Review and test (ideally with `--dry-run` first) before running against a production installation.

---

## ⚖️ License

MIT License – Copyright (c) 2026 [pc-fee.com](https://pc-fee.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software to use, copy, modify, merge, publish, and/or distribute it, subject to the condition that this copyright notice is retained in all copies or substantial portions of the software.

**Disclaimer:** This script is provided without any warranty. Use at your own risk. pc-fee.com accepts no liability for any damages arising from the use of this script. Backups before planned changes are mandatory.

---

## 🔗 References

- [n8n Sandbox install script](../install/README.md)
- [n8n Sandbox Service (GitHub)](https://github.com/n8n-io/n8n-sandbox-service)
- [Docker Compose Docs](https://docs.docker.com/compose/)
- [pc-fee.com Blog](https://pc-fee.com/blog)
