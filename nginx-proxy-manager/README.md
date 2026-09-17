# 🌐 Nginx Proxy Manager

[🏠 Overview](../) → 🌐 Nginx Proxy Manager

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Guide](https://img.shields.io/badge/Guide-Nginx%20Proxy%20Manager-FE5200?style=for-the-badge)](https://pc-fee.com/nginx-proxy-manager/) [![Docs](https://img.shields.io/badge/Docs-nginxproxymanager.com-2496ED?style=for-the-badge)](https://nginxproxymanager.com/) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../LICENSE)

Scripts for a self-hosted [Nginx Proxy Manager](https://nginxproxymanager.com/) (NPM) instance via Docker Compose — the reverse proxy every other stack in this repo (LibreChat, n8n, ...) runs behind. Install it first, then point the other stacks at the `shared_proxy` network it creates.

---

## 🚀 Quick Install

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/install/install-npm.sh)"
```

One command, from any directory. Before you run it, point a DNS **A record** for the admin domain (e.g. `npm.example.com`) at the server. The installer then checks DNS and ports, creates the external `shared_proxy` network, starts a pinned NPM version under `/opt/nginx-proxy-manager`, creates the admin account, publishes the admin panel on that domain with a Let's Encrypt certificate and binds port 81 to localhost. Over an existing instance it only proceeds after an explicit choice and a backup. Details: [install/README.md](install/README.md).

---

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [install](install/README.md) | NPM installation script with automatic admin account, SSL for the admin panel and localhost-only port 81 |
| [uninstall](uninstall/README.md) | NPM removal script with inventory and dry-run |
| [update](update/README.md) | NPM update script that moves the pinned version forward, with confirmation step and backup |

---

## ✨ What You Get

- ✅ Self-hosted NPM via Docker Compose on the external `shared_proxy` network
- ✅ One shared entry point on ports 80 and 443 for every other stack in this repo
- ✅ Admin account created automatically with a random password — no open **Welcome!** setup screen
- ✅ Admin panel on its own domain via HTTPS (Force SSL, HSTS, HTTP/2); port 81 bound to `127.0.0.1` only
- ✅ A pinned NPM version, so the installer's API calls are known to work
- ✅ An update script that finds newer releases, shows what would change and waits for your yes, backs up `data/`, `letsencrypt/` and the Compose file, and handles major version jumps
- ✅ An uninstall script with a full inventory, separate confirmations and `--dry-run`
- ✅ All three scripts run from anywhere and locate the installation themselves

---

## 🔗 References

- [Installation Guide](install/README.md)
- [Update Script](update/README.md)
- [Uninstall Script](uninstall/README.md)
- [pc-fee.com Guide](https://pc-fee.com/nginx-proxy-manager/)
- [Hardening / Security](https://pc-fee.com/nginx-proxy-manager/#security)
- [Official Docs](https://nginxproxymanager.com/)
- [Blog](https://pc-fee.com/blog)

---

## License

This project is licensed under the MIT License — see the [LICENSE](../LICENSE) file in the repository root.

<sub>The scripts in this folder were researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using them in production.</sub>

<sub>[← Back to the overview](../)</sub>
