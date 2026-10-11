# 🚀 Admin Tool Install Script

[🏠 Overview](../../../) → [💬 LibreChat](../../) → [🔧 Maintenance](../) → Install

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs) [![GitHub](https://img.shields.io/badge/GitHub-LibreChat-181717?style=for-the-badge&logo=github)](https://github.com/danny-avila/LibreChat) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#requirements) [![Re-runnable](https://img.shields.io/badge/Re--runnable-yes-2E7D32?style=flat-square)](#what-it-does)

Installs the [admin tool](../admin-tool/README.md) for an existing [LibreChat](https://www.librechat.ai/) Docker installation. It asks where the tool should go, shows what it is about to do, and changes nothing until you confirm.

---

## Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/maintenance/install/install-admin-lc.sh)
```

Checks the prerequisites, looks for LibreChat, asks for the install location (suggested: `/opt/admin-lc`) and shows a summary. Only after you confirm does it download the tool and, if you like, start the menu right away.

---

## What it does

1. **Checks the prerequisites.** If `git` is missing, it offers to install it with `apt-get` — only after you agree.
2. **Looks for LibreChat** in `/opt/librechat`. If it isn't there, you can enter another path; otherwise the tool asks for it on its first start.
3. **Asks where to install** the tool. `/opt/admin-lc` is only a suggestion. If the folder already contains the admin tool, it offers to update it in place.
4. **Shows a summary** of the target, the source and every planned step. The default answer is **no**.
5. **Installs:** downloads the repository into a temporary folder, copies only `librechat/maintenance/admin-tool` to the target, makes all scripts executable and, if a LibreChat path is known, stores it in `config.sh`. The temporary folder is deleted afterwards.
6. **Offers to start** the menu.

Running it again is safe: an existing install is detected, and an existing `config.sh` is only overwritten if you say yes.

---

## Requirements

- An existing LibreChat Docker installation (see the [LibreChat install script](../../install/README.md))
- Bash, and root or `sudo` — `sudo` is only called after you agreed: to installing `git`, or to the summary
- `git` (offered for installation if missing) and `curl` for the one-liner
- A terminal for the questions, or `--yes` for unattended use

---

## Options

| Option | Effect |
|--------|--------|
| `--dir <path>` | Install location instead of the suggested `/opt/admin-lc` (still confirmed) |
| `--yes`, `-y` | Answer all questions with the default or yes (also `ASSUME_YES=1`) |
| `--help`, `-h` | Print usage |

Passing options to the one-liner:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/maintenance/install/install-admin-lc.sh) --dir /srv/admin-lc
```

---

## Known pitfalls

- **Only plain paths are accepted.** Spaces and special characters are refused (allowed are `A-Z a-z 0-9 . _ @ + - /`), because the path ends up in `config.sh`.
- **Some locations are refused on purpose:** system folders such as `/opt` or `/usr` themselves, anything that overlaps with the LibreChat installation, and folders that are not empty and contain no admin tool.
- **A custom location has to be remembered.** The [uninstall script](../uninstall/README.md) only looks in `/opt/admin-lc` by itself; for any other place, pass `--dir`.
- **`sudo` is not part of the one-liner.** The script elevates itself where needed; `sudo bash <(…)` fails on many systems.
- **Without a terminal and without `--yes`,** the script stops before changing anything.

---

## Security

The script runs parts of the installation with root privileges and downloads code from this repository. It asks before every change, never touches LibreChat itself, and writes only to the folder you chose. Read it before you run it.

---

## Disclaimer

This script is provided "as is", without warranty of any kind. Use it at your own risk. The author assumes no liability for damages, data loss, or other consequences resulting from its use. Test it in a non-production environment first.

---

## License

This project is licensed under the MIT License — see the [LICENSE](../../../LICENSE) file in the repository root.

<sub>This script was researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using it in production.</sub>

<sub>[← Back to the overview](../)</sub>
