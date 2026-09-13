# 🔍 SearXNG

[🏠 Overview](../) → 🔍 SearXNG

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-docs.searxng.org-2496ED?style=for-the-badge)](https://docs.searxng.org/)
[![GitHub](https://img.shields.io/badge/GitHub-SearXNG-181717?style=for-the-badge&logo=github)](https://github.com/searxng/searxng)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../LICENSE)

Scripts for the complete life cycle of a self-hosted [SearXNG](https://docs.searxng.org/) metasearch instance — **install**, **update** and **uninstall**. Runs via **Docker Compose** in the shared `shared_proxy` network behind [Nginx Proxy Manager](https://nginxproxymanager.com), with **no publicly bound ports**. A self-hosted SearXNG is the web search source n8n can be pointed at, so the **AI Assistant and agents there can search the web** — optional, and equally usable from any HTTP client.

---

## 🚀 Quick Install

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/searxng/install/install-searxng.sh)"
```

Sets up SearXNG from scratch: checks the prerequisites (Docker, Compose, the `shared_proxy` network), prompts for domain, install path, image tag and time zone, then writes `settings.yml` and `docker-compose.yml` and starts the container. It refuses to install over an existing setup instead of overwriting it. Details and the step-by-step variant: [install/README.md](install/README.md).

---

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [install](install/README.md) | Installs SearXNG from scratch |
| [uninstall](uninstall/README.md) | Removes a SearXNG installation completely, with a dry-run mode |
| [update](update/README.md) | Updates an existing installation, with backup and confirmation |

---

## ✨ What You Get

- ✅ Self-hosted SearXNG via Docker Compose in the `shared_proxy` network
- ✅ No host ports opened — all traffic goes through Nginx Proxy Manager
- ✅ A generated `secret_key`, so no secret has to be handled by hand
- ✅ The JSON output format enabled by default — that is what lets n8n use this instance as its web search (the *Add web search* dialog takes the instance URL, no API key) and what makes `/search?format=json` usable from an HTTP Request node
- ✅ SearXNG's built-in rate-limiter/bot-detection is **deliberately disabled** — see [install/README.md](install/README.md#security) for why, and for the recommended alternative (an NPM Access List)
- ✅ An update path with version check, backup of the config and confirmation before anything changes
- ✅ A removal path that shows a full inventory first and asks before deleting anything

Every script runs from anywhere as a one-liner and asks for (or auto-detects) the installation folder instead of guessing it from its own location.

---

## 🔗 References

- [Install script](install/README.md) · [Update script](update/README.md) · [Uninstall script](uninstall/README.md)
- [Official SearXNG documentation ↗](https://docs.searxng.org/)
- [SearXNG on GitHub ↗](https://github.com/searxng/searxng)
- [pc-fee.com Guide ↗](https://pc-fee.com/searxng/)
- [Blog ↗](https://pc-fee.com/blog)

---

## License

This project is licensed under the MIT License — see the [LICENSE](../LICENSE) file in the repository root.

<sub>The scripts in this folder were researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using them in production.</sub>

<sub>[← Back to the overview](../)</sub>
