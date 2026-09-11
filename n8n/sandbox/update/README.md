# 🔄 n8n Sandbox Update Script

[🏠 Overview](../../../) → [🔗 n8n](../../) → [🧪 Sandbox](../) → Update

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![GitHub](https://img.shields.io/badge/GitHub-n8n--sandbox--service-181717?style=for-the-badge&logo=github)](https://github.com/n8n-io/n8n-sandbox-service)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../LICENSE)

Companion script to the [n8n Sandbox install script](../install/README.md) — updates an existing installation to a new image version, with automatic backup, health check, and rollback on failure.

Since the install script's `docker-compose.yml` controls all three sandbox images through a single `SANDBOX_IMAGE_TAG` variable in `.env`, updating never touches `docker-compose.yml` itself — only `.env` changes.

---

## Quick Update

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/update/update-n8n-sandbox.sh)
```

No leading `sudo` needed — same self-elevation behavior as the install script (see its README for why `sudo bash <(curl ...)` should never be used).

Want to see what would happen without changing anything first?

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/update/update-n8n-sandbox.sh) --dry-run
```

---

## What it does

1. Detects whether it's already running as `root`; if not, transparently prefixes every privileged command with `sudo`
2. Checks Docker + Docker Compose are available and finds the installation (default `/opt/n8n-sandbox`)
3. Reads the currently installed version from `.env` and checks Docker Hub for the latest available version
4. Asks which version to update to (defaults to the latest), then verifies that version actually exists for the API, Runner, and Sandbox-Template images before doing anything
5. Backs up `.env`, `docker-compose.yml`, and the `sandbox-tls` mTLS volume
6. Updates `SANDBOX_IMAGE_TAG` in `.env`, pulls the new images, and restarts the stack
7. Waits for the Sandbox API's Docker health check to report `healthy`
8. **Automatic rollback** to the previous version (config + volume + restart) if the health check fails
9. Offers to remove the now-unused old-version images afterwards

---

## Requirements

- An existing installation from [install-n8n-sandbox.sh](../install/README.md)
- Docker + Docker Compose still installed
- Outbound HTTPS access to `hub.docker.com` (used only to look up version numbers — images themselves are still pulled from GHCR, same as during install)

---

## Usage

Make the script executable and run it:

```bash
chmod +x update-n8n-sandbox.sh
./update-n8n-sandbox.sh
```

Or run it straight from GitHub:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/update/update-n8n-sandbox.sh)
```

### Options & environment variables

| Flag / Variable | Effect |
|---|---|
| `--dry-run` | Shows every step and what would change, but changes nothing |
| `INSTALL_DIR` | Pre-sets the install path, skipping that prompt |
| `TARGET_VERSION` | Pre-sets the target version, skipping that prompt (e.g. `1.4.0`) |
| `BACKUP_DIR` | Backup location (default: `<INSTALL_DIR>/backups`) |
| `MAX_BACKUPS` | How many backups to keep, oldest are rotated out (default: `5`) |
| `ASSUME_YES=1` | Skips all confirmations — use with care, ideally combined with `--dry-run` first |

Example, fully unattended:

```bash
INSTALL_DIR=/opt/n8n-sandbox TARGET_VERSION=1.4.0 ASSUME_YES=1 \
  bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/update/update-n8n-sandbox.sh)
```

---

## Versions and pinning

The install script defaults `SANDBOX_IMAGE_TAG` to `latest`. This update script always moves you to a concrete, pinned version number (e.g. `1.4.0`) instead of a moving tag — that's what makes a reliable rollback possible in the first place. If your installation is currently on `latest`/`stable`, the first run of this script pins it to a specific version; every run after that is a normal version-to-version update.

---

## Backup & rollback

Before touching anything, a timestamped backup is created containing:

- `.env` (all secrets, plus the previous `SANDBOX_IMAGE_TAG`)
- `docker-compose.yml`
- a `tar.gz` of the `sandbox-tls` Docker volume (the mTLS certificates)

If the Sandbox API doesn't report `healthy` after the update, the script automatically restores this backup and restarts the stack on the previous version — no manual intervention needed. Old backups beyond `MAX_BACKUPS` are rotated out automatically.

---

## Troubleshooting

**After an update the assistant reports `ETARGET` / `No matching version found for @n8n/workflow-sdk@…`**

Updating pulls the official sandbox image, which ships with an npm cache baked in at build time. Workspace setup installs with `--prefer-offline`, so any SDK version published after that build date can't be resolved and setup fails. Reported upstream as [n8n-sandbox-service#178](https://github.com/n8n-io/n8n-sandbox-service/issues/178).

This is not a fault of the update — a fresh install hits it just the same. Repair it with the [fix-npm-cache script](../fix-npm-cache/README.md):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/fix-npm-cache/fix-n8n-sandbox-npm-cache.sh)
```

Note that the fix is local: **every** update pulls the official image again and brings the problem back, so re-run it after each update until n8n ships a fix upstream.

---

## References

- [n8n Sandbox install script](../install/README.md)
- [n8n Sandbox uninstall script](../uninstall/README.md)
- [n8n Sandbox npm cache fix](../fix-npm-cache/README.md)
- [n8n Sandbox Service (GitHub)](https://github.com/n8n-io/n8n-sandbox-service)
- [n8n-sandbox-service Release Process](https://github.com/n8n-io/n8n-sandbox-service/blob/main/docs/RELEASE.md)
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
[LICENSE](../../../LICENSE) file in the repository root.

<sub>This script and its documentation were created with the help of AI models
(Claude Sonnet 5, Anthropic), commissioned by pc-fee.com. Please verify for
yourself — ideally with `--dry-run` first — before running against a production
installation.</sub>

<sub>[← Back to the overview](../)</sub>
