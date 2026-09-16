# 🧩 Code Interpreter

[🏠 Overview](../../) → [💬 LibreChat](../) → Code Interpreter

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs) [![GitHub](https://img.shields.io/badge/GitHub-LibreChat-181717?style=for-the-badge&logo=github)](https://github.com/danny-avila/LibreChat) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../LICENSE)

Two independent ways to give LibreChat a sandboxed code-execution backend. Both run behind an existing Nginx Proxy Manager, open no host ports, and are installed, updated and removed with the scripts in their own subfolder.

---

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [LibreChat-AI](LibreChat-AI/README.md) | `LibreChat-AI/code-interpreter` — MicroVM isolation (own guest kernel) when `/dev/kvm` is available, NsJail as a fallback, JWT-signed jobs. |
| [usnavy13](usnavy13/README.md) | `usnavy13/LibreCodeInterpreter` — NsJail sandboxing only, prebuilt images, a few minutes of install time, no compiling. |

---

## 🤔 Which one?

Both isolate generated code with **NsJail**: separate namespaces, seccomp filters, cgroup limits, execution as a non-root user. **LibreChat-AI** goes a step further when `/dev/kvm` is available and runs each execution in its own **MicroVM** with a dedicated guest kernel — stronger isolation, but a heavier install with more moving parts. **usnavy13** stays with NsJail alone: lean, prebuilt images, ready in a few minutes. If in doubt, start with usnavy13 and move to LibreChat-AI later if you need the extra isolation layer.

---

## 🔗 References

- [LibreChat](https://www.librechat.ai/) · [Docs](https://www.librechat.ai/docs) · [GitHub](https://github.com/danny-avila/LibreChat)
- LibreChat-AI variant: [code-interpreter](https://github.com/LibreChat-AI/code-interpreter)
- usnavy13 variant: [LibreCodeInterpreter](https://github.com/usnavy13/LibreCodeInterpreter) · [SECURITY.md](https://github.com/usnavy13/LibreCodeInterpreter/blob/main/docs/SECURITY.md)
- [Nginx Proxy Manager](https://nginxproxymanager.com/) · [Docker Compose Docs](https://docs.docker.com/compose/)
- [pc-fee.com Blog](https://pc-fee.com/blog)

---

## License

This project is licensed under the MIT License — see the [LICENSE](../../LICENSE) file in the repository root.

<sub>The scripts in this folder were researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using them in production.</sub>

<sub>[← Back to the overview](../)</sub>
