# 🔗 n8n

[🏠 Overview](../) → 🔗 n8n

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-n8n-EA4B71?style=for-the-badge)](https://docs.n8n.io)
[![GitHub](https://img.shields.io/badge/GitHub-n8n-181717?style=for-the-badge&logo=github)](https://github.com/n8n-io/n8n)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../LICENSE)

Automated scripts for a self-hosted [n8n](https://n8n.io) instance (including the `n8nio/runners` task-runner image), running behind Nginx Proxy Manager.

---

## 🚀 Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/install/install-n8n.sh)
```

Sets up n8n from scratch: directories, `.env`, `docker-compose.yml`, and container start. Details: [install/README.md](install/README.md).

---

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [install](install/README.md) | n8n installation script |
| [sandbox](sandbox/README.md) | n8n Sandbox Service (isolated code execution) scripts |
| [update](update/README.md) | n8n update script |

---

## ✨ What You Get

- ✅ Self-hosted n8n + task-runners via Docker Compose (SQLite, `shared_proxy` network)
- ✅ Behind Nginx Proxy Manager (no exposed ports)
- ✅ A companion update script with backup, health check, and automatic rollback
- ✅ An optional isolated code-execution sandbox for the AI Assistant

---

## 🔗 References

- [Installation Guide](install/README.md)
- [Official Docs](https://docs.n8n.io)
- [Blog](https://pc-fee.com/blog)

---

## License

This project is licensed under the MIT License — see the [LICENSE](../LICENSE) file in the repository root.

<sub>[← Back to the overview](../)</sub>
