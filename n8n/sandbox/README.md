# 🧪 n8n Sandbox

[🏠 Overview](../../) → [🔗 n8n](../) → Sandbox

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![GitHub](https://img.shields.io/badge/GitHub-n8n--sandbox--service-181717?style=for-the-badge&logo=github)](https://github.com/n8n-io/n8n-sandbox-service)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

Scripts for the self-hosted [n8n Sandbox Service](https://github.com/n8n-io/n8n-sandbox-service) (isolated code execution for n8n) via Docker Compose — running in the shared `shared_proxy` network behind [Nginx Proxy Manager](https://nginxproxymanager.com/), with no publicly bound ports. Works alongside an existing n8n installation or completely standalone.

---

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [install](install/README.md) | n8n Sandbox installation script |
| [update](update/README.md) | n8n Sandbox update script |
| [uninstall](uninstall/README.md) | n8n Sandbox removal script |
| [fix-npm-cache](fix-npm-cache/README.md) | Fix for the stale npm cache in the official sandbox image (`ETARGET`) |

---

## 🔗 References

- [n8n Sandbox Service (GitHub)](https://github.com/n8n-io/n8n-sandbox-service)
- [Blog](https://pc-fee.com/blog)

---

## License

This project is licensed under the MIT License — see the [LICENSE](../../LICENSE) file in the repository root.

<sub>[← Back to the overview](../)</sub>
