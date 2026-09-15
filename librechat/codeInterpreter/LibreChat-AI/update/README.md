# 🔄 Code Interpreter Update Script

[🏠 Overview](../../../../) → [💬 LibreChat](../../../) → [🧩 Code Interpreter](../../) → [LibreChat-AI](../) → Update

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs) [![GitHub](https://img.shields.io/badge/GitHub-code--interpreter-181717?style=for-the-badge&logo=github)](https://github.com/LibreChat-AI/code-interpreter) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#) [![Ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#security) [![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#options) [![Backup](https://img.shields.io/badge/Backup-before%20every%20run-2E7D32?style=flat-square)](#what-gets-backed-up)

Companion script to the [Code Interpreter install script](../install/README.md) — updates an existing installation to the current upstream source, **rebuilds the locally built images**, regenerates the patched NsJail sandbox launcher when upstream changes it, and brings the stack back up behind the Nginx Proxy Manager. **No host port is ever published.**

> Unlike LibreChat itself, this stack pulls **no ready-made image** from a registry. Every update compiles the API, worker, gateway and sandbox images from source. Expect **10–30+ minutes** and roughly **10 GB free** on the Docker root — 15 GB if the sandbox runtimes are rebuilt too.

---

## Quick Update

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/update/update-avila-code-interpreter.sh)"
```

Finds the installation on its own, prints the current and the future state per component, and asks once before anything changes. Prompts are read from `/dev/tty`, so the one-liner works despite the script itself arriving on stdin.

Want to see what would happen without changing anything first?

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/update/update-avila-code-interpreter.sh)" -- --dry-run
```

---

## What it does

1. **Summary** — installation path, isolation mode (MicroVM or NsJail), auth mode, source revision, free disk space, existing backups
2. **Checks for news** — `git fetch --depth=1` plus `docker compose pull --ignore-pull-failures`; the running stack stays untouched, only `.git/` and image layers are written
3. **Current → future state** — one row per component: source revision, the locally built images, and the registry base images with their short digests
4. **Asks** — how many backups to keep, whether to rebuild the sandbox runtimes, then one final confirmation
5. **Executes** — backup, `git merge --ff-only`, regenerate the NsJail patch, validate the Compose config, `docker compose build`, `up -d`, wait for every service to report healthy, rotate backups, prune dangling images

If neither the source nor a base image changed, the script prints `NOCHANGE` and exits without creating a backup or restarting anything. That makes it safe to run from cron as often as you like.

---

## Requirements

- An existing installation from [install-avila-code-interpreter.sh](../install/README.md), recognised by the `docker-compose.override.yml` containing `container_name: avila-api`
- Root (or `sudo`), Bash, `git`, `tar`, Docker with the Compose plugin
- Roughly 10 GB free on the Docker root (`docker info` → `DockerRootDir`), 15 GB when `data/pkgs` is rebuilt
- The external network `shared_proxy` and a running Nginx Proxy Manager, same as for the installation

---

## Options

| Flag / Variable | Effect |
|---|---|
| `--dir <path>` | Use this installation path, skip auto-detection |
| `--keep <n>` | Number of backups to keep (default: ask, fallback 5) |
| `--force-build` | Rebuild and restart even when nothing changed upstream |
| `--pull` | Also refresh the base images referenced in the Dockerfiles |
| `--no-cache` | Build without the Docker build cache (much slower) |
| `--pkgs` | Always rebuild the sandbox runtimes under `data/pkgs` (NsJail only) |
| `--no-pkgs` | Never rebuild the sandbox runtimes (NsJail only) |
| `--dry-run` | Show what would happen, change nothing |
| `--yes` | Skip the questions (same as `ASSUME_YES=1`, for cron) |
| `INSTALL_DIR` | Same as `--dir` |
| `KEEP_BACKUPS` | Same as `--keep` |
| `LOG_FILE` | Log location (default: `/var/log/avila-code-interpreter-update.log`) |

Example, fully unattended from root's crontab:

```bash
30 4 * * 0 /usr/local/sbin/update-avila-code-interpreter.sh --yes --keep 5 >/dev/null 2>&1
```

Without a terminal the script never asks and never changes anything unless `--yes` (or `ASSUME_YES=1`) is set.

---

## Why the NsJail patch is re-checked

In NsJail-only mode (`KVM_ENABLED=false`) the installer does not run the upstream sandbox launcher as shipped. It mounts a **patched copy** of `docker/start-direct-sandbox.sh` over it, because the original fails in three independent ways: the missing `export ROOTFS`, the `/usr/sbin` symlink that makes a bind mount replace all of `/usr/bin`, and Bash's stale command cache.

A source update can change that file, and the mounted copy would then silently keep running the old launcher. So the update script:

1. checks whether upstream actually touched the file
2. applies the three fixes to the **fetched** version and verifies all three markers — **before** merging anything
3. aborts with a ready-made `git diff` command if a fix no longer applies, leaving the running stack completely untouched
4. only regenerates `nsjail-fix/start-direct-sandbox.sh` after a successful merge, keeping the previous copy as `….vor-<timestamp>`

In MicroVM mode none of this applies — the runtimes are baked into the block root image and no patch is mounted.

---

## What gets backed up

Written to `backups/avila-code-interpreter_<timestamp>.tar.gz` (mode 600) before any change:

| Item | Why |
|---|---|
| `.env` | Service tokens, egress grant secret, the Ed25519 execution-manifest key pair, the JWT public key — none of it recoverable |
| `docker-compose.override.yml` | Container names, `ports: !reset []`, the `shared_proxy` attachment |
| `nsjail-fix/` | Patched sandbox launcher and the curl-free health check |
| `librechat-jwt-block.txt` | Only if still present — it holds the **private** JWT signing key |

Deliberately **not** in the archive: `data/pkgs` (several GB, rebuildable at any time) and the contents of Redis and MinIO. Those hold per-execution session data and generated files, not conversations — LibreChat keeps the chat history itself.

There is no automatic rollback after a failed health check, because a rebuild takes far too long to undo blindly. Instead the script fails early and safely: a broken Compose config resets the source revision, a failed build leaves the old stack running, and the final summary prints copy-paste rollback commands.

---

## Known pitfalls

**`docker restart` is not enough for LibreChat.** This script never touches LibreChat, so no restart is needed. But if you edit LibreChat's `.env` yourself, use a real stop+start: `docker stop LibreChat && docker start LibreChat`.

**Locally modified tracked files block the source update.** The script says so and only rebuilds. Resolve with `git -C <dir> checkout -- <file>`.

**A failed Compose validation rolls the source back.** If the new upstream `docker-compose.yaml` renames a service the override still references, the script resets the repository to the previous revision and never rebuilds — the running stack survives.

**New `.env` variables are only reported, never written.** After a source update the script lists keys that exist in `.env.example` but not in your `.env`. Copy what you need by hand, then `docker compose up -d`.

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
