# 🔄 Code Interpreter Update Script

[🏠 Overview](../../../../) → [💬 LibreChat](../../../) → [🧩 Code Interpreter](../../) → [🚀 LibreChat-AI](../) → Update

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs) [![GitHub](https://img.shields.io/badge/GitHub-code--interpreter-181717?style=for-the-badge&logo=github)](https://github.com/LibreChat-AI/code-interpreter) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#) [![Ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#security) [![Re-runnable](https://img.shields.io/badge/Re--runnable-yes-2E7D32?style=flat-square)](#what-it-does) [![Backup](https://img.shields.io/badge/Backup-before%20every%20run-2E7D32?style=flat-square)](#what-gets-backed-up) [![Rollback](https://img.shields.io/badge/Rollback-automatic-2E7D32?style=flat-square)](#automatic-rollback) [![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#options)

Companion script to the [Code Interpreter install script](../install/README.md) — works like the n8n update script: shows the installed and the newest version, asks which one to update to, **rebuilds the locally built images**, brings the stack back up behind the Nginx Proxy Manager and **rolls back automatically** if the new version doesn't come up healthy. Leftovers of older installer versions are cleaned up along the way. **No host port is ever published.**

> Unlike LibreChat itself, this stack pulls **no ready-made image** from a registry. Every update compiles the API, worker, gateway and sandbox images from source. Expect **10–30+ minutes** and roughly **10 GB free** on the Docker root — about 18 GB if the sandbox runtimes are rebuilt too (the old ones are kept for a rollback).

---

## Quick Update

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/update/update-avila-code-interpreter.sh)"
```

Finds the installation on its own, prints the current and the future state per component, and asks once before anything changes. Prompts are read from `/dev/tty`, so the one-liner works despite the script itself arriving on stdin. Add `-- --dry-run` to walk through the whole run without changing anything (see [Options](#options)).

---

## What it does

1. **Summary** — installation path, isolation mode (MicroVM or NsJail), auth mode, installed version, free disk space, existing backups
2. **Choose the version** — as in the n8n update: installed and newest published version side by side, then *"Auf welche Version updaten? [newest]"*. Any published version can be entered, including an older one (downgrade). Already on the newest? The script asks whether to continue anyway (rebuild and restart).
3. **Checks for news** — fetches exactly the chosen version tag (`git fetch --depth=1`), plus `docker compose pull --ignore-pull-failures`; the running stack stays untouched, only `.git/` and image layers are written
4. **Current → future state** — one row per component: installed → target version, the locally built images, and the registry base images with their short digests
5. **Asks** — how many backups to keep, whether to rebuild the sandbox runtimes, then one final confirmation
6. **Executes** — backup, saves the running images as a rollback point, switches to the target version (`git checkout --detach <tag>`), cleans up leftovers, validates the Compose config, `docker compose build`, `up -d`, waits for every service to report healthy, rotates backups, prunes dangling images
7. **Rolls back automatically** if anything fails — see [Automatic rollback](#automatic-rollback)

Run from cron (or with `--yes`) it asks nothing and goes to the newest version. If the installation already runs it, no base image changed and there is nothing to clean up, the script prints `NOCHANGE` and exits without creating a backup or restarting anything — safe to run as often as you like.

---

## Versions

Only published versions (tags like `v1.10.4`) are ever installed — never the moving `main` branch. Upstream cuts a new version after each successful CI run on `main`, often several per week. Pre-releases (`-rcN`) are never suggested, but can be entered explicitly.

`--version vX.Y.Z` (or `CODEAPI_VERSION`) fixes the target and skips the question — handy for cron if you want to stay on a particular version.

Installations made before the switch to versions sit on an arbitrary `main` revision. The first run moves them onto the target version; the summary shows them as `main-Stand <commit>`.

---

## Requirements

- An existing installation from [install-avila-code-interpreter.sh](../install/README.md), recognised by the `docker-compose.override.yml` containing `container_name: avila-api`
- Root (or `sudo`), Bash, `git`, `tar`, Docker with the Compose plugin
- Roughly 10 GB free on the Docker root (`docker info` → `DockerRootDir`), about 18 GB when `data/pkgs` is rebuilt
- The external network `shared_proxy` and a running Nginx Proxy Manager, same as for the installation

---

## Options

| Flag / Variable | Effect |
|---|---|
| `--dir <path>` | Use this installation path, skip auto-detection |
| `--version <vX.Y.Z>` | Target this version instead of asking (default: newest) |
| `--keep <n>` | Number of backups to keep (default: ask, fallback 5) |
| `--force-build` | Rebuild and restart even when nothing changed upstream |
| `--pull` | Also refresh the base images referenced in the Dockerfiles |
| `--no-cache` | Build without the Docker build cache (much slower) |
| `--pkgs` | Always rebuild the sandbox runtimes under `data/pkgs` (NsJail only) |
| `--no-pkgs` | Never rebuild the sandbox runtimes (NsJail only) |
| `--dry-run` | Show what would happen, change nothing |
| `--yes` | Skip the questions (same as `ASSUME_YES=1`, for cron) |
| `INSTALL_DIR` | Same as `--dir` |
| `CODEAPI_VERSION` | Same as `--version` |
| `KEEP_BACKUPS` | Same as `--keep` |
| `LOG_FILE` | Log location (default: `/var/log/avila-code-interpreter-update.log`) |

Example, fully unattended from root's crontab:

```bash
30 4 * * 0 /usr/local/sbin/update-avila-code-interpreter.sh --yes --keep 5 >/dev/null 2>&1
```

Without a terminal the script never asks and never changes anything unless `--yes` (or `ASSUME_YES=1`) is set.

---

## Leftovers of older installations

Two things from older installer versions are cleaned up automatically — each only if present, each checked against the target version **before** anything changes:

**The patched NsJail launcher.** In NsJail-only mode (`KVM_ENABLED=false`) older installers mounted a patched copy of `docker/start-direct-sandbox.sh` (missing `export ROOTFS`, the `/usr/sbin` symlink bind trap, Bash's command cache). Since upstream commit `da8775f` (1 Sep 2026) — and so in every published version from `v1.0.0` on — the launcher uses its own static helper (`/sandbox-rootfs-setup`) that has none of these problems. A copy still mounted on top would hide it, so the script removes that mount from `docker-compose.override.yml` (previous state kept as `….vor-<timestamp>`) and, once the stack is healthy, renames the old copy to `….veraltet-<timestamp>`. The curl-free health check in `nsjail-fix/` stays — the image's own health check script is hidden once the sandbox's `/usr` is mounted.

**The remote-bridge switch.** Upstream's Compose file enables the remote bridge by default; in hardened mode the API then refuses to start without `CODEAPI_BRIDGE_TOKEN`. This setup doesn't use the bridge, so the script appends `CODEAPI_BRIDGE_AUTH_MODE=static` and `CODEAPI_BRIDGE_DYNAMIC_WORKERS=false` to the interpreter's `.env` if neither is set yet (previous state kept as `.env.vor-<timestamp>`). Secrets and keys in the `.env` are not touched.

If the Compose validation fails afterwards, the source revision **and** both files are restored to their previous state.

---

## What gets backed up

Written to `backups/avila-code-interpreter_<timestamp>.tar.gz` (mode 600) before any change:

| Item | Why |
|---|---|
| `.env` | Service tokens, egress grant secret, the Ed25519 execution-manifest key pair, the JWT public key — none of it recoverable |
| `docker-compose.override.yml` | Container names, `ports: !reset []`, the `shared_proxy` attachment |
| `nsjail-fix/` | The curl-free health check (and, on older installations, the former patched launcher) |
| `librechat-jwt-block.txt` | Only if still present — it holds the **private** JWT signing key |

Deliberately **not** in the archive: `data/pkgs` (several GB, rebuildable at any time) and the contents of Redis and MinIO. Those hold per-execution session data and generated files, not conversations — LibreChat keeps the chat history itself.

Backups are named after the version they were taken from, e.g. `avila-code-interpreter_v1.9.1_<timestamp>.tar.gz`, just like the n8n backups.

---

## Automatic rollback

As with n8n, a failed update rolls back on its own. The difference: this stack builds its images itself (10–30 minutes), so rebuilding the old version would take just as long. Instead, right before the build the script tags every running image as `:avila-rollback`. A rollback re-tags those and starts them again with `up -d --no-build` — no rebuild, about as quick as n8n's.

What triggers it and what happens:

| Failure | Containers restarted? | Rolled back |
|---|---|---|
| Compose config invalid | no — the old stack keeps running | source, `docker-compose.override.yml`, `.env` |
| Build fails | no — the old stack keeps running | source, files, image tags |
| Sandbox runtimes (`data/pkgs`) can't be built | no | source, files, image tags, old `data/pkgs` |
| A service doesn't come up healthy | yes — the old images are started again | all of the above |
| Any other unexpected error during the update | depending on how far it got | all of the above |

When `data/pkgs` is rebuilt, the old runtimes are kept as `data/pkgs.rollback-<timestamp>` until the new version is confirmed healthy — that is why the free-space requirement rises to about 18 GB in that case. After a successful update the rollback tags and the old runtimes are removed.

The final summary of a successful run also shows how to return to the previous version later: `update-avila-code-interpreter.sh --version <previous>`.

---

## Known pitfalls

**`docker restart` is not enough for LibreChat.** This script never touches LibreChat, so no restart is needed. But if you edit LibreChat's `.env` yourself, use a real stop+start: `docker stop LibreChat && docker start LibreChat`.

**Locally modified tracked files block the source update.** The script says so and only rebuilds. Resolve with `git -C <dir> checkout -- <file>`.

**Don't use `git pull` in the installation directory.** It sits on a version tag ("detached HEAD"), not on a branch. Version changes go through this script.

**A failed Compose validation rolls the source back.** If the new upstream `docker-compose.yaml` renames a service the override still references, the script resets the repository to the previous revision (and restores any file it cleaned up) and never rebuilds — the running stack survives.

**New `.env` variables are only reported, never written.** After a source update the script lists keys that exist in `.env.example` but not in your `.env`. Copy what you need by hand, then `docker compose up -d`. `CODEAPI_BRIDGE_TOKEN` and `CODEAPI_BRIDGE_WORKER_ID` are left out of that list on purpose — setting a bridge token switches the unused bridge back on.

**The build cache is kept on purpose.** It makes the next run far faster. Reclaim space with `docker system df` and `docker builder prune`.

---

## Useful commands

```bash
cd /opt/avila-code-interpreter && docker compose ps
```

Follow the logs, preview an update, or force a rebuild including fresh base images:

```bash
cd /opt/avila-code-interpreter && docker compose logs -f
sudo ./update-avila-code-interpreter.sh --dry-run
sudo ./update-avila-code-interpreter.sh --force-build --pull
```

---

## Security

- **No host port is ever published.** The override keeps `ports: !reset []` for every service; after each update the script re-checks all containers with `docker port` and warns if an upstream change introduced a published port.
- **`shared_proxy` is never modified.** All other stacks on that network keep running.
- **Secrets stay where they belong.** The backup archive is `chmod 600`, and the private JWT signing key is never copied into the interpreter's `.env`.
- **Isolation mode is reported, not silently changed.** NsJail-only shares the host kernel and is, per the upstream [security disclaimer](https://github.com/LibreChat-AI/code-interpreter#security-disclaimer), suitable for local testing — not for untrusted code. The script repeats that warning on every run.

---

## References

- [Code Interpreter install script](../install/README.md)
- [Code Interpreter uninstall script](../uninstall/README.md)
- [code-interpreter (GitHub)](https://github.com/LibreChat-AI/code-interpreter)
- [Security Disclaimer](https://github.com/LibreChat-AI/code-interpreter#security-disclaimer)
- [LibreChat Docs](https://www.librechat.ai/docs)
- [Nginx Proxy Manager](https://nginxproxymanager.com/)
- [Docker Compose Docs](https://docs.docker.com/compose/)
- [pc-fee.com Blog](https://pc-fee.com/blog)

---

## Disclaimer

This script is provided "as is", without warranty of any kind. Use it at your
own risk. The author assumes no liability for damages, data loss, or other
consequences resulting from its use. Test it in a non-production environment
first.

---

## License

This project is licensed under the MIT License — see the
[LICENSE](../../../../LICENSE) file in the repository root.

<sub>This script was researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using it in production.</sub>

<sub>[← Back to the overview](../)</sub>
