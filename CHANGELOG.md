# Changelog

All notable changes to Backupd will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.0.0] - 2025-12-13

### Changed

- **Major Rebranding** - Renamed from "Backup Management Tool" to "Backupd"
  - Main script: `backup-management.sh` → `backupd.sh`
  - Install directory: `/etc/backup-management/` → `/etc/backupd/`
  - Command: `backup-management` → `backupd`
  - Systemd units: `backup-management-*` → `backupd-*`
  - GitHub repository: `wnstify/backup-management-tool` → `wnstify/backupd`
  - Lock files: `backup-management-*.lock` → `backupd-*.lock`

### Breaking Changes

- **Installation path changed** - New installs use `/etc/backupd/`
- **Command changed** - Use `sudo backupd` instead of `sudo backup-management`
- **Systemd units renamed** - All `backup-management-*` units now `backupd-*`
- **Existing users** - Must uninstall old version before installing v2.0.0

### Notes

- This is a clean break - no migration from v1.x installations
- All functionality remains the same, only naming changed
- Historical changelog entries below retain original names for accuracy

---

## [1.6.2] - 2024-12-12

### Fixed

- **Ntfy notifications missing Title header** - Added `-H "Title: $notification_title"` to curl commands in `lib/verify.sh`
- **Files verification exits early** - Fixed SIGPIPE causing early exit during files backup verification due to `pipefail`

### Technical

- Added `|| true` to `tar|head` pipeline in files verification to prevent SIGPIPE exit
- Files backups are not encrypted (by design) - only database backups use GPG encryption

---

## [1.6.1] - 2024-12-12

### Fixed

- **Critical: Script exits after banner** - Fixed `show_update_banner()` causing script to exit when no update available due to `set -euo pipefail`
- **Missing updater.sh in installation** - Added `updater.sh` to `LIB_MODULES` array in `install.sh`

### Technical

- Added `|| true` after `check_for_updates_silent` command substitution to prevent exit on non-zero return
- Changed `show_update_banner()` to always return 0 (display function, not a check)

---

## [1.6.0] - 2024-12-12

### Changed

- **Rebranding** - Updated from Webnestify to Backupd
- **New Domain** - Website now at backupd.io
- **Updated Copyright** - License and documentation updated to Backupd

### Notes

- Email addresses remain @webnestify.cloud for support continuity
- No functional changes to backup/restore operations

---

## [1.5.0] - 2024-12-12

### Added

- **Built-in Auto-Update System**
  - New `lib/updater.sh` module for update functionality
  - Checks GitHub releases API for latest version
  - One-click update from menu (press `U`) or command line (`--update`)
  - Silent version check on startup (once per 24 hours)
  - Update banner shown when new version available
  - SHA256 checksum verification of downloaded releases
  - Automatic backup of current installation before update
  - Automatic rollback if update fails
  - Previous version kept at `{install_dir}.backup`

- **New CLI Flags**
  - `--help, -h` - Show help message
  - `--version, -v` - Show version information
  - `--update` - Check for and install updates
  - `--check-update` - Check for updates without installing

### Changed

- **Main Menu**
  - Added `U) Update tool` option
  - Changed exit from `8` to `0` for consistency
  - Update banner displays at top when update available

- **Unconfigured Menu**
  - Added `U) Update tool` option (can update before setup)
  - Changed exit from `2` to `0`

### Technical

- Version comparison uses semantic versioning
- Update check results cached for 24 hours in `/tmp/.backup-mgmt-update-check`
- Downloads from GitHub releases: `https://github.com/wnstify/backup-management-tool/releases`
- Expects release archives named `backup-management-v{version}.tar.gz`
- Expects checksums in `SHA256SUMS` file alongside release

---

## [1.4.2] - 2024-12-11

### Added

- **Ploi Panel Support**
  - Added Ploi to supported panels list
  - Path pattern: `/home/*/*` (domain folders directly in user home)
  - Detection via `ploi` user in `/etc/passwd`
  - Setup wizard now asks for database username (defaults to `ploi` when Ploi detected)

### Changed

- **Database Authentication Step**
  - Setup wizard now prompts for database username (was hardcoded to `root`)
  - Panel-aware defaults: Ploi defaults to `ploi`, others default to `root`
  - Supports any MySQL/MariaDB user with appropriate permissions

---

## [1.4.1] - 2024-12-11

### Added

- **Database Restore Verification Prompt**
  - After database restore, user must verify their site is working before cleanup
  - Type `Yes, I checked the website` to confirm site works and clean up backup files
  - Type `N` to save SQL files to `/root/db-restore-recovery-TIMESTAMP/` for manual recovery
  - Invalid responses also save files as a precaution
  - Prevents accidental loss of backup files if restore causes issues

### Fixed

- **Database Restore Safety**
  - Previously, downloaded backup files were deleted immediately after restore
  - Now SQL files are preserved until user confirms site is working
  - If site has issues, user can access saved SQL files for manual recovery

---

## [1.4.0] - 2024-12-11

### Added

- **Multi-Panel Support**
  - Auto-detects installed hosting panel (Enhance, xCloud, RunCloud, Ploi, cPanel, Plesk, CloudPanel, CyberPanel, aaPanel, HestiaCP, Virtualmin)
  - Panel presets with correct web path patterns for each panel
  - Custom path option for non-standard setups
  - New setup step (Step 1b) for web application paths configuration

- **Multi-Application Support**
  - No longer limited to WordPress - backs up any web application
  - Smart site naming that detects app type:
    - WordPress: Uses `wp option get siteurl` or `WP_HOME` from wp-config.php
    - Laravel: Uses `APP_URL` from .env file
    - Node.js: Uses `name` from package.json
    - Generic: Falls back to folder name
  - Full backup support (no excludes) for disaster recovery

- **Panel Detection Functions**
  - `detect_panel()` - Auto-detects installed panel
  - `detect_panel_by_service()` - Checks for panel services
  - `detect_panel_by_user()` - Checks for panel-specific users
  - `detect_panel_by_files()` - Checks for panel-specific files
  - `get_site_name()` - Smart site naming for different app types

### Changed

- **Backup Script Architecture**
  - Uses configurable `WEB_PATH_PATTERN` instead of hardcoded `/var/www/*`
  - Uses configurable `WEBROOT_SUBDIR` for panels with subdirectory structures
  - Site scanning now uses glob pattern matching for flexibility
  - Backup script logs the pattern being used for transparency

- **Restore Script Improvements**
  - Removed hardcoded path dependencies
  - Prompts user for restore path when metadata is missing
  - Better handling of old vs new backup formats
  - User-configurable base path for legacy backups

- **Configuration**
  - New config values: `PANEL_KEY`, `WEB_PATH_PATTERN`, `WEBROOT_SUBDIR`
  - Setup wizard now includes panel/path configuration step

### Technical

- Panel definitions stored in `PANEL_DEFINITIONS` associative array
- Each panel has: name, path pattern, webroot subdirectory, detection method
- Supported panels:
  - Enhance: `/var/www/*/public_html` (webroot: `public_html`) - detected via `appcd` service
  - xCloud: `/var/www/*/public_html` (webroot: `public_html`) - detected via `xcloud` user
  - RunCloud: `/home/*/webapps/*` (webroot: `.`) - detected via `runcloud` user
  - Ploi: `/home/*/*` (webroot: `.`) - detected via `ploi` user
  - cPanel: `/home/*/public_html` (webroot: `.`)
  - Plesk: `/var/www/vhosts/*/httpdocs` (webroot: `.`)
  - CloudPanel: `/home/*/htdocs/*` (webroot: `.`)
  - CyberPanel: `/home/*/public_html` (webroot: `.`)
  - aaPanel: `/www/wwwroot/*` (webroot: `.`)
  - HestiaCP: `/home/*/web/*/public_html` (webroot: `public_html`)
  - Virtualmin: `/home/*/public_html` (webroot: `.`)
  - Custom: User-defined pattern

---

## [1.3.2] - 2024-12-11

### Fixed

- **Enhance Panel / Overlay Container Compatibility**
  - Complete rewrite of backup/restore architecture for containerized hosting panels
  - Backups now archive **contents inside** `public_html` instead of the entire site directory
  - Restores extract **into** existing `public_html` directory, preserving container overlay
  - Fixes "empty directory" issue where restored files weren't visible to users in overlay containers
  - Backward compatible: automatically detects and handles old backup format

### Added

- **Restore Path Metadata**
  - New `.restore-path` metadata file uploaded with each backup
  - Stores exact restore path for reliable restore operations
  - Eliminates guesswork when matching backup to site directory

### Changed

- **Backup Format**
  - Archives now contain `./` (contents) instead of `dirname/` (full directory)
  - Ownership now set based on target directory owner after extraction
  - Removes dependency on stored UIDs which may become invalid after user recreation

---

## [1.3.1] - 2024-12-11

### Fixed

- **Files Restore Script**
  - Fixed restore to work with per-site archives (each site has its own backup file)
  - Restore now groups backups by site name and shows latest backup for each
  - Supports restoring multiple sites individually or all at once
  - Properly extracts directory name from archive instead of assuming single archive

---

## [1.3.0] - 2024-12-11

### Added

- **Modular Architecture**
  - Refactored monolithic 3,200-line script into 10 separate modules
  - New `lib/` directory contains all functional modules
  - Each module handles a specific responsibility (core, crypto, config, etc.)
  - Easier to maintain, test, and extend

### Changed

- **Code Organization**
  - `core.sh` - Colors, print functions, input validation, helper utilities
  - `crypto.sh` - Encryption, secrets, key derivation functions
  - `config.sh` - Configuration file read/write operations
  - `generators.sh` - Script generation for backup/restore/verify
  - `status.sh` - Status display and log viewing
  - `backup.sh` - Backup execution and cleanup functions
  - `verify.sh` - Backup integrity verification
  - `restore.sh` - Restore execution functions
  - `schedule.sh` - Schedule management and systemd timer setup
  - `setup.sh` - Interactive setup wizard

- **Main Script**
  - `backup-management.sh` reduced from 3,200 to ~210 lines
  - Sources all modules from `lib/` directory
  - Handles symlink resolution for correct lib path
  - Cleaner entry point with only main menu and install/uninstall logic

- **Installer**
  - Now downloads all library modules individually
  - Creates `lib/` directory in installation path
  - Shows download progress for each module
  - Fails gracefully if any module download fails

### Technical

- Modules are sourced in dependency order
- Symlink resolution ensures lib path works when called via `/usr/local/bin/backup-management`
- All module functions remain globally accessible after sourcing
- No functional changes to backup/restore/verify operations

---

## [1.2.0] - 2024-12-09

### Added

- **SHA256 Checksums**
  - Every backup now generates a `.sha256` checksum file
  - Checksum uploaded alongside backup to cloud storage
  - Enables verification of backup integrity

- **Verify Backup Integrity**
  - New menu option: "Run backup now" → "Verify backup integrity"
  - Downloads latest backup and verifies checksum
  - Tests decryption (for database backups)
  - Tests archive extraction (for files backups)
  - Lists archive contents without restoring
  - Sends notification with verification result

- **Scheduled Integrity Check (Optional)**
  - New menu option: "Manage schedules" → "Set/change integrity check schedule"
  - Automatic weekly/monthly verification of backups
  - Runs non-interactively using stored encryption passphrase
  - Logs results to `/etc/backup-management/logs/verify_logfile.log`
  - Sends notification with pass/fail status
  - Schedule presets: Weekly, bi-weekly, monthly, daily, or custom

- **Checksum Verification on Restore**
  - Restore scripts now verify checksum before restoring
  - Warning shown if checksum mismatch detected
  - Option to continue anyway or abort

### Changed

- Manage Schedules menu now has 9 options (added integrity check schedule)
- Retention cleanup also deletes corresponding `.sha256` files
- Files backup listing excludes `.sha256` files

### Security

- Backups can now be verified for tampering/corruption
- End-to-end integrity verification from upload to restore
- Scheduled verification catches silent backup corruption early

---

## [1.1.1] - 2024-12-09

### Added

- **Retention Cleanup Notifications**
  - Push notification when old backups are removed
  - Warning notification if cleanup encounters errors
  - Failure notification if cutoff time calculation fails
  - Notifications sent via ntfy (if configured)

### Changed

- Retention cleanup now reports "No old backups to remove" when nothing to clean
- Notifications include count of removed backups and errors

---

## [1.1.0] - 2024-12-09

### Added

- **Retention Policy System**
  - Configurable retention periods (1 minute to 365 days, or disabled)
  - Automatic cleanup of old backups after each backup run
  - Manual cleanup option via "Run backup now" → "Run cleanup now"
  - Retention policy display in status page
  - Change retention policy via "Manage schedules" menu

- **Testing Options**
  - 1 minute retention for quick testing
  - 1 hour retention for extended testing

- **Log Rotation**
  - Automatic log rotation at 10MB
  - Keeps 5 backup log files
  - Prevents disk space issues from growing logs

- **Retention Error Logging**
  - Cleanup errors now logged instead of silently ignored
  - Shows specific error messages from rclone
  - Summary shows both success count and error count

- **Run Cleanup Now**
  - Manual trigger for retention cleanup
  - Shows cutoff time and files being deleted
  - Works independently of backup schedule

### Changed

- Setup wizard now includes Step 6: Retention Policy
- Schedule management menu expanded with retention option
- Status page now displays current retention policy
- Backup scripts regenerated when retention policy changes

### Security

- **MySQL Password Protection**
  - Passwords no longer visible in `ps aux` output
  - Uses `--defaults-extra-file` with secure temp auth file
  - Auth file cleaned up on exit (including on errors)

- **Fixed Lock Files**
  - Lock files now in fixed location (`/var/lock/backup-management-*.lock`)
  - Properly prevents concurrent backup/restore operations
  - Restore scripts wait up to 60 seconds if backup is running

- **Input Validation**
  - Added `validate_path()` - blocks shell metacharacters and path traversal
  - Added `validate_url()` - validates HTTP/HTTPS URLs
  - Added `validate_password()` - enforces minimum 8 characters
  - Config values are escaped to prevent injection

- **Disk Space Checks**
  - Database backups require 1GB free in /tmp
  - Files backups require 2GB free in /tmp
  - Prevents failed backups due to full disk

- **Timeout Protection**
  - rclone uploads: 30 minute timeout with retries
  - rclone verification: 60 second timeout
  - curl notifications: 10 second timeout
  - Prevents indefinite hangs on network issues

- **Improved Cleanup**
  - All temp files cleaned up on EXIT/INT/TERM signals
  - MySQL auth files always removed
  - Salt file (.s) now properly unlocked during uninstall

- **umask 077**
  - All scripts now set restrictive umask
  - Temp files created with secure permissions

### Fixed

- Lock file bug where each run created new temp directory (lock was useless)
- `chattr` now only affects specific secret files, not all dotfiles
- `backup_name` variable scope bug in files restore
- Uninstall now properly unlocks `.s` salt file before removal
- Installer works when piped from curl (reads from /dev/tty)

---

## [1.0.0] - 2024-12-08

### Added

- Initial release
- Database backup with GPG encryption
- Web application files backup with compression
- Secure credential storage (AES-256, machine-bound)
- Systemd timer scheduling
- Interactive setup wizard
- Database restore wizard
- Files restore wizard
- ntfy.sh notification support
- Detailed logging
- One-line installer

### Security

- Machine-bound encryption keys
- Random hidden directory for secrets
- Immutable file flags (chattr +i)
- No plain-text credential storage

---

## Version History Summary

| Version | Date | Highlights |
|---------|------|------------|
| 1.6.2 | 2024-12-12 | Fixed ntfy notifications and SIGPIPE in files verification |
| 1.6.1 | 2024-12-12 | Fixed script exit after banner, missing updater.sh in install |
| 1.6.0 | 2024-12-12 | Backupd rebranding, new domain backupd.io |
| 1.5.0 | 2024-12-12 | Built-in auto-update system, CLI flags |
| 1.4.2 | 2024-12-11 | Ploi panel support, configurable database username |
| 1.4.1 | 2024-12-11 | Database restore verification prompt, safer restore process |
| 1.4.0 | 2024-12-11 | Multi-panel support, multi-app backup, smart site naming |
| 1.3.2 | 2024-12-11 | Enhance panel / overlay container compatibility |
| 1.3.1 | 2024-12-11 | Fixed files restore for per-site archives |
| 1.3.0 | 2024-12-11 | Modular architecture, code refactoring |
| 1.2.0 | 2024-12-09 | Checksums, backup integrity verification |
| 1.1.1 | 2024-12-09 | Retention cleanup notifications |
| 1.1.0 | 2024-12-09 | Retention policy, security hardening, log rotation |
| 1.0.0 | 2024-12-08 | Initial release |

---

<p align="center">
  <strong>Built with ❤️ by <a href="https://backupd.io">Backupd</a></strong>
</p>