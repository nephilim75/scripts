# 🔄 LibreChat Update Script

[🏠 Overview](../../) → [💬 LibreChat](../) → Update

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements)
[![Host-ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#what-it-does)
[![Re-runnable](https://img.shields.io/badge/Re--runnable-yes-2E7D32?style=flat-square)](#what-it-does)
[![Backup](https://img.shields.io/badge/Backup-before%20every%20update-2E7D32?style=flat-square)](#what-gets-backed-up)
[![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#options)

Companion to the [install script](../install/README.md) — updates a [LibreChat](https://www.librechat.ai/) stack that was installed with it: **repository**, **Docker images**, and a **restart of the stack**, each only when something actually changed. Before anything is touched it takes a **backup of the configuration and a `mongodump` of the chat database**. Like the installer and the [uninstall script](../uninstall/README.md), it runs **from anywhere** and finds the installation itself.

> Nothing is changed without confirmation. The check phase (`git fetch`, `docker compose pull`) leaves the running stack untouched — the summary comes first, the restart only after you say yes.

---

## Quick Update

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/update/update-librechat.sh)"
```

Locates your installation, checks the LibreChat repository and every image in the Compose config for something new, and prints a **NOW → AFTER** summary. If nothing changed it exits with `NOCHANGE` without writing a single byte. Add `-- --dry-run` to walk through the whole run without changing anything (see [Options](#options)).

---

## Why this script?

The manual route is three commands (`git pull`, `docker compose pull`, `docker compose up -d`), and all three have sharp edges on a LibreChat installation:

- `git pull` on the installer's shallow clone silently turns into a merge commit if anything local was touched — this script uses `merge --ff-only` and skips the repository entirely when tracked files are modified, rather than leaving a half-merged checkout behind
- a plain `docker compose up -d` from the wrong directory ignores `docker-compose.override.yml` and **re-opens the host ports** the installer deliberately closed; every Compose call here runs from the install directory, so the override is always in effect
- after a repository update, the new `docker-compose.yml` may not match your override anymore — the configuration is validated **before** the restart, not during it
- there is no undo for a bad update unless somebody made a backup first, so one is taken automatically: config files plus a hot `mongodump`, with no downtime
- restarting for nothing is still a restart — if neither the repository nor a single image changed, the script stops before the backup step

---

## What it does

1. Checks prerequisites (root, Docker running, Docker Compose, `tar`, optionally `git`)
2. Determines the install path: Compose project label → `/app/.env` and `/app/uploads` bind-mount source → `/opt/librechat`, and asks if several installations exist
3. Takes inventory: containers and their state, image IDs from `docker compose config --images`, the repository's branch and commit, which config files exist, how many backups there already are
4. Warns and skips the repository part if tracked files were modified locally, naming the files
5. Checks for updates without touching the stack: `git fetch` (`--depth=1` on a shallow clone, so it stays shallow) and `docker compose pull`
6. Exits with `NOCHANGE` if neither repository nor images moved
7. Prints a **NOW → AFTER** summary — commit, per-image IDs, what will be backed up, what will be deleted — and asks for confirmation (default: no)
8. Creates the backup archive: config files plus `mongodump --archive --gzip` of the `LibreChat` database, plus a `manifest.txt`
9. Runs `git merge --ff-only`, then validates the Compose configuration, then `docker compose up -d`
10. Keeps the newest `--keep` backups (default 5), prunes dangling images
11. Reports leftovers it deliberately does not delete — e.g. a `meili_data_*` directory orphaned by a Meilisearch version bump

It opens no host ports: the stack keeps the `docker-compose.override.yml` written by the installer, where the published ports are reset and only the NPM network is attached.

---

## What gets backed up

Written to `<install dir>/backups/librechat_<timestamp>.tar.gz`, `chmod 600`, before the first change:

| Inside the archive | Content |
|---|---|
| `config/.env` | Keys, secrets, domains — the one file that cannot be reproduced |
| `config/librechat.yaml` | Endpoint and model configuration |
| `config/docker-compose.override.yml` | NPM network, closed host ports |
| `mongodump-LibreChat.archive.gz` | All chats, users and settings, dumped from the running container |
| `manifest.txt` | Timestamp, host, install path, the commit before the update |

The dump is taken with the stack running — no downtime, no stopped database. Restore instructions (including the `mongorestore` line) are printed at the end of every successful run. Use `--no-db` to skip the dump when you only want the config, e.g. on a host where the database is backed up elsewhere.

What is *not* in the archive: `data-node/`, `meili_data_*/`, `uploads/` and `images/` in their raw form. The `mongodump` covers the chat data; uploaded files and the search index are not copied, because a routine update does not touch them.

---

## Requirements

- Bash ≥ 4, `curl`, `tar`
- Docker + Docker Compose (v2 plugin or the legacy `docker-compose` binary — both are detected)
- `git`, if the repository should be updated too (without it, only the images are)
- root, via `sudo` or a root shell
- An installation created by [install-librechat.sh](../install/README.md)

---

## Installation

The same thing step by step, if you prefer to read the script before running it:

```bash
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/update/update-librechat.sh && chmod +x update-librechat.sh && sudo ./update-librechat.sh --dry-run
```

It can be run from any directory — it detects the path to your installation, or takes it from `--dir`.

---

## Options

| Flag / Variable | Effect |
|---|---|
| `--dry-run` | Shows every step and what would change, performs no fetch, no pull and no restart |
| `--dir <path>` / `INSTALL_DIR` | Sets the install path explicitly and skips detection |
| `--keep <n>` / `KEEP_BACKUPS` | Number of backups to keep (default: 5) |
| `--no-db` | Skips the `mongodump`, backs up the config files only |
| `--yes` / `ASSUME_YES=1` | Skips the confirmation — for cron |
| `LOG_FILE` | Log file, default `/var/log/librechat-update.log` |
| `--help` | Prints usage and exits |

With `bash -c "$(curl ...)"`, arguments go after a `--` separator, because `bash -c` assigns the first argument to `$0`:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/update/update-librechat.sh)" -- --dry-run
```

Unattended from cron — save the script once to `/usr/local/sbin/` and run it every Sunday at 04:30, keeping ten backups:

```bash
30 4 * * 0 INSTALL_DIR=/opt/librechat KEEP_BACKUPS=10 ASSUME_YES=1 /usr/local/sbin/update-librechat.sh >/dev/null 2>&1
```

Everything from the inventory onwards is appended to `LOG_FILE`, so a cron run leaves a readable trail.

---

## Known pitfalls

- **`ASSUME_YES=1` confirms the restart, not the outcome.** An unattended run will update to whatever upstream published, including a breaking change. On a production instance, run it interactively or at least read the log afterwards.
- **A locally edited, tracked file stops the repository update, not the image update.** The script says which file and how to discard the change (`git checkout -- <file>`); until then you keep getting image-only updates.
- **New `.env` variables are not merged for you.** If upstream adds a setting to `.env.example`, your `.env` keeps working but misses it — the script prints a reminder, the LibreChat changelog has the details.
- **A Meilisearch version bump leaves the old index directory behind.** The Compose file then points at a new `meili_data_<version>` folder; the old one is reported, never deleted, and can go once the new index has rebuilt.
- **`mongodump` needs the database container running.** If `mongodb` is stopped the script says so and continues with a config-only backup instead of failing.
- **The backup lives inside the install directory.** That is fine for a rollback, useless if the disk dies — copy `backups/` off-host if it is your only copy.

---

## Security

This script requires root and restarts a running service. The Quick Update one-liner executes a remote script directly — review it first (see [Installation](#installation)) if you would rather not run it sight unseen. Prompts are read from `/dev/tty`, never from stdin, so a pipe cannot feed confirmations into it; without a real terminal it aborts rather than assuming a yes, unless `ASSUME_YES=1` is set deliberately. The backup archive contains your `.env` — every secret of the installation, plus a full dump of all chats — and is therefore written `chmod 600` into a `chmod 700` directory; treat copies of it like the `.env` itself. Apart from `github.com` (repository) and the configured image registries, it contacts nothing. Nothing is deleted except backups beyond `--keep` and Docker's dangling images.

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
