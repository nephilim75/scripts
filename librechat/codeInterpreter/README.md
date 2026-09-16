# 🚀 usnavy13

[🏠 Overview](../../../../) → [💬 LibreChat](../../../) → [🧩 Code Interpreter](../../) → usnavy13

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs) [![GitHub](https://img.shields.io/badge/GitHub-LibreCodeInterpreter-181717?style=for-the-badge&logo=github)](https://github.com/usnavy13/LibreCodeInterpreter) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../../LICENSE)

This folder contains the lifecycle scripts for the **LibreCodeInterpreter** variant of the LibreChat Code Interpreter. LibreCodeInterpreter is an independent add-on that gives LibreChat the ability to execute generated Python code in a sandboxed environment.

The scripts here install, update, and cleanly remove the stack under `/opt/LibreCodeInterpreter`. The service is always placed behind an existing Nginx Proxy Manager and does not bind any host ports.

---

## Quick Install

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/usnavy13/install/install-librecodeinterpreter.sh)"
```

This installs LibreCodeInterpreter behind your existing Nginx Proxy Manager. After the installation, create an API key in the dashboard and add it to LibreChat's `.env`.

---

## Structure

| Folder | Description |
|--------|-------------|
| [install](install/README.md) | Install LibreCodeInterpreter as a new stack. |
| [update](update/README.md) | Update an existing LibreCodeInterpreter installation. |
| [uninstall](uninstall/README.md) | Completely remove LibreCodeInterpreter. |

---

## What You Get

- ✅ A self-hosted code-execution backend for LibreChat
- ✅ No host ports opened — access only through the `shared_proxy` Docker network
- ✅ Automatic generation of the `MASTER_API_KEY`
- ✅ Domain validation and Nginx Proxy Manager integration hints
- ✅ Backup before every update
- ✅ Clean uninstall with separate confirmation steps

---

## Security

- The stack does not expose ports on the host. All traffic flows through Nginx Proxy Manager.
- The `MASTER_API_KEY` is generated randomly and shown once at the end of the installation.
- The API key used by LibreChat is embedded in the URL and may appear in NPM access logs. Rotate it in the dashboard if needed.
- All lifecycle scripts require root or `sudo`.

---

## References

- [LibreCodeInterpreter (GitHub)](https://github.com/usnavy13/LibreCodeInterpreter)
- [SECURITY.md](https://github.com/usnavy13/LibreCodeInterpreter/blob/main/docs/SECURITY.md)
- [Official LibreChat](https://www.librechat.ai/)
- [LibreChat Docs](https://www.librechat.ai/docs)
- [Nginx Proxy Manager](https://nginxproxymanager.com/)
- [Docker Compose Docs](https://docs.docker.com/compose/)
- [pc-fee.com Blog](https://pc-fee.com/blog)

---

## License

This project is licensed under the MIT License — see the [LICENSE](../../../../LICENSE) file in the repository root.

<sub>The scripts in this folder were researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using them in production.</sub>

<sub>[← Back to the overview](../)</sub>
