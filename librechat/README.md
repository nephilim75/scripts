# LibreChat

A collection of scripts and guides for installing, maintaining and operating LibreChat in a Docker-based setup behind Nginx Proxy Manager.

---

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [install](https://github.com/nephilim75/scripts/tree/main/librechat/install) | LibreChat installation scripts and install guide |
| [maintenance](https://github.com/nephilim75/scripts/tree/main/librechat/maintenance) | planned maintenance and health checks |
| [backup](https://github.com/nephilim75/scripts/tree/main/librechat/backup) | planned backup and restore scripts |
| [update](https://github.com/nephilim75/scripts/tree/main/librechat/update) | planned update procedures |
| [troubleshooting](https://github.com/nephilim75/scripts/tree/main/librechat/troubleshooting) | planned diagnostics and log guides |

---

## 🚀 Quickstart

1. Read the install guide:
   - [install/README.md](install/README.md)
2. Start the installation:
   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/install/install-librechat.sh)
   ```
3. Follow the DNS and NPM proxy setup printed by the script.

---

## ✅ Current focus

The current LibreChat section is centered on a clean Docker installation workflow behind an existing Nginx Proxy Manager setup.

The project is intentionally kept modular so that later sections such as maintenance, updates, backup, and troubleshooting can be added without cluttering the initial install flow.

---

## 🧩 Goals

This area is meant to provide:

- simple installation
- reproducible setup steps
- clear operational guidance
- a clean expansion path for future LibreChat maintenance tasks

---

## 📌 Notes

- The installation is designed for a Docker-based environment behind Nginx Proxy Manager.
- Always validate the configuration before production use.
- Keep scripts and documentation aligned as the project grows.

---

## 🔗 References

- [install/README.md](install/README.md)
- [scripts/README.md](../README.md)
