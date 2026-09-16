# 🚀 usnavy13

[🏠 Overview](../../../) → [💬 LibreChat](../../) → [🧩 Code Interpreter](../) → usnavy13

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs) [![GitHub](https://img.shields.io/badge/GitHub-LibreCodeInterpreter-181717?style=for-the-badge&logo=github)](https://github.com/usnavy13/LibreCodeInterpreter) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../LICENSE)

Installs, updates and removes `usnavy13/LibreCodeInterpreter` — a lean, NsJail-sandboxed code-execution backend for LibreChat — behind an Nginx Proxy Manager. Covers the complete life cycle: **install**, **update** and **uninstall**.

> **For context:** this variant sandboxes every execution with NsJail alone — separate namespaces, seccomp filters, cgroup limits, execution as a non-root user. The [LibreChat-AI option](../LibreChat-AI/) adds MicroVM isolation with a dedicated guest kernel on top of that. See the [decision guide](../) if you're unsure which to pick.

---

## 🚀 Quick Install

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/usnavy13/install/install-librecodeinterpreter.sh)"
```

The installer checks all prerequisites first and aborts with a clear message if something is missing. Updating and removing it again are one-liners too — see [update](update/README.md) and [uninstall](uninstall/README.md).

---

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [install](install/README.md) | Install LibreCodeInterpreter as a new stack. |
| [uninstall](uninstall/README.md) | Completely remove LibreCodeInterpreter. |
| [update](update/README.md) | Update an existing LibreCodeInterpreter installation. |

---

## ✨ What You Get

- ✅ A self-hosted code-execution backend for LibreChat
- ✅ No host ports opened — access only through the `shared_proxy` Docker network
- ✅ Automatic generation of the `MASTER_API_KEY`
- ✅ Domain validation and Nginx Proxy Manager integration hints
- ✅ Backup before every update
- ✅ Clean uninstall with separate confirmation steps

---

## 🔗 References

- [Install script](install/README.md) · [Update script](update/README.md) · [Uninstall script](uninstall/README.md)
- [LibreCodeInterpreter (GitHub)](https://github.com/usnavy13/LibreCodeInterpreter)
- [SECURITY.md](https://github.com/usnavy13/LibreCodeInterpreter/blob/main/docs/SECURITY.md)
- [Official LibreChat](https://www.librechat.ai/)
- [LibreChat Docs](https://www.librechat.ai/docs)
- [Nginx Proxy Manager](https://nginxproxymanager.com/)
- [Docker Compose Docs](https://docs.docker.com/compose/)
- [pc-fee.com Blog](https://pc-fee.com/blog)

---

## License

This project is licensed under the MIT License — see the
[LICENSE](../../../LICENSE) file in the repository root.

<sub>The scripts in this folder were researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using them in production.</sub>

<sub>[← Back to the overview](../)</sub>
