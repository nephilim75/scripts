# Code Interpreter – LibreChat-AI option

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs)
[![GitHub](https://img.shields.io/badge/GitHub-code--interpreter-181717?style=for-the-badge&logo=github)](https://github.com/LibreChat-AI/code-interpreter)

[![Isolation](https://img.shields.io/badge/Isolation-MicroVM%20%2B%20NsJail-2E7D32?style=flat-square)](https://github.com/LibreChat-AI/code-interpreter#security-disclaimer)
[![Auth](https://img.shields.io/badge/Auth-JWT%20EdDSA-2E7D32?style=flat-square)](#securing-jobs-with-jwt)
[![Ports](https://img.shields.io/badge/Host--ports-none-2E7D32?style=flat-square)](#security)
[![Tested](https://img.shields.io/badge/Tested-Debian%2012%20%7C%2013-A81D33?style=flat-square&logo=debian&logoColor=white)](#prerequisites)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#)

Installs `LibreChat-AI/code-interpreter` — a fork of `ClickHouse/code-interpreter`,
maintained by the LibreChat team — in a fully hardened configuration behind an Nginx
Proxy Manager.

> **Don't get confused:** the folder name "LibreChat-AI" refers to the GitHub
> organisation this interpreter project lives under. It is **not** LibreChat itself,
> but an extension for it.

---

## Installation

One command, in a root shell or with `sudo`:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/LibreChat-AI/install/install-avila-code-interpreter.sh)"
```

The script walks you through everything else and aborts with a clear message if
something is missing. It never overwrites anything that already exists.

> **Use `tmux` or `screen`.** The build takes 10–30+ minutes. If the SSH connection
> drops, the installation dies halfway through otherwise.

---

## Prerequisites

- **Debian 12 or 13** with Docker and the Docker Compose plugin (not tested on other
  distributions)
- a running **Nginx Proxy Manager** and the Docker network **`shared_proxy`**
- `git` and `openssl`
- **at least 15 GB** of free disk space (without KVM: **20 GB**)
- `/dev/kvm` for full hardening — see below
- in "local" mode: an existing LibreChat installation on the same server

All of this is checked by the script before anything is written.

These prerequisites are built up step by step in the blog series "Spielecke" on
**[pc-fee.com](https://pc-fee.com/blog/)**:
[Docker & Docker Compose](https://pc-fee.com/2026/05/03/docker-compose/),
[Nginx Proxy Manager](https://pc-fee.com/2026/05/03/nginx-proxy-manager/) and
[installing LibreChat](../../install/). If you followed the series, you are ready to
go here. (The articles are in German; any equivalent guide will do just as well.)

---

## What the script asks

| Question | Meaning |
|---|---|
| **Installation path** | default `/opt/avila-code-interpreter` |
| **Mode: local or external** | see next section |
| **Path to LibreChat** | only in "local" mode, default `/opt/librechat` |
| **Domain** | only in "external" mode |
| **Secure jobs with JWT?** | strongly recommended, default: yes |
| **Create a swap file?** | only if no swap exists |
| **Continue without KVM?** | only if `/dev/kvm` is missing |

### "Local" or "external" mode

**Local** — LibreChat runs on the **same** server. Both containers reach each other
directly by container name on the `shared_proxy` network. **No domain** and **no
proxy host** are needed. This is the simpler and safer route.

**External** — LibreChat runs on a **different** server. The interpreter then gets
its own domain through the Nginx Proxy Manager.

### Securing jobs with JWT

Without JWT the interpreter accepts **any** job that reaches it. With JWT, LibreChat
signs every job with a private key and the interpreter verifies the signature with
the matching public key. The script generates the key pair (Ed25519 / EdDSA)
automatically.

The **private key belongs exclusively on the LibreChat side**. In "local" mode the
script writes it straight into LibreChat's `.env` if you want, then deletes its own
copy. In "external" mode it leaves a ready-made text block at
`librechat-jwt-block.txt` for you to transfer to the LibreChat server — and to delete
there afterwards.

### MicroVM or NsJail

If the script finds a usable `/dev/kvm`, the sandbox runs in **MicroVM mode**: every
execution gets its own guest kernel. That is the configuration the project
documentation describes as adequately secured.

Without KVM, only **NsJail mode** remains, which shares the kernel with the host.
According to the project documentation that is fine for local testing, **not** for
production systems with unknown users. The script shows this notice and asks
explicitly before continuing.

---

## What the script sets up

- clones the repository to `/opt/avila-code-interpreter`
- generates all secrets plus an Ed25519 key pair for signed execution manifests
- writes a `.env` with `chmod 600`
- creates a `docker-compose.override.yml`: fixed container names (`avila-*`),
  attachment to `shared_proxy`, **all host ports removed**
- builds the images locally and starts the stack
- in NsJail mode additionally: builds the runtimes (Python, Node, Bun, Bash) under
  `data/pkgs` and applies three fixes for known upstream bugs via a read-only volume
  mount — the cloned repo itself stays untouched
- verifies at the end that no container has a public port

---

## After the installation

### "Local" mode

LibreChat's `.env` then contains (or gets this written by the script):

```
LIBRECHAT_CODE_BASEURL=http://avila-api:3112/v1
```

Then **stop and start** LibreChat:

```bash
docker stop LibreChat && docker start LibreChat
```

### "External" mode

1. Point an A record for the domain at this server (the script shows the IP)
2. Create a proxy host in the Nginx Proxy Manager:

   | Field | Value |
   |---|---|
   | Domain | your interpreter domain |
   | Scheme | `http` |
   | Forward Hostname | `avila-api` |
   | Forward Port | `3112` |
   | Websockets Support | on |
   | SSL | Let's Encrypt, Force SSL, HTTP/2, HSTS |

3. Transfer the block from `librechat-jwt-block.txt` to the LibreChat server and add
   it to the `.env` there. Then stop and start LibreChat.
4. Recommended: create an **Access List** in NPM that allows only the IP of the
   LibreChat server.

---

## Known pitfalls

**`docker restart` is not enough.** A plain restart does **not** re-read the `.env`.
You need `docker stop` and `docker start` — or, in the admin tool, "Application
control → LibreChat → stop first, then start".

**In a `.env` the last assignment wins.** If older lines with
`LIBRECHAT_CODE_BASEURL=` or `CODEAPI_` from a previous interpreter are still further
down the file, they override the new values. Typical symptom: `unknown_kid`, because
the old key identifier is still in effect. Remove or comment out the old lines.

**The error `<runtime> is unknown`** on every code execution in NsJail mode means the
runtimes under `data/pkgs` are missing — it is not a problem with the request. The
script builds them and verifies the result, so this message should not come up.

**The build gets killed without a message.** That is an OOM kill caused by too little
RAM. This is why the script offers a 4 GB swap file beforehand.

---

## Useful commands

```bash
cd /opt/avila-code-interpreter

docker compose ps          # status
docker compose logs -f     # logs, quit with Ctrl+C
docker compose logs -f api # logs of the API only

# update
git pull && docker compose build && docker compose up -d
```

---

## Uninstalling

Mind the order — the connection is severed first, deletion comes after.

**1. Disconnect LibreChat from the interpreter.** In `/opt/librechat/.env`, remove or
comment out the line `LIBRECHAT_CODE_BASEURL=` and every line starting with
`CODEAPI_`. That file belongs to LibreChat and of course stays — what gets deleted in
a moment is only the interpreter's directory.

```bash
docker stop LibreChat && docker start LibreChat
```

**2. Remove the interpreter.**

```bash
cd /opt/avila-code-interpreter
docker compose down -v --rmi all
docker rmi avila-package-init
cd /opt && rm -rf avila-code-interpreter
```

The `--rmi all` flag deletes the images as well. It is particularly worthwhile here:
they were built locally and take up several GB. If another stack on the server
happens to use the same image, Docker refuses the deletion on its own and says so —
nothing can break.

The image `avila-package-init` only exists in NsJail mode and is not part of the
Compose project, hence the separate command. If there was no NsJail mode, Docker
simply reports that it doesn't know the image — that is fine too.

To check whether anything is left over:

```bash
docker images | grep -i -E 'avila|code-interpreter'
```

**3. Only in "external" mode: clean up the proxy host.** Delete the proxy host for
the interpreter domain in the Nginx Proxy Manager — and the A record at your domain
provider, unless the domain is needed elsewhere. In "local" mode this step doesn't
apply; neither of them ever existed there.

**4. Optional: the swap file.** If the script created one, it stays and does no harm.
If it is no longer needed:

```bash
swapoff /swapfile-avila-code-interpreter
sed -i '\|^/swapfile-avila-code-interpreter |d' /etc/fstab
rm /swapfile-avila-code-interpreter
```

---

## Security

- No container binds a port publicly on the host — verified at the end of the
  installation
- Redis and MinIO are not attached to the `shared_proxy` network and are reachable
  only from inside the project's own network
- Execution manifests are signed (Ed25519)
- Egress gateway and hardened mode are enabled
- The `.env` is `chmod 600` and contains secrets — do not put it in a Git repo

---

<sub>This script was researched, written and iteratively revised with the help of AI
models. All technical statements were checked against the official project
documentation and source code. Please verify for yourself before using it in
production.</sub>

<sub>[← Back to the overview](../)</sub>