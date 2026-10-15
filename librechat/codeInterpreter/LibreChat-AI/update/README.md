# 🔄 Code Interpreter Update Script

[🏠 Overview](../../../../) → [💬 LibreChat](../../../) → [🧩 Code Interpreter](../../) → [🚀 LibreChat-AI](../) → Update

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs) [![GitHub](https://img.shields.io/badge/GitHub-LibreChat-181717?style=for-the-badge&logo=github)](https://github.com/danny-avila/LibreChat) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#) [![Host-ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#security) [![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#options) [![Backup](https://img.shields.io/badge/Backup-before%20every%20run-2E7D32?style=flat-square)](#what-gets-backed-up) [![Rollback](https://img.shields.io/badge/Rollback-automatic-2E7D32?style=flat-square)](#automatic-rollback)

Companion script to the [Code Interpreter install script](../install/README.md), built like the n8n update script: it shows the installed and the newest version, asks **which version to update to**, backs up the configuration, switches to the prebuilt images of that version, waits for every service to report healthy — and **rolls back automatically** if it doesn't. **No host port is ever published.**

---

## Quick Update

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/update/update-avila-code-interpreter.sh)"
```

Finds the installation on its own and asks once before anything changes. Prompts are read from `/dev/tty`, so the one-liner works despite the script itself arriving on stdin. Add `-- --dry-run` to walk through it without changing anything (see [Options](#options)).

---

## What it does

1. **Summary** — installation path, installed version, isolation mode, auth mode, free disk space, existing backups.
2. **Choose the version** — installed and newest version side by side, then *"Auf welche Version updaten? [newest]"*. Any published version with prebuilt images can be entered, including an older one (downgrade). Already on the newest? The script asks whether to continue anyway (reload and restart).
3. **Checks for news** — fetches the configuration of exactly that version and checks the base images (redis, minio). The running stack stays untouched.
4. **Current → future state** — one row per component: version, the image tag of every service, the base images.
5. **Asks** — whether to rebuild the sandbox runtimes (NsJail mode, only when upstream changed them), how many backups to keep, then one final confirmation.
6. **Executes** — backup, switch of configuration and image tag, Compose validation, image pull, restart, health check of every service.
7. **Rolls back automatically** if anything fails — see [Automatic rollback](#automatic-rollback).
8. **Cleans up** — images of the previous version, old backups, dangling images.

If the target version is already installed and no base image changed, the script prints `NOCHANGE` and exits without a backup or restart — safe to run as often as you like.

---

## Requirements

- An installation from the current [install-avila-code-interpreter.sh](../install/README.md) — recognised by the `docker-compose.override.yml` containing `container_name: avila-api` and the prebuilt images
- Root (or `sudo`), Bash, `git`, `tar`, Docker with the Compose plugin
- About 4 GB free on Docker's root directory, about 12 GB when the sandbox runtimes are rebuilt

Installations made with an earlier version of the installer (images built locally) are not converted. The script says so and changes nothing; remove them with the [uninstall script](../uninstall/README.md) and install again.

---

## Options

| Flag / Variable | Effect |
|---|---|
| `--dir <path>` | Use this installation path, skip auto-detection |
| `--version <vX.Y.Z>` | Target this version instead of asking (default: newest) |
| `--keep <n>` | Number of backups to keep (default: ask, fallback 5) |
| `--force` | Reload and restart even when nothing changed |
| `--pkgs` | Always rebuild the sandbox runtimes under `data/pkgs` (NsJail only) |
| `--no-pkgs` | Never rebuild the sandbox runtimes (NsJail only) |
| `--dry-run` | Show what would happen, change nothing |
| `--yes` | Skip the questions (same as `ASSUME_YES=1`, for cron) |
| `INSTALL_DIR` | Same as `--dir` |
| `CODEAPI_VERSION` | Same as `--version` |
| `KEEP_BACKUPS` | Same as `--keep` |
| `LOG_FILE` | Log location (default: `/var/log/avila-code-interpreter-update.log`) |

Example, fully unattended from root's crontab — goes to the newest version, rolls back on failure:

```bash
30 4 * * 0 /usr/local/sbin/update-avila-code-interpreter.sh --yes --keep 5 >/dev/null 2>&1
```

Without a terminal the script never asks and never changes anything unless `--yes` (or `ASSUME_YES=1`) is set. To stay on one version, add `--version vX.Y.Z` to the cron line.

---

## Versions

Only published versions (tags such as `v1.10.4`) are ever installed — never the moving `main` branch. The developers publish a new version after each successful CI run, often several per week, and prebuilt images since **v1.10.0**. Their images carry the code revision (`sha-<commit>`) as tag; the script maps version and revision and checks, without downloading anything, that every image exists before offering a version. Pre-releases (`-rcN`) are never suggested but can be entered explicitly.

A version switch changes exactly two lines in the interpreter's `.env` — `CODEAPI_VERSION` and `CODEAPI_IMAGE_TAG` — plus the checked-out configuration of that version (`git checkout --detach <tag>`). Secrets and keys stay as they are.

---

## What gets backed up

Written to `backups/avila-code-interpreter_<version>_<timestamp>.tar.gz` (mode 600) before any change — named after the version it was taken from, like the n8n backups:

| Item | Why |
|---|---|
| `.env` | Service tokens, egress grant secret, the Ed25519 execution-manifest key pair, the JWT public key, version and image tag — none of it recoverable |
| `docker-compose.override.yml` | Container names, prebuilt images, `ports: !reset []`, the `shared_proxy` attachment |
| `nsjail-fix/` | The curl-free health check of the sandbox (NsJail mode) |
| `librechat-jwt-block.txt` | Only if still present — it holds the **private** JWT signing key |

Deliberately **not** in the archive: `data/pkgs` (several GB, rebuildable at any time) and the contents of Redis and MinIO — per-execution session data and generated files, not conversations. LibreChat keeps the chat history itself.

---

## Automatic rollback

As with n8n, a failed update rolls back on its own. The images of the previous version stay on disk until the new one is confirmed healthy, so a rollback simply restores the previous `.env` and configuration and starts the old images again — no download, no rebuild. The base images (redis, minio) are additionally tagged `:avila-rollback` before the update, because their tag can move to a newer image during the pull.

| Failure | Containers restarted? | Rolled back |
|---|---|---|
| Compose config invalid for the new version | no — the old stack keeps running | `.env`, configuration |
| Images can't be pulled | no — the old stack keeps running | `.env`, configuration |
| Sandbox runtimes (`data/pkgs`) can't be built | no | `.env`, configuration, old `data/pkgs` |
| A service doesn't come up healthy | yes — the previous version is started again | all of the above, base images |
| Any other unexpected error during the update | depending on how far it got | all of the above |

When `data/pkgs` is rebuilt, the old runtimes are kept as `data/pkgs.rollback-<timestamp>` until the new version is healthy. After a rollback the images of the failed version are removed again.

The summary of a successful run also shows how to return to the previous version later — as a one-liner with `-- --version <previous>` appended.

---

## Known pitfalls

**`docker restart` is not enough for LibreChat.** This script never touches LibreChat, so no restart is needed. If you edit LibreChat's `.env` yourself, use a real stop and start: `docker stop LibreChat && docker start LibreChat`.

**A brand-new version is not offered yet.** Its prebuilt images may appear a little after the version itself; until then the previous version counts as the newest. A later run (or cron) picks it up.

**Locally modified files in the repository block the update.** The script lists them and stops before changing anything. Reset with `git -C /opt/avila-code-interpreter checkout -- .`.

**Don't use `git pull` in the installation directory.** It sits on a version tag ("detached HEAD"), not on a branch, and the image tag lives in the `.env`. Version changes go through this script.

---

## Useful commands

```bash
cd /opt/avila-code-interpreter && docker compose ps
```

Follow the logs, preview an update, or go to a specific version:

```bash
cd /opt/avila-code-interpreter && docker compose logs -f
sudo ./update-avila-code-interpreter.sh --dry-run
sudo ./update-avila-code-interpreter.sh --version v1.10.3
```

---

## Security

- **No host port is ever published.** After each update the script checks every container with `docker port` and warns if a new version introduced a published port.
- **`shared_proxy` is never modified.** All other stacks on that network keep running.
- **Secrets stay where they belong.** The backup archive is `chmod 600`; the private JWT signing key is never copied into the interpreter's `.env`.
- **Isolation mode is reported, not silently changed.** NsJail-only shares the host kernel and is, per the upstream [security disclaimer](https://github.com/LibreChat-AI/code-interpreter#security-disclaimer), suitable for local testing — not for untrusted code.

---

## References

- [LibreChat](https://www.librechat.ai/) · [Docs](https://www.librechat.ai/docs) · [GitHub](https://github.com/danny-avila/LibreChat)
- Code Interpreter, Variante LibreChat-AI: [code-interpreter](https://github.com/LibreChat-AI/code-interpreter)
- [Nginx Proxy Manager](https://nginxproxymanager.com/) · [Docker Compose Docs](https://docs.docker.com/compose/)
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
