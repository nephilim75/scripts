# Code Interpreter – usnavy13 option

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs)
[![GitHub](https://img.shields.io/badge/GitHub-LibreCodeInterpreter-181717?style=for-the-badge&logo=github)](https://github.com/usnavy13/LibreCodeInterpreter)

[![Sandbox](https://img.shields.io/badge/Sandbox-NsJail-2E7D32?style=flat-square)](#security)
[![Auth](https://img.shields.io/badge/Auth-API--key-2E7D32?style=flat-square)](#the-two-keys--dont-mix-them-up)
[![Ports](https://img.shields.io/badge/Host--ports-none-2E7D32?style=flat-square)](#security)
[![Tested](https://img.shields.io/badge/Tested-Debian%2012%20%7C%2013-A81D33?style=flat-square&logo=debian&logoColor=white)](#prerequisites)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](#)

*[Deutsche Fassung](./README.md)*

Installs `usnavy13/LibreCodeInterpreter` behind an Nginx Proxy Manager — the lean
option: prebuilt images, a few minutes of installation time, no compiling.

> **For context:** the code here runs in NsJail sandboxes — separate namespaces,
> seccomp filters, cgroup limits, execution as a non-root user. That matches the
> NsJail mode of the [MicroVM option](../LibreChat-AI/); what is additionally
> possible there is a dedicated guest kernel per execution. See the
> [decision guide](../).

---

## Installation

One command, in a root shell or with `sudo`:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/librechat/codeInterpreter/usnavy13/install/install-librecodeinterpreter.sh)"
```

The script checks all prerequisites first and aborts with a clear message if
something is missing. It never overwrites anything that already exists.

---

## Prerequisites

- **Debian 12 or 13** with Docker and the Docker Compose plugin (not tested on other
  distributions)
- a running **Nginx Proxy Manager** and the Docker network **`shared_proxy`**
- `git` and `openssl`
- a **domain** pointing at this server
- `/opt/LibreCodeInterpreter` must not exist yet

---

## What the script asks

| Question | Meaning |
|---|---|
| **NPM's Docker network** | default `shared_proxy`, checked for existence |
| **Domain** | e.g. `code.example.com` |

That's all. Everything else happens automatically.

---

## What the script sets up

- clones the repository to `/opt/LibreCodeInterpreter`
- generates a random **`MASTER_API_KEY`** (32 bytes, hex) — this is what you sign in
  to the admin dashboard with
- writes the `.env` with `chmod 600`
- creates a `docker-compose.override.yml` that removes every host port binding and
  attaches the API container to the Nginx Proxy Manager's network
- pulls the images and starts the stack (`redis`, `garage`, `api`)
- verifies at the end that no container is publicly reachable

---

## After the installation

### 1. DNS

Point an A record for your domain at this server. The script prints the public IP it
detected.

### 2. Proxy host in the Nginx Proxy Manager

**Details tab**

| Field | Value |
|---|---|
| Domain | your interpreter domain |
| Scheme | `http` |
| Forward Hostname | `code-interpreter-api` |
| Forward Port | `8000` |
| Websockets Support | on |

**SSL tab** — request Let's Encrypt, enable Force SSL, HTTP/2 and HSTS.

> The script prints the exact container name at the end, in case it differs.

### 3. Check

| Purpose | URL |
|---|---|
| Health check | `https://YOUR-DOMAIN/health` |
| Admin dashboard | `https://YOUR-DOMAIN/admin-dashboard` |

### 4. Create your own API key in the dashboard

**This is the step people skip.** The `MASTER_API_KEY` from the installation is
**not** the key LibreChat authenticates with. It only serves to sign you in to the
admin dashboard. If you put it into LibreChat, the connection will not work.

The key for LibreChat is created in the dashboard:

1. open `https://YOUR-DOMAIN/admin-dashboard`
2. sign in with the `MASTER_API_KEY`
3. create a new API key there
4. copy the key shown — it is usually visible in full only **once**

The advantage of this separation: you can revoke or replace this one key later
without touching dashboard access.

### 5. Connecting LibreChat

In `/opt/librechat/.env`, **a single line**:

```
LIBRECHAT_CODE_BASEURL=https://<the key from the dashboard>@YOUR-DOMAIN
```

Example with `code.example.com` and a key `abc123`:

```
LIBRECHAT_CODE_BASEURL=https://abc123@code.example.com
```

Then **stop and start** LibreChat:

```bash
docker stop LibreChat && docker start LibreChat
```

A plain `docker restart` does **not** re-read the `.env`. To confirm the values
arrived:

```bash
docker exec LibreChat env | grep LIBRECHAT_CODE
```

#### Why the key sits in the URL

The obvious approach would be the documented one, with two separate lines and
`LIBRECHAT_CODE_API_KEY`. That does **not** work here: in LibreChat v0.8.8-rc1 this
variable is never read anywhere. Without active JWT authentication LibreChat simply
sends no auth header, the interpreter answers with 401, and the chat shows "Code
execution is not authorized". The key in the URL is therefore not a makeshift fix but
the only route that currently holds.

Two things that are easy to miss:

- **No `/v1` at the end.** The address ends with the domain, nothing more. Appending
  `/v1` out of habit gets you a 404.
- **The key ends up in the Nginx Proxy Manager's access logs**, because it is part of
  the URL. Anyone archiving or sharing those logs should know that. If the key does
  get out, revoke it in the dashboard and create a new one.

> An option is planned in the [admin tool](../../maintenance/) that asks for the key
> and writes the line into the `.env` for you. Until then, enter it by hand.

---

## The two keys — don't mix them up

| | what for | where from |
|---|---|---|
| **`MASTER_API_KEY`** | signing in to the admin dashboard | generated by the script, stored in the `.env` |
| **API key** | LibreChat authenticating against the interpreter | you create it yourself in the dashboard |

The master key is the skeleton key: whoever has it gets into the dashboard and can
create as many API keys as they like. It therefore belongs **nowhere** in LibreChat's
configuration — only the key created in the dashboard goes there.

The script shows the master key once at the end. It is also stored permanently in
`/opt/LibreCodeInterpreter/.env` and can be read at any time:

```bash
grep MASTER_API_KEY /opt/LibreCodeInterpreter/.env
```

Treat both keys like passwords.

---

## Useful commands

```bash
cd /opt/LibreCodeInterpreter

docker compose ps            # status
docker compose logs -f api   # logs, quit with Ctrl+C

# update
docker compose pull && docker compose up -d
```

---

## Uninstalling

Mind the order — the connection is severed first, deletion comes after.

**1. Disconnect LibreChat from the interpreter.** In `/opt/librechat/.env`, remove or
comment out the line `LIBRECHAT_CODE_BASEURL=`. That file belongs to LibreChat and
stays — what gets deleted in a moment is only the interpreter's directory under
`/opt/LibreCodeInterpreter`.

```bash
docker stop LibreChat && docker start LibreChat
```

**2. Remove the interpreter.** This clears out containers, volumes, images and the
`.env` holding the master key. API keys created in the dashboard are gone afterwards
too, so revoking individual keys is unnecessary.

```bash
cd /opt/LibreCodeInterpreter
docker compose down -v --rmi all
cd /opt && rm -rf LibreCodeInterpreter
```

The `--rmi all` flag also deletes the pulled images — otherwise they keep taking up
space although nothing is running any more. If another stack on the server happens to
use the same image (Redis, say), Docker refuses the deletion on its own and says so.
So nothing can break.

**3. Clean up the proxy host.** Delete the proxy host for the interpreter domain in
the Nginx Proxy Manager — and the A record at your domain provider, unless the domain
is needed elsewhere.

---

## Security

### How the code is shielded

According to the project documentation, every execution runs in an **NsJail
sandbox**:

- separate namespaces for processes, filesystem and network
- seccomp filters restricting the permitted system calls
- cgroup limits against exhausting CPU, memory and process count
- rlimits for file sizes and open files
- execution as a non-root user (default UID `1001`)
- runtimes and libraries are mounted read-only

### Who gets through

The domain is publicly reachable — anyone who knows it can call it up. That doesn't
mean they can use the service: **every endpoint requires an API key**, and the
dashboard additionally requires the master key. Without a key there is nothing but a
rejection. Protection therefore rests on the key, not on keeping the address secret.

From which follows the most important practical point: **treat both keys like
passwords.** If the dashboard key falls into the wrong hands, revoke it in the
dashboard and create a new one. The `.env` is `chmod 600` and holds the master key —
it belongs in no Git repo.

### What the script does on top

- No container binds a port on the host — the override removes every port binding.
  The service stays reachable inside the Docker networks, but not from the host or
  from outside. This is verified at the end of the installation
- Access from outside runs exclusively through the Nginx Proxy Manager

### Access list — optional, not required

An **access list** in NPM lets only certain IP addresses through. It is an additional
hurdle, not a replacement for the API key, and mainly worthwhile when **LibreChat
runs on a different server**: the sender is then a fixed, known IP you can enter.

If LibreChat runs on the **same** server, better leave it alone. Requests from
LibreChat then come out of the Docker network and carry an internal address such as
`172.18.0.5`, not your server's public IP. A list containing your own IP would lock
LibreChat out — dashboard reachable, code execution dead. A symptom whose cause takes
a long time to find.

> Further details on hardening are in the
> [project documentation](https://github.com/usnavy13/LibreCodeInterpreter/blob/main/docs/SECURITY.md).

---

<sub>This script was researched, written and iteratively revised with the help of AI
models. All technical statements were checked against the project documentation and
source code. Please verify for yourself before using it in production.</sub>

<sub>[← Back to the overview](../)</sub>