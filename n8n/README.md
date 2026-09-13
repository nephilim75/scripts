# 🔗 n8n

[🏠 Overview](../) → 🔗 n8n

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-n8n-EA4B71?style=for-the-badge)](https://docs.n8n.io)
[![GitHub](https://img.shields.io/badge/GitHub-n8n-181717?style=for-the-badge&logo=github)](https://github.com/n8n-io/n8n)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../LICENSE)

Scripts for the complete life cycle of a self-hosted [n8n](https://n8n.io) instance — **install**, **update** and **uninstall** — plus the optional **n8n Sandbox Service** for isolated code execution. Everything runs via **Docker Compose** in the shared `shared_proxy` network behind [Nginx Proxy Manager](https://nginxproxymanager.com), with **no publicly bound ports**.

---

## 🚀 Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/install/install-n8n.sh)
```

Sets up n8n from scratch: checks the prerequisites, prompts for domain, install path, version and time zone, then writes `.env` and `docker-compose.yml` and starts the containers. It refuses to install over an existing setup instead of overwriting it. Details and the step-by-step variant: [install/README.md](install/README.md).

---

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [install](install/README.md) | Installs n8n and the task runner from scratch |
| [sandbox](sandbox/README.md) | n8n Sandbox Service — isolated code execution, install/update/uninstall |
| [uninstall](uninstall/README.md) | Removes an n8n installation completely, with a dry-run mode |
| [update](update/README.md) | Updates an existing installation, with backup and automatic rollback |

---

## ✨ What You Get

- ✅ Self-hosted n8n plus the `n8nio/runners` task runner via Docker Compose (SQLite, `shared_proxy` network)
- ✅ No host ports opened — all traffic goes through Nginx Proxy Manager
- ✅ A generated runner auth token and encryption key, so no secrets have to be handled by hand
- ✅ An update path with version check, full backup, health check and automatic rollback on failure
- ✅ A removal path that shows a full inventory first and asks twice before deleting anything
- ✅ An optional, isolated sandbox for the n8n AI Assistant, usable alongside an existing instance or standalone

Every script runs from anywhere as a one-liner and asks for the installation folder instead of guessing it from its own location.

---

## 🔗 References

- [Install script](install/README.md) · [Update script](update/README.md) · [Uninstall script](uninstall/README.md)
- [n8n Sandbox Service scripts](sandbox/README.md)
- [Official n8n documentation ↗](https://docs.n8n.io)
- [n8n on GitHub ↗](https://github.com/n8n-io/n8n)
- [Blog ↗](https://pc-fee.com/blog)

---

## License

This project is licensed under the MIT License — see the [LICENSE](../LICENSE) file in the repository root.

<sub>The scripts in this folder were researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using them in production.</sub>

<sub>[← Back to the overview](../)</sub>