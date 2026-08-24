# Code Interpreter for LibreChat

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Docs](https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge)](https://www.librechat.ai/docs)
[![GitHub](https://img.shields.io/badge/GitHub-LibreChat-181717?style=for-the-badge&logo=github)](https://github.com/danny-avila/LibreChat)

*[Deutsche Fassung](./README.md)*

Installation scripts for a **self-hosted code interpreter** that LibreChat can use
instead of the paid service from LibreChat.ai.

---

## Part of the blog series "Die Spielecke"

These scripts belong to the series on **[pc-fee.com](https://pc-fee.com/blog/)** and
build on the server that takes shape there step by step. If you followed the series,
you already have everything assumed here:

1. [Docker & Docker Compose](https://pc-fee.com/2026/05/03/docker-compose/)
2. [Nginx Proxy Manager](https://pc-fee.com/2026/05/03/nginx-proxy-manager/), including
   the `shared_proxy` Docker network
3. [Installing LibreChat](../install/)

The code interpreter is the next building block on top of that. If you are joining
midway, work through those three first — otherwise the scripts will stop right at
the start and tell you what is missing.

> The blog articles are in German. The prerequisites themselves are standard Docker
> and Nginx Proxy Manager setups, so any equivalent guide will do.

---

## What does a code interpreter do?

When someone in the chat asks "work this out for me" or "make a chart from this CSV
file", the language model writes a small program to do it. That program is not run by
LibreChat itself but by a separate service — the code interpreter. LibreChat sends
the code over and gets the result back.

There is a reason for that separation: this is program code nobody has read
beforehand. Both options below therefore shield it from the rest of the server —
they differ in how far they go.

---

## Two options to choose from

| | [LibreChat-AI](./LibreChat-AI/) | [usnavy13](./usnavy13/) |
|---|---|---|
| **Project** | `LibreChat-AI/code-interpreter` | `usnavy13/LibreCodeInterpreter` |
| **Origin** | Fork of ClickHouse, maintained by the LibreChat team | Community project |
| **Shielding** | MicroVM with its own guest kernel (libkrun) + NsJail, or NsJail alone | NsJail: namespaces, seccomp, cgroup limits, non-root |
| **Access control** | Signed jobs via JWT (EdDSA) | API key |
| **Effort on your side** | one command, a few questions | one command, two questions |
| **Server compute time** | images are built locally, 10–30+ min | prebuilt images are pulled, a few minutes |
| **Disk space** | script requires 15 GB free (20 GB without KVM) | around 9 GB of images |
| **Own domain required** | only in "external" mode | yes |
| **Server requirement** | `/dev/kvm` for the strongest shielding | none in particular |

Either way you type **one** command, answer a few questions and let the rest run. The
difference in time is not on your side but on the server's: the LibreChat-AI option
compiles its images itself, hence the long bar. Use `tmux` or `screen` for it, then
the installation survives a dropped SSH connection.

---

## Which one fits you?

**[LibreChat-AI](./LibreChat-AI/)** is the more thorough option. If your server
offers `/dev/kvm`, every code execution runs in its own small virtual machine with
its own kernel. That is the configuration the project documentation describes as
adequately secured, and the right choice for an instance other people will use too.

One command tells you whether your server can do it:

```bash
[ -r /dev/kvm ] && [ -w /dev/kvm ] && echo "KVM available" || echo "no KVM"
```

On cheap VPS offerings — especially OpenVZ- or LXC-based ones — KVM is often not
passed through. The script then falls back to **NsJail mode**, which shares the
kernel with the host. The project documentation classes that mode as suitable for
local testing, not for production systems with unknown users. For trying things out
and for your own use it is perfectly usable — the script points out the difference
and asks once before continuing.

**[usnavy13](./usnavy13/)** is the lean option: prebuilt images, done in a few
minutes, around 9 GB of disk space. Here too the code runs in NsJail sandboxes —
with separate namespaces, seccomp filters, cgroup limits and execution as a non-root
user. In terms of shielding this option is therefore on par with the NsJail mode of
the LibreChat-AI option. What is missing is the MicroVM layer on top. A good choice
if your server has no KVM, is small, or you just want to get to know the feature.

The real difference thus shrinks to a single question: **own guest kernel or not.**
That exists only with LibreChat-AI and only with KVM. Everything else — effort, disk
space, access control — are trade-offs with no right or wrong answer.

Both options execute foreign code. The same sober advice applies to both that applies
to any service on a server: a current backup never hurts. For LibreChat there is the
[admin tool](../maintenance/) for that.

---

## Shared prerequisites

- **Debian 12 or 13** with **Docker** and the **Docker Compose plugin** (not tested
  on other distributions)
- a running **Nginx Proxy Manager**
- the external Docker network **`shared_proxy`**
- `git` and `openssl`
- root privileges or `sudo`

Both scripts check all of this before writing anything, and give a concrete hint for
every missing item. Neither script ever binds a port publicly on the host — all
access goes through Docker networks or the Nginx Proxy Manager.

---

## Where to go next

- **[LibreChat-AI/](./LibreChat-AI/)** — MicroVM or NsJail, jobs signed via JWT
- **[usnavy13/](./usnavy13/)** — lean, prebuilt images, API key

---

<sub>The scripts in this folder were researched, written and iteratively revised with
the help of AI models. All technical statements were checked against the respective
project documentation and source code. Please verify for yourself before using them
in production.</sub>