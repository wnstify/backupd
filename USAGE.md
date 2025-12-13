# Usage Guide

Complete usage documentation for **Backupd v2.0.1** by Backupd.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Main Menu](#main-menu)
- [Setup Wizard](#setup-wizard)
- [Running Backups](#running-backups)
- [Retention & Cleanup](#retention--cleanup)
- [Integrity Verification](#integrity-verification)
- [Restoring Backups](#restoring-backups)
- [Managing Schedules](#managing-schedules)
- [Viewing Status & Logs](#viewing-status--logs)
- [Notifications](#notifications)
- [Updating the Tool](#updating-the-tool)
- [Command Line Usage](#command-line-usage)
- [Advanced Configuration](#advanced-configuration)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before running Backupd, ensure you have the following:

### System Requirements

| Requirement | Notes |
|-------------|-------|
| **OS** | Ubuntu 20.04+, Debian 10+ (or compatible) |
| **Access** | Root or sudo |
| **MySQL/MariaDB** | For database backups |
| **systemd** | For scheduled backups |

### Auto-installed by the installer

The following will be **automatically installed** if missing:
- **pigz** - parallel gzip for fast compression
- **rclone** - for remote cloud storage

### Usually pre-installed

These packages are typically already available on most Linux systems:
- `openssl` - credential encryption
- `gpg` - backup encryption  
- `tar` - archive creation
- `curl` - notifications

### Verify prerequisites (optional)

```bash
# Check tools (these are usually pre-installed)
which openssl gpg tar curl

# After installation, verify auto-installed tools
which pigz rclone
```

---

## Getting Started

### First Run

After installation, run the tool:

```bash
sudo backupd
```

On first run, you'll see the disclaimer and welcome screen:

```
========================================================
              Backupd v2.0.1
                    by Backupd
========================================================

┌────────────────────────────────────────────────────────┐
│                      DISCLAIMER                        │
├────────────────────────────────────────────────────────┤
│ This tool is provided "as is" without warranty.        │
│ The author is NOT responsible for any damages or       │
│ data loss. Always create a server SNAPSHOT before      │
│ running backup/restore operations. Use at your risk.   │
└────────────────────────────────────────────────────────┘

Welcome! This tool needs to be configured first.

  1. Run setup wizard
  U. Update tool
  0. Exit

Select option [1, U, 0]:
```

Select **1** to begin the setup wizard.

---

## Main Menu

After configuration, you'll see the main menu:

```
========================================================
              Backupd v2.0.1
                    by Backupd
========================================================

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

Select option [1-7, U, 0]:
```

### Menu Options

| Option | Description |
|--------|-------------|
| **1. Run backup now** | Manually trigger database and/or file backups |
| **2. Restore from backup** | Restore databases or files from existing backups |
| **3. View status** | Display current configuration and system status |
| **4. View logs** | View backup logs for troubleshooting |
| **5. Manage schedules** | Add, modify, or disable backup schedules |
| **6. Reconfigure** | Run the setup wizard again |
| **7. Uninstall** | Remove the tool completely |
| **U. Update tool** | Check for and install updates from GitHub |
| **0. Exit** | Exit the application |

---

## Setup Wizard

The setup wizard guides you through initial configuration.

### Step 1: Backup Type Selection

```
Step 1: Backup Type Selection
-----------------------------
What would you like to back up?
1. Database only
2. Files only (web applications)
3. Both Database and Files
Select option [1-3]:
```

**Recommendations:**
- Choose **3 (Both)** for complete protection
- Choose **1 (Database only)** if files are managed separately
- Choose **2 (Files only)** if databases are managed separately

### Step 2: Encryption Password

```
Step 2: Encryption Password
---------------------------
Your backups will be encrypted with AES-256.
Enter encryption password:
Confirm encryption password:
```

**Important:**
- Use a strong, unique password
- **Store this password securely** - you'll need it to restore backups
- This password encrypts your database backups
- Credentials are stored with a different machine-bound encryption

### Step 3: Database Authentication

```
Step 3: Database Authentication
--------------------------------
On many systems, root can access MySQL/MariaDB via socket authentication.

Do you need to use a password for database access? (y/N):
```

**Options:**

1. **Socket Authentication (Recommended)**
   - Press Enter or type `N`
   - Works if you can run `mysql` without a password as root
   - More secure - no password stored

2. **Password Authentication**
   - Type `Y`
   - Enter your database root password
   - Password is encrypted and stored securely

### Step 4: Remote Storage (rclone)

```
Step 4: Remote Storage (rclone)
--------------------------------
Available rclone remotes:
b2:
s3:
gdrive:

Enter remote name (without colon): b2
Enter path for database backups (e.g., backups/db): myserver/db-backups
Enter path for files backups (e.g., backups/files): myserver/file-backups
```

**Note:** If rclone is not installed, the setup wizard will automatically install it for you and prompt you to configure a remote.

**Prerequisites:**
- At least one rclone remote must be configured
- If no remotes exist, the wizard will launch `rclone config` for you

**Manual rclone configuration (if needed):**
```bash
# Configure a remote
rclone config
```

### Step 5: Notifications (Optional)

```
Step 5: Notifications (optional)
---------------------------------
Set up ntfy notifications? (y/N): y
Enter ntfy topic URL (e.g., https://ntfy.sh/mytopic): https://ntfy.sh/my-backups
Do you have an ntfy auth token? (y/N):
```

**ntfy.sh Setup:**
1. Go to [ntfy.sh](https://ntfy.sh)
2. Create a unique topic name
3. Install the ntfy app on your phone
4. Subscribe to your topic

### Step 6: Retention Policy

```
Step 6: Retention Policy
------------------------
How long should backups be kept before automatic deletion?

Select retention period:
  1) 1 minute (TESTING ONLY)
  2) 1 hour (TESTING)
  3) 7 days
  4) 14 days
  5) 30 days (default)
  6) 60 days
  7) 90 days
  8) 365 days (1 year)
  9) No automatic cleanup

Select option [1-9]:
```

**Retention Options:**

| Option | Use Case |
|--------|----------|
| 1 minute / 1 hour | Testing only - verify cleanup works |
| 7 days | Short-term, high-frequency backups |
| 14-30 days | Standard retention (recommended) |
| 60-90 days | Extended retention for compliance |
| 365 days | Long-term archival |
| No cleanup | Manual management via cloud provider |

**Note:** Old backups are automatically deleted after each successful backup. You can also run cleanup manually from the menu.

### Step 7: Script Generation

The wizard generates all backup and restore scripts automatically.

```
Step 7: Generating Backup Scripts
----------------------------------
✓ Database backup script generated
✓ Database restore script generated
✓ Files backup script generated
✓ Files restore script generated
```

### Step 8: Schedule Backups

```
Step 8: Schedule Backups (systemd timers)
-----------------------------------------
Schedule automatic database backups? (Y/n): y

Select schedule for database backup:
1. Hourly
2. Every 2 hours
3. Every 6 hours
4. Daily (at midnight)
5. Daily (at 3 AM)
6. Weekly (Sunday at midnight)
7. Custom schedule

Select option [1-7]:
```

**Recommended Schedules:**

| Backup Type | Recommendation | Systemd OnCalendar |
|-------------|----------------|-------------------|
| Database | Every 2 hours | `*-*-* 0/2:00:00` |
| Files | Daily (3 AM) | `*-*-* 03:00:00` |

---

## Running Backups

### From Main Menu

```
Run Backup
==========

1. Run database backup
2. Run files backup
3. Run both (database + files)
4. Run cleanup now (remove old backups)
5. Verify backup integrity
6. Back to main menu

Select option [1-6]:
```

### Manual Backup Progress

**Database Backup:**
```
==== 2025-01-15 03:00:01 START per-db backup ====
  → Dumping: myapp_production
    OK: myapp_production
  → Dumping: blog_database
    OK: blog_database
Archive verified.
Generating checksum...
Checksum: a1b2c3d4e5f6...
Uploading to remote storage...
Uploaded to b2:myserver/db-backups
Running retention cleanup (keeping backups newer than 43200 minutes)...
  Deleting old backup: myserver-db_backups-2024-12-01-0300.tar.gz.gpg
Retention cleanup complete. Removed 1 old backup(s).
==== 2025-01-15 03:00:45 END (success) ====
```

**Files Backup:**
```
==== 2025-01-15 03:00:01 START files backup ====
[FILES-BACKUP] Scanning /var/www...
[FILES-BACKUP] [site1.com] Archiving...
[FILES-BACKUP] [site1.com] Checksum: f1e2d3c4b5a6...
[FILES-BACKUP] [site1.com] Uploading...
[FILES-BACKUP] [site1.com] Done
[FILES-BACKUP] [site2.com] Archiving...
[FILES-BACKUP] [site2.com] Checksum: 9a8b7c6d5e4f...
[FILES-BACKUP] [site2.com] Uploading...
[FILES-BACKUP] [site2.com] Done
[FILES-BACKUP] Running retention cleanup (keeping backups newer than 43200 minutes)...
[FILES-BACKUP] Retention cleanup complete. No old backups to remove.
==== 2025-01-15 03:05:32 END (success) ====
```

### Direct Script Execution

You can also run backup scripts directly:

```bash
# Database backup
/etc/backupd/scripts/db_backup.sh

# Files backup
/etc/backupd/scripts/files_backup.sh
```

---

## Retention & Cleanup

The tool automatically manages backup retention, deleting old backups based on your configured policy.

### How Retention Works

1. **After each backup** — Old backups are automatically checked and deleted
2. **Based on file age** — Uses the backup file's modification time from cloud storage
3. **Safe cleanup** — Only deletes files matching backup patterns

### Automatic Cleanup

When you run a backup (manually or scheduled), cleanup runs automatically at the end:

```
Running retention cleanup (keeping backups newer than 43200 minutes)...
  Deleting old backup: myserver-db_backups-2024-12-01-0300.tar.gz.gpg
  Deleting old backup: myserver-db_backups-2024-12-02-0300.tar.gz.gpg
Retention cleanup complete. Removed 2 old backup(s).
```

### Manual Cleanup

Run cleanup on-demand without running a backup:

```
Run Cleanup Now
===============

Current retention policy: 30 days

This will delete backups older than 43200 minutes.

Continue? (y/N): y

Cutoff time: 2024-12-16 03:00:00

Checking database backups at b2:myserver/db-backups...
  Deleting: myserver-db_backups-2024-12-01-0300.tar.gz.gpg (2024-12-01 03:00)
Checking files backups at b2:myserver/file-backups...
  (no old backups found)

✓ Cleanup complete. Removed 1 old backup(s).
```

### Cleanup Error Handling

If cleanup encounters errors, they are logged:

```
Running retention cleanup (keeping backups newer than 43200 minutes)...
  Deleting old backup: myserver-db_backups-2024-12-01-0300.tar.gz.gpg
  [ERROR] Failed to delete myserver-db_backups-2024-12-02.tar.gz.gpg: permission denied
[WARNING] Retention cleanup completed with 1 error(s). Removed 1 old backup(s).
```

### Cleanup Notifications

If ntfy notifications are configured, you'll receive alerts:

| Scenario | Notification |
|----------|--------------|
| Success (files deleted) | "DB Retention Cleanup on hostname - Removed 3 old backup(s)" |
| Warning (some errors) | "DB Retention Cleanup Warning on hostname - Removed: 2, Errors: 1" |
| Failure | "DB Retention Cleanup Failed on hostname - Could not calculate cutoff time" |

**Note:** No notification is sent if there are zero old backups to remove (to avoid spam).

### Changing Retention Policy

To change the retention period after setup:

```
Manage schedules → Change retention policy
```

This regenerates the backup scripts with the new retention value.

---

## Integrity Verification

The tool provides comprehensive backup integrity verification to ensure your backups are not corrupted and can be successfully restored.

### SHA256 Checksums

Every backup automatically generates a SHA256 checksum:

```
Generating checksum...
Checksum: a1b2c3d4e5f6789...
```

The checksum is stored alongside the backup as `backup-file.tar.gz.gpg.sha256`.

### Verify Backup Integrity

Test your backups without restoring them:

```
Verify Backup Integrity
=======================

This will download and verify backups without restoring them.
It checks: checksum, decryption, and archive contents.

1. Verify database backup
2. Verify files backup
3. Verify both
4. Back

Select option [1-4]:
```

**What it tests:**

| Check | Database | Files |
|-------|----------|-------|
| Download | ✓ | ✓ |
| Checksum verification | ✓ | ✓ |
| Decryption test | ✓ | - |
| Archive extraction test | ✓ | ✓ |
| List contents | ✓ | ✓ |

### Verification Output

```
═══════════════════════════════════════
Verifying Database Backup
═══════════════════════════════════════

Latest backup: myserver-db_backups-2025-01-15-0300.tar.gz.gpg
Downloading backup...
Verifying checksum...
✓ Checksum verified
Testing decryption...
Enter encryption password: ********
✓ Decryption and archive verified

Archive contents:
mysql-server1-db_backups-2025-01-15-0300/
mysql-server1-db_backups-2025-01-15-0300/myapp_production-2025-01-15-0300.sql.gz
mysql-server1-db_backups-2025-01-15-0300/blog_database-2025-01-15-0300.sql.gz
... (15 files total)

═══════════════════════════════════════
Verification Summary
═══════════════════════════════════════

✓ Database: PASSED - myserver-db_backups-2025-01-15-0300.tar.gz.gpg - 15 files
✓ Files: PASSED - https__site1.com-2025-01-15-0300.tar.gz - 1247 files
```

### Checksum Verification on Restore

When restoring, checksums are automatically verified:

```
[DB-RESTORE] Downloading backup...
[DB-RESTORE] Verifying checksum...
[DB-RESTORE] ✓ Checksum verified
[DB-RESTORE] Decrypting...
```

If checksum fails:

```
[DB-RESTORE] [ERROR] Checksum mismatch! Backup may be corrupted.
[DB-RESTORE]   Expected: a1b2c3d4...
[DB-RESTORE]   Got:      x9y8z7w6...
Continue anyway? (y/N):
```

### Verification Notifications

| Result | Notification |
|--------|--------------|
| All passed | "✓ Backup Verification PASSED on hostname - DB: PASSED, Files: PASSED" |
| Any failed | "⚠️ Backup Verification FAILED on hostname - DB: FAILED, Files: PASSED" |

### Scheduled Integrity Check (Optional)

Automate verification with a weekly integrity check:

```
Manage schedules → Set/change integrity check schedule
```

```
Schedule Integrity Check
========================

This will schedule automatic backup verification.
It downloads the latest backup and verifies:
  • SHA256 checksum
  • Decryption (using stored passphrase)
  • Archive contents

Results are logged and sent via notification (if configured).

Select schedule for integrity check:
1. Weekly (Sunday at 2 AM) - recommended
2. Weekly (Saturday at 3 AM)
3. Every 2 weeks (1st and 15th at 2 AM)
4. Monthly (1st day at 2 AM)
5. Daily at 4 AM (for critical systems)
6. Custom schedule
7. Cancel
```

**How it differs from manual verification:**

| | Manual (Menu) | Scheduled |
|--|---------------|-----------|
| **Password** | Asks you | Uses stored passphrase |
| **Interaction** | Interactive | Fully automatic |
| **When** | On-demand | Weekly/custom schedule |
| **Output** | Screen | Log file + notification |

**Log file location:**
```
/etc/backupd/logs/verify_logfile.log
```

**Sample log output:**
```
[2025-01-19 02:00:01] ==== INTEGRITY CHECK START ====
[2025-01-19 02:00:01] Checking database backup...
[2025-01-19 02:00:01] Latest: myserver-db_backups-2025-01-15-0300.tar.gz.gpg
[2025-01-19 02:00:15] Checksum: OK
[2025-01-19 02:00:18] Decryption: OK (15 files)
[2025-01-19 02:00:18] Checking files backup...
[2025-01-19 02:00:18] Latest: https__site1.com-2025-01-15-0300.tar.gz
[2025-01-19 02:00:45] Checksum: OK
[2025-01-19 02:00:48] Archive: OK (1247 files)
[2025-01-19 02:00:48] ==== SUMMARY ====
[2025-01-19 02:00:48] Database: PASSED - 15 files
[2025-01-19 02:00:48] Files: PASSED - 1247 files
[2025-01-19 02:00:48] ==== INTEGRITY CHECK END ====
```

**Scheduled notifications:**

| Result | Notification |
|--------|--------------|
| Passed | "✓ Integrity Check PASSED on hostname - DB: PASSED (15 files), Files: PASSED (1247 files)" |
| Warning | "⚠️ Integrity Check WARNING on hostname - DB: WARNING, Files: PASSED" |
| Failed | "⚠️ Integrity Check FAILED on hostname - DB: FAILED, Files: PASSED" |

**Disable scheduled check:**
```
Manage schedules → Disable integrity check schedule
```

### Best Practices

1. **Run verification weekly** — Catches corruption early
2. **Test after major changes** — After server updates, storage changes
3. **Verify before disaster** — Don't wait until you need to restore
4. **Check the encryption password** — Verification proves you have the right password

---

## Restoring Backups

### Database Restoration

```
========================================================
           Database Restore Utility
========================================================

Step 1: Encryption Password
----------------------------
Enter backup encryption password: ********

Step 2: Select Backup
---------------------
[DB-RESTORE] Fetching backups from b2:myserver/db-backups...
[DB-RESTORE] Found 5 backup(s).

   1) myserver-db_backups-2025-01-15-0300.tar.gz.gpg
   2) myserver-db_backups-2025-01-14-0300.tar.gz.gpg
   3) myserver-db_backups-2025-01-13-0300.tar.gz.gpg

Select backup [1-5]:
```

**Step 3: Select Databases**
```
Step 3: Select Databases
------------------------
   1) myapp_production
   2) blog_database
   3) ecommerce_db
  A) All databases
  Q) Quit

Selection: 1,2
```

**Confirmation:**
```
Restoring 2 database(s)...
Confirm? (yes/no): yes

Restoring: myapp_production
  ✓ Success
Restoring: blog_database
  ✓ Success

========================================================
           IMPORTANT: Verify Your Site
========================================================

Database restore completed. Before we clean up the backup
files, please verify that your website is working correctly.

Check your website now, then return here.

------------------------------------------------------------------------
If your site is working correctly:
  Type exactly: Yes, I checked the website

If your site is NOT working (quick option):
  Type: N
  (We will save the SQL files to /root/ for manual recovery)
------------------------------------------------------------------------

Your response: Yes, I checked the website

[DB-RESTORE] Site verified. Cleaning up backup files...
[DB-RESTORE] Restore complete!

Done.
```

**If site is NOT working (type N):**
```
Your response: N

[DB-RESTORE] Site not working. Saving SQL files for manual recovery...
[DB-RESTORE]   Saved: myapp_production-2025-01-15-0300.sql.gz
[DB-RESTORE]   Saved: blog_database-2025-01-15-0300.sql.gz

========================================================
           SQL Files Saved
========================================================

Your SQL backup files have been saved to:
  /root/db-restore-recovery-20250115-120000

To manually restore a database:
  gunzip -c /root/db-restore-recovery-20250115-120000/DBNAME-*.sql.gz | mysql DBNAME

Or to view the SQL without restoring:
  gunzip -c /root/db-restore-recovery-20250115-120000/DBNAME-*.sql.gz | less

Remember to delete these files after you're done:
  rm -rf /root/db-restore-recovery-20250115-120000
```

**Safety Features:**
- Backup files are NOT deleted until you verify site is working
- Quick `N` option saves SQL files to `/root/` for manual recovery
- Invalid responses also save files as a precaution
- Saved SQL files can be manually re-imported if needed

### Files Restoration

Each site is backed up as a separate archive for easier restore. The restore utility groups backups by site and shows the latest available backup for each.

```
========================================================
           Files Restore Utility
========================================================

Step 1: Select Site Backup
--------------------------
[FILES-RESTORE] Fetching backups from b2:myserver/file-backups...
[FILES-RESTORE] Found 3 site(s) with backups.

Available sites:
   1) https__site1.com
      Latest: https__site1.com-2025-01-15-0300.tar.gz
   2) https__site2.com
      Latest: https__site2.com-2025-01-15-0300.tar.gz
   3) blog.example.com
      Latest: blog.example.com-2025-01-14-0300.tar.gz

  A) Restore all sites (latest backup of each)
  Q) Quit

Select site(s) to restore [1-3, comma-separated, A for all]: 1,2
```

**Step 2: Confirm Restore**
```
Step 2: Confirm Restore
-----------------------
Sites to restore:
  - https__site1.com (https__site1.com-2025-01-15-0300.tar.gz)
  - https__site2.com (https__site2.com-2025-01-15-0300.tar.gz)

This will OVERWRITE existing sites. Continue? (yes/no): yes
```

**Step 3: Restoring Sites**
```
Step 3: Restoring Sites
-----------------------

[FILES-RESTORE] Restoring: https__site1.com
[FILES-RESTORE]   Backup: https__site1.com-2025-01-15-0300.tar.gz
[FILES-RESTORE]   Downloading...
[FILES-RESTORE]   Verifying checksum...
[FILES-RESTORE]   Checksum: OK
[FILES-RESTORE]   Extracting to: /var/www/site1.com
[FILES-RESTORE]   Backing up existing to: site1.com.pre-restore-20250115-120000
[FILES-RESTORE]   Success

[FILES-RESTORE] Restoring: https__site2.com
[FILES-RESTORE]   Backup: https__site2.com-2025-01-15-0300.tar.gz
[FILES-RESTORE]   Downloading...
[FILES-RESTORE]   Checksum: OK
[FILES-RESTORE]   Extracting to: /var/www/site2.com
[FILES-RESTORE]   Success

========================================================
           Restore Complete!
========================================================
```

**Safety Features:**
- Each site backed up as separate archive for selective restore
- Existing sites are backed up before overwriting (`site.pre-restore-timestamp`)
- If restore fails, original is automatically restored
- Checksum verification before extraction
- Supports restoring one, multiple, or all sites at once

---

## Managing Schedules

```
Manage Backup Schedules
=======================

Current Schedules:

✓ Database (systemd): *-*-* *:00:00
✓ Files (systemd): *-*-* 03:00:00
✓ Integrity check (systemd): Sun *-*-* 02:00:00

Retention Policy:
✓ Retention: 30 days

Options:
1. Set/change database backup schedule
2. Set/change files backup schedule
3. Disable database backup schedule
4. Disable files backup schedule
5. Change retention policy
6. Set/change integrity check schedule (optional)
7. Disable integrity check schedule
8. View timer status
9. Back to main menu

Select option [1-9]:
```

### Schedule Options

| Option | Systemd OnCalendar | Description |
|--------|-------------------|-------------|
| Hourly | `hourly` | Every hour at :00 |
| Every 2 hours | `*-*-* 0/2:00:00` | Every 2 hours at :00 |
| Every 6 hours | `*-*-* 0/6:00:00` | At 00:00, 06:00, 12:00, 18:00 |
| Daily at midnight | `*-*-* 00:00:00` | Daily at midnight |
| Daily at 3 AM | `*-*-* 03:00:00` | Daily at 3 AM (recommended for files) |
| Weekly | `Sun *-*-* 00:00:00` | Sundays at midnight |
| Custom | Your expression | Any valid systemd OnCalendar expression |

### Integrity Check Schedule Options

| Option | Schedule | Use Case |
|--------|----------|----------|
| Weekly (Sunday 2 AM) | `Sun *-*-* 02:00:00` | Recommended for most users |
| Weekly (Saturday 3 AM) | `Sat *-*-* 03:00:00` | Alternative day |
| Bi-weekly | `*-*-01,15 02:00:00` | 1st and 15th of month |
| Monthly | `*-*-01 02:00:00` | First day of month |
| Daily | `*-*-* 04:00:00` | Critical systems only |

### Retention Options

| Period | Minutes | Use Case |
|--------|---------|----------|
| 1 minute | 1 | Testing only |
| 1 hour | 60 | Testing only |
| 7 days | 10080 | Short-term |
| 14 days | 20160 | Standard |
| 30 days | 43200 | Default |
| 60 days | 86400 | Extended |
| 90 days | 129600 | Long-term |
| 365 days | 525600 | Annual |
| Disabled | 0 | No automatic cleanup |

### View Timer Status

Option 6 shows detailed systemd timer information:

```
Timer Status
============

backupd-db.timer
  Loaded: loaded
  Active: active (waiting)
  Next: 2025-01-15 04:00:00 UTC
  Last: 2025-01-15 03:00:01 UTC

backupd-files.timer
  Loaded: loaded
  Active: active (waiting)
  Next: 2025-01-16 03:00:00 UTC
  Last: 2025-01-15 03:00:01 UTC

backupd-verify.timer
  Loaded: loaded
  Active: active (waiting)
  Next: 2025-01-19 02:00:00 UTC
  Last: 2025-01-12 02:00:01 UTC
```

### Custom Schedule Examples

Systemd uses OnCalendar expressions (not cron):

```
# Every 30 minutes
*-*-* *:0/30:00

# At 3:30 AM daily
*-*-* 03:30:00

# Every Monday and Thursday at 2 AM
Mon,Thu *-*-* 02:00:00

# First day of every month at 4 AM
*-*-01 04:00:00

# Every weekday at 6 AM
Mon..Fri *-*-* 06:00:00
```

**Test your expression:**
```bash
systemd-analyze calendar "*-*-* 03:30:00"
```

---

## Viewing Status & Logs

### System Status

```
System Status
=============

✓ Configuration: COMPLETE
✓ Secure storage: /etc/.a7x9m2k4q1

Backup Scripts:
✓ Database backup script
✓ Files backup script

Restore Scripts:
✓ Database restore script
✓ Files restore script

Scheduled Backups (systemd timers):
✓ Database: *-*-* *:00:00 (hourly)
✓ Files: *-*-* 03:00:00 (daily at 3 AM)
✓ Integrity check: Sun *-*-* 02:00:00 (weekly)

Retention Policy:
✓ Retention: 30 days

Remote Storage:
✓ Remote: b2
        Database path: myserver/db-backups
        Files path: myserver/file-backups

Recent Backup Activity:
  Last DB backup: 2025-01-15 03:00
  Last Files backup: 2025-01-15 03:00

───────────────────────────────────────────────────────
  Backupd | https://backupd.io
───────────────────────────────────────────────────────
```

**Note:** If retention is set to "No automatic cleanup", it will display as a warning:
```
Retention Policy:
⚠ Retention: No automatic cleanup
```

**Note:** Integrity check is optional and shows differently if not configured:
```
Scheduled Backups (systemd timers):
✓ Database: *-*-* *:00:00 (hourly)
✓ Files: *-*-* 03:00:00 (daily at 3 AM)
  Integrity check: NOT SCHEDULED (optional)
```

### Viewing Logs

```
View Logs
=========

1. Database backup log
2. Files backup log
3. Back to main menu

Select option [1-3]:
```

Logs are displayed using `less` for easy navigation:
- Use arrow keys to scroll
- Press `q` to quit
- Press `/` to search
- Press `G` to go to end

---

## Notifications

The tool supports push notifications via [ntfy.sh](https://ntfy.sh) for backup events.

### Notification Types

| Event | Title | Message |
|-------|-------|---------|
| **DB Backup Success** | DB Backup Successful on hostname | All 5 databases backed up |
| **DB Backup Errors** | DB Backup Completed with Errors on hostname | Backed up: 4, Failed: db_name |
| **Files Backup Success** | Files Backup Success on hostname | 3 sites backed up |
| **Files Backup Errors** | Files Backup Errors on hostname | Success: 2, Failed: site.com |
| **DB Retention Success** | DB Retention Cleanup on hostname | Removed 3 old backup(s) |
| **DB Retention Warning** | DB Retention Cleanup Warning on hostname | Removed: 2, Errors: 1 |
| **DB Retention Failed** | DB Retention Cleanup Failed on hostname | Could not calculate cutoff time |
| **Files Retention Success** | Files Retention Cleanup on hostname | Removed 2 old backup(s) |
| **Files Retention Warning** | Files Retention Cleanup Warning on hostname | Removed: 1, Errors: 1 |
| **Files Retention Failed** | Files Retention Cleanup Failed on hostname | Could not calculate cutoff time |

### Setting Up ntfy

1. **Create a topic:**
   - Go to [ntfy.sh](https://ntfy.sh)
   - Choose a unique topic name (e.g., `myserver-backups-a8x2k`)
   - Keep this name secret - anyone with the name can subscribe

2. **Subscribe on your devices:**
   - Install the ntfy app (iOS/Android)
   - Subscribe to your topic

3. **Configure in the tool:**
   ```
   Manage schedules → Configure notifications
   ```

4. **Optional: Use authentication:**
   - For private topics, create an account at ntfy.sh
   - Generate an access token
   - Enter the token during setup

### Testing Notifications

Run a manual backup to test notifications:

```bash
sudo backupd  # Select "Run backup now"
```

You should receive a notification on your subscribed devices.

---

## Updating the Tool

The tool includes a built-in update system that checks for new versions from GitHub releases.

### Update Banner

When a new version is available, you'll see a banner on startup:

```
┌────────────────────────────────────────────────────────┐
│  Update available: 1.6.1 → 1.6.2                        │
│  Select 'U' from menu or run: backupd --update│
└────────────────────────────────────────────────────────┘
```

### Updating via Menu

Select **U** from the main menu:

```
Update Backupd
==============================

→ Current version: 1.6.1
→ Checking for updates...
→ Latest version:  1.6.2

Update available: 1.6.1 → 1.6.2

This will:
  - Download the new version from GitHub
  - Backup your current installation
  - Replace script files (NOT your configuration)
  - Your settings and credentials will be preserved

Proceed with update? [y/N]: y

→ Downloading version 1.6.2...
→ Verifying checksum...
✓ Checksum verified
✓ Current version backed up to: /usr/local/backupd.backup
→ Applying update...
✓ Update complete! Version: 1.6.2

→ Please restart the tool to use the new version.
```

### Updating via Command Line

```bash
# Check for updates and install
sudo backupd --update

# Check for updates only (no install)
sudo backupd --check-update
```

### What Gets Updated

| Component | Updated? | Notes |
|-----------|----------|-------|
| Script files | ✅ Yes | New code/features |
| Library modules | ✅ Yes | `lib/*.sh` files |
| Your configuration | ❌ No | `/etc/.{random}/` preserved |
| Encrypted credentials | ❌ No | Safe and untouched |
| Cron jobs/timers | ❌ No | Your schedules preserved |
| rclone config | ❌ No | Cloud storage settings preserved |

### Rollback

If an update fails, the tool automatically rolls back to the previous version. A backup of your previous installation is kept at:

```
/usr/local/backupd.backup
```

### Update Check Frequency

- Updates are checked once per 24 hours (cached)
- Silent check on startup (non-blocking)
- No automatic updates - always requires user confirmation

---

## Command Line Usage

### Basic Commands

```bash
# Run the interactive menu
backupd

# The tool must be run as root
sudo backupd

# Show help
backupd --help

# Show version
backupd --version

# Check for and install updates
sudo backupd --update

# Check for updates only
sudo backupd --check-update
```

### Direct Script Access

For automation or scripting, access the generated scripts directly:

```bash
# Run database backup
/etc/backupd/scripts/db_backup.sh

# Run files backup
/etc/backupd/scripts/files_backup.sh

# Run database restore (interactive)
/etc/backupd/scripts/db_restore.sh

# Run files restore (interactive)
/etc/backupd/scripts/files_restore.sh

# Run integrity check (non-interactive, if configured)
/etc/backupd/scripts/verify_backup.sh
```

### Systemd Timer Management

The tool uses systemd timers for scheduling. Useful commands:

```bash
# List all backup timers
systemctl list-timers | grep backupd

# Check timer status
systemctl status backupd-db.timer
systemctl status backupd-files.timer
systemctl status backupd-verify.timer

# Manually trigger a backup (via systemd)
systemctl start backupd-db.service
systemctl start backupd-files.service

# View timer logs
journalctl -u backupd-db.service -f
journalctl -u backupd-files.service -f

# Disable a timer
systemctl disable backupd-db.timer
systemctl stop backupd-db.timer

# Re-enable a timer
systemctl enable backupd-db.timer
systemctl start backupd-db.timer
```

### Log File Locations

```bash
# Database backup log
/etc/backupd/logs/db_logfile.log

# Files backup log
/etc/backupd/logs/files_logfile.log

# Integrity check log (if scheduled)
/etc/backupd/logs/verify_logfile.log

# Tail logs in real-time
tail -f /etc/backupd/logs/db_logfile.log
tail -f /etc/backupd/logs/verify_logfile.log
```

**Log Rotation:**
Logs are automatically rotated when they exceed 10MB:
- Current log: `db_logfile.log`
- Rotated logs: `db_logfile.log.1`, `db_logfile.log.2`, ... up to `.5`
- Oldest logs are automatically deleted

---

## Advanced Configuration

### Manual Configuration File

Configuration is stored in `/etc/backupd/.config`:

```bash
DO_DATABASE="true"
DO_FILES="true"
RCLONE_REMOTE="b2"
RCLONE_DB_PATH="myserver/db-backups"
RCLONE_FILES_PATH="myserver/file-backups"
RETENTION_MINUTES="43200"
RETENTION_DESC="30 days"
```

### Retention Values

| Description | RETENTION_MINUTES |
|-------------|-------------------|
| 1 minute | 1 |
| 1 hour | 60 |
| 7 days | 10080 |
| 14 days | 20160 |
| 30 days | 43200 |
| 60 days | 86400 |
| 90 days | 129600 |
| 365 days | 525600 |
| Disabled | 0 |

### Secure Credentials Location

The path to encrypted credentials is stored in:
```
/etc/backupd/.secrets_location
```

This points to a randomly-named directory like `/etc/.a7x9m2k4q1/`

### Modifying Backup Scripts

The generated scripts are fully customizable:

```bash
# Database backup script
/etc/backupd/scripts/db_backup.sh

# Files backup script
/etc/backupd/scripts/files_backup.sh
```

**Common Modifications:**

1. **Exclude specific databases:**
   ```bash
   EXCLUDE_REGEX='^(information_schema|performance_schema|sys|mysql|test_db)$'
   ```

2. **Change WWW directory:**
   ```bash
   WWW_DIR="/home/websites"
   ```

3. **Exclude directories from file backup:**
   Add `--exclude` flags to the tar command

---

## Best Practices

### Before You Start

1. **Create a server snapshot** before any restore operation
2. **Test your backups** regularly by doing test restores
3. **Store encryption password** in a secure password manager
4. **Monitor notifications** to catch backup failures early

### Backup Strategy

| Data Type | Frequency | Recommended Retention |
|-----------|-----------|----------------------|
| Databases | Hourly | 7-14 days |
| Files | Daily | 30 days |
| Full snapshot | Weekly | 90 days |

### Retention Recommendations

| Use Case | Retention Period |
|----------|------------------|
| Development/Testing | 7 days |
| Production (standard) | 30 days |
| Production (compliance) | 90 days |
| Archival/Legal | 365 days |

**Testing Retention:**
Use the 1-minute option to verify cleanup works:
1. Set retention to 1 minute
2. Run a backup
3. Wait 2 minutes
4. Run another backup → first backup should be deleted
5. Change retention back to your desired period

### Security Recommendations

1. **Limit SSH access** to your server
2. **Use strong passwords** for encryption
3. **Enable 2FA** on your cloud storage provider
4. **Regularly rotate** cloud storage credentials
5. **Monitor backup logs** for anomalies

### Disaster Recovery Plan

1. Document your rclone remote configuration
2. Store encryption password securely (not on the server)
3. Test restore procedure quarterly
4. Keep a local copy of backupd.sh
5. Document your server configuration

### Storage Management

The tool now handles retention automatically! Configure your retention policy in the setup wizard or via "Manage schedules".

For additional cost savings, configure lifecycle rules on your cloud storage:
- Move older backups to cold storage (Glacier, B2 cold, etc.)
- Set up cross-region replication for critical backups

---

## Troubleshooting

### Backup Failures

**Check logs first:**
```bash
tail -100 /etc/backupd/logs/db_logfile.log
tail -100 /etc/backupd/logs/files_logfile.log
```

**Common issues:**

1. **rclone errors**: Run `rclone ls remote:path` to test connectivity
2. **Database errors**: Check MySQL is running with `systemctl status mysql`
3. **Permission errors**: Ensure running as root
4. **Disk space**: Check with `df -h`

### Restore Failures

1. **Wrong password**: Double-check your encryption password
2. **Corrupted backup**: Try an older backup
3. **Network issues**: Check rclone connectivity

### Retention/Cleanup Issues

1. **Cleanup not running**: Verify `RETENTION_MINUTES` is set in config (not 0)
2. **Files not being deleted**: Check rclone permissions on cloud storage
3. **Wrong files deleted**: Verify the file pattern matches (e.g., `*-db_backups-*.tar.gz.gpg`)
4. **Cleanup errors**: Check logs for specific rclone errors

**Test cleanup manually:**
```bash
# List files that would be cleaned (without deleting)
rclone lsf remote:path --include "*.tar.gz.gpg"

# Check file modification times
rclone lsl remote:path/filename
```

### Getting Help

1. Check the logs in `/etc/backupd/logs/`
2. Run `rclone` commands manually to test
3. Review [GitHub Issues](https://github.com/wnstify/backupd-tool/issues)
4. Contact support at [backupd.io](https://backupd.io)

---

<p align="center">
  <strong>Backupd</strong> by <a href="https://backupd.io">Backupd</a>
</p>