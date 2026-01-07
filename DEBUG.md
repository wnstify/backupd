# Debugging Guide

Comprehensive guide for troubleshooting **Backupd** issues using the structured logging system.

## Table of Contents

- [Quick Start](#quick-start)
- [Log Locations](#log-locations)
- [Log Levels](#log-levels)
- [Understanding Log Format](#understanding-log-format)
- [Auto-Redaction](#auto-redaction)
- [Reporting Issues](#reporting-issues)
- [Common Problems](#common-problems)
- [Advanced Debugging](#advanced-debugging)

---

## Quick Start

### Something went wrong?

```bash
# Step 1: Check the error log
sudo tail -50 /var/log/backupd.log

# Step 2: Reproduce with verbose logging
sudo backupd -vv backup db

# Step 3: Export for GitHub issue
sudo backupd --log-export
```

### Log is too long?

```bash
# View only errors
sudo grep "\[ERROR\]" /var/log/backupd.log

# View last session only
sudo grep "LOG SESSION" /var/log/backupd.log | tail -2
```

---

## Log Locations

| Log File | Purpose | Auto-Created |
|----------|---------|--------------|
| `/var/log/backupd.log` | Structured error log (main) | Yes |
| `/etc/backupd/logs/db_logfile.log` | Database backup script output | Yes |
| `/etc/backupd/logs/files_logfile.log` | Files backup script output | Yes |
| `/etc/backupd/logs/verify_logfile.log` | Verification output | Yes |
| `/etc/backupd/logs/debug.log` | Legacy debug log | With --debug |
| `/tmp/backupd-issue-log.txt` | Sanitized export | With --log-export |

### Viewing Logs

```bash
# Main structured log
sudo tail -f /var/log/backupd.log

# Backup script output
sudo tail -f /etc/backupd/logs/db_logfile.log

# systemd journal
sudo journalctl -u backupd-db -f
```

---

## Log Levels

| Level | Flag | Use Case |
|-------|------|----------|
| **INFO** | (default) | Normal operations - errors, warnings, key events |
| **DEBUG** | `--verbose` | Troubleshooting - adds system info, command details |
| **TRACE** | `-vv` | Deep debugging - adds function entry/exit, timing |

### Examples

```bash
# INFO level (default) - logs errors and key operations
sudo backupd backup db

# DEBUG level - includes system information
sudo backupd --verbose backup db

# TRACE level - includes function tracing
sudo backupd -vv backup db

# Custom log file
sudo backupd --log-file /tmp/debug.log backup db
```

### What Each Level Logs

**INFO (default):**
- Session start/end
- CLI commands received
- Errors with stack traces
- Warnings

**DEBUG (--verbose):**
- Everything in INFO, plus:
- System information (OS, kernel, bash version)
- Tool versions (openssl, restic, rclone, etc.)
- Configuration keys (no values)
- Command execution details

**TRACE (-vv):**
- Everything in DEBUG, plus:
- Function entry/exit
- Function arguments (redacted)
- Execution timing
- Internal state changes

---

## Understanding Log Format

### Standard Entry

```
[2025-01-15 03:00:01.123] [INFO] [run_backup@backup.sh:45] Starting database backup
│                         │      │                        │
│                         │      │                        └── Message
│                         │      └── function@file:line
│                         └── Log level
└── Timestamp (milliseconds)
```

### Error with Stack Trace

```
[2025-01-15 03:00:05.789] [ERROR] [run_backup@backup.sh:78] Database connection failed
--- Stack Trace ---
  at run_backup() in backup.sh:78
  at cli_backup() in cli.sh:25
  at cli_dispatch() in cli.sh:15
  at main() in backupd.sh:627
--- End Stack Trace ---
--- Error Context ---
Exit Code: 1
Working Directory: /etc/backupd
User: root
--- End Error Context ---
```

### Session Markers

```
================================================================================
LOG SESSION: 20250115-030001-12345
Started: 2025-01-15T03:00:01+00:00
Version: 3.1.0
Command: /usr/local/bin/backupd backup db
Log Level: INFO
================================================================================
[... log entries ...]
================================================================================
LOG SESSION ENDED: 20250115-030001-12345
Ended: 2025-01-15T03:00:45+00:00
================================================================================
```

### System Information (DEBUG level)

```
--- System Information ---
OS: Ubuntu 24.04 LTS
Kernel: 6.8.0-90-generic
Arch: x86_64
Hostname: [REDACTED]
Bash: 5.2.21(1)-release
User: root (EUID: 0)
--- Tool Versions ---
openssl: OpenSSL 3.0.13
restic: restic 0.17.3
rclone: rclone v1.65.0
argon2: installed
tar: tar (GNU tar) 1.35
curl: curl 8.5.0
systemctl: installed
--- Backupd Configuration ---
Install dir: /etc/backupd
Config file: exists
Config keys: DO_DATABASE DO_FILES RCLONE_REMOTE ...
--- End System Information ---
```

---

## Auto-Redaction

The logging system automatically redacts sensitive data before writing to logs.

### What Gets Redacted

| Pattern | Example Before | Example After |
|---------|----------------|---------------|
| Passwords | `password=secret123` | `password=[REDACTED]` |
| Passphrases | `passphrase=mypass` | `passphrase=[REDACTED]` |
| Tokens | `token=tk_abc123xyz` | `token=[REDACTED]` |
| API keys | `sk_live_abcdef123` | `[API_KEY]` |
| Bearer tokens | `Bearer eyJhbGc...` | `Bearer [REDACTED]` |
| Authorization | `Authorization: xyz` | `Authorization: [REDACTED]` |
| ntfy tokens | `ntfy_token=abc` | `ntfy_token=[REDACTED]` |
| Webhook tokens | `webhook_token=xyz` | `webhook_token=[REDACTED]` |
| DB passwords | `db_pass=secret` | `db_pass=[REDACTED]` |
| MySQL passwords | `-p'secret'` | `-p'[REDACTED]'` |
| Home paths | `/home/john/` | `/home/[USER]/` |
| Secret dirs | `/etc/.a7x9m2k4/` | `/etc/[SECRET_DIR]/` |
| SHA256 hashes | `a1b2c3...` (64 chars) | `<SHA256>` |
| MD5 hashes | `d41d8c...` (32 chars) | `<HASH32>` |
| Machine IDs | `machine-id=abc123` | `machine-id=[REDACTED]` |
| rclone remotes | `rclone_remote=b2:bucket` | `rclone_remote=[REDACTED_REMOTE]` |

### Verify Redaction

Test that redaction is working:

```bash
# Source the logging library
source /etc/backupd/lib/logging.sh

# Test redaction
log_redact "password=secret123 token=tk_abc /home/myuser/path"
# Output: password=[REDACTED] token=[REDACTED] /home/[USER]/path
```

---

## Reporting Issues

### Step 1: Reproduce with Logging

```bash
# Run the failing command with TRACE level
sudo backupd -vv backup db
```

### Step 2: Export Sanitized Log

```bash
# Export for sharing (extra sanitization applied)
sudo backupd --log-export

# Output location
cat /tmp/backupd-issue-log.txt
```

### Step 3: Review Before Sharing

**Always review the exported log file before attaching to GitHub issues.**

The export applies extra sanitization, but you should verify:
- No hostnames you want to keep private
- No internal paths that reveal infrastructure
- No custom data in log messages

### Step 4: Create GitHub Issue

1. Go to [GitHub Issues](https://github.com/wnstify/backupd/issues)
2. Click "New Issue"
3. Include:
   - What you were trying to do
   - What happened instead
   - The exported log file content
4. Submit

### Exported Log Format

```markdown
# Backupd Debug Log
# Generated: 2025-01-15T03:00:00+00:00
# Version: 2.2.11

## System Information

```
OS: Ubuntu 24.04 LTS
Kernel: 6.8.0-90-generic
Arch: x86_64
Bash: 5.2.21(1)-release
Backupd: 3.1.0

openssl: OpenSSL 3.0.13
restic: restic 0.17.3
rclone: rclone v1.65.0
```

## Log Entries

```
[2025-01-15 03:00:01.123] [INFO] [cli_dispatch@cli.sh:15] CLI dispatch: backup db
[2025-01-15 03:00:01.456] [ERROR] [run_backup@backup.sh:78] Failed to connect
--- Stack Trace ---
  at run_backup() in backup.sh:78
  ...
```
```

---

## Common Problems

### Database Backup Fails

**Symptoms:**
```
[ERROR] [run_backup@backup.sh:45] mysqldump failed with exit code 1
```

**Solutions:**
1. Check MySQL is running: `systemctl status mysql`
2. Test connection: `mysql -u root -e "SHOW DATABASES"`
3. Check credentials: Verify socket auth or password

### rclone Upload Fails

**Symptoms:**
```
[ERROR] [upload_backup@backup.sh:120] rclone copy failed
```

**Solutions:**
1. Test rclone: `rclone ls remote:path`
2. Check credentials: `rclone config show`
3. Check network: `ping -c 3 google.com`

### Permission Denied

**Symptoms:**
```
[ERROR] Permission denied: /var/log/backupd.log
```

**Solutions:**
1. Run as root: `sudo backupd`
2. Check file permissions: `ls -la /var/log/backupd.log`
3. Check directory: `ls -la /var/log/`

### Decryption Fails

**Symptoms:**
```
[ERROR] [decrypt_backup@restore.sh:89] gpg: decryption failed: Bad session key
```

**Solutions:**
1. Verify encryption password
2. Check backup isn't corrupted: `file backup.tar.gz.gpg`
3. Try an older backup

### Out of Disk Space

**Symptoms:**
```
[ERROR] [create_archive@backup.sh:67] tar: Error writing to archive
```

**Solutions:**
1. Check space: `df -h`
2. Clean old files: `sudo apt clean`
3. Use --dry-run to check size first

---

## Advanced Debugging

### Enable Bash Tracing

For very deep debugging, enable bash's xtrace:

```bash
# Run with bash tracing
sudo bash -x /etc/backupd/backupd.sh backup db 2>&1 | tee /tmp/bash-trace.log
```

### Check Function Timing

With TRACE level, function timing is logged:

```bash
sudo backupd -vv backup db

# Look for timing in logs:
# [TRACE] EXIT run_backup (code=0, 1234ms)
```

### Manual Log Analysis

```bash
# Count errors
grep -c "\[ERROR\]" /var/log/backupd.log

# Find unique errors
grep "\[ERROR\]" /var/log/backupd.log | sort -u

# Find slow operations (TRACE level)
grep "EXIT.*ms)" /var/log/backupd.log | sort -t',' -k2 -n

# View specific session
SESSION_ID="20250115-030001-12345"
sed -n "/LOG SESSION: $SESSION_ID/,/LOG SESSION ENDED: $SESSION_ID/p" /var/log/backupd.log
```

### Environment Variables

| Variable | Effect |
|----------|--------|
| `BACKUPD_LOG_FILE=/path` | Override default log location |
| `BACKUPD_DEBUG=1` | Enable legacy debug mode |
| `NO_COLOR=1` | Disable colored output |

### Log Rotation

The structured log at `/var/log/backupd.log` grows over time. To manage size:

```bash
# Check current size
du -h /var/log/backupd.log

# Manual rotation (keeps last 1000 lines)
sudo tail -1000 /var/log/backupd.log > /tmp/backupd.log.new
sudo mv /tmp/backupd.log.new /var/log/backupd.log

# Or use logrotate (add to /etc/logrotate.d/backupd):
# /var/log/backupd.log {
#     weekly
#     rotate 4
#     compress
#     missingok
#     notifempty
# }
```

---

## CLI Reference

### Logging Flags

```bash
--log-file PATH    # Write logs to custom file
--verbose          # Enable DEBUG level (can stack: --verbose --verbose)
-vv                # Enable TRACE level (shorthand)
--log-export       # Export sanitized log to /tmp/backupd-issue-log.txt
```

### Legacy Debug Flags

```bash
--debug            # Enable legacy debug mode
--debug-status     # Show debug log status
--debug-export     # Export legacy debug log
```

### Environment Variables

```bash
BACKUPD_LOG_FILE=/path/to/log.txt  # Override log file location
BACKUPD_DEBUG=1                     # Enable legacy debug
```

---

## Support

- **Documentation**: [USAGE.md](USAGE.md)
- **GitHub Issues**: [github.com/wnstify/backupd/issues](https://github.com/wnstify/backupd/issues)
- **Website**: [backupd.io](https://backupd.io)

When reporting issues, always include:
1. Backupd version (`backupd --version`)
2. OS and version (`cat /etc/os-release`)
3. Exported log (`backupd --log-export`)

---

<p align="center">
  <strong>Backupd</strong> by <a href="https://backupd.io">Backupd</a>
</p>
