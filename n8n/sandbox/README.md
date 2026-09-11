# n8n Sandbox

Scripts for the self-hosted [n8n Sandbox Service](https://github.com/n8n-io/n8n-sandbox-service) (isolated code execution for n8n) via Docker Compose — running in the shared `shared_proxy` network behind [Nginx Proxy Manager](https://nginxproxymanager.com/), with no publicly bound ports. Works alongside an existing n8n installation or completely standalone.

## 📂 Structure

| Folder | Description |
|--------|-------------|
| [fix-npm-cache](https://github.com/nephilim75/scripts/tree/main/n8n/sandbox/fix-npm-cache/README.md) | Fix for the stale npm cache in the official sandbox image (`ETARGET`) |
| [install](https://github.com/nephilim75/scripts/tree/main/n8n/sandbox/install/README.md) | n8n Sandbox installation script |
| [update](https://github.com/nephilim75/scripts/tree/main/n8n/sandbox/update/README.md) | n8n Sandbox update script |
| [uninstall](https://github.com/nephilim75/scripts/tree/main/n8n/sandbox/uninstall/README.md) | n8n Sandbox removal script |
