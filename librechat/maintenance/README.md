# 🔧 LibreChat Maintenance

[🏠 Overview](../../) → [💬 LibreChat](../) → Maintenance

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs) [![GitHub](https://img.shields.io/badge/GitHub-LibreChat-181717?style=for-the-badge&logo=github)](https://github.com/danny-avila/LibreChat) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

The admin tool for running [LibreChat](https://www.librechat.ai/) instances from the command line — an interactive, menu-driven tool aimed at people who are new to Linux — together with the scripts to install and remove it.

---

## 🚀 Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/maintenance/install/install-admin-lc.sh)
```

Installs the admin tool after asking where it should go (suggested: `/opt/admin-lc`). Nothing is changed until you confirm the summary.

---

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [admin-tool](admin-tool/README.md) | The admin tool itself: menu, modules and shared helpers |
| [install](install/README.md) | Installs the admin tool, or updates an existing install in place |
| [uninstall](uninstall/README.md) | Removes the admin tool and nothing else |

---

## ✨ What You Get

- One menu for user admin, containers, SMTP, instance settings, the Code Interpreter, backups and reinstallation
- Clear, coloured output that explains each step and asks before anything destructive
- A tool that updates itself from this repo
- Clean removal that leaves LibreChat untouched

---

## 🔗 References

- [LibreChat](https://www.librechat.ai/) · [Docs](https://www.librechat.ai/docs) · [GitHub](https://github.com/danny-avila/LibreChat)
- [pc-fee.com Blog](https://pc-fee.com/blog)

---

## License

This project is licensed under the MIT License — see the [LICENSE](../../LICENSE) file in the repository root.

<sub>The scripts in this folder were researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using them in production.</sub>

<sub>[← Back to the overview](../)</sub>
