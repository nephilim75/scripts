# Docker & Docker Compose Installer

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-Docker%20Engine-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://docs.docker.com/engine/install/debian/)
[![GitHub](https://img.shields.io/badge/GitHub-scripts-181717?style=for-the-badge&logo=github)](https://github.com/nephilim75/scripts/tree/main/docker%20%26%20docker%20compose/install)

[![Distro](https://img.shields.io/badge/Debian-10%20%7C%2011%20%7C%2012%20%7C%2013-A81D33?style=flat-square&logo=debian&logoColor=white)](#prerequisites)
[![Ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#security)
[![Idempotent](https://img.shields.io/badge/Re--runnable-yes-2E7D32?style=flat-square)](#known-pitfalls)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#)

Installs **Docker Engine** and the **Docker Compose plugin** on Debian, straight from
Docker's own `apt` repository — no distro-packaged `docker.io`, no standalone
Python `docker-compose`.

> **Debian-only.** The script reads `/etc/os-release`, refuses to run on
> Debian-derivatives such as Ubuntu or Raspberry Pi OS (they need their own
> repository line), and picks the matching Docker repository for whichever Debian
> codename it finds — `buster`, `bullseye`, `bookworm`, `trixie`, or newer.

---

## Installation

One command, in a root shell or with `sudo`:

```bash
bash -c "$(curl -fsSL "https://raw.githubusercontent.com/nephilim75/scripts/main/docker%20%26%20docker%20compose/install/install-docker.sh")"
```

The script prints what it detected and what it is about to do at every step,
shows a **summary of every planned action** and asks for explicit confirmation
(`[j/N]`) before touching anything, and aborts with a clear message the moment
something looks wrong. It is safe to run more than once: existing installations
are detected and simply completed or left alone.

---

## Prerequisites

- A **Debian** system (`ID=debian` in `/etc/os-release`) — `buster`/10 through
  `trixie`/13 and newer are recognised by name; unknown/newer codenames are
  attempted anyway with a warning
- `amd64`, `arm64`, or `armhf` (other architectures are attempted with a warning,
  since Docker may not publish packages for them)
- Either **root**, or a regular user with **`sudo`** installed
- Outgoing HTTPS access to `download.docker.com` (GPG key and package repository)

All of this is checked by the script before anything is installed.

---

## What the script does

| Step | Action |
|---|---|
| **1. Detect** | Reads `ID`, `VERSION_CODENAME`, `VERSION_ID` from `/etc/os-release` and the CPU architecture via `dpkg --print-architecture` |
| **Summary & confirmation** | Prints exactly what's about to happen (see below) and waits for `[j/N]` before changing anything |
| **2. Clean up** | Removes conflicting old packages (`docker.io`, `docker-compose`, `podman-docker`, standalone `containerd`/`runc`, …) |
| **3. Prerequisites** | Updates package lists, installs `ca-certificates`, `curl`, `gnupg` |
| **4. GPG key** | Downloads Docker's official signing key to `/etc/apt/keyrings/docker.asc` |
| **5. Repository** | Writes `/etc/apt/sources.list.d/docker.list` with the `stable` channel for the *detected* codename and architecture |
| **6. Install** | `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin` |
| **7. Enable** | `systemctl enable --now docker` |
| **8. Group** | Optionally adds a user to the `docker` group (see below) |
| **9. Verify** | `docker --version`, `docker compose version`, and a `hello-world` test container, followed by a colored summary of everything that happened |

### What the script asks

| Question | Meaning |
|---|---|
| **Installation jetzt starten? [j/N]** | Shown once, right after the summary, before any package is touched or removed. Anything other than `j` aborts cleanly — nothing has been changed yet at that point. |

Every other step runs on its own; there's nothing else to answer.

### Optional environment variables

| Variable | Meaning |
|---|---|
| `ADD_USER=<name>` | User to add to the `docker` group (default: the user who invoked `sudo`) |
| `SKIP_USER_ADD=1` | Don't touch group membership at all |
| `ASSUME_YES=1` | Skip the confirmation prompt (for unattended/automated runs) |

Example:

```bash
sudo ADD_USER=username bash install-docker.sh
```

Unattended, e.g. from another script or a CI pipeline:

```bash
sudo ASSUME_YES=1 bash install-docker.sh
```

---

## After the installation

The script finishes with a green **"Installation erfolgreich"** box and its own
summary (system, Docker Engine + Compose versions, whether a user was added to
the group, whether the `hello-world` test container ran) — no need to scroll back
through the log to see whether something was skipped.

If a user was added to the `docker` group, that only takes effect after they log
out and back in (or run `newgrp docker`) — not immediately in the same shell. Until
then, `docker` commands for that user still need `sudo`.

Quick check that everything works:

```bash
docker --version
docker compose version
docker run --rm hello-world
```

---

## Known pitfalls

**"Cannot connect to the Docker daemon"** right after installation, for a
non-root user: the group membership from step 8 hasn't taken effect in the current
session yet. Log out and back in, or use `sudo` for now.

**`buster`/Debian 10 is oldoldstable.** Docker's repository may stop publishing
updates for it at any time. The script installs anyway but warns about it.

**An unknown/very new codename** (e.g. a fresh Debian release the script doesn't
recognise by name yet) is attempted regardless — if Docker hasn't published a
repository for it yet, `apt-get update` fails with a clear error naming the
codename, rather than silently falling back to something wrong.

**Running on Ubuntu, Raspberry Pi OS, or another Debian derivative** is refused on
purpose. Their `ID_LIKE` includes `debian`, but they need Docker's *own*
repository for their own codenames — mixing them in would install broken packages.

**Piping the script straight into `bash` via `curl | bash`** (as in the one-liner
above) means the `[j/N]` prompt still works normally — `bash` reads it from your
terminal, not from the pipe. Only in a non-interactive context (cron, CI, another
script) does the prompt have no terminal to read from; use `ASSUME_YES=1` there.

---

## Useful commands

```bash
docker compose ps                 # container status of a stack
docker compose logs -f            # follow logs, quit with Ctrl+C
systemctl status docker           # daemon status
docker system df                  # disk usage (images, containers, volumes)
docker system prune -a            # clean up unused images/containers (careful!)
```

---

## Uninstalling

```bash
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo rm -rf /var/lib/docker /var/lib/containerd
sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.asc
sudo apt-get update
```

`purge` removes the packages *and* their config files, but leaves image/container
data in `/var/lib/docker` untouched unless you remove it explicitly — do that only
if you're sure nothing else needs it.

To also remove a user from the `docker` group:

```bash
sudo gpasswd -d <username> docker
```

---

## Security

- Only Docker's own signed `apt` repository is added — no third-party scripts are
  piped into a shell beyond this one, and no `curl | bash` step runs with an
  unpinned key
- The GPG key is fetched once and pinned via `signed-by` in the repository entry,
  not trusted globally
- Adding a user to the `docker` group is equivalent to giving that user root on the
  host (containers can mount the host filesystem) — only do this for users you'd
  trust with `sudo` anyway
- The script never opens or forwards any network port itself; that's entirely up
  to whatever you run in Docker afterwards

---

<sub>This script was researched, written and iteratively revised with the help of AI
models (Claude Sonnet 5, Anthropic). All technical statements were checked against
the official Docker documentation. Please verify for yourself before using it in
production.</sub>

<sub>[← Back to the overview](../)</sub>
