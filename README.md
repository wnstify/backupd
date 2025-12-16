# Backupd

<p align="center">
  <img src="https://img.shields.io/badge/version-2.1.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License">
  <img src="https://img.shields.io/badge/platform-Linux-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/shell-bash-4EAA25.svg" alt="Shell">
</p>

<p align="center">
  <strong>Secure, automated backup solution for web servers</strong><br>
  Database & files backup with encryption, cloud storage, and scheduling
</p>

<p align="center">
  <a href="https://backupd.io">Website</a> •
  <a href="#features">Features</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="USAGE.md">Usage Guide</a> •
  <a href="SECURITY.md">Security</a> •
  <a href="CHANGELOG.md">Changelog</a>
</p>

---

## Overview

Backupd is a comprehensive backup daemon for Linux servers running MySQL/MariaDB databases and web applications. It provides automated, encrypted backups to 40+ cloud storage providers via rclone.

### Key Highlights

- **Secure by Default** - AES-256 encryption with machine-bound keys
- **Multi-Panel Support** - Auto-detects 12+ hosting control panels
- **Cloud Storage** - Works with AWS S3, Google Cloud, Backblaze, Wasabi, and 40+ providers
- **Automated Scheduling** - systemd timers with configurable retention
- **Easy Recovery** - Interactive restore wizards for databases and files

---

## Features

### Backup Capabilities

| Feature | Description |
|---------|-------------|
| **Database Backup** | Full MySQL/MariaDB dumps with GPG encryption |
| **Files Backup** | Web application files with compression |
| **Incremental Support** | Via rclone's intelligent sync |
| **Retention Policies** | Automatic cleanup of old backups |
| **Integrity Verification** | SHA256 checksums for all backups |

### Security Features

| Feature | Description |
|---------|-------------|
| **AES-256 Encryption** | Military-grade encryption for all credentials |
| **Machine-Bound Keys** | Encryption keys tied to server hardware |
| **PBKDF2 Key Derivation** | 600,000 iterations (OWASP 2023 standard) |
| **Secure Passphrase Handling** | Hidden from process list |
| **Immutable Secrets** | Protected with `chattr +i` |

### Supported Hosting Panels

Backupd auto-detects and configures paths for:

- **Enhance** - `/var/www/*/public_html`
- **xCloud** - `/var/www/*/public_html`
- **RunCloud** - `/home/*/webapps/*`
- **Ploi** - `/home/*/*`
- **cPanel** - `/home/*/public_html`
- **Plesk** - `/var/www/vhosts/*/httpdocs`
- **CloudPanel** - `/home/*/htdocs/*`
- **CyberPanel** - `/home/*/public_html`
- **aaPanel** - `/www/wwwroot/*`
- **HestiaCP** - `/home/*/web/*/public_html`
- **Virtualmin** - `/home/*/public_html`
- **Custom** - User-defined paths

### Supported Applications

- WordPress (auto-detects site URL)
- Laravel (reads APP_URL from .env)
- Node.js (reads name from package.json)
- PHP applications
- Static sites
- Any web application

---

## Quick Start

### One-Line Installation

```bash
curl -fsSL https://raw.githubusercontent.com/wnstify/backupd/main/install.sh | sudo bash
```

### Manual Installation

```bash
# Clone the repository
git clone https://github.com/wnstify/backupd.git
cd backupd

# Run installer
sudo bash install.sh
```

### First Run

```bash
# Start the interactive setup wizard
sudo backupd
```

The setup wizard will guide you through:

1. **Backup Type** - Choose database, files, or both
2. **Panel Detection** - Auto-detect or specify paths
3. **Encryption** - Set your backup password
4. **Database Auth** - Configure MySQL/MariaDB access
5. **Cloud Storage** - Configure rclone remote
6. **Notifications** - Optional ntfy.sh alerts
7. **Retention** - Set backup retention policy
8. **Scheduling** - Configure automated backups

---

## Requirements

### System Requirements

- Linux server (Debian, Ubuntu, RHEL, CentOS, Arch)
- Bash 4.0+ (5.1+ recommended)
- Root access
- systemd (for scheduling)

### Required Dependencies

| Dependency | Minimum | Recommended | Purpose |
|------------|---------|-------------|---------|
| bash | 4.0 | 5.1+ | Script execution |
| openssl | 1.1.1 | 3.0.13+ | Encryption |
| gpg | 2.2.0 | 2.4.0+ | Backup encryption |
| rclone | 1.50.0 | 1.68.0+ | Cloud storage |
| mysql/mariadb | 5.7 | 8.0+ | Database backups |
| tar | 1.28 | 1.34+ | Archiving |
| curl | 7.64.0 | 8.4.0+ | Updates & notifications |

### Optional Dependencies

| Dependency | Purpose |
|------------|---------|
| pigz | Parallel compression (10-20x faster) |
| zstd | Modern compression (optional) |
| chattr | Immutable file protection |

---

## Usage

### Interactive Menu

```bash
sudo backupd
```

### Command Line Options

```bash
backupd --help          # Show help
backupd --version       # Show version
backupd --update        # Update to latest version
backupd --check-update  # Check for updates
```

### Common Operations

```bash
# Run database backup manually
sudo /etc/backupd/scripts/db_backup.sh

# Run files backup manually
sudo /etc/backupd/scripts/files_backup.sh

# Check backup status
sudo backupd  # Select "View status"

# Restore from backup
sudo backupd  # Select "Restore from backup"
```

For comprehensive usage instructions, see [USAGE.md](USAGE.md).

---

## Architecture

```
backupd/
├── backupd.sh          # Main entry point (286 lines)
├── install.sh          # One-line installer
├── lib/
│   ├── core.sh         # Colors, validation, panel detection
│   ├── crypto.sh       # Machine-bound encryption
│   ├── config.sh       # Configuration management
│   ├── generators.sh   # Backup script generation
│   ├── setup.sh        # Interactive wizard
│   ├── schedule.sh     # systemd timer management
│   ├── backup.sh       # Backup execution
│   ├── restore.sh      # Restore operations
│   ├── verify.sh       # Integrity verification
│   ├── status.sh       # Status display
│   └── updater.sh      # Auto-update system
├── CHANGELOG.md
├── DISCLAIMER.md
├── LICENSE
├── README.md
├── SECURITY.md
└── USAGE.md
```

### Data Flow

```
Setup → Secrets Storage → Config File
  ↓
Script Generation
  ↓
Backup Execution:
  ├── Database: SQL dump → Compress → GPG Encrypt → rclone Upload
  └── Files: tar Archive → Compress → rclone Upload → Checksum
  ↓
Scheduled via systemd timers
  ↓
Retention Cleanup → Notifications
```

---

## Security

Backupd implements multiple layers of security:

- **Machine-Bound Encryption** - Keys derived from `/etc/machine-id`
- **PBKDF2 Key Derivation** - 600,000 iterations (OWASP 2023)
- **AES-256-CBC** - For credential storage
- **GPG AES-256** - For backup encryption
- **Secure Passphrase Handling** - Uses `--passphrase-fd` (not visible in `ps`)
- **Immutable Files** - Secrets protected with `chattr +i`
- **MySQL Defaults File** - Credentials never on command line
- **systemd Hardening** - `PrivateTmp=yes` isolation

For detailed security information, see [SECURITY.md](SECURITY.md).

---

## Configuration

### Configuration File

Location: `/etc/backupd/.config`

```bash
DO_DATABASE=true
DO_FILES=true
PANEL_KEY=enhance
WEB_PATH_PATTERN=/var/www/*/public_html
WEBROOT_SUBDIR=public_html
RCLONE_REMOTE=myremote
RCLONE_DB_PATH=backups/db
RCLONE_FILES_PATH=backups/files
RETENTION_MINUTES=10080
RETENTION_DESC=7 days
```

### Secrets Storage

Location: `/etc/.{random_id}/` (hidden, immutable)

- `.s` - Salt (64 bytes)
- `.c1` - Encryption passphrase
- `.c2` - Database username
- `.c3` - Database password
- `.c4` - ntfy token (optional)
- `.c5` - ntfy URL (optional)

### Log Files

Location: `/etc/backupd/logs/`

- `db_logfile.log` - Database backup logs
- `files_logfile.log` - Files backup logs
- `verify_logfile.log` - Verification logs

Logs rotate automatically at 10MB (keeps 5 backups).

---

## Notifications

Backupd supports push notifications via [ntfy.sh](https://ntfy.sh):

- Backup start/success/failure
- Retention cleanup events
- Integrity verification results

Configure during setup or use any ntfy-compatible server.

---

## Troubleshooting

### Common Issues

**Backup fails with "No databases found"**
- Verify MySQL/MariaDB is running
- Check database credentials in setup

**Files backup shows "No sites found"**
- Verify web path pattern matches your setup
- Run setup wizard to reconfigure paths

**rclone upload timeout**
- Check network connectivity
- Verify rclone remote configuration: `rclone config`

**Permission denied errors**
- Ensure running as root: `sudo backupd`
- Check file permissions on backup directories

### Debug Mode

Check logs for detailed error information:

```bash
# View database backup log
sudo less /etc/backupd/logs/db_logfile.log

# View files backup log
sudo less /etc/backupd/logs/files_logfile.log
```

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Support

- **Website:** [backupd.io](https://backupd.io)
- **GitHub Issues:** [Report a bug](https://github.com/wnstify/backupd/issues)
- **Documentation:** [USAGE.md](USAGE.md) | [SECURITY.md](SECURITY.md)

---

## Disclaimer

This software is provided "as is" without warranty. Always create server snapshots before running backup/restore operations. See [DISCLAIMER.md](DISCLAIMER.md) for full terms.

---

<p align="center">
  <strong>Built with care by <a href="https://backupd.io">Backupd</a></strong><br>
  <sub>Secure backups made simple</sub>
</p>
