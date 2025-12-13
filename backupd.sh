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

VERSION="2.0.1"
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

  # Stop and disable timers
  systemctl stop backupd-db.timer 2>/dev/null || true
  systemctl stop backupd-files.timer 2>/dev/null || true
  systemctl stop backupd-verify.timer 2>/dev/null || true
  systemctl disable backupd-db.timer 2>/dev/null || true
  systemctl disable backupd-files.timer 2>/dev/null || true
  systemctl disable backupd-verify.timer 2>/dev/null || true

  # Remove cron jobs (legacy)
  ( crontab -l 2>/dev/null | grep -Fv "$SCRIPTS_DIR/db_backup.sh" | grep -Fv "$SCRIPTS_DIR/files_backup.sh" ) | crontab - 2>/dev/null || true

  # Remove secrets
  local secrets_dir
  secrets_dir="$(get_secrets_dir)"
  if [[ -n "$secrets_dir" && -d "$secrets_dir" ]]; then
    unlock_secrets "$secrets_dir"
    rm -rf "$secrets_dir"
  fi

  # Remove install directory
  rm -rf "$INSTALL_DIR"

  # Remove command
  rm -f "/usr/local/bin/backupd"

  # Remove systemd units
  rm -f /etc/systemd/system/backupd-db.service
  rm -f /etc/systemd/system/backupd-db.timer
  rm -f /etc/systemd/system/backupd-files.service
  rm -f /etc/systemd/system/backupd-files.timer
  rm -f /etc/systemd/system/backupd-verify.service
  rm -f /etc/systemd/system/backupd-verify.timer
  systemctl daemon-reload 2>/dev/null || true

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
      echo "  3. View status"
      echo "  4. View logs"
      echo "  5. Manage schedules"
      echo "  6. Reconfigure"
      echo "  7. Uninstall"
      echo
      echo "  U. Update tool"
      echo "  0. Exit"
      echo
      read -p "Select option [1-7, U, 0]: " choice

      case "$choice" in
        1) run_backup ;;
        2) run_restore ;;
        3) show_status ;;
        4) view_logs ;;
        5) manage_schedules ;;
        6) run_setup ;;
        7) uninstall_tool ;;
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
  echo "Usage: backupd [OPTIONS]"
  echo
  echo "Options:"
  echo "  --help, -h          Show this help message"
  echo "  --version, -v       Show version information"
  echo "  --update            Check for and install updates"
  echo "  --check-update      Check for updates (no install)"
  echo "  --dev-update        Update from develop branch (testing only)"
  echo
  echo "Run without arguments to start the interactive menu."
}

show_version() {
  echo "Backupd v${VERSION}"
  echo "by ${AUTHOR}"
  echo "${WEBSITE}"
}

parse_arguments() {
  case "${1:-}" in
    --help|-h)
      show_help
      exit 0
      ;;
    --version|-v)
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
  --help|-h|--version|-v)
    parse_arguments "$@"
    ;;
esac

# Check if running as root (required for most operations)
if [[ $EUID -ne 0 ]]; then
  echo "This tool must be run as root."
  exit 1
fi

# Parse remaining arguments that require root
parse_arguments "$@"

# Create install directory if needed
mkdir -p "$INSTALL_DIR"

# Install command if not already installed
if [[ ! -L "/usr/local/bin/backupd" ]]; then
  install_command
fi

# Run main menu
main_menu
