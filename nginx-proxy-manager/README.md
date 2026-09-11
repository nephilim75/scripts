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
cp install-npm.sh /root/ && chmod +x /root/install-npm.sh && /root/install-npm.sh
```

Sets up NPM with a known-good `docker-compose.yml` and the `shared_proxy` Docker network. Details: [install/README.md](install/README.md).

---

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [install](install/README.md) | NPM installation script |
| [update](update/README.md) | NPM auto-update script with backup |

---

## 🔗 References

- [Installation Guide](install/README.md)
- [pc-fee.com Guide](https://pc-fee.com/nginx-proxy-manager/)
- [Official Docs](https://nginxproxymanager.com/)
- [Blog](https://pc-fee.com/blog)

---

## License

This project is licensed under the MIT License — see the [LICENSE](../LICENSE) file in the repository root.

<sub>[← Back to the overview](../)</sub>
