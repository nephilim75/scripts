# 🔧 LibreChat Maintenance

<a href="https://pc-fee.com/blog/" target="_blank" rel="noopener noreferrer">
  <img src="https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge" alt="Visit the pc-fee.com blog for additional resources and tutorials" />
</a>
<a href="https://www.librechat.ai/docs" target="_blank" rel="noopener noreferrer">
  <img src="https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge" alt="Read the official LibreChat documentation" />
</a>

<br><br>

Interactive menu-driven maintenance tool for deployed [LibreChat](https://www.librechat.ai/) instances based on pc-fee.com's [blog posts](https://pc-fee.com/blog). Handles user management, container control, SMTP configuration, instance settings, the Code Interpreter, backups, purging, and reinstallation.

Written in POSIX `sh`, aimed at people who are new to Linux: every menu explains what it does, asks before anything destructive happens, and says what to do next.

---

## 🚀 Setup & Usage

### First Time Setup

1. Create admin directory:

```bash
sudo mkdir -p /opt/admin-lc
cd /opt/admin-lc
```

2. Clone librechat/maintenance content directly into /opt/admin-lc:

```bash
sudo git clone --depth 1 https://github.com/nephilim75/scripts.git temp
sudo cp -r temp/librechat/maintenance/. .
sudo rm -rf temp
```

3. Make all scripts executable:

```bash
sudo find . -name '*.sh' -exec chmod +x {} +
```

> `find` instead of a fixed pattern like `modules/*/*.sh`: scripts live at different depths (for example `modules/codeinterpreter/usnavy13/`), and new folders are added over time.

### Run Maintenance Tool

```bash
cd /opt/admin-lc
sudo ./menu.sh
```

An interactive menu appears with options for all maintenance tasks.

### Updating

The tool updates itself: **main menu → 8) Admin-Tool aktualisieren**. It backs up the current state to `/tmp`, pulls the latest version, fixes permissions and line endings, and restarts the menu. Your own `config.sh` is left untouched.

---

## 🗺️ Menu structure

```text
Main menu
├── 1  User admin
│   ├── Create user
│   ├── Delete user
│   ├── List all users
│   ├── Ban / unban user
│   └── Reset password
├── 2  Container management (Docker)
│   ├── LibreChat          ┐
│   ├── MongoDB            │
│   ├── Meilisearch        │  each opens the same submenu:
│   ├── RAG API            │  status · logs · start · stop
│   ├── Vector DB          │  restart · delete (incl. data)
│   ├── Admin panel        ┘
│   ├── Restart whole stack (no data loss)
│   └── Update LibreChat
├── 3  Mail & password reset (SMTP)
│   ├── Show configuration
│   ├── Configure / change
│   └── Delete configuration
├── 4  Instance settings
│   ├── Welcome message
│   │   ├── Show
│   │   └── Change
│   └── Registration on / off
├── 5  Code Interpreter
│   ├── usnavy13                     [installed / not installed]
│   │   ├── Install
│   │   ├── Connect to LibreChat
│   │   ├── Status
│   │   ├── Start / stop / restart
│   │   ├── Logs
│   │   ├── Update
│   │   └── Remove                   (destructive)
│   └── LibreChat-AI                 [planned]
├── 6  Backup
│   ├── Create backup
│   ├── List backups
│   └── Restore backup
├── 7  Delete / reinstall LibreChat   (destructive)
│   ├── Dry-run purge (shows what would be deleted)
│   ├── Purge
│   └── Reinstall
├── 8  Update this tool
└── 0  Exit
```

Both Code Interpreter variants show whether they are installed, so you always know which branch applies to your server.

---

## 📋 Features

### 👤 User Admin

- Create new users
- Delete users
- List all users
- Ban/unban users
- Reset user passwords

### 🐳 Container management (Docker)

- Status, logs, start, stop, restart for each service
- Delete a single container including its data volume
- Restart the whole stack without data loss
- Update LibreChat itself

### 📧 Mail & SMTP

- View current SMTP configuration
- Configure new SMTP settings
- Update existing configuration
- Delete SMTP configuration

### ⚙️ Instance settings

- Change the welcome message
- Turn user registration on or off

### 🧮 Code Interpreter (usnavy13)

- Install (fetches the installer from this repo, so it is always current)
- Connect to LibreChat — enters the API key, offers the required stop/start, then verifies the value arrived
- Status — domain, dashboard URL, `MASTER_API_KEY`, state of the LibreChat connection
- Start, stop, restart all services together
- Logs, kept short by default
- Update via `pull` + `up -d`
- Remove — preview first, then separate prompts for images and the LibreChat entry

### 💾 Backup

- Create, list and restore backups

### 🔄 Lifecycle Management

- **Dry-run purge** (show what would be deleted)
- **Full purge** (delete everything)
- **Reinstall** (fresh installation)

---

## 📂 Modules

| Module | Purpose |
|--------|---------|
| `lib/` | Shared helpers: colours, prompts, `.env` access, path detection |
| `modules/useradmin/` | User creation, deletion, management |
| `modules/appctl/` | Container management for all LibreChat services |
| `modules/mail/` | SMTP configuration and email setup |
| `modules/instance/` | Welcome message, registration on/off |
| `modules/codeinterpreter/` | Code Interpreter variants (`usnavy13/`, `libreai/`) |
| `modules/backup/` | Create, list and restore backups |
| `modules/lifecycle/` | Purge and reinstall operations |
| `modules/selfupdate/` | Updates this tool from the repo |

---

## 🧩 Conventions

Useful to know before adding a module:

- Every script computes its own `PROJECT_ROOT` and then sources `lib/common.sh`. In POSIX `sh` a sourced file cannot determine its own path, so this cannot be done centrally.
- Output goes through `heading`, `info`, `success`, `warn`, `error` and `breadcrumb` so that colours and wording stay consistent.
- Anything destructive asks first, and says what will happen before it happens.
- Changes to LibreChat's `.env` need a real stop and start — `docker restart` does not re-read it.
- Save files with Unix line endings. A trailing `\r` makes the shell look for an interpreter called `/bin/sh<CR>` and report a confusing "not found".

---

## 🔗 References

- [Installation Guide](../install/README.md)
- [Official Docs](https://www.librechat.ai/docs)
- [GitHub Repository](https://github.com/danny-avila/LibreChat)
- [Blog](https://pc-fee.com/blog)

---

<sub>The scripts in this folder were researched, written and iteratively revised with the help of AI models. All technical statements were checked against the respective project documentation and source code. Please verify for yourself before using them in production. </sub>
