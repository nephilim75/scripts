# 🧹 n8n Uninstall Script

[🏠 Overview](../../) → [🔗 n8n](../) → Uninstall

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-n8n-EA4B71?style=for-the-badge)](https://docs.n8n.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#)
[![Host-ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#)
[![Re-runnable](https://img.shields.io/badge/Re--runnable-yes-2E7D32?style=flat-square)](#what-it-does)
[![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#quick-uninstall)

Companion script to the [n8n install script](../install/README.md) — removes an n8n instance completely: containers, the install directory (`n8n_data`, `backups`, `.env` with all secrets, `docker-compose.yml`), and optionally the Docker images.

> Destructive by design: this deletes all workflows, credentials and execution history with no built-in undo. Run with `--dry-run` first, and make sure you have a backup (e.g. from the [update script](../update/README.md)) if you might want the data back.

---

## Quick Uninstall

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/uninstall/uninstall-n8n.sh)
```

Asks for your installation folder (default `/opt/n8n`), shows exactly what it found, then asks for explicit confirmation (default answer is **no**) before deleting anything. Add `--dry-run` to see what would happen without touching anything — see [Configuration](#configuration-optional) below.

---

## Why this script?

- shows a full inventory (containers, directories, `.env`, backups, matching images) before asking for confirmation — nothing is a surprise
- two separate confirmations, both defaulting to "no": one for the data, one for the images
- never touches the `shared_proxy` network, Nginx Proxy Manager, or a separately installed n8n Sandbox — all of that is detected and called out explicitly if present
- supports `--dry-run` and unattended operation via environment variables, for scripted teardown
- runs from anywhere via `bash <(curl ...)`, just like the installer and update script — no need to download it into the install folder first

---

## What it does

1. Checks prerequisites (Docker installed & running, Docker Compose available)
2. Asks for the install path (`INSTALL_DIR`, default `/opt/n8n`)
3. If the directory is already gone, checks for orphaned containers instead of doing nothing silently
4. Shows an inventory: containers, the install directory's contents (`n8n_data`, `.env`, number of backups in `backups/`), and any locally matching `n8nio/n8n` / `n8nio/runners` images
5. Warns explicitly if a separate n8n Sandbox installation is detected on the same host — it is not touched
6. Asks for confirmation before deleting anything (default: no)
7. Runs `docker compose down --remove-orphans` to stop and remove the containers
8. Optionally removes the `n8nio/n8n` / `n8nio/runners` images (asked separately, also defaults to no)
9. Removes the install directory (`.env` and all)
10. Reminds you to delete the matching Proxy Host in Nginx Proxy Manager

---

## Requirements

- Bash ≥ 5
- `curl`
- `docker compose` (v2)
- Sufficient rights to run Docker commands and delete `INSTALL_DIR` (e.g. root, or `docker` group membership plus write access to the install path) — same assumption as `install-n8n.sh` and `update-n8n.sh`, this script has no built-in `sudo` handling of its own

---

## Installation

The same thing step by step, if you prefer to look at the script before running it:

```bash
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/uninstall/uninstall-n8n.sh
chmod +x uninstall-n8n.sh
./uninstall-n8n.sh
```

Can be run from any directory — it will ask for the path to your installation.

---

## Configuration (optional)

| Flag / Variable | Effect |
|---|---|
| `--dry-run` | Shows every step and what would be deleted, but changes nothing |
| `INSTALL_DIR` | Pre-sets the install path, skipping that prompt |
| `ASSUME_YES=1` | Skips both confirmations (data **and** images are removed without asking) — use with care, ideally combined with `--dry-run` first |

Example, fully unattended:

```bash
INSTALL_DIR=/opt/n8n ASSUME_YES=1 bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/uninstall/uninstall-n8n.sh)
```

---

## What's left alone, on purpose

- **`shared_proxy` Docker network** — shared with Nginx Proxy Manager and possibly other services (including a separate n8n Sandbox); never removed by this script
- **Nginx Proxy Manager itself** — untouched; you still need to delete the Proxy Host you created for your n8n domain manually
- **A separately installed n8n Sandbox** — a completely independent stack with its own [uninstall script](../sandbox/uninstall/README.md); detected and called out, but never touched here

---

## Security

This script deletes data and needs the same level of access as the installer: it requires working Docker access (root or `docker` group membership) but has no privilege-elevation logic of its own. The Quick Uninstall one-liner executes a remote script directly via `bash <(curl ...)` — review the script first (see [Installation](#installation)) if you don't want to run it sight unseen. The only network calls it makes are local Docker daemon calls; it does not contact any external service. Deletion is irreversible: `n8n_data` (all workflows, credentials and execution history) and `.env` (your `N8N_ENCRYPTION_KEY` and runner auth token) are removed without any built-in backup step — take one yourself first if there's any chance you'll want the data back. Optional image removal only deletes local images by ID and fails harmlessly with a warning if an image is still referenced elsewhere; it does not force-remove anything in use.

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

<sub>This script was created with the help of AI models (Claude, Anthropic),
commissioned by pc-fee.com. Please verify for yourself — ideally with
`--dry-run` first — before using it in production.</sub>

<sub>[← Back to the overview](../)</sub>
