# Backupd Usage Guide

Comprehensive guide for using Backupd - the secure backup daemon for web servers.

---

## Table of Contents

- [Installation](#installation)
- [Initial Setup](#initial-setup)
- [Running Backups](#running-backups)
- [Restoring Backups](#restoring-backups)
- [Scheduling](#scheduling)
- [Verification](#verification)
- [Configuration](#configuration)
- [Command Reference](#command-reference)
- [Advanced Usage](#advanced-usage)
- [Troubleshooting](#troubleshooting)

---

## Installation

### Prerequisites

Before installing Backupd, ensure you have:

1. **Root access** to your Linux server
2. **MySQL or MariaDB** installed (for database backups)
3. **rclone** configured with at least one remote

#### Installing rclone

```bash
# Install rclone
curl https://rclone.org/install.sh | sudo bash

# Configure a remote (interactive)
rclone config
```

### One-Line Installation

```bash
curl -fsSL https://raw.githubusercontent.com/wnstify/backupd/main/install.sh | sudo bash
```

### Manual Installation

```bash
# Clone repository
git clone https://github.com/wnstify/backupd.git
cd backupd

# Run installer
sudo bash install.sh

# Verify installation
backupd --version
```

### Verify Dependencies

After installation, verify all dependencies:

```bash
# Check required tools
command -v bash && bash --version | head -1
command -v openssl && openssl version
command -v gpg && gpg --version | head -1
command -v rclone && rclone version | head -1
command -v mysql || command -v mariadb
command -v tar && tar --version | head -1
command -v curl && curl --version | head -1

# Check optional tools
command -v pigz && pigz --version
command -v zstd && zstd --version
```

---

## Initial Setup

### Starting the Setup Wizard

```bash
sudo backupd
```

Select **"Run setup wizard"** from the menu.

### Step-by-Step Configuration

#### Step 1: Backup Type Selection

```
What would you like to backup?

  1. Databases only
  2. Web files only
  3. Both databases and files (recommended)

Select option [1-3]: 3
```

**Recommendation:** Choose option 3 for complete disaster recovery capability.

#### Step 2: Web Application Paths

Backupd auto-detects your hosting panel:

```
Detected Panel: Enhance

Panel Presets:
  1. Enhance (/var/www/*/public_html)
  2. xCloud (/var/www/*/public_html)
  3. RunCloud (/home/*/webapps/*)
  ...
  12. Custom (specify your own path)

Select option [1-12]: 1
```

For custom paths, use glob patterns:
- `/var/www/*` - All directories in /var/www
- `/home/*/public_html` - public_html in each home directory
- `/srv/sites/*` - Custom site directory

#### Step 3: Encryption Password

```
Enter a strong password for encrypting backups.
This password will be required to restore backups.

Enter encryption password (min 8 chars): ********
Confirm password: ********
```

**Important:** Store this password securely! Without it, you cannot restore encrypted backups.

#### Step 4: Database Authentication

```
Database Authentication Method:

  1. Socket authentication (uses system user)
  2. Password authentication

Select option [1-2]: 2

Enter database username [root]: root
Enter database password: ********
Testing connection... OK
```

#### Step 5: Cloud Storage Configuration

```
Available rclone remotes:
  1. s3-backup
  2. backblaze
  3. google-drive

Select remote [1-3]: 1

Enter path for database backups [backups/db]: backups/databases
Enter path for files backups [backups/files]: backups/files
```

#### Step 6: Notifications (Optional)

```
Setup push notifications via ntfy.sh?

  1. Yes, configure notifications
  2. No, skip notifications

Select option [1-2]: 1

Enter ntfy server URL: https://ntfy.sh
Enter ntfy topic: my-server-backups
Enter ntfy access token (optional):
```

#### Step 7: Retention Policy

```
How long should backups be kept?

  1. 1 day
  2. 3 days
  3. 7 days (recommended)
  4. 14 days
  5. 30 days
  6. 90 days
  7. 365 days
  8. Forever (no automatic deletion)

Select option [1-8]: 3
```

#### Step 8: Schedule Configuration

```
Configure automated backups?

Database backup schedule:
  1. Every hour
  2. Every 2 hours (recommended)
  3. Every 6 hours
  4. Daily at midnight
  5. Custom schedule

Select option [1-5]: 2

Files backup schedule:
  1. Daily at 3 AM (recommended)
  2. Daily at midnight
  3. Every 12 hours
  4. Weekly (Sunday 3 AM)
  5. Custom schedule

Select option [1-5]: 1
```

### Setup Complete

```
✓ Configuration saved
✓ Backup scripts generated
✓ Systemd timers configured
✓ Schedules enabled

Setup complete! Your backups are now configured.

To run a backup now: sudo backupd → Run backup now
To check status: sudo backupd → View status
```

---

## Running Backups

### From Interactive Menu

```bash
sudo backupd
```

Select **"Run backup now"**:

```
Run Backup Now
==============

  1. Run database backup
  2. Run files backup
  3. Run both
  4. Run cleanup now
  5. Verify backup integrity
  6. Back to main menu

Select option [1-6]:
```

### From Command Line

```bash
# Run database backup directly
sudo /etc/backupd/scripts/db_backup.sh

# Run files backup directly
sudo /etc/backupd/scripts/files_backup.sh

# Both backups
sudo /etc/backupd/scripts/db_backup.sh && sudo /etc/backupd/scripts/files_backup.sh
```

### What Happens During Backup

#### Database Backup Process

1. **Lock acquisition** - Prevents concurrent backups
2. **Disk space check** - Requires 1GB free in /tmp
3. **Database discovery** - Lists all non-system databases
4. **Per-database dump** - Uses `mysqldump --single-transaction`
5. **Compression** - pigz (parallel) or gzip fallback
6. **Encryption** - GPG with AES-256
7. **Upload** - rclone with checksum verification
8. **Checksum creation** - SHA256 for integrity
9. **Retention cleanup** - Removes old backups
10. **Notification** - Sends success/failure alert

#### Files Backup Process

1. **Lock acquisition** - Prevents concurrent backups
2. **Disk space check** - Requires 2GB free in /tmp
3. **Site discovery** - Scans configured path pattern
4. **Site identification** - Detects WordPress, Laravel, etc.
5. **Archive creation** - tar with pigz compression
6. **Upload** - rclone with checksum verification
7. **Metadata storage** - Saves restore path info
8. **Checksum creation** - SHA256 for integrity
9. **Retention cleanup** - Removes old backups
10. **Notification** - Sends success/failure alert

### Monitoring Backup Progress

```bash
# Watch database backup log in real-time
sudo tail -f /etc/backupd/logs/db_logfile.log

# Watch files backup log in real-time
sudo tail -f /etc/backupd/logs/files_logfile.log
```

---

## Restoring Backups

### Database Restore

```bash
sudo backupd
```

Select **"Restore from backup"** → **"Restore database(s)"**

```
Available Database Backups:
===========================

  1. server-db_backups-2024-12-16-1000.tar.gz.gpg (2.3 GB)
  2. server-db_backups-2024-12-15-1000.tar.gz.gpg (2.1 GB)
  3. server-db_backups-2024-12-14-1000.tar.gz.gpg (2.2 GB)

Select backup to restore [1-3]: 1
```

The restore process:

1. **Download** - Fetches backup from cloud storage
2. **Verify checksum** - Ensures integrity
3. **Decrypt** - Prompts for encryption password
4. **Extract** - Lists available databases
5. **Select databases** - Choose which to restore
6. **Restore** - Imports SQL into MySQL/MariaDB
7. **Verify** - Asks you to check your site works
8. **Cleanup** - Removes temp files (or saves for recovery)

### Files Restore

```bash
sudo backupd
```

Select **"Restore from backup"** → **"Restore files/sites"**

```
Available Sites:
================

  1. example.com (latest: 2024-12-16-0300)
  2. mysite.org (latest: 2024-12-16-0300)
  3. store.example.com (latest: 2024-12-16-0300)

Select site to restore [1-3]: 1

Available backups for example.com:
  1. example.com-2024-12-16-0300.tar.gz
  2. example.com-2024-12-15-0300.tar.gz
  3. example.com-2024-12-14-0300.tar.gz

Select backup [1-3]: 1
```

### Emergency Restore

If you need to restore without the interactive wizard:

```bash
# Download backup manually
rclone copy myremote:backups/db/server-db_backups-2024-12-16.tar.gz.gpg /tmp/

# Verify checksum
rclone copy myremote:backups/db/server-db_backups-2024-12-16.tar.gz.gpg.sha256 /tmp/
cd /tmp && sha256sum -c server-db_backups-2024-12-16.tar.gz.gpg.sha256

# Decrypt
gpg --decrypt server-db_backups-2024-12-16.tar.gz.gpg > backup.tar.gz

# Extract
tar -xzf backup.tar.gz

# Restore specific database
mysql database_name < database_name.sql
```

---

## Scheduling

### View Current Schedules

```bash
sudo backupd
```

Select **"Manage schedules"** → **"View timer status"**

Or from command line:

```bash
# View all backupd timers
systemctl list-timers --all | grep backupd

# Check specific timer
systemctl status backupd-db.timer
systemctl status backupd-files.timer
```

### Modify Schedules

```bash
sudo backupd
```

Select **"Manage schedules"**:

```
Manage Schedules
================

  1. Set/change database backup schedule
  2. Set/change files backup schedule
  3. Disable database schedule
  4. Disable files schedule
  5. Change retention policy
  6. Set/change integrity check schedule
  7. Disable integrity check
  8. View timer status
  9. Back to main menu
```

### Schedule Presets

**Database Backup Schedules:**

| Option | Schedule | Use Case |
|--------|----------|----------|
| Every hour | `*-*-* *:00:00` | High-transaction sites |
| Every 2 hours | `*-*-* 0/2:00:00` | Recommended default |
| Every 6 hours | `*-*-* 0/6:00:00` | Lower-traffic sites |
| Daily | `*-*-* 00:00:00` | Low-change databases |

**Files Backup Schedules:**

| Option | Schedule | Use Case |
|--------|----------|----------|
| Daily 3 AM | `*-*-* 03:00:00` | Recommended default |
| Daily midnight | `*-*-* 00:00:00` | Alternative timing |
| Every 12 hours | `*-*-* 0/12:00:00` | Frequent changes |
| Weekly | `Sun *-*-* 03:00:00` | Stable sites |

### Custom Schedules

For custom schedules, use systemd timer syntax:

```bash
# Edit timer directly
sudo systemctl edit backupd-db.timer

# Add custom OnCalendar
[Timer]
OnCalendar=*-*-* 04:30:00
```

See `man systemd.time` for calendar syntax.

---

## Verification

### Manual Verification

```bash
sudo backupd
```

Select **"Run backup now"** → **"Verify backup integrity"**

### Scheduled Verification

```bash
sudo backupd
```

Select **"Manage schedules"** → **"Set/change integrity check schedule"**

Options:
- Weekly (Sunday 4 AM)
- Bi-weekly
- Monthly
- Daily
- Custom

### What Verification Checks

1. **Download latest backup** from cloud storage
2. **Verify SHA256 checksum** matches
3. **Test decryption** (for database backups)
4. **Validate archive structure**
5. **List contents** without extracting
6. **Send notification** with results

### Verification Log

```bash
# View verification log
sudo less /etc/backupd/logs/verify_logfile.log
```

---

## Configuration

### Configuration File

Location: `/etc/backupd/.config`

```bash
# View current configuration
sudo cat /etc/backupd/.config
```

Example configuration:

```bash
DO_DATABASE=true
DO_FILES=true
PANEL_KEY=enhance
WEB_PATH_PATTERN=/var/www/*/public_html
WEBROOT_SUBDIR=public_html
RCLONE_REMOTE=s3-backup
RCLONE_DB_PATH=backups/db
RCLONE_FILES_PATH=backups/files
RETENTION_MINUTES=10080
RETENTION_DESC=7 days
```

### Modifying Configuration

**Recommended:** Use the interactive wizard:

```bash
sudo backupd
```

Select **"Reconfigure"** to re-run the setup wizard.

**Manual editing** (advanced):

```bash
# Edit configuration
sudo nano /etc/backupd/.config

# Regenerate scripts after changes
sudo backupd  # Select Reconfigure
```

### Secrets Management

Secrets are stored encrypted at `/etc/.{random_id}/`:

```bash
# Find secrets location
cat /etc/backupd/.secrets_location

# Secrets are immutable (chattr +i)
# To modify, run setup wizard which handles unlock/lock
```

**Never edit secrets manually.** Use the setup wizard to update credentials.

---

## Command Reference

### Main Commands

| Command | Description |
|---------|-------------|
| `sudo backupd` | Launch interactive menu |
| `backupd --help` | Show help message |
| `backupd --version` | Show version |
| `backupd --update` | Update to latest version |
| `backupd --check-update` | Check for updates |

### Backup Scripts

| Script | Description |
|--------|-------------|
| `/etc/backupd/scripts/db_backup.sh` | Run database backup |
| `/etc/backupd/scripts/files_backup.sh` | Run files backup |
| `/etc/backupd/scripts/db_restore.sh` | Restore databases |
| `/etc/backupd/scripts/files_restore.sh` | Restore files |
| `/etc/backupd/scripts/verify_backup.sh` | Verify backup integrity |

### systemd Commands

```bash
# List all backupd timers
systemctl list-timers --all | grep backupd

# Start/stop timers
sudo systemctl start backupd-db.timer
sudo systemctl stop backupd-db.timer

# Enable/disable timers
sudo systemctl enable backupd-db.timer
sudo systemctl disable backupd-db.timer

# Check timer status
systemctl status backupd-db.timer
systemctl status backupd-files.timer

# View timer logs
journalctl -u backupd-db.service -f
```

---

## Advanced Usage

### Multiple rclone Remotes

To backup to multiple destinations, configure multiple rclone remotes and run backups twice:

```bash
# First remote
sudo RCLONE_REMOTE=primary /etc/backupd/scripts/db_backup.sh

# Second remote (mirror)
rclone sync primary:backups/db secondary:backups/db
```

### Custom Exclusions

Modify the generated backup script to add exclusions:

```bash
# Edit files backup script
sudo nano /etc/backupd/scripts/files_backup.sh

# Add exclusions to tar command
tar --exclude='*.log' --exclude='node_modules' --exclude='.git' ...
```

### Pre/Post Backup Hooks

Add custom commands before/after backups:

```bash
# Create hook script
cat > /etc/backupd/hooks/pre-backup.sh << 'EOF'
#!/bin/bash
# Put site in maintenance mode
wp maintenance-mode activate --path=/var/www/example.com/public_html
EOF

chmod +x /etc/backupd/hooks/pre-backup.sh

# Call from backup script (requires manual edit)
```

### Backup to Local Storage

Configure rclone with a local remote:

```bash
# Create local remote
rclone config create local-backup local

# Use during setup
# Remote: local-backup
# Path: /mnt/backup-drive/backups
```

### Encryption Key Backup

**Critical:** Back up your encryption key externally:

```bash
# Export encryption key (store securely off-server!)
sudo cat /etc/backupd/.secrets_location
# Note the path, e.g., /etc/.a1b2c3d4e5f6

# Back up the salt file
sudo cp /etc/.a1b2c3d4e5f6/.s /secure/external/location/

# The encryption password you set is also required
# Store it in a password manager!
```

---

## Troubleshooting

### Common Issues

#### "No databases found"

```bash
# Check MySQL is running
sudo systemctl status mysql

# Check credentials
mysql -u root -p -e "SHOW DATABASES"

# Re-run setup to fix credentials
sudo backupd  # Select Reconfigure
```

#### "No sites found"

```bash
# Check path pattern
cat /etc/backupd/.config | grep WEB_PATH_PATTERN

# Test pattern manually
ls -la /var/www/*/public_html 2>/dev/null

# Re-configure paths
sudo backupd  # Select Reconfigure
```

#### "rclone upload failed"

```bash
# Test rclone configuration
rclone lsd myremote:

# Test write access
echo "test" > /tmp/test.txt
rclone copy /tmp/test.txt myremote:backups/

# Check network
ping -c 3 google.com
```

#### "GPG decryption failed"

```bash
# Verify password is correct
# GPG will prompt for password

# Try manual decryption
gpg --decrypt backup.tar.gz.gpg

# If password lost, backup cannot be recovered!
```

#### "Permission denied"

```bash
# Ensure running as root
sudo backupd

# Check file permissions
ls -la /etc/backupd/
ls -la /etc/backupd/scripts/
```

### Log Analysis

```bash
# View recent database backup entries
sudo tail -100 /etc/backupd/logs/db_logfile.log

# Search for errors
sudo grep -i "error\|failed\|warning" /etc/backupd/logs/db_logfile.log

# View systemd journal
journalctl -u backupd-db.service --since "1 hour ago"
```

### Reset Configuration

To start fresh:

```bash
# Uninstall completely
sudo backupd  # Select Uninstall

# Remove any remaining files
sudo rm -rf /etc/backupd

# Find and remove secrets
sudo find /etc -maxdepth 1 -type d -name ".*" -exec ls -la {} \;

# Reinstall
curl -fsSL https://raw.githubusercontent.com/wnstify/backupd/main/install.sh | sudo bash
```

### Getting Help

1. Check logs: `/etc/backupd/logs/`
2. Review documentation: [README.md](README.md), [SECURITY.md](SECURITY.md)
3. Open an issue: [GitHub Issues](https://github.com/wnstify/backupd/issues)
4. Visit website: [backupd.io](https://backupd.io)

---

<p align="center">
  <strong>Need more help?</strong><br>
  Visit <a href="https://backupd.io">backupd.io</a> or open a <a href="https://github.com/wnstify/backupd/issues">GitHub issue</a>
</p>
