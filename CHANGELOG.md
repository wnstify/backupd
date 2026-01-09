# Changelog

All notable changes to Backupd will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [3.2.1] - 2026-01-09

### Added

- **Schedule Conflict Auto-Suggest (BACKUPD-033)** — Intelligent alternative time suggestions when conflicts detected
  - `parse_simple_oncalendar()` — Extracts hour/minute from OnCalendar expressions
  - `find_used_time_slots()` — Discovers occupied time slots across all jobs
  - `suggest_alternative_times()` — Generates conflict-free alternative schedules
  - Suggests ±30min, ±1hr, ±2hr alternatives automatically
  - Filters suggestions to exclude already-used time slots
  - JSON output includes separate `warnings` and `suggestions` arrays

- **Bulk Schedule Operations (BACKUPD-034)** — Set or disable schedules across all jobs at once
  - `backupd job schedule --all db '*-*-* 02:00:00'` — Set database backup schedule for all jobs
  - `backupd job schedule --all files --disable` — Disable files backup for all jobs
  - `create_all_job_schedules()` — Bulk schedule creation function
  - `disable_all_job_schedules()` — Bulk schedule disabling function
  - JSON output with operation details and per-job results
  - Follows `regenerate_all_job_scripts()` pattern for consistency

- **Schedule Templates/Presets (BACKUPD-035)** — Reusable schedule configurations
  - 12 built-in templates: hourly, every_2h, every_6h, daily_midnight, daily_1am, daily_2am, daily_3am, daily_4am, weekly_sun_2am, weekly_sat_3am, biweekly, monthly
  - `backupd schedule templates` — List all available templates
  - `backupd schedule templates show <name>` — Show template details
  - `backupd job schedule <job> <type> --template <name>` — Apply template to job
  - `SCHEDULE_TEMPLATES` associative array in lib/schedule.sh
  - Helper functions: `get_template_schedule()`, `get_template_display()`, `get_template_description()`, `detect_template_name()`, `list_schedule_templates()`

### Changed

- **`check_schedule_conflicts()`** — Now includes auto-suggest functionality
  - Outputs suggested alternatives after conflict warnings
  - Maintains backward compatibility (still advisory, returns 0)

- **`--all` flag in `cli_job_schedule()`** — Extended to support SET and DISABLE modes
  - Original SHOW behavior preserved when no backup_type specified
  - New SET mode: `--all <type> <schedule>`
  - New DISABLE mode: `--all <type> --disable`

### Technical

- **lib/jobs.sh** — Added 4 new functions for conflict auto-suggest (~135 lines)
- **lib/jobs.sh** — Added 2 new functions for bulk operations (~100 lines)
- **lib/schedule.sh** — Added SCHEDULE_TEMPLATES and 5 helper functions (~75 lines)
- **lib/cli.sh** — Extended cli_job_schedule() with --template flag and bulk operation modes (~160 lines)
- **lib/cli.sh** — Added cli_schedule_templates() with list/show subcommands (~105 lines)

---

## [3.2.0] - 2026-01-09

### Added

- **Per-Job Scheduling via CLI** — Independent backup schedules for each job without interactive menu
  - `backupd job schedule <job_name> <type> <schedule>` — Set backup schedule via CLI
  - Support for all 4 backup types: `db`, `files`, `verify`, `verify-full`
  - `--show` flag displays current schedule(s) for a job
  - `--disable` flag stops timer but preserves config for re-enabling
  - `--json` flag for automation and API integration
  - `--all` flag shows cross-job schedule overview
  - Schedules persisted to `/etc/backupd/jobs/{jobname}/job.conf` as `SCHEDULE_{TYPE}`

- **Schedule Validation & Conflict Detection**
  - `validate_schedule_format()` — Validates OnCalendar expressions before timer creation
  - `check_schedule_conflicts()` — Warns about overlapping schedules across jobs
  - `list_all_job_schedules()` — Cross-job schedule overview

- **Interactive Schedule Menu**
  - New `schedule_interactive_menu()` for non-CLI users
  - Guided schedule selection with preset options
  - Accessible via `backupd job configure <name>`

- **FlashPanel Support** — Full auto-detection support for FlashPanel hosting control panel
  - Non-isolated mode: `/home/flashpanel/{site}` — all sites under single flashpanel user
  - Isolated mode: `/home/{user}/{site}` — each site has its own system user
  - Automatic mode detection based on `/home/flashpanel/` directory presence
  - Service detection via `flashpanel.service` or `/root/.flashpanel/agent/flashpanel` binary
  - Panel selection menu options for manual mode selection
  - Mode override prompt during setup for edge cases

- **Panel Detection Enhancements**
  - `detect_flashpanel_isolation_mode()` — New helper function to detect FlashPanel isolation mode
  - FlashPanel service detection in `detect_panel_by_service()` with binary fallback
  - Interactive mode switching when FlashPanel is detected

- **Comprehensive Supported Panels Documentation**
  - New "Supported Panels" section in USAGE.md with complete panel reference
  - Table of all 14 supported panels with directory patterns and detection methods
  - Dedicated FlashPanel Support subsection with mode explanations and examples

### Changed

- **Panel Selection Menu** — Added FlashPanel (standard) and FlashPanel (isolated) options
  - Menu options 12 and 13 for FlashPanel modes
  - Shifted Virtualmin to option 14, Custom path to option 15
  - Updated case statement mappings

- **Setup Wizard** — Enhanced FlashPanel handling
  - Shows detected isolation mode with path pattern
  - Prompts user to confirm or switch modes
  - Clear messaging: "FlashPanel detected (non-isolated mode)" or "(isolated mode)"

- **Job Management** — Enhanced schedule visibility
  - `backupd job show <name>` now includes "Schedules:" section
  - Timer status (active/inactive) displayed for each schedule type

### Fixed

- **enable_job() Timer Recreation** — Re-enabling a disabled job now recreates timers from stored configuration
  - Reads SCHEDULE_DB, SCHEDULE_FILES, SCHEDULE_VERIFY, SCHEDULE_VERIFY_FULL from config
  - Automatically calls `create_job_timer()` for each non-empty schedule

### Technical

- **Multi-Schedule Implementation (Phase A+B+C):**
  - `lib/cli.sh` — Added `cli_job_schedule()` function (~175 lines)
  - `lib/cli.sh` — Updated `cli_job_show()` with schedules section
  - `lib/cli.sh` — Updated `cli_job_help()` with schedule command documentation
  - `lib/jobs.sh` — Added `validate_schedule_format()` function
  - `lib/jobs.sh` — Added `check_schedule_conflicts()` function
  - `lib/jobs.sh` — Added `list_all_job_schedules()` function
  - `lib/jobs.sh` — Fixed `enable_job()` to recreate timers from config
  - `lib/schedule.sh` — Added `schedule_interactive_menu()` function

- **FlashPanel Implementation:**
  - `lib/core.sh` — Added `flashpanel` and `flashpanel-isolated` to PANEL_DEFINITIONS array
  - `lib/core.sh` — Added `detect_flashpanel_isolation_mode()` function
  - `lib/core.sh` — Added FlashPanel detection block in `detect_panel_by_service()`
  - `lib/setup.sh` — Added FlashPanel menu options and mode override prompt
  - `USAGE.md` — Added Supported Panels section with FlashPanel documentation
  - `README.md` — Added FlashPanel to multi-panel support list

- **CLI Exit Codes for Schedule Command:**
  - 0: Success
  - 2: Usage error (missing arguments)
  - 3: Job not found
  - 4: Invalid backup type
  - 5: Timer creation failed

- **Panel Definitions Added:**
  | Panel Key | Display Name | Path Pattern | Webroot | Detection |
  |-----------|--------------|--------------|---------|-----------|
  | `flashpanel` | FlashPanel | `/home/flashpanel/*` | `.` | Service |
  | `flashpanel-isolated` | FlashPanel (Isolated) | `/home/*/*` | `.` | Service |

- **Commits:** BACKUPD-008 through BACKUPD-032 (25 total)

---

## [3.1.4] - 2026-01-09

### Added

- **Multi-distribution package manager support** — Automatic detection and installation of dependencies across 6 package managers
  - apt (Debian, Ubuntu, Mint, Pop!_OS, Kali, Raspbian)
  - dnf (Fedora, RHEL 8+, Rocky Linux, AlmaLinux, Amazon Linux)
  - yum (RHEL 7, CentOS 7, Oracle Linux)
  - pacman (Arch Linux, Manjaro, EndeavourOS, Artix)
  - apk (Alpine Linux)
  - zypper (openSUSE, SLES)

- **wget fallback support** — All HTTP operations now work with either curl or wget (BACKUPD-007)
  - `download_to_file()` helper with curl/wget fallback
  - `fetch_url()` helper with curl/wget fallback
  - Updated `curl_with_retry()` with wget fallback
  - Updated `check_network()` with wget fallback
  - Updated `get_latest_version()` with wget fallback

- **Explicit dependency checks** — Added sha256sum and base64 to required commands validation

### Improved

- **Unsupported distribution handling** — Graceful warnings with manual install instructions instead of failures (BACKUPD-005)
- **Error messages** — Distro-appropriate install hints via `get_install_hint()` function (BACKUPD-006)
- **bzip2 installation** — Now uses package manager abstraction for RHEL-family distros (BACKUPD-002)
- **unzip installation** — Cross-distribution support via package manager abstraction (BACKUPD-004)
- **argon2 installation** — Works across all 6 supported package managers (BACKUPD-003)
- **systemd detection** — Improved messaging when systemd/systemctl not available

### Technical

- Added `detect_package_manager()` function with caching
- Added `pkg_install()` abstraction for cross-distro package installation
- Added `pkg_update()` with run-once semantics
- Added `get_install_hint()` for user-friendly error messages
- Removed hardcoded `apt-get` calls in favor of package manager abstraction

---

## [3.1.3] - 2026-01-09

### Fixed

- **Function stack validation** - Log mismatch when function exit doesn't match expected name (BUG-LOG-001)
- **Password redaction** - Enhanced regex for quoted passwords with spaces (BUG-LOG-002)
- **Session ID precision** - Added subsecond precision to debug session IDs (BUG-LOG-004)
- **Path validation** - Allow bracket characters in file paths (BUG-CORE-005)
- **Network check order** - Try curl before ICMP ping (often blocked) (BUG-CORE-001)
- **Disk space warnings** - Improved logging when df parsing fails (BUG-CORE-004)
- **Bash-specific docs** - Document compgen usage requirement (BUG-CORE-003)
- **chattr logging** - Log debug message when immutable flag fails (BUG-CRYPTO-002)
- **Salt file atomicity** - Use atomic write for salt generation (BUG-CRYPTO-004)
- **Machine ID persistence** - Create persistent fallback when /etc/machine-id missing (BUG-CRYPTO-003)
- **sed escaping** - Escape special characters in sed replacements (BUG-GEN-002)
- **INSTALL_DIR placeholder** - Use placeholder instead of hardcoded path (BUG-GEN-003)
- **JSON escaping** - Escape special chars in history JSON fields (BUG-VERIFY-004)
- **Cross-platform dates** - Python fallback for GNU date -d (BUG-VERIFY-002, BUG-BACKUP-001)
- **History rotation lock** - Add flock to prevent race conditions (BUG-VERIFY-003)
- **Restore cleanup trap** - Clean temp files on interrupt (BUG-BACKUP-003)
- **Error output sanitization** - Capture restic errors to variable (BUG-BACKUP-005)
- **Empty schedule display** - Show "(unknown)" for missing schedules (BUG-SCHEDULE-001)
- **Cron removal pattern** - More precise grep pattern (BUG-SCHEDULE-002)
- **Schedule documentation** - Document RandomizedDelaySec behavior (BUG-SCHEDULE-003)
- **Service regeneration** - Always regenerate service files (BUG-SCHEDULE-004)
- **Temp file cleanup** - Add trap for backup temp files (BUG-CLI-001)
- **Argument validation** - Validate --backup-id has value (BUG-CLI-002)
- **Array re-declaration** - Unset before re-declaring associative arrays (BUG-CLI-004)
- **Symlink verification** - Check symlink target before reinstalling (BUG-CORE-002)

### Breaking Changes

- **verify command** - Removed `-q` shortcut; use `--quick` instead (BUG-CLI-003)

---

## [3.1.2] - 2026-01-08

### Fixed

- **CRITICAL: Missing lib modules in dev-update** - Added 4 missing modules (`restic.sh`, `history.sh`, `jobs.sh`, `migration.sh`) to `lib_files` array in `do_dev_update()` (BUG-001)

### Security

- **Path traversal protection** - Added archive validation before tar extraction to prevent malicious path escapes (BUG-002)
- **Symlink attack prevention** - Moved update cache from `/tmp/` to `~/.cache/backupd/` (BUG-004)
- **TLS 1.2+ enforcement** - Added `--tlsv1.2` to all curl commands (BUG-009)
- **Regex injection prevention** - Changed checksum lookup to use `grep -F` for fixed string matching (BUG-008)

### Improved

- **Network reliability** - Replaced ICMP ping with HTTP check to `api.github.com` for connectivity (BUG-006)
- **Download resilience** - Added `curl_with_retry()` helper with 3 attempts and exponential backoff (BUG-012)
- **Backup safety** - Added return code checking to `backup_current_version()` to prevent updates without valid backup (BUG-005)
- **Safe rollback** - Changed rollback to rename-before-delete pattern to prevent installation loss on failure (BUG-011)
- **Atomic updates** - Implemented staging directory approach for atomic update application (BUG-010)
- **Dev update validation** - Added syntax check for all lib files before completing dev updates (BUG-003, BUG-016)
- **JSON parsing** - Added jq-based parsing with regex fallback for GitHub API responses (BUG-013)
- **Download timeouts** - Added `--max-time` to checksum and dev downloads (BUG-014)
- **Race condition prevention** - Added flock to prevent multiple simultaneous update checks (BUG-015)
- **Version comparison** - Fixed handling of pre-release versions and empty strings (BUG-007, BUG-017)
- **Error logging** - Added debug logging for API failures in `get_latest_version()` (BUG-018)

---

## [3.1.1] - 2026-01-07

### Fixed

- **Installer missing v3.1.0 modules** - Added `history.sh`, `jobs.sh`, `migration.sh` to installer's `LIB_MODULES` array
- **Missing history.sh source** - Added `history.sh` to backupd.sh library sources

---

## [3.1.0] - 2026-01-07

### Added

- **Multi-Job Support** - Manage multiple independent backup jobs
  - Each job has its own configuration, scripts, and schedules
  - Jobs can target different remote destinations
  - All jobs share the same database credentials and restic password
  - New CLI: `backupd job {list|show|create|delete|clone|run|enable|disable}`

- **Job Management Commands**
  - `backupd job list` - List all configured jobs
  - `backupd job show <name>` - Display job configuration and status
  - `backupd job create <name>` - Create a new backup job
  - `backupd job delete <name>` - Delete a job and its timers
  - `backupd job clone <src> <dst>` - Clone job configuration
  - `backupd job run <name> [db|files|all]` - Run backup for specific job
  - `backupd job enable/disable <name>` - Enable or disable a job
  - `backupd job regenerate <name>` - Regenerate backup scripts
  - `backupd job timers <name>` - Show systemd timers for a job

- **Automatic Migration** - Existing single-config installations automatically migrate to "default" job on first run

- **Backup History Command** - View operation history via CLI
  - `backupd history` - Show last 20 operations
  - `backupd history db -n 50` - Filter by type, control count
  - `backupd history verify` - View verification history
  - `backupd history --json` - JSON output for APIs/scripts
  - Types: `db`, `files`, `backup`, `verify`, `verify_quick`, `verify_full`, `cleanup`
  - Storage: `/etc/backupd/history.jsonl` (auto-rotating, max 50 records)

- **Job-Aware History** - History tracks which job performed each operation
  - New `job` field in all history records
  - `get_job_history()` - Filter history by job name
  - `get_history_by_jobs()` - Summary statistics per job

### Changed

- **Directory Structure** - Jobs stored in `/etc/backupd/jobs/{jobname}/`
  - `job.conf` - Job-specific configuration
  - `scripts/` - Generated backup scripts for the job

- **Backward Compatibility** - Existing commands work on "default" job
  - `backupd backup db` uses default job configuration
  - Legacy timer names preserved for default job

---

## [3.0.0] - 2026-01-06

### Changed

- **Complete Backup Engine Rewrite** - Replaced GPG+tar+pigz with restic
  - Restic provides content-addressable deduplication (80-85% storage savings)
  - Built-in AES-256 encryption (no separate GPG dependency)
  - Built-in compression and verification
  - Repository-based backup model with snapshots

- **Retention Policy** - Now uses days instead of minutes
  - Config key changed: `RETENTION_MINUTES` -> `RETENTION_DAYS`
  - Cleaner configuration (e.g., `RETENTION_DAYS="30"` instead of `RETENTION_MINUTES="43200"`)
  - Options: 7, 14, 30, 60, 90, 365 days

- **Encryption Password** - Renamed to "Repository Password"
  - More accurate terminology for restic's password model
  - Same encryption strength (AES-256)

- **Setup Wizard Simplified**
  - Removed testing retention options (1 min, 1 hour)
  - Removed "No automatic cleanup" option
  - Streamlined retention selection

### Added

- **New `lib/restic.sh` Module** - Dedicated restic operations
  - `init_restic_repo()` - Initialize restic repository
  - `run_restic_backup()` - Execute backup with progress
  - `run_restic_forget()` - Apply retention policy
  - `run_restic_check()` - Verify repository integrity
  - `list_restic_snapshots()` - List available backups
  - `restore_restic_snapshot()` - Restore from snapshot

- **Restic Repository Initialization**
  - Automatic during setup wizard
  - Creates repository on remote storage
  - Password-protected with user's encryption password

- **Built-in Verification**
  - `restic check` validates repository integrity
  - No separate checksum files needed
  - Faster verification than download+decrypt

### Removed

- **GPG Dependency** - No longer required for backup encryption
  - Restic handles all encryption internally
  - GPG may still be installed for other purposes

- **pigz Dependency** - No longer required for compression
  - Restic handles compression internally
  - More efficient deduplication-aware compression

- **Legacy tar-based Backup Scripts**
  - Old backup format no longer generated
  - Restore still supports legacy format for migration

- **Testing Retention Options**
  - Removed 1 minute and 1 hour testing options
  - Production-focused retention choices only

- **No Automatic Cleanup Option**
  - All installations now have retention policy
  - Prevents unbounded storage growth

### Migration

- **Existing v2.x installations**: Run setup wizard to migrate to restic
- **Existing backups**: Legacy tar.gz.gpg backups remain accessible for restore
- **New backups**: All new backups use restic format

### Technical

- New config value: `RESTIC_REPO_INITIALIZED` (true/false)
- Backup script generation updated for restic commands
- Generated scripts embed restic functions from lib/restic.sh
- Repository password stored using existing secure credential system

---

## [2.3.0] - 2026-01-06

### Added

- **Pushover Push Notifications** - Third notification channel alongside ntfy and webhooks
  - Native support for [Pushover](https://pushover.net) push notifications
  - Configure via interactive menu (Notifications → Configure Pushover)
  - Configure via CLI: `backupd notifications set-pushover --user-key KEY --api-token TOKEN`
  - Test notifications: `backupd notifications test-pushover`
  - Disable: `backupd notifications disable-pushover`
  - Full CLI status: `backupd notifications status [--json]`

- **Priority-Based Sound Alerts** - Smart notification urgency mapping
  - **Failures** (priority 1, siren/falling): Bypass quiet hours, immediate alert
  - **Success** (priority 0, magic): Pleasant confirmation sound
  - **Warnings** (priority 0, bike): Attention-worthy but not urgent
  - **Silent/Background** (priority -1, none): No notification sound
  - Critical failures like backup failures and integrity check failures use high priority to ensure visibility

- **Event-Specific Notification Sounds** - 22 notification events with tailored sounds
  - Database backup success/failure/warning
  - Files backup success/failure/warning
  - Retention cleanup success/warning
  - Integrity verification passed/failed
  - Script regeneration notifications
  - All events mapped to appropriate priority and sound

- **CLI Notifications Subcommand** - Full non-interactive notification management
  - `backupd notifications status` - Show all notification channel configurations
  - `backupd notifications status --json` - JSON output for API integration
  - `backupd notifications set-pushover` - Configure Pushover credentials
  - `backupd notifications test-pushover` - Send test notification
  - `backupd notifications disable-pushover` - Remove Pushover configuration

### Changed

- **Notification System Architecture** - Updated `send_notification()` to support 6 parameters
  - Added `priority` parameter (5th): -2 to 2 (Pushover priority levels)
  - Added `sound` parameter (6th): Pushover sound name
  - All 22 notification calls updated with appropriate priority/sound
  - Backward compatible: existing ntfy and webhook notifications unaffected

- **Script Regeneration** - Enhanced `regenerate_scripts_silent()` function
  - Now regenerates all 6 scripts (backup + verify) when notification settings change
  - Ensures Pushover credentials are embedded in all generated scripts
  - Previously only regenerated backup scripts (4), now includes verify scripts (6)

- **Encrypted Secrets** - Added Pushover credential storage
  - `.c8` - Pushover user key (encrypted, immutable)
  - `.c9` - Pushover API token (encrypted, immutable)
  - Integrated with existing lock/unlock/migrate secret functions

### Technical

- **Modified Files:**
  - `lib/crypto.sh` - Added `SECRET_PUSHOVER_USER` and `SECRET_PUSHOVER_TOKEN` constants, updated lock/unlock arrays
  - `lib/notifications.sh` - Added `configure_pushover()`, `test_pushover_notification()`, updated menus and regeneration
  - `lib/generators.sh` - Added `send_pushover()` function to all 4 script generators, updated 22 notification calls
  - `lib/cli.sh` - Added notifications subcommand with status, set-pushover, test-pushover, disable-pushover
  - `backupd.sh` - Added `notifications` to allowed subcommands in dispatch

- **Pushover API Integration:**
  - Endpoint: `https://api.pushover.net/1/messages.json`
  - Authentication: 30-character alphanumeric user key + API token
  - Retry logic: 3 attempts with exponential backoff (2s, 4s, 8s delays)
  - HTTP timeout: 15 seconds per request
  - Validates 200 OK response for success

- **Notification Priority Mapping:**
  | Event Type | Priority | Sound | Behavior |
  |------------|----------|-------|----------|
  | Backup/Verify Failure | 1 (High) | siren/falling | Bypasses quiet hours |
  | Success | 0 (Normal) | magic | Standard notification |
  | Warning | 0 (Normal) | bike | Standard notification |
  | Background/Started | -1 (Low) | none | Silent, no sound |

---

## [2.2.11] - 2026-01-06

### Added

- **REST API Support Flags** - New CLI flags for API and GUI integration
  - `--job-id ID` - Pass job tracking ID for API progress monitoring
  - `--backup-id ID` - Specify backup ID for non-interactive restore operations
  - `--passphrase PASS` - Provide encryption passphrase for non-interactive `verify --full`
  - `logs --json` - Structured JSON output from log files for parsing

- **Progress File Tracking** - Real-time progress tracking at `/var/run/backupd/`
  - Progress files written during backup/restore operations
  - JSON format with percentage, current operation, and timestamps
  - Directory created by installer with `tmpfiles.d` for reboot persistence

### Fixed

- **Global Flags Position** - `--dry-run` and `--json` now work both before AND after subcommand
  - Previously: `backupd --json backup db` failed
  - Now works: `backupd --json backup db` AND `backupd backup db --json`

### Changed

- **Help Text Updated** - All subcommand help text updated with new options and examples
- **Install Script** - Adds `/var/run/backupd/` directory and `tmpfiles.d` configuration
- **Uninstall Script** - Properly cleans up progress directory and `tmpfiles.d` config

### Security

- **Passphrase Redaction in Logs** - Fixed `--passphrase VALUE` being logged in plain text
  - Added `redact_cmdline_args()` function to sanitize command lines before logging
  - Fixed in: `lib/logging.sh`, `lib/cli.sh`, `lib/debug.sh`
  - Also redacts `BACKUPD_PASSPHRASE=value` environment variable patterns

### Environment Variables

New environment variables supported for non-interactive operation:
- `JOB_ID` - Alternative to `--job-id` flag
- `BACKUP_ID` - Alternative to `--backup-id` flag
- `BACKUPD_PASSPHRASE` - Alternative to `--passphrase` flag

---

## [2.2.10] - 2026-01-05

### Fixed

- **Installer Missing Library Files** - `install.sh` now downloads all 16 lib files
  - Added missing: `lib/exitcodes.sh`, `lib/logging.sh`, `lib/cli.sh`
  - Same fix applied to installer that was done in v2.2.9 for `--dev-update`

---

## [2.2.9] - 2026-01-05

### Fixed

- **Error Logging System** - Errors now properly logged to `/var/log/backupd.log`
  - `print_error()` now calls `log_error()` with stack trace
  - `print_warning()` now calls `log_warn()` for audit trail
  - Guards prevent issues during module load order
  - Direct `echo >&2` patterns replaced with `print_error()`

- **Backup Script Error Capture** - CLI wrapper captures generated script errors
  - New `run_backup_script()` function in `lib/cli.sh`
  - Extracts `[ERROR]` lines from script output
  - Logs failures with context to structured log
  - Handles `pipefail` correctly for exit code capture

- **Dev Update Missing Files** - `--dev-update` now downloads all lib files
  - Added missing: `lib/exitcodes.sh`, `lib/logging.sh`, `lib/cli.sh`
  - File list now matches all 16 lib/*.sh files

### Technical

- `lib/core.sh`: `print_error()` and `print_warning()` now log with `type` guard
- `lib/cli.sh`: New `run_backup_script()` wrapper (30 lines)
- `lib/crypto.sh`: Direct stderr writes converted to `print_error()`
- `lib/updater.sh`: `lib_files` array updated from 13 to 16 files

---

## [2.2.8] - 2026-01-05

### Added

- **Structured Logging System** - Comprehensive logging for troubleshooting and GitHub Issues
  - Automatic error logging to `/var/log/backupd.log` on every run
  - Log levels: INFO (default), DEBUG (`--verbose`), TRACE (`-vv`)
  - Function name, file, line number in every log entry
  - Automatic stack traces for errors
  - Session markers with timestamps and version info
  - `--log-file PATH` - Write logs to custom file
  - `--verbose` - Increase verbosity (stackable: `-vv` for TRACE)
  - `--log-export` - Export sanitized log for GitHub issue submission

- **Auto-Redaction of Sensitive Data** - Security-first logging
  - Passwords, tokens, API keys automatically redacted
  - Database credentials (`-p'...'`, `--password=...`) sanitized
  - Home paths (`/home/user/`) replaced with `/home/[USER]/`
  - Secret directories redacted
  - SHA256/MD5 hashes replaced with `<SHA256>`/`<HASH32>`
  - rclone remotes sanitized
  - Bearer tokens and Authorization headers redacted

- **GitHub Issue Templates** - Streamlined bug reporting
  - Form-based bug report template with logging instructions
  - Feature request template with component selection
  - Links to documentation and debug guide
  - Pull request template with checklist

- **DEBUG.md** - Comprehensive debugging documentation
  - Quick start troubleshooting guide
  - Log locations and formats explained
  - Auto-redaction patterns documented
  - Common problems with solutions
  - Advanced debugging techniques

### Changed

- **Help Output** - Added logging options section with automatic log file info
- **README.md** - Updated with logging documentation and file structure
- **USAGE.md** - Added Logging & Debugging section

### Technical

- New module: `lib/logging.sh` (503 lines)
- Function instrumentation with `log_func_enter` across 11 library files
- Safe arithmetic operations (`VERBOSE_LEVEL=$((VERBOSE_LEVEL + 1))`) for `set -e` compatibility
- LOG_FILE preserved when already set before sourcing
- All scripts pass `bash -n` syntax validation

---

## [2.2.7] - 2026-01-05

### Added

- **CLI Subcommand Dispatcher** - Full command-line interface for non-interactive usage
  - `backupd backup {db|files|all}` - Run backups from command line
  - `backupd restore {db|files} [--list]` - Restore or list backups
  - `backupd status` - Show system status
  - `backupd verify [--quick|--full]` - Verify backup integrity
  - `backupd schedule {list|enable|disable}` - Manage schedules
  - `backupd logs [TYPE] [--lines N]` - View backup logs
  - Each subcommand has its own `--help` with CLIG-compliant formatting

- **--dry-run Flag** - Preview operations without executing
  - Works with `backup`, `restore`, `schedule`, and `verify` commands
  - Shows exactly what would happen without making changes
  - Uses `[DRY-RUN]` prefix in output for clarity

- **--json Output** - Machine-readable JSON output for automation
  - `backupd verify --json` returns structured JSON with status, checksums, timestamps
  - Enables integration with monitoring tools and scripts
  - Includes error details in JSON format when operations fail

- **--quiet Flag** - Suppress non-essential output for scripts/cron
  - Only critical errors and final status shown
  - Perfect for cron jobs and automated pipelines

- **Standardized Exit Codes** - Consistent exit codes across all commands
  - 0: Success
  - 1: General error
  - 2: Configuration error
  - 3: Insufficient disk space
  - 64-78: Reserved for specific error categories

- **CLIG-Compliant Help** - Enhanced help formatting for all subcommands
  - Follows Command Line Interface Guidelines
  - Consistent structure: Usage, Commands, Options, Examples
  - Context-aware examples for each subcommand

### Changed

- **Help Output** - Now uses standardized CLIG format with clear sections
- **Error Messages** - More descriptive with actionable suggestions
- **Version Output** - Cleaner format with proper exit code

---

## [2.2.5] - 2025-12-22

### Fixed

- **Restore Extraction Failure** - Fixed critical bug where files were not being extracted to website root
  - Root cause: `2>/dev/null` was hiding all tar errors, making failures silent
  - Backup uses `pigz` compression, but restore was using `gzip` - now uses pigz if available
  - Added verification that files were actually extracted (counts items after extraction)
  - Now shows extraction errors instead of hiding them
  - Shows "Success (X items extracted)" or specific error message

- **SIGPIPE Crash (Exit 141)** - Fixed critical bug causing restore script to crash silently
  - Root cause: `tar -tf | head` with `set -o pipefail` causes SIGPIPE when head closes the pipe
  - This killed the script mid-restore with exit code 141 (128 + SIGPIPE)
  - Fix: Changed to `2>/dev/null | head ... || true` to prevent pipeline failure

- **Wrong File Ownership After Restore** - Fixed incorrect group ownership on restored files
  - Previous behavior: Applied directory's group (`user:www-data`) to all files
  - Correct behavior: Files get `user:user`, directory keeps `user:www-data`
  - Root cause: `chown -R "$dir_owner"` used directory's group for all contents
  - Fix: Use `find ... -exec chown "$dir_user:$dir_user"` for contents only
  - This preserves web server access to the directory while maintaining correct file ownership

### Changed

- **Extraction now uses pigz** - If pigz is available, uses it for decompression (matches backup)
- **Added `-p` flag** - Preserves permissions during extraction (`tar -xpf`)
- **Extraction verification** - Counts extracted files and fails if zero items extracted
- **Ownership handling** - Contents get `user:user`, directory preserves `user:www-data` for web access

---

## [2.2.4] - 2025-12-22

### Fixed

- **Restore Loop Early Exit** - Fixed critical bug where restore loop would exit after first site
  - Cause: `set -e` combined with conditional cleanup `[[ ... ]] && rm` returning exit code 1 when condition was false
  - When a site had no backup to clean up (empty `backup_name`), the condition failed and `set -e` terminated the script
  - Fix: Added `|| true` to conditional cleanup lines to ensure zero exit code
  - Affected: Both new format (contents-only) and old format (directory) extraction paths

---

## [2.2.3] - 2025-12-22

### Fixed

- **Files Restore "All Sites" Bug** - Fixed critical issue where restoring all sites could silently skip some sites
  - Added pre-flight check to identify sites missing restore-path metadata before starting
  - User is now warned about sites requiring manual path entry before restore begins
  - Added comprehensive tracking of restored/failed/skipped sites throughout the process
  - Added detailed final summary showing:
    - Number of sites successfully restored
    - Sites that failed with specific error reasons
    - Sites that were skipped and why
    - Overall status (ALL RESTORED / PARTIAL / NONE)

### Changed

- **Restore Path Pre-fetch** - Restore path metadata is now fetched once during pre-flight check
  - Eliminates redundant remote calls during restore loop
  - Provides upfront visibility into which sites need manual paths

### Technical Details

- Silent `continue` statements now track failures/skips in arrays
- Failure reasons are categorized: `download_failed`, `extraction_failed`, `mkdir_failed`, `path_not_exists`, `invalid_archive`
- Skip reasons are categorized: `checksum_mismatch`, `no_path_provided`, `path_not_created`

---

## [2.2.2] - 2025-12-22

### Changed

- **xCloud Panel Path** - Updated default path pattern for xCloud panel
  - Changed from `/var/www/*/public_html` (webroot: `public_html`) to `/var/www/*` (webroot: `.`)
  - xCloud sites are backed up directly from `/var/www/*` without subdirectory
  - Detection method unchanged: checks for `xcloud` user in `/etc/passwd`
  - **Note**: Existing installations are unaffected (path stored in config file)

### Fixed

- **Systemd Timer Consistency** - Added missing `RandomizedDelaySec` to verification timers in install.sh
  - `backupd-verify.timer`: Added `RandomizedDelaySec=300` (5 min jitter)
  - `backupd-verify-full.timer`: Added `RandomizedDelaySec=3600` (1 hour jitter)
  - Prevents thundering herd when multiple servers run verifications
  - Now consistent with db/files backup timers

- **Log Path Display** - Fixed incorrect log path shown when enabling monthly full verification
  - Was showing: `verify_logfile.log`
  - Now shows: `verify_full_logfile.log` (correct path)
  - Only affected the message shown to users, not actual log location

### Note

> **Version 2.2.1 was skipped** due to a GitHub release artifact naming issue that caused the
> auto-updater to fail. The release was retracted and v2.2.2 published with corrected asset names.

---

## [2.2.0] - 2025-12-21

### Added

- **Dedicated Notifications Menu** - New main menu option (7. Notifications)
  - Configure ntfy URL and token
  - Configure webhook URL and Bearer token
  - Test notifications (sends to all configured channels)
  - View notification failure log
  - Disable all notifications with one action
  - `lib/notifications.sh` - New 478-line module for notification management

- **Webhook Notifications** - Dual-channel notification system
  - Send backup events to any webhook endpoint (n8n, Slack, Discord, custom APIs)
  - JSON payload with event, title, hostname, message, timestamp, and details
  - Optional Bearer token authentication for secure endpoints
  - Works alongside or independently of ntfy notifications
  - Configure from dedicated Notifications menu

- **Robust Notification Failure Handling**
  - 3-attempt retry with exponential backoff (1s, 2s, 4s delays)
  - HTTP status code validation (only 2xx = success)
  - Dedicated failure log: `/etc/backupd/logs/notification_failures.log`
  - CRITICAL alert when both ntfy AND webhook channels fail
  - Prevents silent notification failures that could hide backup problems

- **Enhanced View Logs Menu**
  - Shows 4 log types with file sizes
  - Database backup log
  - Files backup log
  - Verification log
  - Notification failures (with entry count, highlighted if non-zero)
  - View all logs directory
  - Clear old logs option (truncates logs > 10MB)

- **Files Restore Shows 3 Backups**
  - Now displays last 3 backups per site (not just latest)
  - Easier to select older restore point
  - Added "Press Enter to continue" after restore completes

- **Monthly Full Verification Timer**
  - New systemd timer: `backupd-verify-full.timer`
  - Runs monthly to check if full restore test is needed
  - Sends reminders if backup restorability was never tested or is overdue

- **Setup Completion Notification**
  - Sends notification when setup wizard completes successfully
  - Includes all configured backup types and remote paths

### Changed

- **Menu Structure Overhaul**
  - Verify backups moved to main menu (option 3) - no longer buried
  - Notifications added as main menu option (7)
  - Renumbered: Reconfigure (8), Uninstall (9)
  - All submenus now use `0` for back (standardized)
  - Schedule menu now loops properly after actions

- **HTTPS Enforcement** (Breaking Change for HTTP users)
  - All notification URLs (ntfy AND webhook) now require HTTPS
  - HTTP URLs are rejected with clear error message
  - Security best practice - no exceptions
  - Helpful guidance shown when HTTP URL entered

- **Clearer Token Prompt**
  - Webhook token prompt now says "most webhooks don't need this"
  - Reduces confusion for users without authentication requirements

- **Enhanced Reconfigure Warning**
  - Explicit warning about backup unrecoverability when changing encryption password
  - Red-highlighted message box with clear consequences
  - Requires typing `YES` (uppercase) to confirm understanding
  - Prevents accidental data loss from password changes

### Fixed

- **Secrets Directory Locking** - Added `.c6` and `.c7` to lock/unlock/migrate functions
  - Fixes "Operation not permitted" error when saving webhook secrets
  - `store_secret()` now unlocks directory before creating new files
- **Webhook JSON Payload** - Added missing `title` field to webhook notifications
- **JSON Default Value** - Fixed bash syntax error `\{\}` → `${4:-"{}"}` in notification function
- **Files Backup Warning** - Fixed undefined `$WWW_DIR` variable, now uses `$WEB_PATH_PATTERN`
- **Verify Hostname** - Fixed wrong variable `$HOSTNAME` → `$hostname_full` in failure notifications
- **Script Regeneration** - Fixed `get_config()` → `get_config_value()` function calls
- **Config Key Mismatch** - Fixed `BACKUP_DB` → `DO_DATABASE` config key references
- **Install Script** - Added `notifications.sh` to module download list
- **Updater** - Added `notifications.sh` to dev-update file list

### Security

- **HTTPS-only notifications** - Enforced for all notification channels
- Webhook tokens encrypted with AES-256 (same as database credentials)
- Prevents credential leakage over unencrypted connections
- Clear error messages guide users to secure configuration

### Technical

- New encrypted secrets: `.c6` (webhook URL), `.c7` (webhook auth token)
- New module: `lib/notifications.sh` (notification configuration UI)
- Updated `send_notification_all()` function for dual-channel delivery
- All 23 notification event types tested and validated (8 success, 8 warning, 7 failure)
- All scripts pass bash syntax validation
- `lib/verify.sh` - Added webhook support alongside ntfy
- `lib/setup.sh` - Added setup_complete notification at end of wizard
- `lib/generators.sh` - Added retry logic and failure logging to all 4 backup templates
- `lib/crypto.sh` - Added `.c6`, `.c7` to lock_secrets(), unlock_secrets(), migrate_secrets()
- `install.sh` - Added backupd-verify-full.service and .timer, notifications.sh module

---

## [2.1.0] - 2025-12-19

### Added

- **Automatic Backup Verification** - Enabled by default during setup
  - Weekly quick check (Sundays 2 AM): Verifies backups exist, no download
  - Monthly reminder (1st of month 3 AM): Sends notification to manually test
  - Ensures backups are actually restorable, not just present

- **Quick Verification Mode** - Bandwidth-efficient backup checks
  - Single API call per backup type (optimized from ~200 calls to 2)
  - Uses `rclone lsl` with associative arrays for efficient checksum matching
  - Verifies backup existence and checksum files without downloading
  - Ideal for large backups (100+ sites, multi-GB files)
  - Runs weekly by default, configurable via schedule menu
  - Sends notification with results (if ntfy configured)

- **Monthly Full Test Reminder** - Reminder-only approach for large sites
  - Does NOT automatically download backups (bandwidth-friendly)
  - Sends notification prompting manual verification
  - Tracks days since last full test (30-day threshold)
  - High-priority notification if backups have NEVER been tested
  - Respects that large sites can have hundreds of GB of backups

- **Argon2id Encryption** - Modern memory-hard key derivation (default when `argon2` package installed)
  - GPU/ASIC resistant, recommended by OWASP
  - Parameters: 64MB memory, 3 iterations, 4 parallel threads
  - Falls back to PBKDF2-SHA256 if `argon2` not available

- **Enhanced PBKDF2** - Increased iterations from 100,000 to 800,000 for fallback mode
  - Meets OWASP recommendations (600,000+ minimum)
  - Only used when Argon2id not available

- **Encryption Version System** - Backward-compatible versioning for stored credentials
  - v1 (legacy): SHA256 + PBKDF2 100k iterations
  - v2 (enhanced): SHA256 + PBKDF2 800k iterations
  - v3 (modern): Argon2id + PBKDF2 100k iterations

- **Encryption Migration** - One-command upgrade to latest algorithm
  - `backupd --migrate-encryption` - Upgrade stored credentials
  - `backupd --encryption-status` - Check current algorithm
  - Automatic script regeneration after migration

### Changed

- **New installations** - Auto-select best available encryption (Argon2id if installed)
- **Installer** - Now installs `argon2` package for modern encryption

### Security

- **Argon2id key derivation** - Memory-hard function resistant to:
  - GPU cracking attacks
  - ASIC acceleration
  - Time-memory trade-off attacks
- **Secret value handling** - Uses `printf '%s'` instead of `echo -n` to prevent value misinterpretation
- **Required checksum verification** - Updates now fail if SHA256 checksum missing or mismatched
- **HTTPS-only downloads** - All downloads enforce `--proto '=https'` (no HTTP downgrade)
- **Stricter curl options** - Added `-f` (fail on errors), empty file detection, timeouts
- **Verified rclone installation** - Both installer and setup wizard download rclone from GitHub releases with SHA256 checksum verification (replaces unsafe `curl | bash`)
- **Strong password requirements** - Encryption password now requires:
  - Minimum 12 characters (up from 8)
  - At least 2 special characters
  - Clear requirements shown before password entry
- **Improved setup wizard** - Shows current encryption algorithm (Argon2id or PBKDF2) during setup

### Added

- **Debug Logging System** - Comprehensive troubleshooting support
  - Enable with `BACKUPD_DEBUG=1` or `--debug` flag
  - `--debug-status` shows log location and status
  - `--debug-export` creates sanitized log safe for sharing
  - Automatic sensitive data redaction (passwords, tokens, paths)
  - Session-based logging with timestamps and call stacks
  - Auto-rotation at 5MB

- **Installer Branch Support** - Install from any branch for testing
  - `--branch develop` flag for testing pre-release versions
  - Shows branch name during installation if not main

### Fixed

- **Graceful ntfy handling** - All operations work when notifications not configured
  - `get_secret` calls for ntfy now have proper error protection
  - Scripts continue normally without notifications instead of crashing
  - Fixed in: `lib/verify.sh`, `lib/generators.sh` (3 locations)

- **Arithmetic operations with `set -e`** - Fixed silent script exits
  - `((var++))` returns exit code 1 when var is 0, causing script to exit
  - Added `|| true` to all counter increment operations
  - Fixed in: `lib/crypto.sh`, `lib/core.sh`, `lib/verify.sh`, `lib/generators.sh`

- **`local` keyword in generated scripts** - Fixed syntax error
  - `local` only valid inside functions, not at script top-level
  - Removed `local` from while loops in generated verification scripts

- **Quick check menu flow** - Now stays in verify submenu after check
  - Previously returned to main menu, requiring re-navigation
  - Wrapped verify menu in loop for better UX

### Technical

- All generated scripts now embed version-aware crypto functions
- Fixed missing `-e` flag in generated script `set` statements
- Existing installations continue working with their current encryption version
- New `lib/debug.sh` module for debug logging infrastructure
- Improved uninstall: now stops services before removing files, correct order of operations
- Quick verification uses single `rclone lsl` call with associative arrays
- Monthly verification changed from full download to reminder-only notification
- All shell scripts pass `bash -n` syntax validation

---

## [2.0.1] - 2025-12-13

### Fixed

- **Setup completion message** - Now shows `backupd` command instead of `backup-management`
- **Systemd timer reference** - Status display now uses `backupd-*` pattern
- **Checksum verification** - Updater now looks for `backupd-v*.tar.gz` filename
- **Lock file names** - Generated scripts now use `backupd-db.lock` and `backupd-files.lock`

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
  - xCloud: `/var/www/*` (webroot: `.`) - detected via `xcloud` user
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

### Security

- Machine-bound encryption keys
- Random hidden directory for secrets
- Immutable file flags (chattr +i)
- No plain-text credential storage

---

## Version History Summary

| Version | Date | Highlights |
|---------|------|------------|
| 3.2.1 | 2026-01-09 | **Schedule auto-suggest**, bulk operations, 12 schedule templates |
| 3.2.0 | 2026-01-09 | **Per-job scheduling CLI**, schedule validation, FlashPanel auto-detection |
| 3.1.4 | 2026-01-09 | Multi-distribution package manager support (6 distros), wget fallback |
| 3.1.3 | 2026-01-09 | 19 bug fixes across logging, crypto, core, CLI modules |
| 3.1.2 | 2026-01-08 | Security & reliability fixes for updater (18 bugs) |
| 3.1.1 | 2026-01-07 | Fix installer missing v3.1.0 lib modules |
| 3.1.0 | 2026-01-07 | Multi-job support, job CLI commands, backup history command, automatic migration |
| 3.0.0 | 2026-01-06 | **Major release**: Restic backup engine, deduplication, retention in days |
| 2.3.0 | 2026-01-06 | Pushover notifications, priority-based sound alerts, CLI notifications subcommand |
| 2.2.11 | 2026-01-06 | REST API support flags, progress file tracking, global flags fix, passphrase redaction |
| 2.2.10 | 2026-01-05 | Installer missing library files fix |
| 2.2.9 | 2026-01-05 | Error logging, backup script error capture, dev-update file list |
| 2.2.8 | 2026-01-05 | Structured logging, auto-redaction, GitHub issue templates, DEBUG.md |
| 2.2.7 | 2026-01-05 | CLI subcommands, --dry-run, --json output, CLIG-compliant help |
| 2.2.5 | 2025-12-22 | Restore extraction fix, SIGPIPE fix, ownership fix |
| 2.2.0 | 2025-12-21 | Notifications menu, webhook support, menu overhaul, HTTPS enforcement, 8 bug fixes |
| 2.1.0 | 2025-12-19 | Argon2id encryption, optimized quick verification, monthly reminder system, graceful ntfy handling |
| 2.0.1 | 2025-12-13 | Branding fixes, lock file names |
| 2.0.0 | 2025-12-13 | Major rebranding to Backupd |
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
  <strong>Built with care by <a href="https://backupd.io">Backupd</a></strong>
</p>
