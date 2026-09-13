# 🔍 SearXNG Update Script

[🏠 Overview](../../) → [🔍 SearXNG](../) → Update

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Guide](https://img.shields.io/badge/Guide-SearXNG-FE5200?style=for-the-badge)](https://pc-fee.com/searxng/)
[![Docs](https://img.shields.io/badge/Docs-docs.searxng.org-2496ED?style=for-the-badge)](https://docs.searxng.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements)
[![Re-runnable](https://img.shields.io/badge/Re--runnable-yes-2E7D32?style=flat-square)](#what-it-does)
[![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#options)
[![Backup](https://img.shields.io/badge/Backup-before%20every%20update-2E7D32?style=flat-square)](#backups)
[![Confirmation](https://img.shields.io/badge/Confirmation-required-2E7D32?style=flat-square)](#the-confirmation-step)

Updates a [SearXNG](https://docs.searxng.org/) instance running via Docker Compose. It shows you what would change and **waits for your confirmation**, takes a **backup of `config/` before every update**. Like the [installer](../install/README.md), it runs **from anywhere** — it finds your installation itself.

This script builds on and complements the pc-fee.com guide:
**[SearXNG (pc-fee.com)](https://pc-fee.com/searxng/)**

---

## Quick Update

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/searxng/update/update-searxng.sh)"
```

One command, from any directory — no download into the install folder first. The script locates your SearXNG installation, checks whether a new image exists, and then shows you a summary and asks before it changes anything (see [The confirmation step](#the-confirmation-step)). If there is no new image it stops right there, without a backup or a restart. Add `-- --dry-run` to see what it would do without downloading anything (see [Options](#options)).

---

## Why this script?

A plain `docker compose pull && up -d` has the same weaknesses here as for any other Compose stack: it does not always recreate the container when a floating tag (e.g. `latest`) moves, it creates no backup of your configuration first, and it gives you no chance to review the change before it happens. This script compares the image ID before and after the pull, shows you the difference and waits for a yes, and only then backs up and recreates.

---

## How it finds your installation

In this order, until a match is found:

1. `--dir` / `INSTALL_DIR`, if given — no guessing at all
2. The Compose working directory label of any running or stopped `searxng/searxng` container
3. The host path behind the container's `/etc/searxng` volume, one level up
4. The installer's default, `/opt/searxng`

A directory only counts as a match if it holds a Compose file referencing a `searxng/searxng` image. If **several** installations are found, the script lists them and asks which one to update — and without a terminal (cron) it aborts instead of picking one silently.

---

## What it does

1. Checks prerequisites (root, Docker, Docker Compose, `tar`)
2. Determines the install path (see above) and reads the image reference from the Compose file, so pinned tags keep working
3. Takes stock: containers and their state, the image currently in use with its build date, the size of `config/`, how many backups already exist
4. Pulls the current image — this only downloads layers, the running container is not touched
5. **Stops here if the image ID is unchanged**, without a backup and without a restart
6. Otherwise shows the summary and asks for confirmation (default answer: no)
7. Creates a backup of `config/` (including `settings.yml` and its `secret_key`)
8. Recreates the container with `--force-recreate`
9. Keeps only the **5 most recent** backups (configurable via `--keep`) and prunes dangling images
10. Logs everything to `/var/log/searxng-update.log`

Safe to run repeatedly: with no new image, or with the confirmation declined, it leaves the host exactly as it was — apart from the downloaded image, which simply waits for the next run.

---

## The confirmation step

Nothing that touches your service happens before you say yes. The summary spells out the difference between now and after:

```text
 JETZT      sha256:1a2b3c4d5e6f  (Stand 2026-06-01)
 NACHHER    sha256:9f8e7d6c5b4a  (Stand 2026-09-10)  <- neu

 Es wird:
   1. config gesichert nach searxng_2026-09-13_07-08-10.tar.gz
   2. der Container neu erstellt - kurze Downtime, meist wenige Sekunden
   3. 2 alte(s) Backup(s) entfernt, aeltestes: searxng_2026-01-01_00-00-00.tar.gz
   4. dangling Images auf diesem Host aufgeraeumt

 Unveraendert bleibt:
   - docker-compose.yml
   - deine settings.yml inkl. secret_key und Limiter-Einstellung
   - das Docker-Netzwerk und alle anderen Stacks darauf

Update jetzt durchfuehren? [j/N]:
```

The prompt is read from `/dev/tty`, so a piped invocation cannot answer it for you. Without a terminal — in cron, for instance — the script does not guess: it aborts unless you passed `--yes`.

---

## Requirements

- Bash ≥ 4, `curl`, `tar`
- Docker + Docker Compose (v2 plugin or the legacy `docker-compose` binary — both are detected)
- root, via `sudo` or a root shell
- A SearXNG installation created by [install-searxng.sh](../install/README.md) or laid out the same way: a Compose file referencing `searxng/searxng`, with `config/` next to it

---

## Installation

The same thing step by step, if you prefer to read the script before running it:

```bash
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/searxng/update/update-searxng.sh
chmod +x update-searxng.sh
sudo ./update-searxng.sh
```

It does not matter where the file lives — the script works with absolute paths only.

---

## Options

| Flag / Variable | Effect |
|---|---|
| `--dry-run` | Lists what would happen and skips the pull entirely, so it downloads nothing — and therefore cannot tell you whether a new image exists |
| `--yes` / `ASSUME_YES=1` | Skips the confirmation. Required for unattended runs such as cron |
| `--dir <path>` / `INSTALL_DIR` | Sets the install path explicitly and skips detection — recommended for cron |
| `--keep <n>` / `KEEP_BACKUPS` | Number of backups to retain (default: 5) |
| `LOG_FILE` | Log file (default: `/var/log/searxng-update.log`) |
| `--help` | Prints usage and exits |

With `bash -c "$(curl ...)"`, arguments go after a `--` separator, because `bash -c` assigns the first argument to `$0`:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/searxng/update/update-searxng.sh)" -- --dry-run
```

---

## Automating with Cron

Download the script once, then run it weekly (e.g. every Sunday at 03:00). Always use the **absolute path**, and pass `--dir` so an unattended run never has to guess:

```bash
sudo crontab -e
```

```cron
0 3 * * 0 /opt/searxng/update-searxng.sh --dir /opt/searxng --yes
```

`--yes` is mandatory here: cron has no terminal, and without it the script aborts at the confirmation rather than updating unattended. `--dir` spares it the detection, so an ambiguous host never stops the job either. Everything it would have shown you still lands in `/var/log/searxng-update.log`, so you can read afterwards what changed.

---

## Backups

Backups live in `backups/` inside the install directory, named `searxng_YYYY-MM-DD_HH-MM-SS.tar.gz`, each containing `config/` (i.e. `settings.yml` with the `secret_key`).

Inspect one without extracting:

```bash
tar tzvf /opt/searxng/backups/searxng_2026-06-07_07-00-24.tar.gz
```

Roll back after a failed update — the script prints these three commands with the correct paths at the end of every run:

```bash
docker compose -f /opt/searxng/docker-compose.yml down
tar xzf /opt/searxng/backups/searxng_2026-06-07_07-00-24.tar.gz -C /opt/searxng
docker compose -f /opt/searxng/docker-compose.yml up -d
```

---

## Known pitfalls

- **`config/` holds your `secret_key`.** Treat backup archives the same way you would treat any other credentials file.
- **`latest` moves without warning.** That is the whole point of the image-ID comparison; do not replace the script with a plain `pull` in cron.
- **Backups now happen only when an update happens.** If nothing new is available, no archive is written. If you relied on the weekly cron run as a backup schedule, set up a separate job for that.
- **A pinned tag never updates.** If your Compose file pins an exact tag, the script honours that pin and will keep reporting `NOCHANGE` — by design.
- **`docker image prune -f` runs after a successful recreate** and removes *all* dangling images on the host, not just SearXNG's — worth knowing on a busy Docker host.

---

## Uninstalling

To remove the whole instance instead of updating it, see the [uninstall script](../uninstall/README.md).

---

## Security

The script requires root: it writes into `/opt`, recreates containers and writes `/var/log/searxng-update.log`. The Quick Update one-liner executes a remote script directly — review it first (see [Installation](#installation)) if you would rather not run it sight unseen. Nothing that affects the running service happens without an explicit yes; the image pull that precedes the question only downloads layers and leaves the container alone. Prompts are read from `/dev/tty`, never from stdin, so a piped invocation cannot silently feed answers into the script; without a real terminal it aborts rather than assuming, and `--yes` has to be set deliberately. Apart from the image pull it makes no outbound connections, and it never touches the `shared_proxy` network.

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
