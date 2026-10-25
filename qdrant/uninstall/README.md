# 🧹 Qdrant Uninstall Script

[🏠 Overview](../../) → [🧮 Qdrant](../) → Uninstall

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-Qdrant-DC244C?style=for-the-badge)](https://qdrant.tech/documentation/) [![GitHub](https://img.shields.io/badge/GitHub-qdrant-181717?style=for-the-badge&logo=github)](https://github.com/qdrant/qdrant) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements) [![Host-ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#whats-left-alone-on-purpose) [![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#options)

Removes a [Qdrant](https://qdrant.tech/) instance installed with the [install script](../install/README.md): the container and the install directory **including all collections** — and, each only after its own confirmation, the backups and the Docker images. The shared proxy network and every other stack stay untouched.

> **This is irreversible.** Deleting the install directory deletes every collection — vectors, payloads, indexes — for example the knowledge base of your n8n RAG workflows. Run `--dry-run` first and make sure a backup exists (`backup-qdrant.sh --backup`). By default the backup directory is kept.

---

## Quick Uninstall

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/uninstall/uninstall-qdrant.sh)" -- --dry-run
```

Shows the complete inventory and every step that would run — and deletes nothing. Run it again without `-- --dry-run` to actually remove the installation; the script then asks before deleting the data, the backups and the images, one question each (default answer: no).

---

## Why this script?

`docker compose down` leaves the data, the API key, the backups and the images behind, and `rm -rf` on the wrong folder is easy. This script finds the installation itself, shows exactly what belongs to it before anything happens, and keeps the line between "this Qdrant installation" and "everything else on the host" explicit.

---

## What it does

1. Checks prerequisites (root, Docker, Docker Compose)
2. Determines the install path the same way as the [update script](../update/README.md): `--dir`, the container's Compose label, the `/qdrant/storage` volume, `/opt/qdrant`. It refuses system directories such as `/`, `/opt` or `/var` even if a matching Compose file lies there.
3. Takes stock without the API (works even if Qdrant is stopped):
   - the container(s) of this Compose file with image and state
   - the install directory with `docker-compose.yml`, `.env`, `storage/` (number and names of the collections, size) and `snapshots/`
   - the backup directory from `.env` with the number of update backups and snapshot sets
   - other containers on the same network (they keep running)
   - other `qdrant/qdrant` containers that do **not** belong to this installation (reported, not touched)
   - the local `qdrant/qdrant` images
4. Asks three separate questions: remove container and install directory, also delete the backup directory, also delete the images
5. Runs `docker compose down --remove-orphans` (external networks are never removed by it), deletes the install directory, then — if confirmed — the backups and the images
6. Reports what is left on purpose: cron entries, log files, the Proxy Host and DNS record, the n8n credentials

If no install directory is found but orphaned Qdrant containers exist, it offers to remove only those.

---

## Requirements

- Root (or `sudo`), Docker + Docker Compose
- An installation created by the [install script](../install/README.md) (or any Compose file with a `qdrant/qdrant` image)

---

## Installation

```bash
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/uninstall/uninstall-qdrant.sh
chmod +x uninstall-qdrant.sh
sudo ./uninstall-qdrant.sh --dry-run
```

---

## Options

| Flag / Variable | Effect |
|---|---|
| `--dry-run` | Shows the inventory and every step, deletes nothing |
| `--dir <path>` / `INSTALL_DIR` | Sets the install path explicitly and skips detection |
| `--yes` / `ASSUME_YES=1` | Skips **all** confirmations — data, backups **and** images are removed without asking |
| `--help` | Prints usage and exits |

Input is always read from the terminal (`/dev/tty`), never from stdin, so the `curl` one-liner cannot swallow its own prompts. Without a terminal (e.g. cron) nothing is deleted unless `ASSUME_YES=1` is set explicitly.

Fully unattended teardown, e.g. when rebuilding a host from scratch:

```bash
sudo INSTALL_DIR=/opt/qdrant ASSUME_YES=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/uninstall/uninstall-qdrant.sh)"
```

---

## What's left alone, on purpose

- **The Docker network** (default `shared_proxy`) — it is shared with Nginx Proxy Manager, n8n, LibreChat and other stacks
- **Every other container**, including other Qdrant containers that do not belong to the detected installation
- **The backup directory** (default `/opt/qdrant-backups`), unless you confirm its deletion separately
- **The images**, unless you confirm their deletion separately
- **Cron entries** for `update-qdrant.sh` / `backup-qdrant.sh` — reported, remove them with `crontab -e`
- **Log files** `/var/log/qdrant-update.log` and `/var/log/qdrant-backup.log`
- **Outside the host:** the Proxy Host in Nginx Proxy Manager, the DNS record, and the Qdrant credentials in n8n

---

## Known pitfalls

- **Kept backups are only useful with a matching version.** Snapshot sets can be restored on the same or next minor version of Qdrant; the update backups contain the old Compose file and can be extracted into a fresh install directory.
- **`--yes` really means yes to everything.** Including backups and images — use it only when that is intended.

---

## Security

The script requires root: it removes containers and deletes directories. It only deletes paths that hold a Compose file with a `qdrant/qdrant` image, refuses system directories, and asks separately before deleting backups and images.

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
