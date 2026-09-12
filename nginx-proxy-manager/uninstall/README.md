# 🌐 Nginx Proxy Manager Uninstall Script

[🏠 Overview](../../) → [🌐 Nginx Proxy Manager](../) → Uninstall

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Guide](https://img.shields.io/badge/Guide-Nginx%20Proxy%20Manager-FE5200?style=for-the-badge)](https://pc-fee.com/nginx-proxy-manager/)
[![Docs](https://img.shields.io/badge/Docs-nginxproxymanager.com-2496ED?style=for-the-badge)](https://nginxproxymanager.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements)
[![Host-ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#what-it-does)
[![Re-runnable](https://img.shields.io/badge/Re--runnable-yes-2E7D32?style=flat-square)](#what-it-does)
[![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#options)

Companion to the [install script](../install/README.md) — removes a [Nginx Proxy Manager](https://nginxproxymanager.com/) instance completely: containers, the install directory (`data/`, `letsencrypt/`, the Compose file), and on request the backups and the Docker images. Like the installer and the [update script](../update/README.md), it runs **from anywhere** and finds the installation itself.

> Destructive by design: `data/` holds the SQLite database with **all Proxy Hosts, access lists and credentials**, `letsencrypt/` holds **all issued certificates**. There is no built-in undo. Run it with `--dry-run` first.

---

## Quick Uninstall

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/uninstall/uninstall-npm.sh)"
```

Locates your installation, shows a full inventory of what it found, then asks for explicit confirmation — the default answer is **no**, and backups and images are asked for separately. Add `-- --dry-run` to see the whole run without deleting anything (see [Options](#options)).

---

## Why this script?

- shows an inventory first — containers, directory contents, number and size of backups, matching images — so nothing is a surprise
- up to three separate confirmations, each defaulting to "no": data, backups, images
- can **keep your backups**: if you decline that question, `backups/` is moved next to the install directory instead of being deleted with it
- never touches the `shared_proxy` network; it lists the other containers still attached to it and points out that they stay up but lose their reverse proxy
- points out leftovers it deliberately does not touch, such as a cron entry for the update script
- runs from anywhere via a one-liner, and refuses to delete anything unattended unless you explicitly pass `ASSUME_YES`

---

## What it does

1. Checks prerequisites (root, Docker running, Docker Compose available)
2. Determines the install path the same way the [update script](../update/README.md#how-it-finds-your-installation) does, and asks if several installations exist
3. If no install directory is left but NPM containers still exist, offers to clean up those orphans instead of silently doing nothing
4. Shows an inventory: containers, `data/`, `letsencrypt/`, the Compose file, backup count and size, matching local images, plus other containers on `shared_proxy`
5. Asks for confirmation before anything is removed (default: no)
6. Runs `compose down --remove-orphans`, or removes orphaned containers individually if no Compose file is left
7. Moves `backups/` out of the way, unless you chose to delete it too
8. Optionally removes the `nginx-proxy-manager` images (asked separately, also defaults to no)
9. Removes the install directory
10. Reports leftovers: a `update-npm.sh` cron entry and `/var/log/npm-update.log` are named but never touched

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
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/uninstall/uninstall-npm.sh
chmod +x uninstall-npm.sh
sudo ./uninstall-npm.sh --dry-run
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
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/uninstall/uninstall-npm.sh)" -- --dry-run
```

Fully unattended teardown, e.g. when rebuilding a host from scratch:

```bash
sudo INSTALL_DIR=/opt/nginx-proxy-manager ASSUME_YES=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/uninstall/uninstall-npm.sh)"
```

---

## What's left alone, on purpose

- **The `shared_proxy` Docker network** — shared with n8n, LibreChat and anything else you proxied. Removing it would break those stacks' Compose files, so it stays.
- **Containers of other stacks** — they keep running, but with the proxy gone they are no longer reachable from outside. Either set up a new reverse proxy or bind their ports directly.
- **Your DNS records and firewall rules** — nothing outside this host is touched.
- **A cron entry for `update-npm.sh`** — reported with a reminder to remove it via `crontab -e`, never edited automatically.
- **`/var/log/npm-update.log`** — kept, so you still have the update history.

---

## Known pitfalls

- **Certificates are gone for good.** Let's Encrypt rate limits apply when you re-issue them later (5 duplicate certificates per week per exact domain set), so a rebuild right after a teardown can fail to get a certificate.
- **Declining the backup question is not a backup strategy.** The archives are moved to `npm-backups-<timestamp>` next to the install directory; move them somewhere off-host if you actually want to keep them.
- **`ASSUME_YES=1` also deletes the backups and the images.** Combine it with `--dry-run` on the first run.
- **Port 80/443 stay free afterwards** — if another service grabs them before you reinstall, the new NPM container will fail to start.

---

## Security

This script deletes data and requires root: it removes containers, images and an entire directory tree under `/opt`. The Quick Uninstall one-liner executes a remote script directly — review it first (see [Installation](#installation)) if you would rather not run it sight unseen. Prompts are read from `/dev/tty`, never from stdin, so a pipe cannot feed confirmations into it; without a real terminal it aborts rather than assuming a yes, unless `ASSUME_YES=1` is set deliberately. Apart from local Docker daemon calls it contacts nothing. Deletion is irreversible: `data/` (SQLite database with all Proxy Hosts, access lists and stored credentials) and `letsencrypt/` (certificates and account keys) are removed without a built-in backup step. Image removal only deletes local images by ID and fails harmlessly with a warning if one is still referenced elsewhere.

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

<sub>This script and its documentation were researched, written and iteratively
revised with the help of AI models (Claude, Anthropic), commissioned by
pc-fee.com. All technical statements were checked against the script itself.
Please verify for yourself — ideally with `--dry-run` first — before using it in
production.</sub>

<sub>[← Back to the overview](../)</sub>
