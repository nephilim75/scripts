# 🩹 n8n Sandbox npm Cache Fix

[🏠 Overview](../../../) → [🔗 n8n](../../) → [🧪 Sandbox](../) → npm Cache Fix

[![Blog](https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge)](https://pc-fee.com/blog/)
[![Upstream](https://img.shields.io/badge/Upstream-Issue%20%23178-D73A49?style=for-the-badge&logo=github)](https://github.com/n8n-io/n8n-sandbox-service/issues/178)
[![GitHub](https://img.shields.io/badge/GitHub-n8n--sandbox--service-181717?style=for-the-badge&logo=github)](https://github.com/n8n-io/n8n-sandbox-service)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](../../../LICENSE)

Diagnoses and repairs a defect in the **official n8n sandbox image** that makes sandbox setup fail with `ETARGET`, leaving the n8n AI Assistant unable to run code or write files.

The script **investigates first** and only changes anything once the problem is actually confirmed. A clean system is left untouched.

---

## Quick Fix

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/fix-npm-cache/fix-n8n-sandbox-npm-cache.sh)
```

Investigate without changing anything:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nephilim75/scripts/main/n8n/sandbox/fix-npm-cache/fix-n8n-sandbox-npm-cache.sh) --check-only
```

> **No leading `sudo` needed:** like the other scripts in this folder, it detects whether it's already running as root and prefixes privileged commands with `sudo` internally.

---

## Status

**Reported upstream — no fix released yet.**

| | |
|---|---|
| Bug report | [n8n-sandbox-service#178](https://github.com/n8n-io/n8n-sandbox-service/issues/178) |
| Filed by | [nephilim75](https://github.com/nephilim75), 2026-09-10 |
| Status as of 2026-09-10 | open, unlabelled, no maintainer response yet |
| Affected | sandbox service `1.3.4` (`latest` resolves to the same digest) |

No need to file a duplicate — if you're hitting this, adding a 👍 or your environment details to the existing issue is more useful. Once n8n ships a fix, this script becomes unnecessary and `--check-only` will report that there's nothing to do.

---

## The problem

Sandbox setup fails on every start:

```
Sandbox workspace setup failed during install-dependencies:
npm error code ETARGET
No matching version found for @n8n/workflow-sdk@0.32.1
```

The sandbox image ships with an **npm cache baked in at build time**. Workspace setup installs with `--prefer-offline`, so npm resolves the SDK version against that cache instead of the registry — even though it fetches the package metadata successfully (`GET 200 … cache stale`).

Any SDK version published *after* the image was built is therefore invisible. As soon as n8n asks for such a version, setup fails. Reported upstream as [n8n-sandbox-service#178](https://github.com/n8n-io/n8n-sandbox-service/issues/178).

**What this is not:** not a broken npm registry, not a network problem, not a stale chat session, and not caused by the scripts in this repo. The requested version exists and is reachable from inside the container.

---

## What it does

1. Verifies Docker, the install directory, and the running `sandbox-runner-1` container
2. Reaches into the runner's inner Docker daemon (Docker-in-Docker) and determines the sandbox image actually in use — read from `SANDBOX_RUNNER_DOCKER_SANDBOX_IMAGE`, falling back to `SANDBOX_IMAGE_TAG` from `.env`
3. Checks whether the image already carries the fix (via an image label)
4. **Investigates:** queries the `@n8n/workflow-sdk` version list from inside the image twice — once with `--prefer-online`, once with `--prefer-offline`. Identical results mean the cache is current and the script exits without touching anything. Diverging results prove the cache is stale
5. Asks for confirmation, then pulls the untouched official image and rebuilds it locally with the npm cache cleared, tagging the result under the name the runner uses
6. **Verifies:** re-runs the offline query and confirms the newest version now resolves

---

## How the detection works

| Query | Meaning |
|-------|---------|
| `npm view --prefer-online @n8n/workflow-sdk versions` | what the registry actually offers |
| `npm view --prefer-offline @n8n/workflow-sdk versions` | what the image's baked-in cache offers |

This mirrors exactly what the failing setup run does. If the offline answer is older than the online one, every SDK release in between is unreachable for setup — which is the failure.

Deliberately **not** used as a signal: the concrete version number from the error message. It comes from n8n and changes with every release, so the comparison above is version-agnostic and keeps working after future releases.

---

## Usage

```bash
# investigate only, never modify
… fix-n8n-sandbox-npm-cache.sh --check-only

# show every step without executing it
… fix-n8n-sandbox-npm-cache.sh --dry-run

# apply even though the check came back clean
… fix-n8n-sandbox-npm-cache.sh --force
```

### Options & environment variables

| Option / variable | Effect |
|-------------------|--------|
| `--check-only` | Investigate and report, change nothing |
| `--dry-run` | Print every mutating step instead of running it |
| `--force` | Apply the fix even if no problem was detected |
| `-h`, `--help` | Show usage |
| `INSTALL_DIR` | Install directory (default: `/opt/n8n-sandbox`) |
| `ASSUME_YES=1` | Skip the confirmation prompt (for automation) |

---

## Requirements

- An existing n8n Sandbox installation (see [install](../install/README.md))
- The sandbox stack running — specifically `sandbox-runner-1`, since the fix is built inside its inner Docker daemon
- Outbound access to `registry.npmjs.org` and the image registry from the runner

---

## Limitations

- **The fix is local and temporary.** It replaces a local image tag. After the next `docker compose pull` of the sandbox stack — including via the [update script](../update/README.md) — the official image is back and the error returns. Re-run this script afterwards.
- **Already running sandbox containers keep the old image** until they're recreated. Restart the runner to force it: `docker compose restart sandbox-runner-1`
- **Open assistant conversations hold on to the error state.** Start a new conversation after applying the fix.
- The original image stays on disk without a name (a *dangling* image) and is removed by `docker image prune`. Harmless — the next pull brings it back.
- Once n8n fixes the image upstream, this script becomes unnecessary. `--check-only` will then simply report that there's nothing to do.

---

## References

- [n8n Sandbox install script](../install/README.md)
- [n8n Sandbox update script](../update/README.md)
- [n8n Sandbox uninstall script](../uninstall/README.md)
- [Upstream bug report (n8n-sandbox-service#178)](https://github.com/n8n-io/n8n-sandbox-service/issues/178)
- [n8n Sandbox Service (GitHub)](https://github.com/n8n-io/n8n-sandbox-service)
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
[LICENSE](../../../LICENSE) file in the repository root.

<sub>This script and its documentation were created with the help of AI models
(Claude Opus 5, Anthropic), commissioned by pc-fee.com. The root cause was
diagnosed on a live installation — npm debug logs from a failing sandbox
container, reproduced and confirmed by re-running the identical install command
before and after clearing the cache. Please verify for yourself — ideally with
`--check-only` first — before running against a production installation.</sub>

<sub>[← Back to the overview](../)</sub>
