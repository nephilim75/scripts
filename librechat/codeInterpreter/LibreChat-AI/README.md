# 🚀 LibreChat-AI

[🏠 Overview](../../../) → [💬 LibreChat](../../) → [🧩 Code Interpreter](../) → LibreChat-AI

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs) [![GitHub](https://img.shields.io/badge/GitHub-LibreChat-181717?style=for-the-badge&logo=github)](https://github.com/danny-avila/LibreChat) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../LICENSE)

Installs, updates and removes [`LibreChat-AI/code-interpreter`](https://github.com/LibreChat-AI/code-interpreter) — the sandboxed code execution service maintained by the LibreChat team — behind an Nginx Proxy Manager. The scripts use the **prebuilt images** the developers publish, install only **published versions**, and cover the whole life cycle: **install**, **update** with automatic rollback, and **uninstall**.

> **Don't get confused:** the folder name "LibreChat-AI" refers to the GitHub organisation this interpreter project lives under. It is **not** LibreChat itself, but an extension for it.

---

## 🚀 Quick Install

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/install/install-avila-code-interpreter.sh)"
```

The installer suggests the newest published version, walks you through everything else and aborts with a clear message if something is missing. Updating and removing are one-liners too — see [update](update/README.md) and [uninstall](uninstall/README.md).

---

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [install](install/README.md) | Sets up the interpreter from prebuilt images: version choice, MicroVM or NsJail, JWT-signed jobs, local or external mode |
| [uninstall](uninstall/README.md) | Removes an installation completely, with a dry-run mode and separate confirmations |
| [update](update/README.md) | Switches to another published version like the n8n update script: backup, health check, automatic rollback |

---

## ✨ What You Get

- ✅ Prebuilt images from the developers (`ghcr.io/librechat-ai/code-interpreter-*`) — no 10–30 minute build of the stack
- ✅ Published versions only (tags such as `v1.10.4`), never the moving `main` branch
- ✅ MicroVM isolation (own guest kernel) when `/dev/kvm` is available, NsJail sandboxing as a fallback
- ✅ Execution manifests signed with Ed25519, egress gateway, hardened mode — and optional JWT-signed jobs from LibreChat
- ✅ No host port ever published — all access via Docker networks or the Nginx Proxy Manager
- ✅ Local mode (same server as LibreChat) or external mode (own domain)
- ✅ Updates with version choice, backup, health check and automatic rollback — cron-ready
- ✅ A removal path with a full inventory first and separate confirmations for data, backups and images

---

## 🔗 References

- [LibreChat](https://www.librechat.ai/) · [Docs](https://www.librechat.ai/docs) · [GitHub](https://github.com/danny-avila/LibreChat)
- Code Interpreter, Variante LibreChat-AI: [code-interpreter](https://github.com/LibreChat-AI/code-interpreter)
- [Nginx Proxy Manager](https://nginxproxymanager.com/) · [Docker Compose Docs](https://docs.docker.com/compose/)
- [pc-fee.com Blog](https://pc-fee.com/blog)

---

## License

This project is licensed under the MIT License — see the [LICENSE](../../../LICENSE) file in the repository root.

<sub>The scripts in this folder were researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using them in production.</sub>

<sub>[← Back to the overview](../)</sub>
