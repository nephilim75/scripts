# 🧮 Qdrant

[🏠 Overview](../) → 🧮 Qdrant

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-Qdrant-DC244C?style=for-the-badge)](https://qdrant.tech/documentation/) [![GitHub](https://img.shields.io/badge/GitHub-qdrant-181717?style=for-the-badge&logo=github)](https://github.com/qdrant/qdrant) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../LICENSE)

Scripts for the complete life cycle of a self-hosted [Qdrant](https://qdrant.tech/) vector database — **install**, **update**, **backup & restore** and **uninstall**. Runs via **Docker Compose** in the shared `shared_proxy` network behind [Nginx Proxy Manager](https://nginxproxymanager.com), with **no publicly bound ports**. Built as the vector store for **n8n** (Qdrant Vector Store node, AI agents, RAG workflows) — reachable internally as `http://qdrant:6333` and from outside through your own domain, including the web dashboard.

---

## 🚀 Quick Install

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/qdrant/install/install-qdrant.sh)"
```

Sets up Qdrant from scratch: checks the prerequisites (Docker, Compose, a running Nginx Proxy Manager, the proxy network), asks for domain, paths, network and image tag (suggesting the newest stable release), generates an admin API key and starts the container. It refuses to install over an existing setup instead of overwriting it. Details: [install/README.md](install/README.md).

---

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [backup](backup/README.md) | Snapshots of all or single collections while Qdrant keeps running, and restore with a version check |
| [install](install/README.md) | Installs Qdrant from scratch with a generated API key |
| [uninstall](uninstall/README.md) | Removes a Qdrant installation, with a dry-run mode and separate confirmations |
| [update](update/README.md) | Updates through every intermediate minor version, with a full backup and rollback commands |

---

## ✨ What You Get

- ✅ Self-hosted Qdrant via Docker Compose in the `shared_proxy` network
- ✅ No host ports opened — n8n talks to `http://qdrant:6333` directly, everything else goes through Nginx Proxy Manager
- ✅ REST API only (port 6333); gRPC is not exposed
- ✅ A generated admin API key, shown once at the end of the install and kept in a root-only `.env`
- ✅ The web dashboard at `https://<your-domain>/dashboard`
- ✅ An update path that never skips a minor version — Qdrant migrates its storage one minor version at a time, so the update script walks through each one (e.g. `v1.17.1 → v1.18.3 → v1.19.2`) and checks every step
- ✅ Two kinds of backup: a full `storage/` archive before every update (for a rollback), and collection snapshots on demand or by cron (for restoring single collections without downtime)
- ✅ A removal path that shows a full inventory first and asks separately for data, backups and images

Every script runs from anywhere as a one-liner and finds the installation itself instead of guessing it from its own location.

---

## 🔗 References

- [Qdrant](https://qdrant.tech/) · [Docs](https://qdrant.tech/documentation/) · [GitHub](https://github.com/qdrant/qdrant)
- [Upgrading Qdrant](https://qdrant.tech/documentation/upgrades/) · [Snapshots](https://qdrant.tech/documentation/snapshots/) · [Security](https://qdrant.tech/documentation/security/)
- [n8n Qdrant credentials](https://docs.n8n.io/integrations/builtin/credentials/qdrant/)
- [Nginx Proxy Manager](https://nginxproxymanager.com/) · [Docker Compose Docs](https://docs.docker.com/compose/)
- [pc-fee.com Blog](https://pc-fee.com/blog)

---

## License

This project is licensed under the MIT License — see the [LICENSE](../LICENSE) file in the repository root.

<sub>The scripts in this folder were researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using them in production.</sub>

<sub>[← Back to the overview](../)</sub>
