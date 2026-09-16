# 🔄 Update LibreCodeInterpreter

[🏠 Overview](../../../../) → [💬 LibreChat](../../../) → [🧩 Code Interpreter](../../) → [🚀 usnavy13](../) → Update

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs) [![GitHub](https://img.shields.io/badge/GitHub-LibreCodeInterpreter-181717?style=for-the-badge&logo=github)](https://github.com/usnavy13/LibreCodeInterpreter) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements) [![Ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#security) [![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#options) [![Backup](https://img.shields.io/badge/Backup-before%20every%20run-2E7D32?style=flat-square)](#what-it-does)

Updates a LibreCodeInterpreter installation that was originally deployed with [`install-librecodeinterpreter.sh`](../install/README.md). The script checks for upstream changes, shows a **before/after** comparison, creates a configuration backup, and only then applies the update.

> **Heads-up:** This script stops and recreates the Docker containers. Expect a short downtime for the code-interpreter endpoint.

---

## Quick Update

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/usnavy13/update/update-librecodeinterpreter.sh)"
```

This downloads the update script and runs it interactively. It will ask before changing anything; use `--yes` for unattended runs (e.g. Cron).

---

## What it does

1. **Detects** the LibreCodeInterpreter installation (default: `/opt/LibreCodeInterpreter`).
2. **Fetches** the latest repository state and **pulls** new Docker images without touching the running stack.
3. **Shows** an "AKTUELLER STAND -> ZUKÜNFTIGER STAND" table with component versions.
4. **Backs up** `.env`, `docker-compose.override.yml`, and any `librechat.yaml` before any change.
5. **Merges** the repository with `git merge --ff-only` (never a normal `pull`, so local commits stay safe).
6. **Validates** the Compose configuration before the containers are restarted.
7. **Recreates** the stack with `docker compose up -d`.
8. **Rotates** old backups and prunes dangling images.

If nothing changed, the script exits with `NOCHANGE` and does not create a backup or restart anything.

---

## Requirements

- Debian 12+ (tested on Debian 12 and 13)
- root or `sudo`
- Docker + Docker Compose plugin
- `git` and `tar`
- An existing LibreCodeInterpreter installation

---

## Options

| Option | Description |
|--------|-------------|
| `--dir <path>` | Force a specific installation path, skip auto-detection. |
| `--keep <n>` | Number of backups to keep (default: 5). |
| `--dry-run` | Show what would happen; change nothing. |
| `--yes` / `-y` | Skip all confirmations (use with Cron). |
| `--help` / `-h` | Show usage. |

Environment variables for unattended operation: `INSTALL_DIR`, `KEEP_BACKUPS`, `ASSUME_YES=1`, `LOG_FILE`.

---

## Backup & rollback

Before every actual update, the script creates a timestamped archive under `<install-dir>/backups/` containing:

- `.env`
- `docker-compose.override.yml`
- `librechat.yaml` (if present)
- a manifest with commit hash, host, and file list

If the update fails or behaves unexpectedly, roll back with:

```bash
cd /opt/LibreCodeInterpreter && docker compose down
mkdir -p /tmp/lci-restore && tar xzf <backup-file> -C /tmp/lci-restore
cp /tmp/lci-restore/config/* /opt/LibreCodeInterpreter/
git -C /opt/LibreCodeInterpreter checkout <old-commit-hash>
cd /opt/LibreCodeInterpreter && docker compose up -d
```

The rollback commands are also printed at the end of each successful run.

---

## Security

- No host ports are opened; the service remains reachable only through the existing `shared_proxy` Docker network.
- The `MASTER_API_KEY` in `.env` is never modified by this script.
- Backups are created with restrictive permissions (`chmod 600`) and stored inside the installation directory.
- Because the script runs as root, review it with `--dry-run` first.

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
