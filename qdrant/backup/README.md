# 💾 Qdrant Backup & Restore Script

[🏠 Overview](../../) → [🧮 Qdrant](../) → Backup

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-Qdrant-DC244C?style=for-the-badge)](https://qdrant.tech/documentation/snapshots/) [![GitHub](https://img.shields.io/badge/GitHub-qdrant-181717?style=for-the-badge&logo=github)](https://github.com/qdrant/qdrant) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements) [![Host-ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#what-it-does) [![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#options)

Backs up and restores the collections of a [Qdrant](https://qdrant.tech/) instance installed with the [install script](../install/README.md) through the **Snapshot API** — **while Qdrant keeps running**. Restore **all or single collections**, with a **version check** before anything is overwritten and an optional **safety backup** of the current state.

> **Restore overwrites.** A collection with the same name is replaced by the snapshot's content. The script lists every collection that will be overwritten, offers to back up its current state first, and asks for a separate confirmation (default answer: no).

---

## Quick Backup

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/backup/backup-qdrant.sh)"
```

One command, from any directory. Without options it opens a small menu: create a backup, restore a backup, or list backups. The script finds your installation and its API key itself. Pass `-- --backup`, `-- --restore` or `-- --list` to skip the menu (see [Options](#options)).

---

## Why this script?

Qdrant's own snapshots are per collection, land in a working folder inside the container, carry a checksum you are supposed to verify, do not include aliases, and can only be restored on the same or the next minor version. This script handles all of that: it copies every snapshot into a dated backup set outside the install directory, verifies the checksum, cleans up Qdrant's working folder, saves the aliases, and refuses a restore that Qdrant would not accept.

It complements the [update script](../update/README.md), which archives the complete `storage/` with Qdrant stopped — that archive is the right tool for rolling back an update, these snapshots are the right tool for getting back one collection without downtime.

---

## What it does

**Backup** (`--backup`)

1. Connects to the running instance through its IP in the Docker network (no host port needed) and checks version and API key
2. Lists the collections and asks whether to back up all of them (default) or which ones; `--collection` skips the question
3. Asks how many backup sets to keep (default 5) and shows what will happen, including free space
4. For every collection: `POST /collections/<name>/snapshots`, copies the file into the backup set, compares its SHA-256 with the checksum Qdrant returned, then deletes the snapshot in Qdrant's working folder
5. Saves the aliases (`aliases.json`), a manifest with collection, file, checksum and point count, and `info.txt` with the Qdrant version
6. Rotates old backup sets

**Restore** (`--restore [<set>]`)

1. Lets you pick a backup set (or takes it from the command line)
2. **Checks version compatibility:** the running Qdrant must be the same minor version (same or newer patch) or the next minor version — otherwise it stops
3. Lets you pick all or single collections, verifies the checksums **before** anything changes
4. Shows for every collection whether it is created or **overwritten** (with point counts now → from backup)
5. Asks separately: back up the current state first (default yes), restore aliases (default yes), and the final confirmation (default no)
6. Uploads each snapshot (`POST /collections/<name>/snapshots/upload?priority=snapshot` with checksum), removes the uploaded copy from Qdrant's working folder, compares the point count
7. Recreates the aliases

**List** (`--list`) shows every backup set with version, collections, point counts and size, plus the number of update backups.

---

## Requirements

- Root (or `sudo`), Docker + Docker Compose, `curl`, `sha256sum`
- A **running** Qdrant installation — snapshots are made through the API
- The API key in `<install path>/.env` (written by the installer) or in the environment variable `QDRANT_API_KEY`
- Free space in the backup directory; Qdrant also writes each snapshot briefly into its own working folder

---

## Installation

```bash
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/backup/backup-qdrant.sh
chmod +x backup-qdrant.sh
sudo ./backup-qdrant.sh
```

---

## Options

| Flag / Variable | Effect |
|---|---|
| `--backup` | Create a backup set |
| `--restore [<set>]` | Restore a backup set; without a name you pick one from the list |
| `--list` | List backup sets |
| `--collection <name>` | Only this collection (repeatable) — for backup and restore |
| `--keep <n>` / `KEEP_SNAPSHOTS` | Number of backup sets to keep (default 5); skips the question |
| `--backup-dir <path>` / `QDRANT_BACKUP_DIR` | Backup directory (default: from `.env`, otherwise `/opt/qdrant-backups`) |
| `--dir <path>` / `INSTALL_DIR` | Sets the install path explicitly and skips detection |
| `--dry-run` | Shows what would happen, changes nothing |
| `--yes` / `ASSUME_YES=1` | Skips the questions — for cron |
| `QDRANT_API_KEY` | API key, if it is not in `.env` |
| `LOG_FILE` | Log file (default `/var/log/qdrant-backup.log`) |
| `--help` | Prints usage and exits |

With `bash -c "$(curl ...)"`, arguments go after a `--` separator:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/backup/backup-qdrant.sh)" -- --restore --collection docs --dry-run
```

---

## Automating with Cron

A nightly backup of all collections at 02:30, keeping the last 7 sets:

```bash
sudo curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/backup/backup-qdrant.sh -o /usr/local/bin/backup-qdrant.sh && sudo chmod +x /usr/local/bin/backup-qdrant.sh && sudo crontab -e
```

```cron
30 2 * * * /usr/local/bin/backup-qdrant.sh --backup --dir /opt/qdrant --keep 7 --yes
```

Without `--yes` the script never changes anything in cron. A restore without a terminal needs the set name explicitly (`--restore <set>`) **and** `--yes` — it is deliberately hard to overwrite data unattended.

---

## Backup sets

Each run creates one folder in the backup directory (mode `700`, files mode `600`):

```
/opt/qdrant-backups/
├── snapshots_2026-10-25_02-30-01/
│   ├── docs.snapshot              # one snapshot per collection
│   ├── kunden_faq.snapshot        # characters other than A-Z a-z 0-9 . _ - become _
│   ├── manifest.tsv               # collection, file, SHA-256, point count
│   ├── aliases.json               # all aliases at backup time
│   └── info.txt                   # Qdrant version, date, host
├── snapshots_2026-10-25_09-12-44_vor-restore/   # safety backup made before a restore
└── qdrant-update_2026-10-25_03-00-01_v1.17.1.tar.gz   # from the update script
```

Safety backups made before a restore are ordinary backup sets and count towards `--keep`.

---

## Known pitfalls

- **Version window.** Qdrant restores a snapshot only on the same or the next minor version (a `v1.18.1` snapshot works on `v1.18.1+` and `v1.19.x`). After an update across several minor versions, older sets are refused — take a fresh backup after every update.
- **Aliases are not part of a collection snapshot.** The script saves them separately and asks whether to recreate them; an existing alias with the same name is re-pointed.
- **Running workflows see the change immediately.** While a collection is being restored, n8n queries against it may fail or return the old state — restore at a quiet moment.
- **Single node only.** The script is built for the single-node setup of the installer, not for a Qdrant cluster.

---

## Security

The script requires root: it reads the API key from `.env` and writes backups that contain your complete vector data and payloads. Backup sets are created with mode `700`/`600`. The API key is only sent to the local instance inside the Docker network and is never printed or logged. Treat the backup directory like the database itself — anyone who can read it can restore your data elsewhere.

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
