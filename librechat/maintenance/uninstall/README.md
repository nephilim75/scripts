# 🧹 Admin Tool Uninstall Script

[🏠 Overview](../../../) → [💬 LibreChat](../../) → [🔧 Maintenance](../) → Uninstall

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs) [![GitHub](https://img.shields.io/badge/GitHub-LibreChat-181717?style=for-the-badge&logo=github)](https://github.com/danny-avila/LibreChat) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements) [![Dry-run](https://img.shields.io/badge/Dry--run-supported-2E7D32?style=flat-square)](#options)

Companion to the [admin tool installer](../install/install-admin-lc.sh) — removes the **admin tool** from `/opt/admin-lc` (or wherever you installed it) and nothing else. It finds the tool itself, shows what it is about to delete, and asks before it removes anything.

> Only the admin tool is removed. [LibreChat](https://www.librechat.ai/), its containers, volumes, data and backups, the `shared_proxy` network and any Code Interpreter stay exactly as they are. The removal itself is permanent, and the tool's `config.sh` (the stored LibreChat path) goes with it.

---

## Quick Uninstall

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/maintenance/uninstall/uninstall-admin-lc.sh)
```

Locates the admin tool (default `/opt/admin-lc`, otherwise it asks for the path), shows an inventory of what would be removed, and asks for confirmation. The default answer is **no**. Append `--dry-run` after the closing parenthesis to see the whole run without deleting anything (see [Options](#options)).

---

## What it does

1. **Finds the tool.** It looks in `/opt/admin-lc` or in the path given with `--dir`, and asks if neither fits. A folder counts as the admin tool only if `menu.sh` and `lib/common.sh` are present — the folder name does not matter.
2. **Shows an inventory.** Path, size, number of files, the top-level contents, the LibreChat path stored in `config.sh`, and everything listed below under "removed". It also lists what stays untouched.
3. **Asks once for the removal** and, separately, once for the update leftovers in `/tmp` — only if there are any. Both default to no.
4. **Removes** the tool and verifies that the directory is really gone.

**Removed:**

| What | Where |
|------|-------|
| The admin tool directory, including its `config.sh` | `/opt/admin-lc` (or your `--dir`) |
| The `.admin-lc-info` file the tool leaves in the Code Interpreter folder (only this one file) | `/opt/LibreCodeInterpreter` |
| Self-update leftovers, on request | `/tmp/admin-lc-update.*`, `/tmp/admin-lc-repo.*`, `/tmp/admin-lc-vor-update-*.tgz` |

**Not touched:** LibreChat (directory, containers, volumes, data, backups), the `shared_proxy` network and other stacks on the host such as Nginx Proxy Manager, the Code Interpreter itself, and packages such as `git` or Docker.

---

## Requirements

- Bash, and root or `sudo` — `sudo` is only called after you confirmed the removal, not before
- a terminal for the questions, or `--yes` / `--dry-run` for unattended use
- `curl` for the one-liner above
- the admin tool (`menu.sh`) closed while you uninstall it

---

## Options

| Option | Effect |
|--------|--------|
| `--dir <path>` | Directory of the admin tool, instead of the default `/opt/admin-lc` |
| `--dry-run` | Show the inventory and stop. Nothing is deleted, and `sudo` is not called |
| `--yes`, `-y` | Answer all questions with yes (also `ASSUME_YES=1`) |
| `--help`, `-h` | Print usage |

Passing options to the one-liner:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/maintenance/uninstall/uninstall-admin-lc.sh) --dry-run --dir /srv/admin-lc
```

To run a local copy, download the script and start it from **outside** the admin tool directory:

```bash
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/maintenance/uninstall/uninstall-admin-lc.sh && bash uninstall-admin-lc.sh --dry-run
```

---

## Safety checks

- The tool is recognised by its files, not by its name, so a folder that merely happens to be called `admin-lc` is refused.
- Refused outright: paths with spaces or special characters (allowed are `A-Z a-z 0-9 . _ @ + - /`), symbolic links, paths too close to the root of the file system, folders that contain a `docker-compose.yml` (that looks like LibreChat), and a folder that contains the script itself.
- All of these checks run again immediately before the deletion, and the script changes to `/` first so it never deletes the directory it is standing in.
- `config.sh` is only read with `grep` to display the stored path. It is never executed.
- Leftovers in `/tmp` are matched by name and symbolic links are skipped.
- Without a terminal and without `--yes`, nothing is deleted.

---

## Known pitfalls

- **A custom install directory is not discovered on its own.** Only `/opt/admin-lc` is tried automatically. For any other location, pass `--dir` or enter the path when asked. Note that the [LibreChat uninstall script](../../uninstall/README.md) also only looks in `/opt/admin-lc` when it reports the admin tool.
- **A running menu is not detected.** Quit `menu.sh` first; removing the directory underneath a running menu leaves that session broken.
- **`config.sh` is gone afterwards.** It only holds the LibreChat path, and a fresh install asks for it again.
- **The script refuses to run from inside the directory it would delete.** Start it from anywhere else.
- **`sudo` is not part of the one-liner.** The script elevates itself where needed; `sudo bash <(…)` fails on many systems.

---

## Security

The script deletes a directory recursively with root privileges, which is why it checks the target several times and asks first. It makes no network connections itself (only the one-liner downloads it), and it does not change Docker, the firewall or installed packages. Read it before you run it, and use `--dry-run` first.

---

## Disclaimer

This script is provided "as is", without warranty of any kind. Use it at your own risk. The author assumes no liability for damages, data loss, or other consequences resulting from its use. Test it in a non-production environment first.

---

## License

This project is licensed under the MIT License — see the [LICENSE](../../../LICENSE) file in the repository root.

<sub>This script was researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using it in production.</sub>

<sub>[← Back to the overview](../)</sub>
