# 🚀 LibreChat-AI

[🏠 Overview](../../../) → [💬 LibreChat](../../) → [🧩 Code Interpreter](../) → LibreChat-AI

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs) [![GitHub](https://img.shields.io/badge/GitHub-code--interpreter-181717?style=for-the-badge&logo=github)](https://github.com/LibreChat-AI/code-interpreter) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../LICENSE)

Installs, updates and removes `LibreChat-AI/code-interpreter` — a fork of `ClickHouse/code-interpreter` maintained by the LibreChat team — in a fully hardened configuration (MicroVM + NsJail, signed execution manifests) behind an Nginx Proxy Manager. Covers the complete life cycle: **install**, **update** and **uninstall**.

> **Don't get confused:** the folder name "LibreChat-AI" refers to the GitHub organisation this interpreter project lives under. It is **not** LibreChat itself, but an extension for it.

---

## 🚀 Quick Install

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/install/install-avila-code-interpreter.sh)"
```

The installer walks you through everything and aborts with a clear message if something is missing. Updating and removing it again are one-liners too — see [update](update/README.md) and [uninstall](uninstall/README.md).

---

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [install](install/README.md) | Sets up the interpreter: MicroVM or NsJail, JWT-signed jobs, local or external mode |
| [uninstall](uninstall/README.md) | Removes an installation completely, with a dry-run mode and separate confirmations |
| [update](update/README.md) | Rebuilds from the current upstream source, with backup and confirmation |

---

## ✨ What You Get

- ✅ MicroVM isolation (own guest kernel) when `/dev/kvm` is available, NsJail sandboxing as a fallback
- ✅ Execution manifests signed with Ed25519, and optional JWT-signed jobs from LibreChat
- ✅ No host port ever published — all access via Docker networks or the Nginx Proxy Manager
- ✅ Local mode (same server as LibreChat) or external mode (own domain)
- ✅ An update path with a current-vs-future summary, config backup, and confirmation before anything rebuilds
- ✅ A removal path with a full inventory first and separate confirmations for data, backups and images

---

## 🔗 References

- [Install script](install/README.md) · [Update script](update/README.md) · [Uninstall script](uninstall/README.md)
- [code-interpreter (GitHub)](https://github.com/LibreChat-AI/code-interpreter)
- [Security Disclaimer](https://github.com/LibreChat-AI/code-interpreter#security-disclaimer)
- [LibreChat Docs](https://www.librechat.ai/docs)
- [Nginx Proxy Manager](https://nginxproxymanager.com/)
- [pc-fee.com Blog](https://pc-fee.com/blog)

---

## License

This project is licensed under the MIT License — see the [LICENSE](../../../LICENSE) file in the repository root.

<sub>The scripts in this folder were researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using them in production.</sub>

<sub>[← Back to the overview](../)</sub>
