# 🌐 Nginx Proxy Manager Update Script

[🏠 Overview](../../) → [🌐 Nginx Proxy Manager](../) → Update

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Guide](https://img.shields.io/badge/Guide-Nginx%20Proxy%20Manager-FE5200?style=for-the-badge)](https://pc-fee.com/nginx-proxy-manager/)
[![Docs](https://img.shields.io/badge/Docs-nginxproxymanager.com-2496ED?style=for-the-badge)](https://nginxproxymanager.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements)
[![Re-runnable](https://img.shields.io/badge/Re--runnable-yes-2E7D32?style=flat-square)](#what-it-does)
[![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#options)
[![Backup](https://img.shields.io/badge/Backup-before%20every%20run-2E7D32?style=flat-square)](#backups)

Updates a [Nginx Proxy Manager](https://nginxproxymanager.com/) (NPM) instance running via Docker Compose. It takes a **backup before every run**, keeps only the most recent ones, and reliably handles **major version jumps** (e.g. v14 → v15). Like the [installer](../install/README.md), it runs **from anywhere** — it finds your installation itself.

This script builds on and complements the pc-fee.com guide:
**[Nginx Proxy Manager (pc-fee.com)](https://pc-fee.com/nginx-proxy-manager/)**

---

## Quick Update

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/update/update-npm.sh)"
```

One command, from any directory — no download into the install folder first. The script locates your NPM installation, backs up `data/` and `letsencrypt/`, pulls the current image and recreates the container **only** if a genuinely new image arrived. Add `-- --dry-run` to see what would happen without changing anything (see [Options](#options)).

---

## Why this script?

The common one-liner (`docker compose down && pull && up`) has two weaknesses:

- **It does not reliably perform major version jumps.** A plain `pull` + `up -d` does not always recreate the container when the `latest` tag moves to a new major version.
- **It creates no backup.** If an update breaks something, there is no way back.

This script fixes both by comparing the image ID before and after the pull, and forcing a clean recreate only when a new image is actually present. On top of that it no longer depends on a fixed path: earlier versions had `/opt/nginx-proxy-manager` hard-coded and had to be started from that directory.

---

## How it finds your installation

In this order, until a match is found:

1. `--dir` / `INSTALL_DIR`, if given — no guessing at all
2. The Compose working directory label of any running or stopped `nginx-proxy-manager` container
3. The host path behind the container's `/data` volume, one level up
4. The installer's default, `/opt/nginx-proxy-manager`

A directory only counts as a match if it holds a Compose file referencing an `nginx-proxy-manager` image. If **several** installations are found, the script lists them and asks which one to update — and without a terminal (cron) it aborts instead of picking one silently.

---

## What it does

1. Checks prerequisites (root, Docker, Docker Compose, `tar`)
2. Determines the install path (see above) and reads the image reference from the Compose file, so pinned tags keep working
3. Creates a backup of `data/` (including the SQLite database) and `letsencrypt/`
4. Keeps only the **5 most recent** backups (configurable via `--keep`)
5. Pulls the current image and compares the image ID before/after
6. Recreates the container **only** when a new image is present (this is what forces major jumps through)
7. Prunes dangling images afterwards
8. Logs everything to `/var/log/npm-update.log` and prints the rollback commands

Safe to run repeatedly: with no new image it changes nothing except writing a fresh backup.

---

## Requirements

- Bash ≥ 4, `curl`, `tar`
- Docker + Docker Compose (v2 plugin or the legacy `docker-compose` binary — both are detected)
- root, via `sudo` or a root shell
- An NPM installation created by [install-npm.sh](../install/README.md) or laid out the same way:
  - a Compose file in the install directory referencing `jc21/nginx-proxy-manager`
  - `data/` and `letsencrypt/` next to it

---

## Installation

The same thing step by step, if you prefer to read the script before running it:

```bash
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/update/update-npm.sh
chmod +x update-npm.sh
sudo ./update-npm.sh
```

It does not matter where the file lives — the script works with absolute paths only.

---

## Options

| Flag / Variable | Effect |
|---|---|
| `--dry-run` | Shows every step including the pull, changes nothing, exits before the recreate |
| `--dir <path>` / `INSTALL_DIR` | Sets the install path explicitly and skips detection — recommended for cron |
| `--keep <n>` / `KEEP_BACKUPS` | Number of backups to retain (default: 5) |
| `LOG_FILE` | Log file (default: `/var/log/npm-update.log`) |
| `--help` | Prints usage and exits |

With `bash -c "$(curl ...)"`, arguments go after a `--` separator, because `bash -c` assigns the first argument to `$0`:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/update/update-npm.sh)" -- --dry-run
```

---

## Automating with Cron

Download the script once, then run it weekly (e.g. every Sunday at 03:00). Always use the **absolute path**, and pass `--dir` so an unattended run never has to guess:

```bash
sudo crontab -e
```

```cron
0 3 * * 0 /opt/nginx-proxy-manager/update-npm.sh --dir /opt/nginx-proxy-manager
```

Cron has no terminal, so the script never prompts there. If it would have to ask — several installations found — it aborts with a clear message instead of updating the wrong one.

---

## Backups

Backups live in `backups/` inside the install directory, named `npm_YYYY-MM-DD_HH-MM-SS.tar.gz`, each containing `data/` and `letsencrypt/`.

Inspect one without extracting:

```bash
tar tzvf /opt/nginx-proxy-manager/backups/npm_2026-06-07_07-00-24.tar.gz
```

Roll back after a failed update — the script prints these three commands with the correct paths at the end of every run:

```bash
docker compose -f /opt/nginx-proxy-manager/docker-compose.yml down
tar xzf /opt/nginx-proxy-manager/backups/npm_2026-06-07_07-00-24.tar.gz -C /opt/nginx-proxy-manager
docker compose -f /opt/nginx-proxy-manager/docker-compose.yml up -d
```

---

## Known pitfalls

- **Certificates and Proxy Hosts live in `data/` and `letsencrypt/`** — nowhere else. A backup that skips one of them is not a backup.
- **`latest` moves across major versions.** That is the whole point of the image-ID comparison; do not replace the script with a plain `pull` in cron.
- **Backups grow.** Five archives of a large `letsencrypt/` add up; check the folder size occasionally or lower `--keep`.
- **A pinned tag never updates.** If your Compose file says `:2.11.3`, the script honours that pin and will keep reporting `NOCHANGE` — by design.
- **`docker image prune -f` runs after a successful recreate** and removes *all* dangling images on the host, not just NPM's. That is the same behaviour as before, but worth knowing on a busy Docker host.

---

## Uninstalling

To remove the whole instance instead of updating it, see the [uninstall script](../uninstall/README.md).

---

## Security

The script requires root: it writes into `/opt`, recreates containers and writes `/var/log/npm-update.log`. The Quick Update one-liner executes a remote script directly — review it first (see [Installation](#installation)) if you would rather not run it sight unseen. Prompts are read from `/dev/tty`, never from stdin, so a piped invocation cannot silently feed answers into the script; without a real terminal it aborts rather than assuming. Apart from the image pull it makes no outbound connections, and it never touches the `shared_proxy` network, your Proxy Hosts or your certificates — those only travel into the backup archive, which is created with the permissions of the directory it lives in, so keep `backups/` root-owned.

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
