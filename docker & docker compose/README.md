# 🐳 Docker & Docker Compose

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-Docker%20Engine-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://docs.docker.com/engine/install/debian/)
[![GitHub](https://img.shields.io/badge/GitHub-scripts-181717?style=for-the-badge&logo=github)](https://github.com/nephilim75/scripts/tree/main/docker%20%26%20docker%20compose)

Automated installation script for **Docker Engine** and the **Docker Compose plugin**
on Debian, straight from Docker's own `apt` repository — the foundation every other
stack in this repo (LibreChat, Nginx Proxy Manager, ...) runs on top of.

---

## 🚀 Quick Install

```bash
bash -c "$(curl -fsSL "https://raw.githubusercontent.com/nephilim75/scripts/main/docker%20%26%20docker%20compose/install/install-docker.sh")"
```

Detects the running Debian version automatically, shows a summary of what it's
about to do, and waits for confirmation before changing anything. Details:
[install/README.md](install/README.md).

---

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [install](install/README.md) | Automated installation script & guide |

---

## ✨ What You Get

- ✅ Docker Engine + Docker Compose plugin from Docker's official `apt` repository
  (no distro-packaged `docker.io`, no standalone Python `docker-compose`)
- ✅ Automatic detection of the Debian codename (`buster` through `trixie` and newer)
  and CPU architecture
- ✅ Summary + `[j/N]` confirmation before any package is touched
- ✅ Optional `docker` group setup for a non-root user
- ✅ Verification at the end: versions + a `hello-world` test container, wrapped up
  in a colored summary

---

## 🔗 References

- [Installation Guide](install/README.md)
- [Official Docs](https://docs.docker.com/engine/install/debian/)
- [Blog](https://pc-fee.com/blog)
