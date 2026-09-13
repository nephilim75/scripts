# 🔄 Docker & Docker Compose Updater

[🏠 Overview](../../) → [🐳 Docker & Docker Compose](../) → Update

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-Docker%20Engine-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://docs.docker.com/engine/install/debian/)
[![GitHub](https://img.shields.io/badge/GitHub-scripts-181717?style=for-the-badge&logo=github)](https://github.com/nephilim75/scripts/tree/main/docker%20%26%20docker%20compose/update)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Distro](https://img.shields.io/badge/Debian-10%20%7C%2011%20%7C%2012%20%7C%2013-A81D33?style=flat-square&logo=debian&logoColor=white)](#prerequisites)
[![Ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#security)
[![Idempotent](https://img.shields.io/badge/Re--runnable-yes-2E7D32?style=flat-square)](#known-pitfalls)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#)

Updates an existing **Docker Engine** and **Docker Compose plugin** installation from
Docker's own `apt` repository — and repairs the **GPG key** and the **repository
entry** along the way if they went missing or stopped matching the running Debian
release.

> **Only for installations from Docker's own repository.** The script looks for the
> `docker-ce` package and refuses to run if Docker came from the Debian package
> `docker.io`, from the convenience script, or from a snap. Those installations need
> [install-docker.sh](../install/README.md) instead, which removes the old packages
> first.

---

## Quick Update

One command, in a root shell or with `sudo`:

```bash
bash -c "$(curl -fsSL "https://raw.githubusercontent.com/nephilim75/scripts/main/docker%20%26%20docker%20compose/update/update-docker.sh")"
```

The script takes stock first — Debian release, architecture, installed versions,
key and repository entry, running containers — shows a **summary of every planned
action** and asks for explicit confirmation (`[j/N]`) before anything is changed.
It then upgrades **only** the five Docker packages; there is no `apt-get upgrade`
across the rest of the system.

---

## Prerequisites

- A **Debian** system (`ID=debian` in `/etc/os-release`) with Docker already
  installed from Docker's official repository (package `docker-ce`)
- Either **root**, or a regular user with **`sudo`** installed
- Outgoing HTTPS access to `download.docker.com`

All of this is checked before anything is changed. On a system without Docker the
script stops and points to [install-docker.sh](../install/README.md).

---

## What the script does

| Step | Action |
|---|---|
| **1. Detect** | Reads `ID`, `VERSION_CODENAME` from `/etc/os-release` and the architecture via `dpkg --print-architecture`; verifies that `docker-ce` is installed and reports the current Engine and Compose versions |
| **2. Check** | Is `/etc/apt/keyrings/docker.asc` present? Does `/etc/apt/sources.list.d/docker.list` match the *running* codename and architecture? |
| **Summary & confirmation** | Prints versions, repository status and running containers, then waits for `[j/N]` |
| **3. Repair** | Re-downloads the GPG key and/or rewrites the repository entry if needed — the old `docker.list` is backed up as `docker.list.bak-<timestamp>` first |
| **4. Compare** | `apt-get update`, then a table of *installed vs. available* for all five Docker packages |
| **5. Upgrade** | `apt-get install --only-upgrade` for exactly those packages that actually have a newer version |
| **6. Service** | Checks that `docker` is running and enabled, starts/enables it if not |
| **7. Verify** | `docker --version`, `docker compose version`, container count before/after, plus a colored summary |

### What the script asks

| Question | Meaning |
|---|---|
| **Update jetzt starten? [j/N]** | Shown once, right after the summary, before key, repository or packages are touched. Anything other than `j` aborts cleanly — nothing has been changed at that point. |

### Optional environment variables

| Variable | Meaning |
|---|---|
| `ASSUME_YES=1` | Skip the confirmation prompt (for unattended/automated runs) |
| `SKIP_REPO_FIX=1` | Only report key/repository problems, don't fix them |

Unattended, e.g. from a cron job or another script:

```bash
sudo ASSUME_YES=1 bash update-docker.sh
```

---

## After the update

The script finishes with a green **"Update abgeschlossen"** box and its own summary
(repository status, which packages were upgraded, new Engine and Compose versions,
containers running before and after).

Upgrading `docker-ce` restarts the Docker daemon. Containers with a restart policy
(`restart: unless-stopped` / `always`) come back on their own; containers started
without one stay down. That's why the summary compares the container count before
and after — if it dropped, bring the affected stacks back up:

```bash
cd /path/to/stack && docker compose up -d
```

---

## Known pitfalls

**Running it more than once is safe.** A second run finds key and repository in
order, reports "Alle Docker-Pakete sind bereits auf dem aktuellen Stand" and changes
nothing.

**After a Debian release upgrade** (e.g. bookworm → trixie) the repository entry
still points at the old codename, and `apt` keeps offering the old packages. The
script notices the mismatch, backs up the old `docker.list` and writes the entry for
the codename that is actually running.

**`apt-get update` fails after the repair** if Docker hasn't published a repository
for the new codename yet. The error names the codename; check
`https://download.docker.com/linux/debian/dists/` and keep the previous entry
(restore it from the `.bak-<timestamp>` copy) until Docker catches up.

**Docker not from `docker-ce`** — an installation from `docker.io`, from the
convenience script, or from a snap is refused on purpose. Mixing repository packages
into such a setup produces a half-broken installation; use
[install-docker.sh](../install/README.md), which removes the conflicting packages
first.

**Piping the script straight into `bash` via `curl | bash`** (as in the one-liner
above) means the `[j/N]` prompt still works normally — `bash` reads it from your
terminal, not from the pipe. Only in a non-interactive context (cron, CI, another
script) does the prompt have no terminal to read from; use `ASSUME_YES=1` there.

---

## Useful commands

```bash
apt-cache policy docker-ce        # installed vs. available version
docker version                    # client and daemon in detail
docker compose version            # Compose plugin version
systemctl status docker           # daemon status after the restart
docker ps -a                      # which containers came back up
journalctl -u docker -f           # follow daemon logs, quit with Ctrl+C
```

---

## Security

- Only Docker's own signed `apt` repository is used; the GPG key is pinned via
  `signed-by` in the repository entry, not trusted globally
- A missing or empty key is fetched once over HTTPS from `download.docker.com` —
  the same source the official installation guide uses
- The repository file is never edited in place: it is backed up with a timestamp
  before a new entry is written
- Only the five Docker packages are upgraded, so an unrelated `apt` hold or a
  pending system upgrade is not silently pulled in
- The script never opens or forwards any network port itself; that's entirely up
  to whatever you run in Docker

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
