# 🧹 Docker & Docker Compose Uninstaller

[🏠 Overview](../../) → [🐳 Docker & Docker Compose](../) → Uninstall

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-Docker%20Engine-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://docs.docker.com/engine/install/debian/#uninstall-docker-engine)
[![GitHub](https://img.shields.io/badge/GitHub-scripts-181717?style=for-the-badge&logo=github)](https://github.com/nephilim75/scripts/tree/main/docker%20%26%20docker%20compose/uninstall)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

[![Distro](https://img.shields.io/badge/Debian-10%20%7C%2011%20%7C%2012%20%7C%2013-A81D33?style=flat-square&logo=debian&logoColor=white)](#prerequisites)
[![Ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#security)
[![Idempotent](https://img.shields.io/badge/Re--runnable-yes-2E7D32?style=flat-square)](#known-pitfalls)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#)

Removes **Docker Engine**, the **Docker Compose plugin**, the Docker `apt`
repository and its GPG key from a Debian system — and, if it exists, the shared
Docker network **`shared_proxy`** that reverse-proxy stacks in this repo attach to.

> **Your data stays by default.** Images, containers and volumes under
> `/var/lib/docker` are *kept* unless you explicitly ask for them to be deleted.
> Deleting them is a separate decision with its own confirmation — see
> [What is removed, what is kept](#what-is-removed-what-is-kept).

---

## Quick Uninstall

One command, in a root shell or with `sudo`:

```bash
bash -c "$(curl -fsSL "https://raw.githubusercontent.com/nephilim75/scripts/main/docker%20%26%20docker%20compose/uninstall/uninstall-docker.sh")"
```

The script takes stock first — Docker version, running containers, images, volumes,
the size of `/var/lib/docker`, whether `shared_proxy` exists — shows a **summary of
every planned action** and asks for explicit confirmation (`[j/N]`) before anything
is removed. Packages, repository and key go; your images and volumes stay.

---

## What is removed, what is kept

| | Default run | With `PURGE_DATA=1` |
|---|---|---|
| Docker packages (`docker-ce`, `docker-ce-cli`, `containerd.io`, both plugins, `docker-ce-rootless-extras`, `docker-model-plugin`) | purged | purged |
| `/etc/apt/sources.list.d/docker.list` + `.bak-*` copies | removed | removed |
| `/etc/apt/keyrings/docker.asc` | removed | removed |
| Docker network `shared_proxy` | removed | removed |
| Running containers | stopped | stopped |
| `/var/lib/docker` (images, containers, volumes) | **kept** | deleted |
| `/var/lib/containerd` | **kept** | deleted |
| `/etc/docker` (daemon config) | **kept** | deleted |
| Group `docker` | kept | deleted |

`purge` removes the packages *and* their config files, but it never touches
`/var/lib/docker` — that is why the data columns above exist at all. Keeping the
data means a later [install-docker.sh](../install/README.md) run finds all images
and volumes unchanged.

---

## Prerequisites

- A **Debian** system on which Docker was installed from Docker's official
  repository (other setups are cleaned up as far as the packages match)
- Either **root**, or a regular user with **`sudo`** installed
- Nothing else — the script works offline; only `apt-get update` at the end needs
  network access, and a failure there is reported as a warning, not an abort

On a system where nothing is left to remove, the script says so and exits without
changing anything.

---

## What the script does

| Step | Action |
|---|---|
| **1. Take stock** | Docker version, service state, installed Docker packages, running/total containers, images, volumes, size of `/var/lib/docker`, presence of `shared_proxy` |
| **Summary & confirmation** | Prints exactly what will be removed and what will be kept, then waits for `[j/N]` |
| **2. Containers** | Stops all running containers |
| **3. Network** | Disconnects any leftover endpoints and removes the `shared_proxy` network |
| **4. Services** | Stops and disables `docker.service`, `docker.socket`, `containerd.service` |
| **5. Packages** | `apt-get purge` for every Docker package that is actually installed, then `apt-get autoremove --purge` |
| **6. Repository** | Removes `docker.list` (including `.bak-*` copies) and `docker.asc`, then `apt-get update` |
| **7. Data** | Default: keeps `/var/lib/docker`, `/var/lib/containerd`, `/etc/docker` and lists them. With `PURGE_DATA=1`: deletes them and the `docker` group |

### What the script asks

| Question | Meaning |
|---|---|
| **Deinstallation jetzt starten? [j/N]** | Shown once, right after the summary, before anything is stopped or removed. Anything other than `j` aborts cleanly. |
| **Zum Bestätigen 'LOESCHEN' eingeben** | Only with `PURGE_DATA=1`: the second, separate confirmation for deleting images, containers and volumes. Any other input keeps the data and removes the rest. |

### Options

Both environment variables and command-line flags work:

| Variable | Flag | Meaning |
|---|---|---|
| `PURGE_DATA=1` | `--purge-data` | Also delete `/var/lib/docker`, `/var/lib/containerd`, `/etc/docker` and the `docker` group — irreversible |
| `KEEP_NETWORK=1` | `--keep-network` | Leave the `shared_proxy` network alone |
| `ASSUME_YES=1` | `--yes` | Answer every prompt with yes, including the `LOESCHEN` confirmation |

Remove everything, data included, in one go:

```bash
sudo PURGE_DATA=1 bash uninstall-docker.sh
```

With the one-liner above, put the variable in front of `bash` the same way:

```bash
sudo PURGE_DATA=1 bash -c "$(curl -fsSL "https://raw.githubusercontent.com/nephilim75/scripts/main/docker%20%26%20docker%20compose/uninstall/uninstall-docker.sh")"
```

---

## Known pitfalls

**Running it more than once is safe.** A second run finds no packages, no repository
and no key, reports "Auf diesem System ist nichts zu deinstallieren" and exits
without touching anything.

**Stopped containers are not restarted.** Step 2 stops everything that runs, and
step 4 disables the service. If you only wanted to remove the packages and keep the
containers for a later reinstall, that still works — the container data lives in
`/var/lib/docker` and survives the default run.

**`shared_proxy` with active endpoints.** If a container refuses to stop, the
network can't be removed. The script disconnects leftover endpoints with
`docker network disconnect -f` first and, if it still fails, says so instead of
aborting the whole uninstall — check with `docker network inspect shared_proxy`
while Docker is still installed.

**A daemon that isn't running** means containers, images and networks can't be
listed, so `shared_proxy` can't be removed either. It disappears together with
`/var/lib/docker` — so on such a system either start Docker once before the
uninstall, or use `PURGE_DATA=1`.

**Data left behind is easy to forget.** After a default run, `/var/lib/docker` can
still hold tens of gigabytes. The final summary names the paths and the `rm -rf`
command for later.

**Piping the script straight into `bash` via `curl | bash`** (as in the one-liner
above) means the `[j/N]` prompt still works normally — `bash` reads it from your
terminal, not from the pipe. Only in a non-interactive context (cron, CI, another
script) does the prompt have no terminal to read from; use `ASSUME_YES=1` there,
and be aware that it also confirms the data deletion when `PURGE_DATA=1` is set.

---

## Useful commands

```bash
docker ps -a                      # what would be stopped (before uninstalling)
docker network inspect shared_proxy   # which containers still hang on the network
du -sh /var/lib/docker            # how much data is at stake
dpkg -l | grep -i docker          # which Docker packages are still installed
sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker   # delete the data later
sudo gpasswd -d <username> docker # remove a user from the docker group
```

---

## Security

- Only packages, the Docker `apt` entry and the pinned GPG key are removed; no other
  `apt` source and no unrelated package is touched
- Deleting data is never the default and needs a second, differently worded
  confirmation (`LOESCHEN`) — `ASSUME_YES=1` is the only way to skip it, and that has
  to be set deliberately
- The group `docker` is only removed together with the data; as long as it exists,
  its members still have root-equivalent access to any Docker installed later
- The script never opens or forwards any network port; the `shared_proxy` network it
  removes is an internal Docker bridge

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
