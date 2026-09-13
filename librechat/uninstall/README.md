# 🗑️ LibreChat Uninstall Script

[🏠 Overview](../../) → [💬 LibreChat](../) → Uninstall

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements)
[![Host-ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#what-it-does)
[![Re-runnable](https://img.shields.io/badge/Re--runnable-yes-2E7D32?style=flat-square)](#what-it-does)
[![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#options)

Companion to the [install script](../install/README.md) — undoes what it set up and removes [LibreChat](https://www.librechat.ai/) completely: the six containers, the project's **Docker volumes**, the install directory with the cloned repository, `.env`, `librechat.yaml`, the override, `data-node/`, `meili_data_*/`, `uploads/`, `images/` and `logs/`, and on request the backups and the Docker images. Like the installer and the [update script](../update/README.md), it runs **from anywhere** and finds the installation itself.

> Destructive by design: this removes **every chat, every user account and every uploaded file**, not just the application. There is no built-in undo. Run it with `--dry-run` first, and keep a backup from the [update script](../update/README.md#what-gets-backed-up) if any of it still matters.

---

## Quick Uninstall

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/uninstall/uninstall-librechat.sh)"
```

Locates your installation, shows a full inventory of what it found — containers, volumes with their sizes, the directory broken down by what each folder holds — then asks for explicit confirmation. The default answer is **no**, and backups and images are asked for separately. Add `-- --dry-run` to see the whole run without deleting anything (see [Options](#options)).

---

## Why this script?

- shows an inventory first — containers, project volumes and their size, `data-node/` (the chat database) with its size, the search index, uploads, number and size of backups, matching images — so nothing is a surprise
- up to four separate confirmations, each defaulting to "no": data, backups, LibreChat images, shared base images
- **separates LibreChat's own images from the base images** (`mongo`, `meilisearch`, `pgvector`): the latter are commonly shared with other stacks on the same host and are asked for on their own
- can **keep your backups**: if you decline that question, `backups/` is moved next to the install directory instead of being deleted with it
- **never deletes a directory outside the installation** — a code interpreter under `/opt/LibreCodeInterpreter` or `/opt/avila-code-interpreter`, an admin tool under `/opt/admin-lc`, and their containers, are detected and listed with a pointer to their own scripts, and left exactly as they are
- refuses to `rm -rf` a system directory even if one is passed via `--dir`, and resolves the path before deleting
- never touches the `shared_proxy` network; it lists the other containers still attached to it so you know what else is running there
- runs from anywhere via a one-liner, and refuses to delete anything unattended unless you explicitly pass `ASSUME_YES`

---

## What it does

1. Checks prerequisites (root, Docker running, Docker Compose available)
2. Determines the install path the same way the [update script](../update/README.md#what-it-does) does, and asks if several installations exist
3. If no install directory is left but LibreChat containers still exist, offers to clean up those orphans instead of silently doing nothing
4. Verifies the resolved path is a real subdirectory — `/`, `/opt`, `/home` and friends are refused outright
5. Shows an inventory: containers, the project's Docker volumes with sizes, the directory contents item by item, backup count and size, the matching local images split into LibreChat's own and shared base images, other containers on `shared_proxy`, and any additional LibreChat components found elsewhere on the host
6. Asks for confirmation before anything is removed (default: no), stating plainly that chats, accounts and uploads go with it
7. Runs `compose down -v --remove-orphans` from the install directory, so the override is in effect and the project's volumes go too — or removes the containers individually if no Compose file is left
8. Removes any project volume that survived, matched by the Compose project label rather than by name
9. Moves `backups/` out of the way, unless you chose to delete it too
10. Optionally removes the images (asked separately per group, both default to no)
11. Removes the install directory
12. Reports leftovers: additional components that stay, an `update-librechat.sh` cron entry, `/var/log/librechat-update.log`, the NPM proxy hosts and the DNS records — all named but never touched

It opens no host ports, and re-running it on an already clean host simply reports that there is nothing to do.

---

## What's left alone, on purpose

- **Every directory outside the installation.** The code interpreter stacks (`/opt/LibreCodeInterpreter`, `/opt/avila-code-interpreter`) and the admin tool (`/opt/admin-lc`) were installed by [their own scripts](../codeInterpreter/README.md) and are removed there — this script only reports that they exist.
- **The `shared_proxy` Docker network** — shared with Nginx Proxy Manager, n8n, SearXNG and anything else you proxied. Removing it would break those stacks' Compose files, so it stays.
- **Containers of other stacks** — completely untouched.
- **Base images**, unless you answer yes to their own question: `mongo`, `getmeili/meilisearch` and `pgvector/pgvector` are frequently used by other projects on the same host.
- **The proxy hosts in Nginx Proxy Manager** for the chat and admin domains — remove those manually in NPM if you no longer need them.
- **Your DNS records and firewall rules** — nothing outside this host is touched.
- **A cron entry for `update-librechat.sh`** — reported with a reminder to remove it via `crontab -e`, never edited automatically.
- **`/var/log/librechat-update.log`** — kept, so you still have the update history.

---

## Requirements

- Bash ≥ 4, `curl`
- Docker + Docker Compose (v2 plugin or the legacy `docker-compose` binary — both are detected)
- root, via `sudo` or a root shell

---

## Installation

The same thing step by step, if you prefer to read the script before running it:

```bash
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/uninstall/uninstall-librechat.sh && chmod +x uninstall-librechat.sh && sudo ./uninstall-librechat.sh --dry-run
```

It can be run from any directory — it asks for, or detects, the path to your installation.

---

## Options

| Flag / Variable | Effect |
|---|---|
| `--dry-run` | Shows every step and what would be deleted, changes nothing |
| `--dir <path>` / `INSTALL_DIR` | Sets the install path explicitly and skips detection |
| `--yes` / `ASSUME_YES=1` | Skips **all** confirmations — data, volumes, backups **and** both image groups are removed without asking |
| `--help` | Prints usage and exits |

With `bash -c "$(curl ...)"`, arguments go after a `--` separator, because `bash -c` assigns the first argument to `$0`:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/uninstall/uninstall-librechat.sh)" -- --dry-run
```

Fully unattended teardown, e.g. when rebuilding a host from scratch:

```bash
sudo INSTALL_DIR=/opt/librechat ASSUME_YES=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/uninstall/uninstall-librechat.sh)"
```

---

## Known pitfalls

- **The chat database is a bind mount, not a volume.** MongoDB stores everything in `data-node/` inside the install directory, so it is deleted with the folder — `docker compose down -v` alone would not have removed it, and keeping the volumes would not have saved it.
- **Declining the backup question is not a backup strategy.** The archive is moved to `librechat-backups-<timestamp>` next to the install directory; move it somewhere off-host if you actually want to keep it.
- **`ASSUME_YES=1` also deletes the backups and both image groups.** Combine it with `--dry-run` on the first run.
- **Deleting the base images can slow down unrelated stacks.** They are pulled again on next use — harmless, but not instant.
- **The `.env` is gone with the directory**, and with it `CREDS_KEY`, `CREDS_IV` and the JWT secrets. A fresh install generates new ones, so any API keys stored inside LibreChat would have to be entered again even if the database were restored from an old backup.
- **A code interpreter keeps running after LibreChat is gone.** It is reported, not removed; until you remove it, it stays attached to `shared_proxy` and keeps its container resources.

---

## Security

This script deletes data and requires root: it removes containers, Docker volumes, images and an entire directory tree under `/opt`. The Quick Uninstall one-liner executes a remote script directly — review it first (see [Installation](#installation)) if you would rather not run it sight unseen. Prompts are read from `/dev/tty`, never from stdin, so a pipe cannot feed confirmations into it; without a real terminal it aborts rather than assuming a yes, unless `ASSUME_YES=1` is set deliberately. The path to be deleted is resolved with `pwd -P` and rejected if it is a system directory or sits too high in the filesystem, so a mistyped `--dir` cannot turn into a `rm -rf` of `/opt`. Apart from local Docker daemon calls it contacts nothing. Deletion is irreversible: `.env` (with all keys and secrets), `data-node/` (all chats and accounts) and `uploads/` are removed without a built-in backup step unless you keep the offered one. Image removal only deletes the images listed in the Compose config and fails harmlessly with a warning if one is still referenced elsewhere.

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
