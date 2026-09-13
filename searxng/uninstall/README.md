# 🔍 SearXNG Uninstall Script

[🏠 Overview](../../) → [🔍 SearXNG](../) → Uninstall

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Guide](https://img.shields.io/badge/Guide-SearXNG-FE5200?style=for-the-badge)](https://pc-fee.com/searxng/)
[![Docs](https://img.shields.io/badge/Docs-docs.searxng.org-2496ED?style=for-the-badge)](https://docs.searxng.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements)
[![Host-ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#what-it-does)
[![Re-runnable](https://img.shields.io/badge/Re--runnable-yes-2E7D32?style=flat-square)](#what-it-does)
[![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#options)

Companion to the [install script](../install/README.md) — removes a [SearXNG](https://docs.searxng.org/) instance completely: the container, the install directory (`config/`, the Compose file), and on request the backups and the Docker images. Like the installer and the [update script](../update/README.md), it runs **from anywhere** and finds the installation itself.

> Destructive by design: `config/` holds `settings.yml` including the generated `secret_key`. There is no built-in undo. Run it with `--dry-run` first.

---

## Quick Uninstall

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/searxng/uninstall/uninstall-searxng.sh)"
```

Locates your installation, shows a full inventory of what it found, then asks for explicit confirmation — the default answer is **no**, and backups and images are asked for separately. Add `-- --dry-run` to see the whole run without deleting anything (see [Options](#options)).

---

## Why this script?

- shows an inventory first — container, directory contents, number and size of backups, matching images — so nothing is a surprise
- up to three separate confirmations, each defaulting to "no": data, backups, images
- can **keep your backups**: if you decline that question, `backups/` is moved next to the install directory instead of being deleted with it
- never touches the `shared_proxy` network; it lists other containers still attached to it so you know what else is running there
- runs from anywhere via a one-liner, and refuses to delete anything unattended unless you explicitly pass `ASSUME_YES`

---

## What it does

1. Checks prerequisites (root, Docker running, Docker Compose available)
2. Determines the install path the same way the [update script](../update/README.md#how-it-finds-your-installation) does, and asks if several installations exist
3. If no install directory is left but SearXNG containers still exist, offers to clean up those orphans instead of silently doing nothing
4. Shows an inventory: container, `config/`, the Compose file, backup count and size, matching local images, plus other containers on `shared_proxy`
5. Asks for confirmation before anything is removed (default: no)
6. Runs `compose down --remove-orphans`, or removes the orphaned container individually if no Compose file is left
7. Moves `backups/` out of the way, unless you chose to delete it too
8. Optionally removes the `searxng/searxng` images (asked separately, also defaults to no)
9. Removes the install directory
10. Reports leftovers: an `update-searxng.sh` cron entry, `/var/log/searxng-update.log`, and any Proxy Host/Access List still configured in NPM — all named but never touched

It opens no host ports, and re-running it on an already clean host simply reports that there is nothing to do.

---

## Requirements

- Bash ≥ 4, `curl`
- Docker + Docker Compose (v2 plugin or the legacy `docker-compose` binary — both are detected)
- root, via `sudo` or a root shell

---

## Installation

The same thing step by step, if you prefer to read the script before running it:

```bash
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/searxng/uninstall/uninstall-searxng.sh
chmod +x uninstall-searxng.sh
sudo ./uninstall-searxng.sh --dry-run
```

It can be run from any directory — it asks for, or detects, the path to your installation.

---

## Options

| Flag / Variable | Effect |
|---|---|
| `--dry-run` | Shows every step and what would be deleted, changes nothing |
| `--dir <path>` / `INSTALL_DIR` | Sets the install path explicitly and skips detection |
| `--yes` / `ASSUME_YES=1` | Skips **all** confirmations — data, backups **and** images are removed without asking |
| `--help` | Prints usage and exits |

With `bash -c "$(curl ...)"`, arguments go after a `--` separator, because `bash -c` assigns the first argument to `$0`:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/searxng/uninstall/uninstall-searxng.sh)" -- --dry-run
```

Fully unattended teardown, e.g. when rebuilding a host from scratch:

```bash
sudo INSTALL_DIR=/opt/searxng ASSUME_YES=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/searxng/uninstall/uninstall-searxng.sh)"
```

---

## What's left alone, on purpose

- **The `shared_proxy` Docker network** — shared with Nginx Proxy Manager, n8n and anything else you proxied. Removing it would break those stacks' Compose files, so it stays.
- **Containers of other stacks** — completely untouched.
- **The Proxy Host and any Access List in Nginx Proxy Manager** — remove those manually in NPM if you no longer need them.
- **Your DNS records and firewall rules** — nothing outside this host is touched.
- **A cron entry for `update-searxng.sh`** — reported with a reminder to remove it via `crontab -e`, never edited automatically.
- **`/var/log/searxng-update.log`** — kept, so you still have the update history.

---

## Known pitfalls

- **Declining the backup question is not a backup strategy.** The archive is moved to `searxng-backups-<timestamp>` next to the install directory; move it somewhere off-host if you actually want to keep it.
- **`ASSUME_YES=1` also deletes the backups and the images.** Combine it with `--dry-run` on the first run.
- **The `secret_key` is gone once `config/` is deleted** (unless you kept a backup) — a fresh install always generates a new one, so any external tooling that hard-coded the old key needs updating too.

---

## Security

This script deletes data and requires root: it removes the container, images and an entire directory tree under `/opt`. The Quick Uninstall one-liner executes a remote script directly — review it first (see [Installation](#installation)) if you would rather not run it sight unseen. Prompts are read from `/dev/tty`, never from stdin, so a pipe cannot feed confirmations into it; without a real terminal it aborts rather than assuming a yes, unless `ASSUME_YES=1` is set deliberately. Apart from local Docker daemon calls it contacts nothing. Deletion is irreversible: `config/` (including `settings.yml` and the `secret_key`) is removed without a built-in backup step unless you keep the offered one. Image removal only deletes local images by ID and fails harmlessly with a warning if one is still referenced elsewhere.

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
