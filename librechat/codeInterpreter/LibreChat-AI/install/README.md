# 🚀 Code Interpreter Install Script

[🏠 Overview](../../../../) → [💬 LibreChat](../../../) → [🧩 Code Interpreter](../../) → [🚀 LibreChat-AI](../) → Install

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/) [![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs) [![GitHub](https://img.shields.io/badge/GitHub-LibreChat-181717?style=for-the-badge&logo=github)](https://github.com/danny-avila/LibreChat) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../../LICENSE)

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#) [![Host-ports](https://img.shields.io/badge/Host--ports-none%20opened-2E7D32?style=flat-square)](#security) [![Re-runnable](https://img.shields.io/badge/Re--runnable-guarded-2E7D32?style=flat-square)](#what-it-does)

Installs [`LibreChat-AI/code-interpreter`](https://github.com/LibreChat-AI/code-interpreter) as its own stack under `/opt/avila-code-interpreter`, behind an Nginx Proxy Manager. The services run from the **prebuilt images** the developers publish on GitHub's container registry — nothing of the stack is compiled locally. Only **published versions** are installed; the script suggests the newest one.

> **Don't get confused:** "LibreChat-AI" is the GitHub organisation this interpreter project lives under. It is **not** LibreChat itself, but an extension for it.

---

## Quick Install

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/install/install-avila-code-interpreter.sh)"
```

Checks every prerequisite first, asks a handful of questions, then installs. Nothing is written before the final confirmation. Use `tmux` or `screen`: in NsJail mode the sandbox runtimes are built locally, which takes 10–20 minutes.

---

## What it does

1. **Checks prerequisites** — `git` (offers to install it), Docker, the Compose plugin (≥ 2.24.4), `openssl`, a running Nginx Proxy Manager, the `shared_proxy` network, and that no `avila-api` container exists yet. If one does, it stops and points to the update and uninstall scripts.
2. **Finds the versions** — reads the published versions from GitHub and checks, without downloading anything, which of them have a complete set of prebuilt images. The newest one becomes the suggestion.
3. **Asks** — installation path, local or external mode, JWT, version (see below).
4. **Swap, then disk space** — offers a 4 GB swap file if none exists, *then* measures the free space on Docker's own root directory, so the check sees what is actually left.
5. **Isolation** — MicroVM mode if `/dev/kvm` is usable; otherwise it shows the upstream security disclaimer and asks before falling back to NsJail-only.
6. **Fetches the configuration** of exactly the chosen version (`git clone --branch <version> --depth 1`).
7. **Writes `.env`** (`chmod 600`) — fresh service secrets, an Ed25519 key pair for signed execution manifests, the JWT verifier, the version and image tag. The unused remote-bridge interface is switched off explicitly; otherwise the hardened API refuses to start without a bridge token.
8. **Writes `docker-compose.override.yml`** — fixed container names (`avila-*`), the prebuilt image for every service, all host ports removed, attachment to `shared_proxy`.
9. **Pulls the images and starts the stack**, then waits until every service reports healthy. In NsJail mode it first builds the sandbox runtimes under `data/pkgs`.
10. **Verifies** that no container publishes a port.
11. **Connects LibreChat** — in local mode with JWT, and only if you agreed: appends the connection block to LibreChat's `.env`. This happens **after** the stack is up, so an aborted installation leaves LibreChat untouched.

---

## Requirements

- **Debian 12 or 13** with Docker and the Docker Compose plugin **2.24.4 or newer**
- a running **Nginx Proxy Manager** and the Docker network **`shared_proxy`**
- `git`, `openssl` (and `curl` for showing the public IP at the end)
- free disk space on Docker's root directory: **6 GB**, in NsJail mode **11 GB**
- `/dev/kvm` for full hardening — see below
- in "local" mode: an existing LibreChat installation on the same server

These prerequisites are built up step by step in the blog series "Spielecke" on **[pc-fee.com](https://pc-fee.com/blog/)**: [Docker & Docker Compose](https://pc-fee.com/2026/05/03/docker-compose/), [Nginx Proxy Manager](https://pc-fee.com/2026/05/03/nginx-proxy-manager/) and [installing LibreChat](../../../install/). (The articles are in German; any equivalent guide will do just as well.)

---

## What the script asks

| Question | Meaning |
|---|---|
| **Installation path** | default `/opt/avila-code-interpreter` |
| **Mode: local or external** | see next section |
| **Path to LibreChat** | only in "local" mode, default `/opt/librechat` |
| **Domain** | only in "external" mode |
| **Secure jobs with JWT?** | strongly recommended, default: yes |
| **Code Interpreter version** | default: the newest published version with prebuilt images; any other such version can be entered |
| **Create a swap file?** | only if no swap exists |
| **Continue without KVM?** | only if `/dev/kvm` is missing |
| **Connect LibreChat automatically?** | only in "local" mode with JWT, default: yes |

### Local or external mode

**Local** — LibreChat runs on the **same** server and reaches the interpreter by container name (`http://avila-api:3112/v1`) on the `shared_proxy` network. No domain, no proxy host. The simpler and safer route.

**External** — LibreChat runs on a **different** server. The interpreter gets its own domain through a proxy host in the Nginx Proxy Manager.

### Securing jobs with JWT

Without JWT the interpreter accepts **any** job that reaches it. With JWT, LibreChat signs every job with a private key and the interpreter verifies the signature with the matching public key. The script generates the key pair (Ed25519 / EdDSA) automatically.

The **private key belongs exclusively on the LibreChat side**. In local mode the script writes it straight into LibreChat's `.env` if you agree — after a timestamped backup of that file — and then deletes its own copy. In external mode it leaves a ready-made block in `librechat-jwt-block.txt` for you to transfer, and to delete afterwards.

### Versions and prebuilt images

The developers publish a new version after each successful CI run, often several per week, and prebuilt images for every release since **v1.10.0**. The images are tagged with the code revision (`sha-<commit>`), not the version number; the script maps one to the other. Older versions without images are rejected at the prompt. The chosen version and its image tag end up in the interpreter's `.env` (`CODEAPI_VERSION`, `CODEAPI_IMAGE_TAG`) — the [update script](../update/README.md) changes exactly these two lines.

### MicroVM or NsJail

If the script finds a usable `/dev/kvm`, the sandbox runs in **MicroVM mode**: every execution gets its own guest kernel. That is the configuration the project documentation describes as adequately secured.

Without KVM only **NsJail mode** remains, which shares the kernel with the host. According to the project documentation that is fine for local testing, **not** for production systems with unknown users. The script shows this notice and asks before continuing. In NsJail mode two extra things happen:

- the sandbox reads its runtimes (Python, Node, Bun, Bash) from `data/pkgs` on the host. No prebuilt package exists for them, so the script builds them once with the project's own `Dockerfile.package-init`;
- the image's health check script is hidden once the sandbox mounts its own `/usr`, so the script installs a curl-free replacement (`nsjail-fix/avila-healthcheck.sh`) that queries the same endpoint.

---

## Installation

The same thing step by step, if you prefer to read the script first:

```bash
curl -fsSLO https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/install/install-avila-code-interpreter.sh
less install-avila-code-interpreter.sh
sudo bash install-avila-code-interpreter.sh
```

To preselect a version at the prompt (for example to test an update later), set `CODEAPI_VERSION`:

```bash
sudo CODEAPI_VERSION=v1.10.3 bash install-avila-code-interpreter.sh
```

---

## After the installation

### Local mode

If you let the script connect LibreChat, only a real restart of LibreChat is left:

```bash
docker stop LibreChat && docker start LibreChat
```

Otherwise transfer the block from `librechat-jwt-block.txt` into LibreChat's `.env` (removing older `LIBRECHAT_CODE_BASEURL=` / `CODEAPI_` lines first), delete the block file, then stop and start LibreChat.

### External mode

1. Point an A record for the domain at this server (the script shows the IP).
2. Create a proxy host in the Nginx Proxy Manager:

   | Field | Value |
   |---|---|
   | Domain | your interpreter domain |
   | Scheme | `http` |
   | Forward Hostname | `avila-api` |
   | Forward Port | `3112` |
   | Websockets Support | on |
   | SSL | Let's Encrypt, Force SSL, HTTP/2, HSTS |

3. Transfer the block from `librechat-jwt-block.txt` to the LibreChat server, add it to the `.env` there, stop and start LibreChat — and delete the block file on this server.
4. Recommended: an **Access List** in NPM that only allows the IP of the LibreChat server.

---

## Known pitfalls

**`docker restart` is not enough.** A plain restart does **not** re-read LibreChat's `.env`. Use `docker stop` and `docker start`.

**In a `.env` the last assignment wins.** If older `LIBRECHAT_CODE_BASEURL=` or `CODEAPI_` lines from a previous interpreter remain further down in LibreChat's `.env`, they override the new values. Typical symptom: `unknown_kid`. The automatic connection comments such lines out; when editing by hand, remove them yourself.

**`<runtime> is unknown`** on every execution in NsJail mode means the runtimes under `data/pkgs` are missing — not a problem with the request. The script builds them and checks the result, so this should not come up.

**A brand-new version is not offered yet.** Its prebuilt images may appear a little later than the version itself. The script then suggests the previous one; the update script picks the new one up on a later run.

**Processes get killed without a message.** That is an out-of-memory kill. On small servers keep the offered swap file.

---

## Useful commands

```bash
cd /opt/avila-code-interpreter
docker compose ps                         # status
docker compose logs -f                    # logs, quit with Ctrl+C
docker compose logs -f api                # API only
grep '^CODEAPI_VERSION=' .env             # installed version
```

Updates go through the [update script](../update/README.md) — not `git pull`: the installation sits on a version tag, not on a branch.

---

## Uninstalling

The [uninstall script](../uninstall/README.md) removes everything again, with a full inventory and separate confirmations.

---

## Security

- No container binds a port on the host — verified at the end of the installation.
- Redis and MinIO are not attached to `shared_proxy` and are reachable only inside the project's own network.
- Execution manifests are signed (Ed25519); egress gateway and hardened mode are on; the unused remote-bridge interface is off.
- The private JWT key is never stored in the interpreter's `.env`; the block file is `chmod 600` and deleted after the automatic connection.
- The `.env` is `chmod 600` and holds secrets — do not put it in a Git repository.
- NsJail-only mode shares the host kernel — see the upstream [security disclaimer](https://github.com/LibreChat-AI/code-interpreter#security-disclaimer).

---

## References

- [LibreChat](https://www.librechat.ai/) · [Docs](https://www.librechat.ai/docs) · [GitHub](https://github.com/danny-avila/LibreChat)
- Code Interpreter, Variante LibreChat-AI: [code-interpreter](https://github.com/LibreChat-AI/code-interpreter)
- [Nginx Proxy Manager](https://nginxproxymanager.com/) · [Docker Compose Docs](https://docs.docker.com/compose/)
- [pc-fee.com Blog](https://pc-fee.com/blog)

---

## Disclaimer

This script is provided "as is", without warranty of any kind. Use it at your
own risk. The author assumes no liability for damages, data loss, or other
consequences resulting from its use. Test it in a non-production environment
first.

---

## License

This project is licensed under the MIT License — see the
[LICENSE](../../../../LICENSE) file in the repository root.

<sub>This script was researched, written and iteratively revised at pc-fee.com with the help of AI models, and reviewed by a human before publication. All technical statements were checked against the official project documentation and source code. Please verify for yourself before using it in production.</sub>

<sub>[← Back to the overview](../)</sub>
