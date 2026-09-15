# 💬 LibreChat

[🏠 Overview](../) → 💬 LibreChat

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs)
[![GitHub](https://img.shields.io/badge/GitHub-LibreChat-181717?style=for-the-badge&logo=github)](https://github.com/danny-avila/LibreChat)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../LICENSE)

Scripts for the complete life cycle of a self-hosted [LibreChat](https://www.librechat.ai) instance with MongoDB, Meilisearch, RAG API and Admin Panel behind Nginx Proxy Manager — **install**, **update** and **uninstall**, plus optional code interpreters and an administration tool.

---

## 🚀 Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/install/install-librechat.sh)
```

The installer sets up everything automatically: directories, `.env`, containers and admin user. Updating and removing it again are one-liners too — see [update](update/README.md) and [uninstall](uninstall/README.md).

---

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [codeInterpreter](codeInterpreter/README.md) | code interpreter installation scripts |
| [install](install/README.md) | Automated installation script & guide |
| [maintenance](maintenance/README.md) | administration scripts |
| [uninstall](uninstall/README.md) | Removes a LibreChat installation completely, with a dry-run mode |
| [update](update/README.md) | Updates an existing installation, with backup and confirmation |

---

## ✨ What You Get

- ✅ Full LibreChat stack (API, Admin Panel, MongoDB, Meilisearch, RAG)
- ✅ Behind Nginx Proxy Manager (no exposed ports)
- ✅ HTTPS/SSL via Let's Encrypt
- ✅ Automated admin user creation
- ✅ Secure random `.env` generation
- ✅ Production-ready setup
- ✅ An update path with change detection, config and database backup, and confirmation before anything restarts
- ✅ A removal path that shows a full inventory first and never touches a directory outside the installation

---

## 🔗 References

- [Install script](install/README.md) · [Update script](update/README.md) · [Uninstall script](uninstall/README.md)
- [Official Docs](https://www.librechat.ai/docs)
- [GitHub Repository](https://github.com/danny-avila/LibreChat)
- [Blog](https://pc-fee.com/blog)

---

## License

This project is licensed under the MIT License — see the [LICENSE](../LICENSE) file in the repository root.

<sub>The scripts in this folder were researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using them in production.</sub>

<sub>[← Back to the overview](https://github.com/nephilim75/scripts/tree/main)</sub>
