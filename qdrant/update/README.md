# 🔄 Qdrant Update Script

[🏠 Overview](../../) → [🧮 Qdrant](../) → Update

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-Qdrant-DC244C?style=for-the-badge)](https://qdrant.tech/documentation/upgrades/) [![GitHub](https://img.shields.io/badge/GitHub-qdrant-181717?style=for-the-badge&logo=github)](https://github.com/qdrant/qdrant) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements) [![Host-ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#what-it-does) [![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#options) [![Backup](https://img.shields.io/badge/Backup-before%20every%20run-2E7D32?style=flat-square)](#backups-and-rollback)

Updates a [Qdrant](https://qdrant.tech/) instance installed with the [install script](../install/README.md). It shows **CURRENT → FUTURE** state, waits for your confirmation, takes a **full backup** of `storage/` before changing anything, and walks through **every intermediate minor version** — Qdrant migrates its storage one minor version at a time and must not skip one.

> **Why several steps?** According to the [official upgrade guide](https://qdrant.tech/documentation/upgrades/), a single-node Qdrant "cannot skip versions to ensure that all data migrations are properly applied" — you upgrade to the latest patch of each intermediate minor version first. From `v1.17.1` to `v1.19.2` the script therefore runs `v1.17.1 → v1.18.3 → v1.19.2` and checks Qdrant after each step.

---

## Quick Update

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/update/update-qdrant.sh)"
```

One command, from any directory. The script finds your installation, reads the running version, plans the upgrade path from the official release list and shows you the plan before it touches anything. If Qdrant is already up to date it stops right there — no backup, no restart. Add `-- --dry-run` to only see the plan (see [Options](#options)).

---

## Why this script?

A plain `docker compose pull && up -d` with a new tag is exactly what Qdrant tells you not to do across several minor versions — the storage migration of a skipped version never runs. It also takes no backup first, and gives you no consistent way back. This script computes the correct path, stops Qdrant for a consistent backup, starts every intermediate version and verifies version, readiness and every collection's point count before it calls the update done.

---

## How it finds your installation

In this order, until a match is found:

1. `--dir` / `INSTALL_DIR`, if given — no guessing at all
2. The Compose working directory label of any `qdrant/qdrant` container
3. The host path behind the container's `/qdrant/storage` volume, one level up
4. The installer's default, `/opt/qdrant`

A directory only counts if it holds a Compose file referencing a `qdrant/qdrant` image. If **several** installations are found, the script asks which one — without a terminal (cron) it aborts instead of picking one. The backup path and the API key are read from the installation's `.env`.

---

## What it does

1. **Takes stock:** install path, image tag, container, running version (`GET /`), every collection with point count and status, size of `storage/`, existing update backups
2. **Checks for news:** loads the stable releases (GitHub releases, falling back to Docker Hub tags), picks the newest — or the one from `--to` — and plans the path through every intermediate minor version. The running stack is not touched.
3. **Shows CURRENT → FUTURE:** Qdrant version, image tag, the full upgrade path
4. **Pre-loads the images** of every step (the running container is not touched) and checks that the backup directory has room for `storage/`
5. **Asks:** how many update backups to keep (default 5), then **one** final confirmation (default answer: no)
6. **Stops Qdrant** and creates the backup `qdrant-update_<timestamp>_<old-version>.tar.gz` with `docker-compose.yml`, `.env` and `storage/`
7. **For every step:** sets the image tag in the Compose file, validates it (`docker compose config --quiet`), runs `up -d`, waits for `/readyz` (up to 300 s) and checks that exactly that version is running — on any failure it stops and prints the rollback commands
8. **Verifies** that every collection still exists with the same point count
9. Removes the images of intermediate versions (the old one stays for a rollback), prunes dangling images, rotates old update backups
10. Prints the rollback commands and a reminder to take a fresh snapshot (see [Known pitfalls](#known-pitfalls))

---

## The confirmation step

Nothing is stopped, backed up or changed before you say yes. Example:

```
 Komponente       AKTUELL                ZUKUENFTIG
 Qdrant           v1.17.1                v1.19.2
 Image-Tag        v1.17.1                v1.19.2

 Update-Pfad (Qdrant erlaubt kein Ueberspringen von Minor-Versionen):
   v1.17.1 -> v1.18.3 -> v1.19.2

 Es wird:
   1. Qdrant gestoppt - Ausfallzeit bis zum Ende des Updates
   2. docker-compose.yml, .env, storage/ gesichert nach /opt/qdrant-backups/qdrant-update_..._v1.17.1.tar.gz
   3. nacheinander gestartet und geprueft: v1.18.3 v1.19.2
   4. kein altes Backup entfernt (es bleiben bis zu 5)

Update jetzt durchfuehren? [j/N]:
```

Qdrant is **unavailable for the whole update** (backup plus every step). n8n workflows that use Qdrant fail during that time, so pick a quiet moment.

---

## Requirements

- Root (or `sudo`), Docker + Docker Compose, `curl`, `tar`
- An installation created by the [install script](../install/README.md) (or any Compose file with a `qdrant/qdrant` image)
- Outbound HTTPS to `api.github.com` (release list) or `hub.docker.com` (fallback), and to the Docker registry for the images
- Free space in the backup directory of at least the size of `storage/`

---

## Installation

```bash
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/update/update-qdrant.sh
chmod +x update-qdrant.sh
sudo ./update-qdrant.sh
```

It does not matter where the file lives — the script finds the installation itself.

---

## Options

| Flag / Variable | Effect |
|---|---|
| `--dry-run` | Shows the plan (versions, path, backup file), downloads and changes nothing |
| `--to <vX.Y.Z>` / `TARGET_VERSION` | Target version instead of the newest stable release (no downgrades) |
| `--keep <n>` / `KEEP_BACKUPS` | Number of update backups to keep (default 5); skips the question |
| `--dir <path>` / `INSTALL_DIR` | Sets the install path explicitly and skips detection |
| `--yes` / `ASSUME_YES=1` | Skips the questions — for cron |
| `LOG_FILE` | Log file (default `/var/log/qdrant-update.log`) |
| `--help` | Prints usage and exits |

With `bash -c "$(curl ...)"`, arguments go after a `--` separator, because `bash -c` assigns the first argument to `$0`:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/update/update-qdrant.sh)" -- --dry-run
```

---

## Automating with Cron

Download the script once, then run it e.g. every Sunday at 03:00. Always use the **absolute path** and pass `--dir`:

```bash
sudo curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/update/update-qdrant.sh -o /usr/local/bin/update-qdrant.sh && sudo chmod +x /usr/local/bin/update-qdrant.sh && sudo crontab -e
```

```cron
0 3 * * 0 /usr/local/bin/update-qdrant.sh --dir /opt/qdrant --yes
```

`--yes` is mandatory here: cron has no terminal, and without it the script aborts at the confirmation without changing anything. Everything it would have shown you lands in `/var/log/qdrant-update.log`. Keep in mind that an unattended update means unattended downtime.

---

## Backups and rollback

Update backups live in the backup directory (default `/opt/qdrant-backups`), named `qdrant-update_YYYY-MM-DD_HH-MM-SS_<old-version>.tar.gz`, mode `600`. Each contains `docker-compose.yml` (with the old image tag), `.env` and the complete `storage/` taken while Qdrant was stopped. Sparse files are archived as sparse (`tar --sparse`).

Inspect one without extracting:

```bash
tar tzvf /opt/qdrant-backups/qdrant-update_2026-10-25_03-00-01_v1.17.1.tar.gz | head
```

Roll back — the script prints these commands with the correct paths at the end of every run, and whenever a step fails:

```bash
docker compose -f /opt/qdrant/docker-compose.yml down
mv /opt/qdrant/storage /opt/qdrant/storage.failed-2026-10-25_03-00-01
tar xzf /opt/qdrant-backups/qdrant-update_2026-10-25_03-00-01_v1.17.1.tar.gz -C /opt/qdrant
docker compose -f /opt/qdrant/docker-compose.yml up -d
```

If the Compose file used a floating tag such as `latest`, the printed rollback contains one extra `sed` line that pins the old version — `latest` points to the new version by then. Once everything runs again, delete the `storage.failed-*` folder.

---

## Known pitfalls

- **Older snapshots may become unusable.** Qdrant restores a snapshot only on the same or the next minor version. After an update across two or more minor versions, snapshots taken before it can no longer be restored — take a fresh one with the [backup script](../backup/README.md) right after the update.
- **Floating tags.** With `latest` in the Compose file, the script determines the version from the running container, runs the same steps with fixed tags and only switches back to `latest` if it points to the target version. If Qdrant is stopped and the tag is floating, the version is unknown — start Qdrant first.
- **No downgrades.** A `--to` lower than the running version is refused; go back with the update backup instead.
- **Major version changes** (`v1.x → v2.x`) are not done automatically — read the release notes first.
- **Large collections take time to load.** The script waits up to 300 s per step for `/readyz`.

---

## Uninstalling

See the [uninstall script](../uninstall/README.md). It asks separately whether the update backups should be deleted too.

---

## Security

The script requires root: it stops and recreates containers, reads the API key from `.env` and writes backups that contain your complete data and the API key. Backups are created with mode `600` in a directory with mode `700`. The API key is only used for read requests against the local instance and is never printed or logged.

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
