# 🔧 LibreChat Maintenance

<a href="https://pc-fee.com/blog/" target="_blank" rel="noopener noreferrer">
  <img src="https://img.shields.io/badge/Blog-pc--fee.com-FE5200?style=for-the-badge" alt="Visit the pc-fee.com blog for additional resources and tutorials" />
</a>
<a href="https://www.librechat.ai/docs" target="_blank" rel="noopener noreferrer">
  <img src="https://img.shields.io/badge/Docs-LibreChat-00B8D9?style=for-the-badge" alt="Read the official LibreChat documentation" />
</a>
<br><br>

Interactive menu-driven maintenance tool for deployed [LibreChat](https://www.librechat.ai/) instances.

Handles user management, SMTP configuration, backups, purging, and reinstallation.

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
sudo mv temp/librechat/maintenance/* .
sudo rm -rf temp
```

3. Make all scripts executable:

```bash
sudo chmod +x menu.sh lib/*.sh modules/*/*.sh
```

### Run Maintenance Tool

```bash
cd /opt/admin-lc
sudo ./menu.sh
```

An interactive menu appears with options for all maintenance tasks.

---

## 📋 Features

### 👤 User Admin
- Create new users
- Delete users
- List all users
- Ban/unban users
- Reset user passwords

### 📧 Mail & SMTP
- View current SMTP configuration
- Configure new SMTP settings
- Update existing configuration
- Delete SMTP configuration

### 🔄 Lifecycle Management
- **Dry-run purge** (show what would be deleted)
- **Full purge** (delete everything)
- **Reinstall** (fresh installation)

---

## 📂 Modules

| Module | Purpose |
|--------|---------|
| `modules/useradmin/` | User creation, deletion, management |
| `modules/mail/` | SMTP configuration and email setup |
| `modules/lifecycle/` | Backup, purge, reinstall operations |

---

## 🔗 References

- [Installation Guide](../install/README.md)
- [Official Docs](https://www.librechat.ai/docs)
- [GitHub Repository](https://github.com/danny-avila/LibreChat)
- [Blog](https://pc-fee.com/blog)
