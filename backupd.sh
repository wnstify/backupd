#!/usr/bin/env bash
# ============================================================================
# Backupd - Backup Daemon
# https://backupd.io
#
# Comprehensive backup and restore solution for WordPress/MySQL environments
# Supports: Database backups, Files backups, Remote storage via rclone
# Secure credential storage with machine-bound encryption
#
# DISCLAIMER:
# This script is provided "as is" without warranty of any kind. The author
# (Backupd) is not responsible for any damages, data loss, or misuse
# arising from the use of this script. Always create a server snapshot
# before running backup/restore operations. Use at your own risk.
# ============================================================================
set -euo pipefail

VERSION="2.2.8"
AUTHOR="Backupd"
WEBSITE="https://backupd.io"
INSTALL_DIR="/etc/backupd"
SCRIPTS_DIR="$INSTALL_DIR/scripts"
CONFIG_FILE="$INSTALL_DIR/.config"

# Lock file locations (fixed, not in temp)
LOCK_DIR="/var/lock"
DB_LOCK_FILE="$LOCK_DIR/backupd-db.lock"
FILES_LOCK_FILE="$LOCK_DIR/backupd-files.lock"

# Determine script directory (handle symlinks)
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# ---------- Source Modules ----------

# Check if lib directory exists
if [[ ! -d "$LIB_DIR" ]]; then
  echo "Error: Library directory not found: $LIB_DIR"
  echo "Please ensure the lib/ directory is in the same location as this script."
  exit 1
fi

# Source all modules in order (dependencies first)
source "$LIB_DIR/core.sh"       # Colors, print functions, validation, helpers
source "$LIB_DIR/exitcodes.sh"  # Standardized exit codes (CLIG compliant)
source "$LIB_DIR/debug.sh"      # Debug logging (must be early for other modules)
source "$LIB_DIR/logging.sh"    # Comprehensive structured logging
source "$LIB_DIR/crypto.sh"     # Encryption, secrets, key derivation
source "$LIB_DIR/config.sh"     # Configuration read/write
source "$LIB_DIR/generators.sh" # Script generation (needed by setup/schedule)
source "$LIB_DIR/status.sh"     # Status display, view logs
source "$LIB_DIR/backup.sh"     # Backup execution, cleanup
source "$LIB_DIR/verify.sh"     # Backup integrity verification
source "$LIB_DIR/restore.sh"    # Restore execution
source "$LIB_DIR/schedule.sh"   # Schedule management
source "$LIB_DIR/setup.sh"      # Setup wizard
source "$LIB_DIR/updater.sh"    # Auto-update functionality
source "$LIB_DIR/notifications.sh" # Notification configuration
source "$LIB_DIR/cli.sh"        # CLI subcommand dispatcher (CLIG compliant)

# ---------- Install Command ----------

install_command() {
  local target="/usr/local/bin/backupd"
  local script_path
  script_path="$(readlink -f "$0")"

  if [[ -L "$target" ]] || [[ -f "$target" ]]; then
    rm -f "$target"
  fi

  ln -s "$script_path" "$target"
  chmod +x "$target"

  print_success "Command 'backupd' installed."
  echo "You can now run 'backupd' from anywhere."
}

# ---------- Uninstall ----------

uninstall_tool() {
  print_header
  echo "Uninstall Backupd"
  echo "================="
  echo
  print_warning "This will remove:"
  echo "  - All backup scripts"
  echo "  - Configuration files"
  echo "  - Secure credential storage"
  echo "  - Systemd timers"
  echo "  - The 'backupd' command"
  echo
  print_warning "Your actual backups in remote storage will NOT be deleted."
  echo
  read -p "Are you sure? Type 'UNINSTALL' to confirm: " confirm

  if [[ "$confirm" != "UNINSTALL" ]]; then
    echo "Cancelled."
    press_enter_to_continue
    return
  fi

  # Step 1: Stop timers first (prevents new backup triggers)
  echo "Stopping timers..."
  systemctl stop backupd-db.timer 2>/dev/null || true
  systemctl stop backupd-files.timer 2>/dev/null || true
  systemctl stop backupd-verify.timer 2>/dev/null || true

  # Step 2: Stop any running services (wait for current backups to finish)
  echo "Stopping services..."
  local services_running=false
  if systemctl is-active --quiet backupd-db.service 2>/dev/null; then
    echo "  Waiting for database backup to complete..."
    services_running=true
  fi
  if systemctl is-active --quiet backupd-files.service 2>/dev/null; then
    echo "  Waiting for files backup to complete..."
    services_running=true
  fi
  if systemctl is-active --quiet backupd-verify.service 2>/dev/null; then
    echo "  Waiting for verification to complete..."
    services_running=true
  fi

  # Stop services (will wait for them to finish since they're Type=oneshot)
  systemctl stop backupd-db.service 2>/dev/null || true
  systemctl stop backupd-files.service 2>/dev/null || true
  systemctl stop backupd-verify.service 2>/dev/null || true

  if [[ "$services_running" == "true" ]]; then
    echo "  Services stopped."
  fi

  # Step 3: Disable all units
  echo "Disabling units..."
  systemctl disable backupd-db.timer 2>/dev/null || true
  systemctl disable backupd-files.timer 2>/dev/null || true
  systemctl disable backupd-verify.timer 2>/dev/null || true
  systemctl disable backupd-db.service 2>/dev/null || true
  systemctl disable backupd-files.service 2>/dev/null || true
  systemctl disable backupd-verify.service 2>/dev/null || true

  # Step 4: Remove systemd units BEFORE removing scripts
  echo "Removing systemd units..."
  rm -f /etc/systemd/system/backupd-db.service
  rm -f /etc/systemd/system/backupd-db.timer
  rm -f /etc/systemd/system/backupd-files.service
  rm -f /etc/systemd/system/backupd-files.timer
  rm -f /etc/systemd/system/backupd-verify.service
  rm -f /etc/systemd/system/backupd-verify.timer
  systemctl daemon-reload 2>/dev/null || true

  # Step 5: Remove cron jobs (legacy)
  ( crontab -l 2>/dev/null | grep -Fv "$SCRIPTS_DIR/db_backup.sh" | grep -Fv "$SCRIPTS_DIR/files_backup.sh" ) | crontab - 2>/dev/null || true

  # Step 6: Remove secrets
  echo "Removing secrets..."
  local secrets_dir
  secrets_dir="$(get_secrets_dir)"
  if [[ -n "$secrets_dir" && -d "$secrets_dir" ]]; then
    unlock_secrets "$secrets_dir"
    rm -rf "$secrets_dir"
  fi

  # Step 7: Remove install directory
  echo "Removing installation..."
  rm -rf "$INSTALL_DIR"

  # Step 8: Remove command symlink
  rm -f "/usr/local/bin/backupd"

  print_success "Uninstall complete."
  echo
  exit 0
}

# ---------- Main Menu ----------

main_menu() {
  while true; do
    print_header

    # Show update banner if available (silent check)
    show_update_banner

    if is_configured; then
      echo "Main Menu"
      echo "========="
      echo
      echo "  1. Run backup now"
      echo "  2. Restore from backup"
      echo "  3. Verify backups"
      echo "  4. View status"
      echo "  5. View logs"
      echo "  6. Manage schedules"
      echo "  7. Notifications"
      echo "  8. Reconfigure"
      echo "  9. Uninstall"
      echo
      echo "  U. Update tool"
      echo "  0. Exit"
      echo
      read -p "Select option [1-9, U, 0]: " choice

      case "$choice" in
        1) run_backup ;;
        2) run_restore ;;
        3) verify_backup_integrity ;;
        4) show_status ;;
        5) view_logs ;;
        6) manage_schedules ;;
        7) manage_notifications ;;
        8) run_setup ;;
        9) uninstall_tool ;;
        [Uu]) do_update ;;
        0) exit 0 ;;
        *) print_error "Invalid option" ; sleep 1 ;;
      esac
    else
      print_disclaimer
      echo "Welcome! This tool needs to be configured first."
      echo
      echo "  1. Run setup wizard"
      echo "  U. Update tool"
      echo "  0. Exit"
      echo
      read -p "Select option [1, U, 0]: " choice

      case "$choice" in
        1) run_setup ;;
        [Uu]) do_update ;;
        0) exit 0 ;;
        *) print_error "Invalid option" ; sleep 1 ;;
      esac
    fi
  done
}

# ---------- CLI Arguments ----------

show_help() {
  echo "Backupd v${VERSION}"
  echo "by ${AUTHOR} (${WEBSITE})"
  echo
  echo "Comprehensive backup and restore solution for WordPress/MySQL servers."
  echo "Supports database backups, files backups, and remote storage via rclone."
  echo
  echo "Usage: backupd [COMMAND] [OPTIONS]"
  echo "       backupd [OPTIONS]"
  echo
  echo "Commands:"
  echo "  backup {db|files|all}       Run backup operations"
  echo "  restore {db|files} [--list] Restore from backup"
  echo "  status                      Show system status"
  echo "  verify [--quick|--full]     Verify backup integrity"
  echo "  schedule {list|enable|disable} Manage schedules"
  echo "  logs [TYPE] [--lines N]     View backup logs"
  echo
  echo "Run 'backupd COMMAND --help' for more information on a command."
  echo
  echo "Options:"
  echo "  --help, -h            Show this help message"
  echo "  --version, -v         Show version information"
  echo "  --quiet, -q           Suppress non-essential output (for scripts/cron)"
  echo "  --json                Output in JSON format (for parsing)"
  echo "  --dry-run, -n         Preview operations without executing"
  echo "  --update              Check for and install updates"
  echo "  --check-update        Check for updates (no install)"
  echo "  --dev-update          Update from develop branch (testing only)"
  echo "  --migrate-encryption  Upgrade encryption to best available algorithm"
  echo "  --encryption-status   Show current encryption algorithm status"
  echo
  echo "Logging options (logs automatically to /var/log/backupd.log):"
  echo "  --log-file PATH       Write logs to custom file instead"
  echo "  --verbose             Increase output verbosity (can be repeated: -vv)"
  echo "  --log-export          Export sanitized log for GitHub issue submission"
  echo "  --debug               Enable legacy debug logging for this session"
  echo "  --debug-status        Show debug log status and location"
  echo "  --debug-export        Export sanitized debug log for sharing"
  echo
  echo "Examples:"
  echo "  backupd backup db              # Backup database now"
  echo "  backupd backup all --quiet     # Backup everything silently"
  echo "  backupd restore db --list      # List available DB backups"
  echo "  backupd verify --dry-run       # Preview verification"
  echo "  backupd status --json          # Get status as JSON"
  echo "  backupd --verbose backup all   # Verbose output with debug logs"
  echo "  backupd --log-export           # Export log for GitHub issue"
  echo
  echo "Environment variables:"
  echo "  BACKUPD_LOG_FILE=path Override default log file location"
  echo "  BACKUPD_DEBUG=1       Enable legacy debug logging"
  echo "  NO_COLOR=1            Disable colored output"
  echo
  echo "Run without arguments to start the interactive menu."
}

show_version() {
  echo "Backupd v${VERSION}"
  echo "by ${AUTHOR}"
  echo "${WEBSITE}"
}

# ---------- Encryption Management ----------

show_encryption_status() {
  echo "Encryption Status"
  echo "================="
  echo

  local secrets_dir
  secrets_dir="$(get_secrets_dir)"

  if [[ -z "$secrets_dir" || ! -d "$secrets_dir" ]]; then
    print_warning "No encryption configured (setup not completed)"
    return 0
  fi

  local current_version best_version
  current_version="$(get_crypto_version "$secrets_dir")"
  best_version="$(get_best_crypto_version)"

  echo "Current algorithm: $(get_crypto_name "$current_version")"
  echo "Best available:    $(get_crypto_name "$best_version")"
  echo

  if [[ "$current_version" -lt "$best_version" ]]; then
    print_warning "Upgrade available!"
    echo "Run 'backupd --migrate-encryption' to upgrade"
  else
    print_success "Using best available encryption"
  fi

  echo
  echo "Algorithm details:"
  echo "  - Argon2id: Memory-hard, GPU/ASIC resistant (requires 'argon2' package)"
  echo "  - PBKDF2:   CPU-hard, widely compatible"
  echo

  if ! argon2_available; then
    print_info "Argon2 not installed. Install with: sudo apt install argon2"
  fi
}

do_migrate_encryption() {
  echo "Encryption Migration"
  echo "===================="
  echo

  local secrets_dir
  secrets_dir="$(get_secrets_dir)"

  if [[ -z "$secrets_dir" || ! -d "$secrets_dir" ]]; then
    print_error "No encryption configured (setup not completed)"
    return 1
  fi

  local current_version best_version
  current_version="$(get_crypto_version "$secrets_dir")"
  best_version="$(get_best_crypto_version)"

  echo "Current: $(get_crypto_name "$current_version")"
  echo "Target:  $(get_crypto_name "$best_version")"
  echo

  if [[ "$current_version" -ge "$best_version" ]]; then
    print_success "Already using best available encryption"
    return 0
  fi

  if [[ "$best_version" == "$CRYPTO_VERSION_ARGON2ID" ]] && ! argon2_available; then
    print_error "Argon2 not installed"
    echo
    echo "Install with: sudo apt install argon2"
    echo "Then run this command again."
    return 1
  fi

  echo "This will:"
  echo "  1. Decrypt all stored credentials"
  echo "  2. Re-encrypt with $(get_crypto_name "$best_version")"
  echo "  3. Regenerate backup scripts"
  echo
  print_warning "Make sure you have a backup of your server before proceeding!"
  echo
  read -p "Continue? (y/N): " confirm

  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    return 0
  fi

  echo
  if migrate_secrets "$secrets_dir" "$current_version" "$best_version"; then
    print_success "Encryption upgraded successfully!"
    echo
    echo "Regenerating backup scripts with new encryption..."

    # Regenerate scripts if configured
    if is_configured; then
      regenerate_all_scripts
      print_success "Backup scripts regenerated"
    fi

    echo
    print_success "Migration complete!"
  else
    print_error "Migration failed"
    return 1
  fi
}

regenerate_all_scripts() {
  local secrets_dir rclone_remote rclone_db_path rclone_files_path retention_minutes
  secrets_dir="$(get_secrets_dir)"
  rclone_remote="$(get_config_value "RCLONE_REMOTE")"
  rclone_db_path="$(get_config_value "RCLONE_DB_PATH")"
  rclone_files_path="$(get_config_value "RCLONE_FILES_PATH")"
  retention_minutes="$(get_config_value "RETENTION_MINUTES")"
  retention_minutes="${retention_minutes:-43200}"

  # Regenerate DB backup script if DB backup is enabled
  local do_db
  do_db="$(get_config_value "DO_DATABASE")"
  if [[ "$do_db" == "true" ]]; then
    generate_db_backup_script "$secrets_dir" "$rclone_remote" "$rclone_db_path" "$INSTALL_DIR/logs" "$retention_minutes"
    generate_db_restore_script "$secrets_dir" "$rclone_remote" "$rclone_db_path"
  fi

  # Regenerate files backup script if files backup is enabled
  local do_files
  do_files="$(get_config_value "DO_FILES")"
  if [[ "$do_files" == "true" ]]; then
    local web_path_pattern webroot_subdir
    web_path_pattern="$(get_config_value "WEB_PATH_PATTERN")"
    web_path_pattern="${web_path_pattern:-/var/www/*}"
    webroot_subdir="$(get_config_value "WEBROOT_SUBDIR")"
    webroot_subdir="${webroot_subdir:-.}"
    generate_files_backup_script "$secrets_dir" "$rclone_remote" "$rclone_files_path" "$INSTALL_DIR/logs" "$retention_minutes" "$web_path_pattern" "$webroot_subdir"
    generate_files_restore_script "$rclone_remote" "$rclone_files_path"
  fi

  # Regenerate verify scripts
  generate_verify_script
  generate_full_verify_script
}

parse_arguments() {
  # Parse global flags that can be combined with other args
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --debug)
        DEBUG_ENABLED=1
        shift
        ;;
      --quiet|-q)
        QUIET_MODE=1
        export QUIET_MODE
        shift
        ;;
      --json)
        JSON_OUTPUT=1
        export JSON_OUTPUT
        shift
        ;;
      --dry-run|-n)
        DRY_RUN=1
        export DRY_RUN
        shift
        ;;
      --log-file)
        if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
          echo "Error: --log-file requires a path argument"
          exit 1
        fi
        log_set_file "$2"
        shift 2
        ;;
      --verbose)
        log_increase_verbosity
        shift
        ;;
      -v)
        # -v is version, not verbose
        show_version
        exit 0
        ;;
      -vv)
        # Allow -vv for double verbosity
        log_increase_verbosity
        log_increase_verbosity
        shift
        ;;
      *)
        # Not a global flag, break to handle subcommands/options
        break
        ;;
    esac
  done

  # If no more args, continue to menu
  if [[ -z "${1:-}" ]]; then
    return 0
  fi

  # Check for subcommands first (dispatch to CLI handler)
  case "${1:-}" in
    backup|restore|status|verify|schedule|logs)
      # Initialize logging before dispatch (since we exit after)
      log_init "$@"
      trap 'log_end' EXIT
      cli_dispatch "$@"
      exit $?
      ;;
  esac

  # Handle option flags
  case "${1:-}" in
    --help|-h)
      show_help
      exit 0
      ;;
    --version)
      show_version
      exit 0
      ;;
    --update)
      do_update
      exit $?
      ;;
    --check-update)
      check_for_updates_verbose
      exit $?
      ;;
    --dev-update)
      do_dev_update "develop"
      exit $?
      ;;
    --migrate-encryption)
      do_migrate_encryption
      exit $?
      ;;
    --encryption-status)
      show_encryption_status
      exit $?
      ;;
    --debug-status)
      debug_status
      exit 0
      ;;
    --debug-export)
      debug_export
      exit $?
      ;;
    --log-export)
      log_export_for_issue
      exit $?
      ;;
    "")
      # No arguments, continue to menu
      return 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information."
      exit 1
      ;;
  esac
}

# ---------- Entry Point ----------

# Parse CLI arguments first (some don't require root)
case "${1:-}" in
  --help|-h|--version|-v|--debug-status|--debug-export|--log-export)
    parse_arguments "$@"
    ;;
esac

# Handle subcommand --help without requiring root
# Check if second arg is --help or -h for any subcommand
case "${1:-}" in
  backup|restore|status|verify|schedule|logs)
    if [[ "${2:-}" == "--help" ]] || [[ "${2:-}" == "-h" ]] || [[ -z "${2:-}" && "${1:-}" != "backup" && "${1:-}" != "restore" ]]; then
      # status, verify, schedule, logs can show help without args
      # backup and restore need a subcommand or --help
      case "${1:-}" in
        status|schedule|logs)
          # These show useful output even without root for --help
          if [[ "${2:-}" == "--help" ]] || [[ "${2:-}" == "-h" ]]; then
            parse_arguments "$@"
          fi
          ;;
        *)
          if [[ "${2:-}" == "--help" ]] || [[ "${2:-}" == "-h" ]]; then
            parse_arguments "$@"
          fi
          ;;
      esac
    fi
    ;;
esac

# Check if running as root (required for most operations)
if [[ $EUID -ne 0 ]]; then
  echo "This tool must be run as root."
  exit 1
fi

# Parse remaining arguments that require root
parse_arguments "$@"

# Initialize debug logging (after parsing --debug flag)
debug_init "$@"

# Initialize structured logging (after parsing --log-file and --verbose flags)
log_init "$@"

# Set up exit trap for debug and structured logging
trap 'debug_end; log_end' EXIT

# Log startup
debug_info "Backupd starting (PID: $$)"
log_info "Backupd $VERSION starting (PID: $$)"

# Create install directory if needed
mkdir -p "$INSTALL_DIR"
debug_trace "Install directory: $INSTALL_DIR"

# Install command if not already installed
if [[ ! -L "/usr/local/bin/backupd" ]]; then
  debug_info "Installing backupd command"
  install_command
fi

# Run main menu
debug_info "Entering main menu"
main_menu
