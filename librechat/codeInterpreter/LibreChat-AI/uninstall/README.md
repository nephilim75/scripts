# 🧹 Code Interpreter Uninstall Script

[🏠 Overview](../../../../) → [💬 LibreChat](../../../) → [🧩 Code Interpreter](../../) → [LibreChat-AI](../) → Uninstall

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs) [![GitHub](https://img.shields.io/badge/GitHub-code--interpreter-181717?style=for-the-badge&logo=github)](https://github.com/LibreChat-AI/code-interpreter) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#) [![Ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#security) [![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#options)

Reverses the [Code Interpreter install script](../install/README.md): the eight `avila-*` containers, the project's Docker volumes, the installation directory — and on request the backups, the locally built images and the swap file the installer created. **LibreChat itself, the `shared_proxy` network and the Nginx Proxy Manager are never touched** without a separate, explicit question.

> Irreversible. The `.env` holds the service tokens and the Ed25519 execution-manifest key pair; `librechat-jwt-block.txt`, if still present, holds the **private** JWT signing key. A reinstall generates new keys, so LibreChat's `.env` has to be refilled either way. Run `--dry-run` first.

---

## Quick Uninstall

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/uninstall/uninstall-avila-code-interpreter.sh)"
```

Detects the installation, prints a full inventory with sizes, and asks separately for every destructive step. Prompts are read from `/dev/tty`, so the one-liner works despite the script itself arriving on stdin.

Run it once as a preview first — same inventory, same commands, nothing deleted:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/uninstall/uninstall-avila-code-interpreter.sh)" -- --dry-run
```

---

## What it removes

| Item | Notes |
|---|---|
| Containers | `avila-api`, `avila-service-worker`, `avila-egress-gateway`, `avila-tool-call-server`, `avila-sandbox-runner`, `avila-file-server`, `avila-redis`, `avila-minio` |
| Docker volumes | Only volumes carrying this project's `com.docker.compose.project` label — MinIO object storage and the Redis queue |
| Installation directory | Cloned repository, `.env`, `docker-compose.override.yml`, `nsjail-fix/`, `data/` including the multi-GB `data/pkgs` runtimes |
| `librechat-jwt-block.txt` | Only present if the JWT block was never transferred to LibreChat |
| Backups | **Separate question.** Declining moves `backups/` next to the installation directory instead of deleting it |
| Locally built images | **Separate question.** Rebuilding them later takes 10–30+ minutes again |
| Base images | **Separate question.** `redis`, `minio` and friends may be shared with other stacks |
| Swap file | **Separate question.** Only the installer's own `/swapfile-avila-code-interpreter`, including its `/etc/fstab` line |

Detection never relies on a name substring. The marker is the installer's own `docker-compose.override.yml` containing `container_name: avila-api`, resolved either from the API container's Compose label or from `/opt/avila-code-interpreter`. Orphaned containers left behind by a manually deleted directory are matched against the fixed list of the eight container names.

---

## What it never touches

**LibreChat.** The `LIBRECHAT_CODE_BASEURL=` and `CODEAPI_*` lines in LibreChat's `.env` are only *reported* by default. Commenting them out is an extra question that defaults to no, ignores `ASSUME_YES`, and always writes a timestamped copy of the file first.

**The `shared_proxy` network.** It is shared with LibreChat, n8n, SearXNG, the Nginx Proxy Manager and others. The script lists which containers remain attached and leaves the network alone.

**Nginx Proxy Manager and DNS.** The proxy host, its certificate, any access list and the A record must be removed by hand. The script names the domain it found in LibreChat's `.env` so you know which entry to look for.

**Anything outside the detected installation.** A path handed in via `--dir` is resolved, rejected if it is a system directory (`/`, `/opt`, `/srv`, …) and rejected if it sits fewer than two levels deep.

**The Docker build cache.** It is host-wide and shared with other builds; the script only prints `docker system df` and `docker builder prune` as a hint.

---

## Requirements

- Root (or `sudo`), Bash, Docker with the Compose plugin
- An installation from [install-avila-code-interpreter.sh](../install/README.md) — or at least leftover `avila-*` containers, which the script offers to clean up on their own
- A real terminal for the questions. Without one nothing is deleted unless `ASSUME_YES=1` is set

---

## Options

| Flag / Variable | Effect |
|---|---|
| `--dir <path>` | Use this installation path, skip auto-detection |
| `--dry-run` | Show what would be removed, delete nothing |
| `--yes` | Skip the safety questions (same as `ASSUME_YES=1`) — still never edits LibreChat's `.env` |
| `INSTALL_DIR` | Same as `--dir` |

---

## The LibreChat side

As long as `LIBRECHAT_CODE_BASEURL=` and the `CODEAPI_*` keys remain in LibreChat's `.env`, LibreChat keeps offering the Code Interpreter and every execution fails against a service that no longer exists. Either let the script comment those lines out, or edit the file yourself — then restart properly:

```bash
docker stop LibreChat && docker start LibreChat
```

A plain `docker restart` does **not** re-read `.env`. This is the single most common reason for "I removed it but it still shows up".

---

## Known pitfalls

**`compose down -v` needs the `.env`.** If it was deleted by hand, Compose may fail on unresolved variables; the script notices and removes the containers individually instead.

**Volumes from a renamed directory.** The Compose project name derives from the directory name. If the directory was renamed after installation, old volumes may still carry the previous label — the script prints the leftovers it finds, and `docker volume ls` / `docker volume rm` clears them.

**`data/pkgs` takes a while to delete.** Several GB of small files written by the package-init container. That is normal, not a hang.

**Kept backups still contain secrets.** Declining the backup deletion moves `backups/` aside — those archives hold former `.env` states. Store or delete them deliberately.

**A cron entry may survive.** If the [update script](../update/README.md) was scheduled, the uninstaller says so; remove it with `crontab -e`.

---

## Security

- **Nothing outside the installation is deleted** — the path is canonicalised and checked against a system-directory deny list before any `rm -rf`.
- **Every destructive step is confirmed separately**: main removal, backups, locally built images, base images, swap file, LibreChat's `.env`. There is no single "delete everything" prompt.
- **Secrets are never echoed.** When listing LibreChat's leftover lines, the value of `CODEAPI_JWT_PRIVATE_JWK_JSON` is replaced with a placeholder so it does not end up in a terminal scrollback or log.
- **No host port was ever published**, so there is nothing to close afterwards — only the NPM proxy host and the DNS record need cleaning up.

---

## References

- [Code Interpreter install script](../install/README.md)
- [Code Interpreter update script](../update/README.md)
- [code-interpreter (GitHub)](https://github.com/LibreChat-AI/code-interpreter)
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
