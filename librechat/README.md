# 💬 LibreChat

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs)
[![GitHub](https://img.shields.io/badge/GitHub-LibreChat-181717?style=for-the-badge&logo=github)](https://github.com/danny-avila/LibreChat)

Automated scripts for self-hosted [LibreChat](https://www.librechat.ai) instance with MongoDB, Meilisearch, RAG API, and Admin Panel behind Nginx Proxy Manager.

---

## 🚀 Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/install/install-librechat.sh)
```

The installer sets up everything automatically: directories, `.env`, Docker Compose, containers, and admin user.

---

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [install](install/README.md) | Automated installation script & guide |
| [maintenance](maintenance/) | Backup, update, restore, monitoring scripts |

---

## ✨ What You Get

- ✅ Full LibreChat stack (API, Admin Panel, MongoDB, Meilisearch, RAG)
- ✅ Behind Nginx Proxy Manager (no exposed ports)
- ✅ HTTPS/SSL via Let's Encrypt
- ✅ Automated admin user creation
- ✅ Secure random `.env` generation
- ✅ Production-ready setup

---

## 📋 Requirements

- Linux server (Debian 12+)
- Docker + Docker Compose
- Nginx Proxy Manager running
- Two domains (chat + admin panel)

---

## 🔗 References

- [Installation Guide](install/README.md)
- [Official Docs](https://www.librechat.ai/docs)
- [GitHub Repository](https://github.com/danny-avila/LibreChat)
- [Blog](https://pc-fee.com/blog)
