# Backupd

A secure, automated backup solution for web applications and MySQL/MariaDB databases with encrypted cloud storage. Supports multiple hosting panels and application types.

**By [Backupd](https://backupd.io)**

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)
![Shell](https://img.shields.io/badge/shell-bash-green.svg)

---

## Overview

This tool provides a complete backup solution for web hosting environments:

1. **Database Backups** — Dumps all MySQL/MariaDB databases, compresses with pigz, encrypts with GPG, uploads to cloud storage
2. **File Backups** — Archives web applications (WordPress, Laravel, Node.js, PHP, etc.) with auto-detected panel paths
3. **Secure Credential Storage** — All credentials (database, cloud storage) are encrypted with AES-256 and bound to your server's machine-id
4. **Automated Scheduling** — Uses systemd timers for reliable, automatic backups with retry on failure
5. **Retention & Cleanup** — Automatic deletion of old backups based on configurable retention policy
6. **Backup Verification** — Weekly quick checks (no download), monthly reminders to test restorability
7. **Easy Restore** — Interactive wizard to browse and restore from any backup point
8. **Notifications** — Optional push notifications via ntfy.sh for backup status alerts

```
┌─────────────────────────────────────────────────────────────────┐
│                        Your Server                              │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐  │
│  │ Database │───▶│ Compress │───▶│ Encrypt  │───▶│  Upload  │──┼──▶ Cloud Storage
│  │  Dump    │    │  (pigz)  │    │  (GPG)   │    │ (rclone) │  │    (S3/B2/etc)
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘  │
│                                                                 │
│  ┌──────────┐    ┌──────────┐                    ┌──────────┐  │
│  │   Web    │───▶│ Compress │───────────────────▶│  Upload  │──┼──▶ Cloud Storage
│  │   Apps   │    │(tar+pigz)│                    │ (rclone) │  │
│  └──────────┘    └──────────┘                    └──────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Why This Tool?

Panel backups fail silently. Whether you're using cPanel, Plesk, Enhance, xCloud, or any other hosting panel — their built-in backup systems can fail without warning. You need an **independent backup layer** that:

- Works alongside (not instead of) your panel's backups
- Stores backups off-server in cloud storage
- Encrypts sensitive data (database credentials, backups)
- Runs automatically on a schedule
- Notifies you of success or failure

This tool provides exactly that.

---

## Features

- 🗄️ **Database Backups** — All MySQL/MariaDB databases, individually compressed and encrypted
- 📁 **Web App File Backups** — Backs up any web application (WordPress, Laravel, Node.js, PHP, static sites)
- 🖥️ **Multi-Panel Support** — Auto-detects Enhance, xCloud, RunCloud, Ploi, cPanel, Plesk, CloudPanel, CyberPanel, aaPanel, HestiaCP, Virtualmin
- 🔐 **Machine-Bound Encryption** — Credentials encrypted with AES-256, tied to your server
- ☁️ **Cloud Storage** — Supports 40+ providers via rclone (S3, B2, Wasabi, Google Drive, etc.)
- ⏰ **Automated Scheduling** — Systemd timers with automatic retry and catch-up
- 🧹 **Retention & Cleanup** — Configurable retention policy with automatic old backup deletion
- ✅ **Integrity Verification** — SHA256 checksums, quick checks (no download), and monthly full test reminders
- 🔔 **Notifications** — Optional alerts via ntfy.sh on backup completion/failure
- 🔄 **Easy Restore** — Interactive restore wizard with safety backups and checksum verification
- 📋 **Detailed Logging** — Full logs with timestamps and automatic log rotation
- 🔄 **Auto-Update** — Built-in update system with version checking and one-click updates

---

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/wnstify/backupd/main/install.sh | sudo bash
```

Then run the setup wizard:

```bash
sudo backupd
```

That's it! The wizard will guide you through configuration.

### Install from Develop Branch (Testing)

```bash
curl -fsSL https://raw.githubusercontent.com/wnstify/backupd/develop/install.sh | sudo bash -s -- --branch develop
```

---

## Requirements

| Requirement | Notes |
|-------------|-------|
| **OS** | Ubuntu 20.04+, Debian 10+ (or compatible) |
| **Access** | Root or sudo |
| **MySQL/MariaDB** | For database backups |
| **systemd** | For scheduled backups |
| **pigz** | Auto-installed (parallel gzip) |
| **rclone** | Auto-installed (cloud storage) |
| **argon2** | Auto-installed (modern encryption, falls back to PBKDF2 if unavailable) |

---

## What Gets Installed

```
/etc/backupd/
├── backupd.sh                # Main script (entry point)
├── lib/                      # Modular library
│   ├── core.sh               # Colors, validation, helpers
│   ├── debug.sh              # Debug logging (sanitized)
│   ├── crypto.sh             # Encryption, secrets
│   ├── config.sh             # Configuration read/write
│   ├── generators.sh         # Script generation
│   ├── status.sh             # Status display
│   ├── backup.sh             # Backup execution
│   ├── verify.sh             # Integrity verification
│   ├── restore.sh            # Restore execution
│   ├── schedule.sh           # Schedule management
│   ├── setup.sh              # Setup wizard
│   └── updater.sh            # Auto-update functionality
├── .config                   # Configuration (retention, paths, etc.)
├── scripts/
│   ├── db_backup.sh          # Database backup script
│   ├── db_restore.sh         # Database restore script
│   ├── files_backup.sh       # Files backup script
│   ├── files_restore.sh      # Files restore script
│   ├── verify_backup.sh      # Quick integrity check (weekly)
│   └── verify_reminder.sh    # Full test reminder (monthly)
└── logs/
    ├── db_logfile.log        # Database backup logs (auto-rotated)
    ├── files_logfile.log     # Files backup logs (auto-rotated)
    └── verify_logfile.log    # Verification logs (auto-rotated)

/etc/.{random}/               # Encrypted secrets (hidden, immutable)
├── .s                        # Salt for key derivation
├── .algo                     # Encryption version (1, 2, or 3)
├── .c1                       # Encryption passphrase
├── .c2                       # Database username
├── .c3                       # Database password
├── .c4                       # ntfy token (optional)
└── .c5                       # ntfy URL (optional)

/usr/local/bin/backupd            # Symlink for easy access

/etc/systemd/system/
├── backupd-db.service
├── backupd-db.timer
├── backupd-files.service
├── backupd-files.timer
├── backupd-verify.service        # Weekly quick check
├── backupd-verify.timer
├── backupd-verify-full.service   # Monthly reminder (no download)
└── backupd-verify-full.timer
```

---

## Usage

### Interactive Menu

```bash
sudo backupd
```

```
╔═══════════════════════════════════════════════════════════╗
║                    Backupd v2.1.0                         ║
║                       by Backupd                          ║
╚═══════════════════════════════════════════════════════════╝

Main Menu
=========

  1. Run backup now
  2. Restore from backup
  3. View status
  4. View logs
  5. Manage schedules
  6. Reconfigure
  7. Uninstall

  U. Update tool
  0. Exit
```

### Manual Backup Triggers

```bash
# Trigger database backup
sudo systemctl start backupd-db

# Trigger files backup
sudo systemctl start backupd-files
```

### View Logs

```bash
# Database backup logs
sudo journalctl -u backupd-db -f

# Files backup logs
sudo journalctl -u backupd-files -f

# Or via menu
sudo backupd  # Select "View Logs"
```

### Check Schedule Status

```bash
# List active timers
systemctl list-timers | grep backupd

# Check specific timer
systemctl status backupd-db.timer
```

### Debug Logging

For troubleshooting issues, enable debug logging:

```bash
# Enable debug mode for a session
BACKUPD_DEBUG=1 sudo backupd

# Or use the --debug flag
sudo backupd --debug

# Check debug log status
sudo backupd --debug-status

# Export sanitized log for sharing (safe - no passwords/secrets)
sudo backupd --debug-export
```

Debug logs are stored at `/etc/backupd/logs/debug.log` and automatically:
- Redact sensitive data (passwords, tokens, secret paths)
- Rotate when exceeding 5MB
- Include system info, timestamps, and call stacks

---

## Security

### How Credentials Are Protected

**Modern encryption (v2.1.0+):**
```
┌─────────────────┐     ┌──────────────┐     ┌─────────────────┐
│   machine-id    │────▶│   + salt     │────▶│    Argon2id     │
│  (unique/server)│     │  (random)    │     │  (derived key)  │
└─────────────────┘     └──────────────┘     └────────┬────────┘
                                                      │
                                                      ▼
┌─────────────────┐     ┌──────────────┐     ┌─────────────────┐
│  Your secrets   │────▶│   AES-256    │────▶│  .enc files     │
│  (credentials)  │     │  + PBKDF2    │     │  (encrypted)    │
└─────────────────┘     └──────────────┘     └─────────────────┘
```

**Protection includes:**
- **Strong password requirements** — 12+ characters, 2+ special characters (enforced)
- **Argon2id key derivation** (memory-hard, GPU/ASIC resistant) — default when `argon2` installed
- **PBKDF2-SHA256 fallback** (800,000 iterations) — if argon2 not available
- AES-256-CBC encryption for all credentials
- Machine-bound keys (won't decrypt on another server)
- Random directory names (`/etc/.{random}/`)
- Immutable file flags (`chattr +i`)
- No plain-text credentials stored anywhere

**Encryption management:**
```bash
# Check current encryption status
sudo backupd --encryption-status

# Upgrade existing installation to modern encryption
sudo backupd --migrate-encryption
```

### What This Protects Against

| Threat | Protected? |
|--------|------------|
| Casual file browsing | ✅ Yes |
| Automated scanners | ✅ Yes |
| Credential reuse attacks | ✅ Yes |
| Server migration/cloning | ✅ Yes (credentials don't transfer) |
| Attacker with root access | ⚠️ Partial (raises the bar significantly) |

### Honest Limitations

If an attacker gains root access to your running server, they could potentially:
- Extract the machine-id and salt
- Derive the encryption key
- Decrypt the credentials

**This is a fundamental limitation** — no solution can fully protect secrets on a compromised server where the secrets must be usable. Our approach raises the bar significantly and stops opportunistic attacks, but it's not impenetrable against a determined attacker with full system access.

### Additional Security Recommendations

- Use SSH keys (disable password auth)
- Enable firewall (ufw/iptables)
- Install fail2ban
- Keep system updated
- Enable 2FA on your cloud storage provider
- Regularly rotate credentials

---

## Cloud Storage Setup

The tool uses [rclone](https://rclone.org) which supports 40+ cloud providers:

| Provider | Command |
|----------|---------|
| Backblaze B2 | `rclone config` → "b2" |
| AWS S3 | `rclone config` → "s3" |
| Wasabi | `rclone config` → "s3" (Wasabi endpoint) |
| Google Drive | `rclone config` → "drive" |
| Dropbox | `rclone config` → "dropbox" |
| SFTP | `rclone config` → "sftp" |

The setup wizard will guide you through rclone configuration, or you can run:

```bash
rclone config
```

---

## Scheduling

Schedules are managed via systemd timers. Available presets:

| Option | Schedule |
|--------|----------|
| Hourly | Every hour |
| Every 2 hours | `*-*-* 0/2:00:00` |
| Every 6 hours | `*-*-* 0/6:00:00` |
| Daily at midnight | `*-*-* 00:00:00` |
| Daily at 3 AM | `*-*-* 03:00:00` |
| Weekly (Sunday) | `Sun *-*-* 00:00:00` |
| Custom | Any systemd OnCalendar expression |

**Recommended:**
- Database backups: Every 2 hours
- File backups: Daily at 3 AM

---

## Retention Policy

Automatic cleanup of old backups based on configurable retention periods:

| Option | Retention Period |
|--------|------------------|
| 1 minute | Testing only |
| 1 hour | Testing only |
| 7 days | Short-term |
| 14 days | Default recommended |
| 30 days | Standard |
| 60 days | Extended |
| 90 days | Long-term |
| 365 days | Annual |
| Disabled | No automatic cleanup |

### How Retention Works

1. **After each backup** — Old backups are automatically checked and deleted
2. **Based on file age** — Uses the backup file's modification time
3. **Safe cleanup** — Only deletes files matching backup patterns (e.g., `*-db_backups-*.tar.gz.gpg`)

### Managing Retention

```bash
sudo backupd  # Select "Manage schedules" → "Change retention policy"
```

Or run manual cleanup:

```bash
sudo backupd  # Select "Run backup now" → "Run cleanup now"
```

### Retention in Status

The status page shows your current retention policy:

```
Retention Policy:
  ✓ Retention: 30 days
```

---

## Restore Process

```bash
sudo backupd  # Select "Restore from Backup"
```

The restore wizard:
1. Lists available backups from cloud storage
2. Downloads selected backup
3. Creates a safety backup of current data
4. Decrypts and extracts (for databases)
5. Restores to original location
6. Verifies restoration

**Always test restores** before you need them!

### Database Restoration — IMPORTANT

> **The database backup contains table structures and data only. It does NOT contain MySQL users or permissions.**

| Scenario | Will Restore Work? |
|----------|-------------------|
| Tables deleted, database exists | Yes |
| Database deleted, user exists | Yes (if backup has `CREATE DATABASE`) |
| Database AND user deleted | **No** — user/grants must be recreated first |

**If you deleted the database AND the database user**, you must manually recreate them before restoring:

```bash
# 1. Create the database
mysql -u root -p -e "CREATE DATABASE mydb;"

# 2. Create the user
mysql -u root -p -e "CREATE USER 'myuser'@'localhost' IDENTIFIED BY 'password';"

# 3. Grant permissions
mysql -u root -p -e "GRANT ALL PRIVILEGES ON mydb.* TO 'myuser'@'localhost';"
mysql -u root -p -e "FLUSH PRIVILEGES;"

# 4. Now run the restore via backupd menu
sudo backupd  # Select "Restore from Backup" → "Database"
```

**Important:** The database credentials must match what's in your application's config file (`wp-config.php` for WordPress, `.env` for Laravel, etc.). If you create a new user with different credentials, update your application config accordingly.

This is standard behavior for database backup tools — they backup data, not MySQL system users.

---

## Notifications

Optional push notifications via [ntfy.sh](https://ntfy.sh):

1. Install ntfy app on your phone
2. Subscribe to a topic (e.g., `myserver-backups`)
3. Configure in backupd settings
4. Receive alerts on backup success/failure

**Note:** Notifications are completely optional. All backup, restore, and verification operations work normally without ntfy configured - you just won't receive push notifications.

---

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/wnstify/backupd/main/install.sh | sudo bash -s -- --uninstall
```

You'll be asked whether to keep or remove configuration and secrets.

---

## Documentation

- [CHANGELOG.md](CHANGELOG.md) — Version history and changes
- [USAGE.md](USAGE.md) — Detailed usage guide
- [SECURITY.md](SECURITY.md) — Security policy and best practices
- [DISCLAIMER.md](DISCLAIMER.md) — Legal disclaimer and responsibilities

---

## Support

- 🐛 **Issues:** [GitHub Issues](https://github.com/wnstify/backupd/issues)
- 📧 **Email:** support@webnestify.cloud
- 🌐 **Website:** [backupd.io](https://backupd.io)

---

## License

MIT License — see [LICENSE.md](LICENSE.md)

---

## Contributing

Contributions welcome! Please read the code of conduct and submit PRs to the `develop` branch.

---

<p align="center">
  <strong>Built with ❤️ by <a href="https://backupd.io">Backupd</a></strong>
</p>