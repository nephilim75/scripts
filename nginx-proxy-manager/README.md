# 🌐 Nginx Proxy Manager

[🏠 Overview](../) → 🌐 Nginx Proxy Manager

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Guide](https://img.shields.io/badge/Guide-Nginx%20Proxy%20Manager-FE5200?style=for-the-badge)](https://pc-fee.com/nginx-proxy-manager/)
[![Docs](https://img.shields.io/badge/Docs-nginxproxymanager.com-2496ED?style=for-the-badge)](https://nginxproxymanager.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../LICENSE)

Scripts for a self-hosted [Nginx Proxy Manager](https://nginxproxymanager.com/) (NPM) instance via Docker Compose — the reverse proxy every other stack in this repo (LibreChat, n8n, ...) runs behind.

---

## 🚀 Quick Install

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/nginx-proxy-manager/install/install-npm.sh)"
```

One command, from any directory: the installer checks Docker, creates the `shared_proxy` network, writes a known-good `docker-compose.yml` under `/opt/nginx-proxy-manager` and starts NPM. Details: [install/README.md](install/README.md).

---

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [install](install/README.md) | NPM installation script |
| [uninstall](uninstall/README.md) | NPM removal script with inventory and dry-run |
| [update](update/README.md) | NPM update script with backup and major-version handling |

---

## 🔗 References

- [Installation Guide](install/README.md)
- [Update Script](update/README.md)
- [Uninstall Script](uninstall/README.md)
- [pc-fee.com Guide](https://pc-fee.com/nginx-proxy-manager/)
- [Official Docs](https://nginxproxymanager.com/)
- [Blog](https://pc-fee.com/blog)

---

## License

This project is licensed under the MIT License — see the [LICENSE](../LICENSE) file in the repository root.

<sub>[← Back to the overview](../)</sub>
