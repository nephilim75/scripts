# 🧹 Uninstall LibreCodeInterpreter

[🏠 Overview](../../../../) → [💬 LibreChat](../../../) → [🧩 Code Interpreter](../../) → [🚀 usnavy13](../) → Uninstall

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs) [![GitHub](https://img.shields.io/badge/GitHub-LibreCodeInterpreter-181717?style=for-the-badge&logo=github)](https://github.com/usnavy13/LibreCodeInterpreter) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements) [![Ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#what-gets-removed) [![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#options)

Removes a LibreCodeInterpreter installation that was originally deployed with [`install-librecodeinterpreter.sh`](../install/README.md). The script deletes containers, Docker volumes, and the installation directory. It asks separately whether to keep, move, or delete backups and whether to remove Docker images.

> **Warning:** This action is irreversible. API keys, generated files, and logs will be lost. Run `--dry-run` first and keep a backup.

---

## Quick Uninstall

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/usnavy13/uninstall/uninstall-librecodeinterpreter.sh)"
```

This downloads the uninstall script and runs it interactively. It will ask multiple times before deleting anything; use `--yes` only if you really mean it.

---

## What it does

1. **Detects** the LibreCodeInterpreter installation (default: `/opt/LibreCodeInterpreter`).
2. **Lists** all containers, volumes, and files that would be removed.
3. **Asks** for confirmation before each destructive step:
   - Remove containers and volumes?
   - Delete or move backups?
   - Remove LibreCodeInterpreter-specific Docker images?
   - Remove shared base images (redis, garage, …)?
4. **Stops and removes** the stack with `docker compose down -v --remove-orphans`.
5. **Deletes** the installation directory.
6. **Reports** any related components that were left untouched (LibreChat, avila-code-interpreter, NPM proxy hosts).

---

## Requirements

- Debian 12+ (tested on Debian 12 and 13)
- root or `sudo`
- Docker + Docker Compose plugin
- An existing LibreCodeInterpreter installation

---

## Options

| Option | Description |
|--------|-------------|
| `--dir <path>` | Force a specific installation path, skip auto-detection. |
| `--dry-run` | Show what would be deleted; change nothing. |
| `--yes` / `-y` | Skip all confirmations (also deletes backups and images without asking). |
| `--help` / `-h` | Show usage. |

Environment variables for unattended operation: `INSTALL_DIR`, `ASSUME_YES=1`.

---

## What gets removed

- Docker containers of the LibreCodeInterpreter stack (`api`, `redis`, `garage`)
- Docker volumes belonging to the project
- The installation directory, including:
  - `.env` (contains `MASTER_API_KEY`)
  - `docker-compose.override.yml`
  - `librechat.yaml` (if present)
  - `logs/`
  - `.git/`
- Optionally: backups inside `backups/`
- Optionally: LibreCodeInterpreter-specific Docker images and shared base images

---

## What stays untouched

- The `shared_proxy` Docker network (used by Nginx Proxy Manager, LibreChat, n8n, etc.)
- Any container or volume outside the detected LibreCodeInterpreter project
- Other installations such as:
  - LibreChat under `/opt/librechat`
  - avila-code-interpreter under `/opt/avila-code-interpreter`
- DNS records and Nginx Proxy Manager proxy hosts (must be removed manually)

---

## Security

- No host ports are opened by the original installation; removing the stack does not expose anything either.
- The script refuses to delete system directories (`/`, `/opt`, `/srv`, `/home`, etc.).
- Input is read from `/dev/tty`, so piping via `curl | bash` cannot accidentally confirm a prompt.
- Without a real terminal, nothing is deleted unless `ASSUME_YES=1` is explicitly set.

---

## References

- [LibreCodeInterpreter (GitHub)](https://github.com/usnavy13/LibreCodeInterpreter)
- [SECURITY.md](https://github.com/usnavy13/LibreCodeInterpreter/blob/main/docs/SECURITY.md)
- [Official LibreChat](https://www.librechat.ai/)
- [LibreChat Docs](https://www.librechat.ai/docs)
- [Nginx Proxy Manager](https://nginxproxymanager.com/)
- [Docker Compose Docs](https://docs.docker.com/compose/)
- [pc-fee.com Blog](https://pc-fee.com/blog)

---

## Disclaimer

This script is provided "as is", without warranty of any kind. Use it at your own risk. The author assumes no liability for damages, data loss, or other consequences resulting from its use. Test it in a non-production environment first.

---

## License

This project is licensed under the MIT License — see the [LICENSE](../../../../LICENSE) file in the repository root.

<sub>This script was researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using it in production.</sub>

<sub>[← Back to the overview](../)</sub>
