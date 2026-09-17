# 🌐 Nginx Proxy Manager Update Script

[🏠 Overview](../../) → [🌐 Nginx Proxy Manager](../) → Update

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Guide](https://img.shields.io/badge/Guide-Nginx%20Proxy%20Manager-FE5200?style=for-the-badge)](https://pc-fee.com/nginx-proxy-manager/) [![Docs](https://img.shields.io/badge/Docs-nginxproxymanager.com-2496ED?style=for-the-badge)](https://nginxproxymanager.com/) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements) [![Re-runnable](https://img.shields.io/badge/Re--runnable-yes-2E7D32?style=flat-square)](#what-it-does) [![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#options) [![Backup](https://img.shields.io/badge/Backup-before%20every%20update-2E7D32?style=flat-square)](#backups)

Updates a [Nginx Proxy Manager](https://nginxproxymanager.com/) (NPM) instance running via Docker Compose. It moves **pinned versions** (as written by the [installer](../install/README.md)) forward to the newest release, shows you what would change and **waits for your confirmation**, takes a **backup before every update**, and reliably handles **major version jumps** (e.g. v14 → v15). Like the installer, it runs **from anywhere** — it finds your installation itself.

This script builds on and complements the pc-fee.com guide:
**[Nginx Proxy Manager (pc-fee.com)](https://pc-fee.com/nginx-proxy-manager/)**

---

## Quick Update

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/update/update-npm.sh)"
```

One command, from any directory — no download into the install folder first. The script locates your NPM installation, checks whether a newer NPM version (or, for a floating tag such as `latest`, a new image) exists, and then shows you a summary and asks before it changes anything (see [The confirmation step](#the-confirmation-step)). If there is nothing new it stops right there, without a backup or a restart. Add `-- --dry-run` to see what it would do without downloading anything (see [Options](#options)).

---

## Why this script?

The common one-liner (`docker compose down && pull && up`) has several weaknesses:

- **It never updates a pinned version.** The installer writes a fixed tag such as `:2.15.1`; pulling that tag again always returns the same image.
- **It does not reliably perform major version jumps.** A plain `pull` + `up -d` does not always recreate the container when the `latest` tag moves to a new major version.
- **It creates no backup.** If an update breaks something, there is no way back.
- **It gives you no say.** By the time you notice, the container is already gone.

This script fixes all of them: for a pinned version it looks up the newest stable release on Docker Hub and moves the pin forward in the Compose file; for a floating tag it compares the image ID before and after the pull. Either way it shows you the difference, waits for a yes, backs up first and forces a clean recreate only when something new is actually present. On top of that it no longer depends on a fixed path — earlier versions had `/opt/nginx-proxy-manager` hard-coded and had to be started from that directory.

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
2. Determines the install path (see above) and reads the image reference from the Compose file
3. Determines the target version:
   - `--version` / `NPM_VERSION`, if given
   - for a pinned version (`x.y.z`): the newest stable release on Docker Hub — **stops here if that is already installed**
   - for a floating tag (`latest`, `2`): the same tag
4. Takes stock: containers and their state, the image currently in use with its build date, the size of `data/` and `letsencrypt/`, how many backups already exist
5. Pulls the target image — this only downloads layers, the running container is not touched
6. For a floating tag, **stops here if the image ID is unchanged**, without a backup and without a restart
7. Otherwise shows the summary and asks for confirmation (default answer: no)
8. Creates a backup of `data/` (including the SQLite database), `letsencrypt/` and the Compose file
9. For a version change, sets the new tag in the Compose file's `image:` line — nothing else in the file is touched
10. Recreates the container with `--force-recreate` — this is what forces major jumps through. If the container does not come up, the previous Compose file is restored and started again
11. Keeps only the **5 most recent** backups (configurable via `--keep`), removes the old NPM image after a version change and prunes dangling images
12. Logs everything to `/var/log/npm-update.log` and prints the rollback commands

Safe to run repeatedly: with nothing new, or with the confirmation declined, it leaves the host exactly as it was — apart from a downloaded image, which simply waits for the next run.

---

## The confirmation step

Nothing that touches your service happens before you say yes. The summary spells out the difference between now and after:

```text
 JETZT      jc21/nginx-proxy-manager:2.15.1  sha256:6b0cc1e34e6f  (Stand 2026-06-03)
 NACHHER    jc21/nginx-proxy-manager:2.16.0  sha256:9f2a71d4c880  (Stand 2026-09-10)  <- neu

 Es wird:
   1. data letsencrypt docker-compose.yml gesichert nach npm_2026-09-13_07-08-10.tar.gz
   2. in docker-compose.yml die Image-Zeile auf jc21/nginx-proxy-manager:2.16.0 gesetzt
      und der Container neu erstellt - kurze Downtime, meist 10-30 Sekunden
   3. 2 alte(s) Backup(s) entfernt, aeltestes: npm_2026-01-01_00-00-00.tar.gz
   4. das alte Image jc21/nginx-proxy-manager:2.15.1 und dangling Images aufgeraeumt

 Unveraendert bleibt:
   - docker-compose.yml bis auf die Image-Zeile, inkl. Portfreigaben und Hardening
   - deine Proxy Hosts, Zertifikate und Zugangsdaten in data/ und letsencrypt/
   - das Docker-Netzwerk und alle anderen Stacks darauf

Update jetzt durchfuehren? [j/N]:
```

The prompt is read from `/dev/tty`, so a piped invocation cannot answer it for you. Without a terminal — in cron, for instance — the script does not guess: it aborts unless you passed `--yes`.

---

## Requirements

- Bash ≥ 4, `curl` (also used to query Docker Hub for pinned versions), `tar`
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
| `--dry-run` | Lists what would happen and skips the pull entirely, so it downloads nothing. For a pinned version it still looks up and shows the target release; for a floating tag it cannot tell you whether a new image exists |
| `--yes` / `ASSUME_YES=1` | Skips the confirmation. Required for unattended runs such as cron |
| `--dir <path>` / `INSTALL_DIR` | Sets the install path explicitly and skips detection — recommended for cron |
| `--version <tag>` / `NPM_VERSION` | Sets the target version explicitly (e.g. `2.15.1`, or `latest` to switch to the floating tag) instead of asking Docker Hub. An older version than the installed one is refused with `--yes` and needs an explicit yes otherwise |
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
0 3 * * 0 /opt/nginx-proxy-manager/update-npm.sh --dir /opt/nginx-proxy-manager --yes
```

For a pinned installation this means: every run moves to the **newest release on Docker Hub**, major versions included. If you want to control jumps yourself, run the script by hand instead, or pin a target with `--version`.

`--yes` is mandatory here: cron has no terminal, and without it the script aborts at the confirmation rather than updating unattended. `--dir` spares it the detection, so an ambiguous host never stops the job either. Everything it would have shown you still lands in `/var/log/npm-update.log`, so you can read afterwards what changed.

---

## Backups

Backups live in `backups/` inside the install directory, named `npm_YYYY-MM-DD_HH-MM-SS.tar.gz`, each containing `data/`, `letsencrypt/` and the Compose file — so a rollback also restores the previous version pin. The [installer](../install/README.md#reinstalling-over-an-existing-instance) writes its pre-reinstall archives (`npm_<timestamp>_pre-reinstall.tar.gz`, `npm_<timestamp>_old-install.tar.gz`) in the same format; they count towards `--keep` and are rotated like any other backup.

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
- **Pinned versions need Docker Hub.** The newest release is looked up at `hub.docker.com`; if that is unreachable, the script aborts and asks for `--version`. Only stable `x.y.z` tags are considered — betas and PR builds are ignored.
- **No automatic downgrade.** Database migrations of a newer release cannot be rolled back by switching the tag. To go back, restore the backup taken before the update — it contains the old Compose file as well.
- **Backups grow.** Five archives of a large `letsencrypt/` add up; check the folder size occasionally or lower `--keep`.
- **Backups now happen only when an update happens.** If nothing new is available, no archive is written. If you relied on the weekly cron run as a backup schedule, set up a separate job for that.
- **Existing cron entries need `--yes` added.** Without it they will stop updating and log an abort instead — which is the safe failure, but a silent one if nobody reads the log.
- **`docker image prune -f` runs after a successful recreate** and removes *all* dangling images on the host, not just NPM's. That is the same behaviour as before, but worth knowing on a busy Docker host.

---

## Uninstalling

To remove the whole instance instead of updating it, see the [uninstall script](../uninstall/README.md).

---

## Security

The script requires root: it writes into `/opt`, recreates containers and writes `/var/log/npm-update.log`. The Quick Update one-liner executes a remote script directly — review it first (see [Installation](#installation)) if you would rather not run it sight unseen. Nothing that affects the running service happens without an explicit yes; the image pull that precedes the question only downloads layers and leaves the container alone. Prompts are read from `/dev/tty`, never from stdin, so a piped invocation cannot silently feed answers into the script; without a real terminal it aborts rather than assuming, and `--yes` has to be set deliberately. Apart from the image pull and, for pinned versions, a read-only query of the Docker Hub tag list, it makes no outbound connections. The only change to your Compose file is the tag in the `image:` line, and only after the backup. It never touches the `shared_proxy` network, your Proxy Hosts or your certificates — those only travel into the backup archive, which is created with the permissions of the directory it lives in, so keep `backups/` root-owned.

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
