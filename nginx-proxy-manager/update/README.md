# Nginx Proxy Manager - Auto Update with Backup

A small, robust Bash script that automatically updates [Nginx Proxy Manager](https://nginxproxymanager.com/) (NPM) running via Docker Compose. It creates a backup before every update, keeps only the latest backups, and reliably handles **major version jumps** (e.g. v14 -> v15).

This script builds on and complements the following blog article:
**[Nginx Proxy Manager (pc-fee.com)](https://pc-fee.com/nginx-proxy-manager/)**

---

## Why this script?

The common one-liner approach (`docker compose down && pull && up`) has two weaknesses:

- **It does not reliably perform major version jumps.** A plain `pull` + `up -d` does not always recreate the container when the `latest` tag points to a new major version.
- **It creates no backup.** If an update breaks something, there is no way back.

This script fixes both by comparing the image ID before and after the pull and forcing a clean recreate only when a new image is actually present.

---

## What it does

1. Creates a backup of `data/` (including the SQLite database) and `letsencrypt/`
2. Keeps only the **5 most recent** backups
3. Pulls the latest image and detects major jumps (e.g. v14 -> v15)
4. Recreates the container **only** when a new image is present
5. Prunes old (dangling) images
6. Logs everything to `/var/log/npm-update.log`

---

## Requirements

- Docker + Docker Compose
- NPM installed under `/opt/nginx-proxy-manager` with this layout (see the blog article):
  - `/opt/nginx-proxy-manager/docker-compose.yml`
  - `/opt/nginx-proxy-manager/data`
  - `/opt/nginx-proxy-manager/letsencrypt`
- The service in `docker-compose.yml` is named `app`
- The image tag is `jc21/nginx-proxy-manager:latest`

---

## Installation

```bash
# Copy the script onto your server (e.g. into the NPM directory)
cp update-npm.sh /opt/nginx-proxy-manager/

# Make it executable
chmod +x /opt/nginx-proxy-manager/update-npm.sh
```

---

## Usage

Run it manually:

```bash
/opt/nginx-proxy-manager/npm-update.sh
```

The script writes all output to the log file. To watch it live:

```bash
tail -f /var/log/npm-update.log
```

---

## Automating with Cron

Run the update weekly (e.g. every Sunday at 03:00). Always use the **absolute path**:

```bash
crontab -e
```

```cron
0 3 * * 0 /opt/nginx-proxy-manager/update-npm.sh
```

---

## Backups

Backups are stored in:

```
/opt/nginx-proxy-manager/backups/
```

Each archive is named `npm_YYYY-MM-DD_HH-MM-SS.tar.gz` and contains `data/` and `letsencrypt/`.

Inspect a backup without extracting it:

```bash
tar tzvf /opt/nginx-proxy-manager/backups/npm_2026-06-07_07-00-24.tar.gz
```

Restore (example):

```bash
cd /opt/nginx-proxy-manager
docker compose down
tar xzf backups/npm_2026-06-07_07-00-24.tar.gz
docker compose up -d
```

---

## Configuration

The most relevant variables are at the top of the script:

| Variable | Default | Description |
| --- | --- | --- |
| `DIR` | `/opt/nginx-proxy-manager` | NPM working directory |
| `BACKUP` | `/opt/nginx-proxy-manager/backups` | Backup target directory |
| `LOG` | `/var/log/npm-update.log` | Log file |

To keep a different number of backups, adjust the `tail -n +6` value (keep N = value - 1).

---

## Disclaimer

All instructions are provided with great care, but you use them at your own risk. **pc-fee.com** accepts no liability for any damage. Backups before planned changes are mandatory.

---

## AI Transparency

This script and its documentation were created with the assistance of AI. The work was carried out by **Nils Weber**, an AI assistant (n8n Automation Architect) at pc-fee.com, in collaboration with a human reviewer. All output was reviewed before publication. Use at your own discretion and always test in a non-production environment first.

---

## License

MIT License - (c) pc-fee.com

## Author

Nils Weber - n8n Automation Architect at [pc-fee.com](https://pc-fee.com)

