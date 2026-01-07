#!/usr/bin/env bash
# ============================================================================
# Backupd - CLI Module
# Subcommand dispatcher for non-interactive CLI usage
# CLIG compliant: https://clig.dev/
# ============================================================================

# ---------- Helper Functions ----------

# Run a backup script and log any errors
# Captures output, displays it, and logs errors if the script fails
run_backup_script() {
  local script_path="$1"
  local backup_type="$2"
  local exit_code=0
  local temp_output

  # Create temp file for capturing output
  temp_output="$(mktemp)"

  # Run script, capture output (disable pipefail temporarily to capture exit code)
  set +o pipefail
  bash "$script_path" 2>&1 | tee "$temp_output"
  exit_code=${PIPESTATUS[0]}
  set -o pipefail

  # If script failed, log the error with context
  if [[ $exit_code -ne 0 ]]; then
    # Extract error lines from output
    local error_lines
    error_lines=$(grep -E '^\[ERROR\]|^ERROR:|failed|Failed' "$temp_output" 2>/dev/null | head -5 | tr '\n' ' ')

    if [[ -n "$error_lines" ]]; then
      log_error "Backup failed ($backup_type): $error_lines"
    else
      log_error "Backup failed ($backup_type) with exit code $exit_code"
    fi
  fi

  rm -f "$temp_output"
  return $exit_code
}

# ---------- CLI Dispatcher ----------

# Main dispatcher - routes subcommands to handlers
# Returns 0 on success, appropriate exit code on failure
cli_dispatch() {
  log_func_enter
  debug_enter "cli_dispatch" "$@"
  log_info "CLI dispatch: $(redact_cmdline_args "$*")"
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    backup)
      cli_backup "$@"
      ;;
    restore)
      cli_restore "$@"
      ;;
    status)
      cli_status "$@"
      ;;
    verify)
      cli_verify "$@"
      ;;
    schedule)
      cli_schedule "$@"
      ;;
    logs)
      cli_logs "$@"
      ;;
    notifications)
      cli_notifications "$@"
      ;;
    history)
      cli_history "$@"
      ;;
    job|jobs)
      cli_job "$@"
      ;;
    *)
      print_error "Unknown command: $subcommand"
      echo "Run 'backupd --help' for usage information."
      return $EXIT_USAGE
      ;;
  esac
}

# ---------- Backup Subcommand ----------

cli_backup() {
  log_func_enter
  debug_enter "cli_backup" "$@"
  local backup_type="${1:-}"
  shift || true

  case "$backup_type" in
    --help|-h|"")
      cli_backup_help
      return 0
      ;;
  esac

  # Parse remaining arguments (global flags that appear after subcommand)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run|-n)
        DRY_RUN=1
        export DRY_RUN
        ;;
      --json)
        JSON_OUTPUT=1
        export JSON_OUTPUT
        ;;
      --quiet|-q)
        QUIET_MODE=1
        export QUIET_MODE
        ;;
      --job-id)
        if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
          JOB_ID="$2"
          export JOB_ID
          shift
        fi
        ;;
      --job-id=*)
        JOB_ID="${1#--job-id=}"
        export JOB_ID
        ;;
      --help|-h)
        cli_backup_help
        return 0
        ;;
      *)
        print_error "Unknown option: $1"
        cli_backup_help
        return $EXIT_USAGE
        ;;
    esac
    shift
  done

  # Require root for actual backup operations (not in dry-run)
  if [[ $EUID -ne 0 ]] && ! is_dry_run; then
    print_error "Backup operations require root privileges."
    return $EXIT_NOPERM
  fi

  # Require configuration
  if ! is_configured; then
    print_error "System not configured. Run 'backupd' to set up first."
    return $EXIT_NOT_CONFIGURED
  fi

  case "$backup_type" in
    db|database)
      if [[ -f "$SCRIPTS_DIR/db_backup.sh" ]]; then
        if is_dry_run; then
          dry_run_msg "bash $SCRIPTS_DIR/db_backup.sh"
          return 0
        fi
        [[ "${QUIET_MODE:-0}" -ne 1 ]] && print_info "Starting database backup..."
        run_backup_script "$SCRIPTS_DIR/db_backup.sh" "database"
        return $?
      else
        print_error "Database backup script not found. Run setup first."
        return $EXIT_NOINPUT
      fi
      ;;
    files)
      if [[ -f "$SCRIPTS_DIR/files_backup.sh" ]]; then
        if is_dry_run; then
          dry_run_msg "bash $SCRIPTS_DIR/files_backup.sh"
          return 0
        fi
        [[ "${QUIET_MODE:-0}" -ne 1 ]] && print_info "Starting files backup..."
        run_backup_script "$SCRIPTS_DIR/files_backup.sh" "files"
        return $?
      else
        print_error "Files backup script not found. Run setup first."
        return $EXIT_NOINPUT
      fi
      ;;
    all|both)
      local exit_code=0

      if [[ -f "$SCRIPTS_DIR/db_backup.sh" ]]; then
        if is_dry_run; then
          dry_run_msg "bash $SCRIPTS_DIR/db_backup.sh"
        else
          [[ "${QUIET_MODE:-0}" -ne 1 ]] && print_info "Starting database backup..."
          run_backup_script "$SCRIPTS_DIR/db_backup.sh" "database" || exit_code=$?
        fi
      else
        print_error "Database backup script not found."
        exit_code=$EXIT_NOINPUT
      fi

      if [[ -f "$SCRIPTS_DIR/files_backup.sh" ]]; then
        if is_dry_run; then
          dry_run_msg "bash $SCRIPTS_DIR/files_backup.sh"
        else
          [[ "${QUIET_MODE:-0}" -ne 1 ]] && print_info "Starting files backup..."
          run_backup_script "$SCRIPTS_DIR/files_backup.sh" "files" || exit_code=$?
        fi
      else
        print_error "Files backup script not found."
        exit_code=$EXIT_NOINPUT
      fi

      return $exit_code
      ;;
    *)
      print_error "Unknown backup type: $backup_type"
      cli_backup_help
      return $EXIT_USAGE
      ;;
  esac
}

cli_backup_help() {
  cat <<EOF
Usage: backupd backup {db|files|all} [OPTIONS]

Create backups of database and/or files, uploading to configured remote storage.
Requires root privileges and prior configuration via 'backupd' interactive setup.

Subcommands:
  db, database    Backup MySQL/MariaDB databases
  files           Backup web files (sites, configs)
  all, both       Backup both database and files

Options:
  --dry-run, -n   Preview what would be executed without running
  --json          Output in JSON format
  --job-id ID     Job ID for progress tracking (used by API)
  --help, -h      Show this help message

Global Options (can appear before OR after 'backup'):
  --quiet, -q     Suppress non-essential output (ideal for cron)
  --debug         Enable debug logging

Examples:
  backupd backup db              # Backup database now
  backupd backup files           # Backup files now
  backupd backup all             # Backup both
  backupd --dry-run backup db    # Preview database backup (preferred)
  backupd backup db --dry-run    # Also works (flag after subcommand)
  backupd --quiet backup db      # Silent mode for cron (preferred)
  backupd backup db --quiet      # Also works (flag after subcommand)

See also: restore, verify, schedule, status
EOF
}

# ---------- Restore Subcommand ----------

cli_restore() {
  local restore_type="${1:-}"
  local list_only=0
  local backup_id="${BACKUP_ID:-}"
  local job_id="${JOB_ID:-}"
  shift || true

  # Parse flags (including global flags that appear after subcommand)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --list|-l)
        list_only=1
        ;;
      --backup-id)
        backup_id="$2"
        shift
        ;;
      --backup-id=*)
        backup_id="${1#--backup-id=}"
        ;;
      --job-id)
        job_id="$2"
        shift
        ;;
      --job-id=*)
        job_id="${1#--job-id=}"
        ;;
      --dry-run|-n)
        DRY_RUN=1
        export DRY_RUN
        ;;
      --json)
        JSON_OUTPUT=1
        export JSON_OUTPUT
        ;;
      --quiet|-q)
        QUIET_MODE=1
        export QUIET_MODE
        ;;
      --help|-h)
        cli_restore_help
        return 0
        ;;
      *)
        if [[ "$1" != -* ]]; then
          : # Let it fall through
        else
          print_error "Unknown option: $1"
          return $EXIT_USAGE
        fi
        ;;
    esac
    shift
  done

  case "$restore_type" in
    --help|-h|"")
      cli_restore_help
      return 0
      ;;
  esac

  # Require root for actual operations (not in dry-run or list mode)
  if [[ $EUID -ne 0 ]] && ! is_dry_run && [[ $list_only -eq 0 ]]; then
    print_error "Restore operations require root privileges."
    return $EXIT_NOPERM
  fi

  # Require configuration
  if ! is_configured; then
    print_error "System not configured. Run 'backupd' to set up first."
    return $EXIT_NOT_CONFIGURED
  fi

  case "$restore_type" in
    db|database)
      if [[ $list_only -eq 1 ]]; then
        cli_list_backups "db"
        return $?
      fi
      if [[ -f "$SCRIPTS_DIR/db_restore.sh" ]]; then
        if is_dry_run; then
          dry_run_msg "bash $SCRIPTS_DIR/db_restore.sh"
          return 0
        fi
        [[ -n "$job_id" ]] && export JOB_ID="$job_id"
        [[ -n "$backup_id" ]] && export BACKUP_ID="$backup_id"
        bash "$SCRIPTS_DIR/db_restore.sh"
        return $?
      else
        print_error "Database restore script not found. Run setup first."
        return $EXIT_NOINPUT
      fi
      ;;
    files)
      if [[ $list_only -eq 1 ]]; then
        cli_list_backups "files"
        return $?
      fi
      if [[ -f "$SCRIPTS_DIR/files_restore.sh" ]]; then
        if is_dry_run; then
          dry_run_msg "bash $SCRIPTS_DIR/files_restore.sh"
          return 0
        fi
        [[ -n "$job_id" ]] && export JOB_ID="$job_id"
        [[ -n "$backup_id" ]] && export BACKUP_ID="$backup_id"
        bash "$SCRIPTS_DIR/files_restore.sh"
        return $?
      else
        print_error "Files restore script not found. Run setup first."
        return $EXIT_NOINPUT
      fi
      ;;
    *)
      print_error "Unknown restore type: $restore_type"
      cli_restore_help
      return $EXIT_USAGE
      ;;
  esac
}

cli_list_backups() {
  local backup_type="$1"
  local rclone_remote rclone_path pattern

  rclone_remote="$(get_config_value 'RCLONE_REMOTE')"

  if [[ "$backup_type" == "db" ]]; then
    rclone_path="$(get_config_value 'RCLONE_DB_PATH')"
    pattern="*-db_backups-*.tar.gz.gpg"
  else
    rclone_path="$(get_config_value 'RCLONE_FILES_PATH')"
    pattern="*.tar.gz"
  fi

  if [[ -z "$rclone_path" ]]; then
    print_error "${backup_type^} backup path not configured"
    return $EXIT_NOT_CONFIGURED
  fi

  if is_json_output; then
    echo "{"
    echo "  \"type\": \"$backup_type\","
    echo "  \"remote\": \"$rclone_remote:$rclone_path\","
    echo "  \"backups\": ["
    local first=1
    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      [[ "$file" == *.sha256 ]] && continue
      [[ $first -eq 0 ]] && echo ","
      echo -n "    \"$file\""
      first=0
    done < <(rclone lsf "$rclone_remote:$rclone_path" --include "$pattern" 2>/dev/null | sort -r)
    echo
    echo "  ]"
    echo "}"
  else
    echo "Available ${backup_type} backups at $rclone_remote:$rclone_path"
    echo
    rclone lsf "$rclone_remote:$rclone_path" --include "$pattern" 2>/dev/null | grep -v '\.sha256$' | sort -r | head -20
    echo
    echo "(Showing most recent 20)"
  fi
}

cli_restore_help() {
  cat <<EOF
Usage: backupd restore {db|files} [OPTIONS]

Restore database or files from a previous backup stored in remote storage.
Requires root privileges. Restore is interactive (prompts for backup selection).

Subcommands:
  db, database    Restore database backup (decrypts and imports SQL)
  files           Restore files backup (extracts archive to original location)

Options:
  --list, -l        List available backups without restoring
  --backup-id ID    Backup file to restore (non-interactive mode)
  --job-id ID       Job ID for progress tracking (used by API)
  --dry-run, -n     Preview what would be executed without running
  --help, -h        Show this help message

Global Options (can appear before OR after 'restore'):
  --json            Output backup list in JSON format (with --list)
  --quiet, -q       Suppress non-essential output

Examples:
  backupd restore db --list               # List available database backups
  backupd restore files --list            # List available files backups
  backupd restore db                      # Interactive database restore
  backupd --dry-run restore db            # Preview restore (preferred)
  backupd restore db --dry-run            # Also works (flag after subcommand)
  backupd --json restore db --list        # JSON list of backups (preferred)
  backupd restore db --list --json        # Also works (flag after subcommand)
  backupd restore db --backup-id file.gpg # Non-interactive restore

See also: backup, verify, status
EOF
}

# ---------- Status Subcommand ----------

cli_status() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        JSON_OUTPUT=1
        ;;
      --help|-h)
        cli_status_help
        return 0
        ;;
      *)
        print_error "Unknown option: $1"
        return $EXIT_USAGE
        ;;
    esac
    shift
  done

  # Status can run without root (read-only)
  if is_json_output; then
    cli_status_json
  else
    cli_status_text
  fi
}

cli_status_text() {
  [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo "System Status"
  [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo "============="
  [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo

  # Configuration
  if is_configured; then
    print_success "Configuration: COMPLETE"
  else
    print_error "Configuration: NOT CONFIGURED"
    echo "Run 'backupd' to set up the backup system."
    return $EXIT_NOT_CONFIGURED
  fi

  # Secrets directory
  local secrets_dir
  secrets_dir="$(get_secrets_dir)"
  if [[ -n "$secrets_dir" ]] && [[ -d "$secrets_dir" ]]; then
    print_success "Secure storage: $secrets_dir"
  else
    print_error "Secure storage: NOT INITIALIZED"
  fi

  # Backup scripts
  [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo
  [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo "Backup Scripts:"
  [[ -f "$SCRIPTS_DIR/db_backup.sh" ]] && print_success "  Database backup script" || print_error "  Database backup script: missing"
  [[ -f "$SCRIPTS_DIR/files_backup.sh" ]] && print_success "  Files backup script" || print_error "  Files backup script: missing"

  # Scheduled backups
  [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo
  [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo "Scheduled Backups:"

  if systemctl is-enabled backupd-db.timer &>/dev/null; then
    local db_schedule
    db_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-db.timer 2>/dev/null | cut -d'=' -f2)
    print_success "  Database: $db_schedule"
  else
    print_warning "  Database: NOT SCHEDULED"
  fi

  if systemctl is-enabled backupd-files.timer &>/dev/null; then
    local files_schedule
    files_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-files.timer 2>/dev/null | cut -d'=' -f2)
    print_success "  Files: $files_schedule"
  else
    print_warning "  Files: NOT SCHEDULED"
  fi

  # Retention
  [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo
  local retention_desc
  retention_desc="$(get_config_value 'RETENTION_DESC')"
  if [[ -n "$retention_desc" ]]; then
    print_success "Retention: $retention_desc"
  else
    print_warning "Retention: NOT CONFIGURED"
  fi

  # Remote storage
  [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo
  local rclone_remote
  rclone_remote="$(get_config_value 'RCLONE_REMOTE')"
  if [[ -n "$rclone_remote" ]]; then
    print_success "Remote: $rclone_remote"
  else
    print_error "Remote: NOT CONFIGURED"
  fi

  # Recent activity
  [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo
  [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo "Recent Activity:"
  if [[ -f "$INSTALL_DIR/logs/db_logfile.log" ]]; then
    local last_db
    last_db=$(grep "START per-db backup" "$INSTALL_DIR/logs/db_logfile.log" 2>/dev/null | tail -1 | awk '{print $2, $3}')
    [[ -n "$last_db" ]] && echo "  Last DB backup: $last_db" || echo "  Last DB backup: none"
  else
    echo "  Last DB backup: no log"
  fi
  if [[ -f "$INSTALL_DIR/logs/files_logfile.log" ]]; then
    local last_files
    last_files=$(grep "START files backup" "$INSTALL_DIR/logs/files_logfile.log" 2>/dev/null | tail -1 | awk '{print $2, $3}')
    [[ -n "$last_files" ]] && echo "  Last Files backup: $last_files" || echo "  Last Files backup: none"
  else
    echo "  Last Files backup: no log"
  fi

  return 0
}

cli_status_json() {
  local configured=false
  local secrets_ok=false
  local db_script=false
  local files_script=false
  local db_schedule=""
  local files_schedule=""
  local retention=""
  local remote=""
  local last_db=""
  local last_files=""

  is_configured && configured=true

  local secrets_dir
  secrets_dir="$(get_secrets_dir)"
  [[ -n "$secrets_dir" && -d "$secrets_dir" ]] && secrets_ok=true

  [[ -f "$SCRIPTS_DIR/db_backup.sh" ]] && db_script=true
  [[ -f "$SCRIPTS_DIR/files_backup.sh" ]] && files_script=true

  if systemctl is-enabled backupd-db.timer &>/dev/null; then
    db_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-db.timer 2>/dev/null | cut -d'=' -f2)
  fi

  if systemctl is-enabled backupd-files.timer &>/dev/null; then
    files_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-files.timer 2>/dev/null | cut -d'=' -f2)
  fi

  retention="$(get_config_value 'RETENTION_DESC' 2>/dev/null)" || retention=""
  remote="$(get_config_value 'RCLONE_REMOTE' 2>/dev/null)" || remote=""

  if [[ -f "$INSTALL_DIR/logs/db_logfile.log" ]]; then
    last_db=$(grep "START per-db backup" "$INSTALL_DIR/logs/db_logfile.log" 2>/dev/null | tail -1 | awk '{print $2, $3}') || last_db=""
  fi
  if [[ -f "$INSTALL_DIR/logs/files_logfile.log" ]]; then
    last_files=$(grep "START files backup" "$INSTALL_DIR/logs/files_logfile.log" 2>/dev/null | tail -1 | awk '{print $2, $3}') || last_files=""
  fi

  cat <<EOF
{
  "configured": $configured,
  "secrets_initialized": $secrets_ok,
  "scripts": {
    "db_backup": $db_script,
    "files_backup": $files_script
  },
  "schedules": {
    "db": "$db_schedule",
    "files": "$files_schedule"
  },
  "retention": "$retention",
  "remote": "$remote",
  "last_backup": {
    "db": "$last_db",
    "files": "$last_files"
  }
}
EOF
}

cli_status_help() {
  cat <<EOF
Usage: backupd status [OPTIONS]

Display backup system status including configuration, schedules, and recent activity.
Shows script availability, scheduled timers, retention policy, and last backup times.

Options:
  --json          Output in JSON format (for scripting/monitoring)
  --help, -h      Show this help message

Global Options:
  --quiet, -q     Suppress headers and formatting

Examples:
  backupd status              # Human-readable status
  backupd status --json       # JSON for monitoring tools
  backupd status --json | jq .configured  # Check if configured

See also: verify, schedule, logs
EOF
}

# ---------- Verify Subcommand ----------

cli_verify() {
  local verify_type=""
  local quick_mode=0
  local full_mode=0
  local passphrase="${BACKUPD_PASSPHRASE:-}"
  local job_id="${JOB_ID:-}"

  # Parse arguments (including global flags that appear after subcommand)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --quick|-q)
        quick_mode=1
        ;;
      --full|-f)
        full_mode=1
        ;;
      --json)
        JSON_OUTPUT=1
        export JSON_OUTPUT
        ;;
      --passphrase)
        passphrase="$2"
        shift
        ;;
      --passphrase=*)
        passphrase="${1#--passphrase=}"
        ;;
      --dry-run|-n)
        DRY_RUN=1
        export DRY_RUN
        ;;
      --quiet)
        # Note: -q means --quick for verify, use --quiet for quiet mode
        QUIET_MODE=1
        export QUIET_MODE
        ;;
      --job-id)
        if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
          job_id="$2"
          JOB_ID="$job_id"
          export JOB_ID
          shift
        fi
        ;;
      --job-id=*)
        job_id="${1#--job-id=}"
        JOB_ID="$job_id"
        export JOB_ID
        ;;
      db|database)
        verify_type="db"
        ;;
      files)
        verify_type="files"
        ;;
      all|both)
        verify_type="both"
        ;;
      --help|-h)
        cli_verify_help
        return 0
        ;;
      *)
        print_error "Unknown option: $1"
        return $EXIT_USAGE
        ;;
    esac
    shift
  done

  # Require root
  if [[ $EUID -ne 0 ]]; then
    print_error "Verify operations require root privileges."
    return $EXIT_NOPERM
  fi

  # Require configuration
  if ! is_configured; then
    print_error "System not configured. Run 'backupd' to set up first."
    return $EXIT_NOT_CONFIGURED
  fi

  # Default to quick mode and both types
  [[ $quick_mode -eq 0 && $full_mode -eq 0 ]] && quick_mode=1
  [[ -z "$verify_type" ]] && verify_type="both"

  # Handle dry-run mode
  if is_dry_run; then
    if [[ $quick_mode -eq 1 ]]; then
      dry_run_msg "verify_quick $verify_type (check checksums exist in remote storage)"
    else
      dry_run_msg "verify_full $verify_type (download, decrypt, and verify latest backups)"
    fi
    return 0
  fi

  if [[ $quick_mode -eq 1 ]]; then
    if is_json_output; then
      cli_verify_quick_json "$verify_type"
      return $?
    fi
    [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo "Running quick verification..."
    verify_quick "$verify_type"
    return $?
  elif [[ $full_mode -eq 1 ]]; then
    # Get passphrase interactively if not provided
    if [[ -z "$passphrase" ]]; then
      echo "Full verification requires the backup encryption passphrase."
      read -sp "Enter encryption passphrase: " passphrase
      echo
    fi

    if [[ -z "$passphrase" ]]; then
      print_error "No passphrase provided."
      return $EXIT_NOINPUT
    fi

    if is_json_output; then
      cli_verify_full_json "$verify_type" "$passphrase"
    else
      [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo "Running full verification..."
      cli_verify_full "$verify_type" "$passphrase"
    fi
    return $?
  fi
}

# JSON output for verify quick command
cli_verify_quick_json() {
  local backup_type="$1"
  local rclone_remote rclone_db_path rclone_files_path
  rclone_remote="$(get_config_value 'RCLONE_REMOTE')"
  rclone_db_path="$(get_config_value 'RCLONE_DB_PATH')"
  rclone_files_path="$(get_config_value 'RCLONE_FILES_PATH')"

  local db_status="SKIPPED" files_status="SKIPPED"
  local db_total=0 db_with_checksum=0 db_total_size=0
  local files_total=0 files_with_checksum=0 files_total_size=0
  local overall_status="PASSED"

  # Check database backups
  if [[ "$backup_type" == "db" || "$backup_type" == "both" ]] && [[ -n "$rclone_db_path" ]]; then
    declare -A checksum_files=()
    local all_files
    all_files=$(rclone lsl "$rclone_remote:$rclone_db_path" 2>/dev/null) || true

    # First pass: count checksums
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local filename
      filename=$(echo "$line" | awk '{print $NF}')
      if [[ "$filename" == *.sha256 ]]; then
        checksum_files["$filename"]=1
      fi
    done <<< "$all_files"

    # Second pass: count and verify backups
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local size filename
      size=$(echo "$line" | awk '{print $1}')
      filename=$(echo "$line" | awk '{print $NF}')
      if [[ "$filename" == *-db_backups-*.tar.gz.gpg ]]; then
        ((db_total++)) || true
        db_total_size=$((db_total_size + size))
        if [[ -n "${checksum_files[${filename}.sha256]:-}" ]]; then
          ((db_with_checksum++)) || true
        fi
      fi
    done <<< "$all_files"

    if [[ $db_total -eq 0 ]]; then
      db_status="FAILED"
      overall_status="FAILED"
    elif [[ $db_with_checksum -lt $db_total ]]; then
      db_status="WARNING"
      [[ "$overall_status" != "FAILED" ]] && overall_status="WARNING"
    else
      db_status="PASSED"
    fi
  fi

  # Check files backups
  if [[ "$backup_type" == "files" || "$backup_type" == "both" ]] && [[ -n "$rclone_files_path" ]]; then
    declare -A checksum_files=()
    local all_files
    all_files=$(rclone lsl "$rclone_remote:$rclone_files_path" 2>/dev/null) || true

    # First pass: count checksums
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local filename
      filename=$(echo "$line" | awk '{print $NF}')
      if [[ "$filename" == *.sha256 ]]; then
        checksum_files["$filename"]=1
      fi
    done <<< "$all_files"

    # Second pass: count and verify backups
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local size filename
      size=$(echo "$line" | awk '{print $1}')
      filename=$(echo "$line" | awk '{print $NF}')
      if [[ "$filename" == *.tar.gz ]] && [[ "$filename" != *.sha256 ]]; then
        ((files_total++)) || true
        files_total_size=$((files_total_size + size))
        if [[ -n "${checksum_files[${filename}.sha256]:-}" ]]; then
          ((files_with_checksum++)) || true
        fi
      fi
    done <<< "$all_files"

    if [[ $files_total -eq 0 ]]; then
      files_status="FAILED"
      overall_status="FAILED"
    elif [[ $files_with_checksum -lt $files_total ]]; then
      files_status="WARNING"
      [[ "$overall_status" != "FAILED" ]] && overall_status="WARNING"
    else
      files_status="PASSED"
    fi
  fi

  # Output JSON
  cat <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "type": "$backup_type",
  "status": "$overall_status",
  "results": {
    "db": {
      "status": "$db_status",
      "total": $db_total,
      "with_checksum": $db_with_checksum,
      "total_size_bytes": $db_total_size
    },
    "files": {
      "status": "$files_status",
      "total": $files_total,
      "with_checksum": $files_with_checksum,
      "total_size_bytes": $files_total_size
    }
  }
}
EOF

  # Return appropriate exit code
  case "$overall_status" in
    PASSED) return 0 ;;
    WARNING) return 2 ;;
    FAILED) return 1 ;;
  esac
}

# Full verification - download, decrypt, and verify
cli_verify_full() {
  local backup_type="$1"
  local passphrase="$2"
  local rclone_remote rclone_db_path rclone_files_path
  local temp_dir overall_status="PASSED"

  rclone_remote="$(get_config_value 'RCLONE_REMOTE')"
  rclone_db_path="$(get_config_value 'RCLONE_DB_PATH')"
  rclone_files_path="$(get_config_value 'RCLONE_FILES_PATH')"

  temp_dir="$(mktemp -d)"
  trap "rm -rf '$temp_dir'" RETURN

  # Verify database backups
  if [[ "$backup_type" == "db" || "$backup_type" == "both" ]] && [[ -n "$rclone_db_path" ]]; then
    echo "Verifying database backups..."
    local latest_db
    latest_db=$(rclone lsf "$rclone_remote:$rclone_db_path" --include "*-db_backups-*.tar.gz.gpg" 2>/dev/null | sort -r | head -1)

    if [[ -n "$latest_db" ]]; then
      echo "  Testing: $latest_db"
      if rclone copy "$rclone_remote:$rclone_db_path/$latest_db" "$temp_dir/" 2>/dev/null; then
        if gpg --batch --quiet --pinentry-mode=loopback --passphrase "$passphrase" -d "$temp_dir/$latest_db" 2>/dev/null | tar -tzf - >/dev/null 2>&1; then
          print_success "  Database backup verified: $latest_db"
        else
          print_error "  Database backup decryption failed: $latest_db"
          overall_status="FAILED"
        fi
      else
        print_error "  Failed to download: $latest_db"
        overall_status="FAILED"
      fi
      rm -f "$temp_dir/$latest_db"
    else
      print_warning "  No database backups found"
      [[ "$overall_status" != "FAILED" ]] && overall_status="WARNING"
    fi
  fi

  # Verify files backups
  if [[ "$backup_type" == "files" || "$backup_type" == "both" ]] && [[ -n "$rclone_files_path" ]]; then
    echo "Verifying files backups..."
    local latest_files
    latest_files=$(rclone lsf "$rclone_remote:$rclone_files_path" --include "*.tar.gz" --exclude "*.sha256" 2>/dev/null | sort -r | head -1)

    if [[ -n "$latest_files" ]]; then
      echo "  Testing: $latest_files"
      if rclone copy "$rclone_remote:$rclone_files_path/$latest_files" "$temp_dir/" 2>/dev/null; then
        if tar -tzf "$temp_dir/$latest_files" >/dev/null 2>&1; then
          print_success "  Files backup verified: $latest_files"
        else
          print_error "  Files backup corrupted: $latest_files"
          overall_status="FAILED"
        fi
      else
        print_error "  Failed to download: $latest_files"
        overall_status="FAILED"
      fi
      rm -f "$temp_dir/$latest_files"
    else
      print_warning "  No files backups found"
      [[ "$overall_status" != "FAILED" ]] && overall_status="WARNING"
    fi
  fi

  echo
  case "$overall_status" in
    PASSED) print_success "Full verification: PASSED" ;;
    WARNING) print_warning "Full verification: WARNING" ;;
    FAILED) print_error "Full verification: FAILED" ;;
  esac

  case "$overall_status" in
    PASSED) return 0 ;;
    WARNING) return 2 ;;
    FAILED) return 1 ;;
  esac
}

# JSON output for full verification
cli_verify_full_json() {
  local backup_type="$1"
  local passphrase="$2"
  local rclone_remote rclone_db_path rclone_files_path
  local temp_dir overall_status="PASSED"
  local db_status="SKIPPED" db_file="" db_verified="false"
  local files_status="SKIPPED" files_file="" files_verified="false"

  rclone_remote="$(get_config_value 'RCLONE_REMOTE')"
  rclone_db_path="$(get_config_value 'RCLONE_DB_PATH')"
  rclone_files_path="$(get_config_value 'RCLONE_FILES_PATH')"

  temp_dir="$(mktemp -d)"
  trap "rm -rf '$temp_dir'" RETURN

  # Verify database backups
  if [[ "$backup_type" == "db" || "$backup_type" == "both" ]] && [[ -n "$rclone_db_path" ]]; then
    local latest_db
    latest_db=$(rclone lsf "$rclone_remote:$rclone_db_path" --include "*-db_backups-*.tar.gz.gpg" 2>/dev/null | sort -r | head -1)

    if [[ -n "$latest_db" ]]; then
      db_file="$latest_db"
      if rclone copy "$rclone_remote:$rclone_db_path/$latest_db" "$temp_dir/" 2>/dev/null; then
        if gpg --batch --quiet --pinentry-mode=loopback --passphrase "$passphrase" -d "$temp_dir/$latest_db" 2>/dev/null | tar -tzf - >/dev/null 2>&1; then
          db_status="PASSED"
          db_verified="true"
        else
          db_status="FAILED"
          overall_status="FAILED"
        fi
      else
        db_status="FAILED"
        overall_status="FAILED"
      fi
      rm -f "$temp_dir/$latest_db"
    else
      db_status="WARNING"
      [[ "$overall_status" != "FAILED" ]] && overall_status="WARNING"
    fi
  fi

  # Verify files backups
  if [[ "$backup_type" == "files" || "$backup_type" == "both" ]] && [[ -n "$rclone_files_path" ]]; then
    local latest_files
    latest_files=$(rclone lsf "$rclone_remote:$rclone_files_path" --include "*.tar.gz" --exclude "*.sha256" 2>/dev/null | sort -r | head -1)

    if [[ -n "$latest_files" ]]; then
      files_file="$latest_files"
      if rclone copy "$rclone_remote:$rclone_files_path/$latest_files" "$temp_dir/" 2>/dev/null; then
        if tar -tzf "$temp_dir/$latest_files" >/dev/null 2>&1; then
          files_status="PASSED"
          files_verified="true"
        else
          files_status="FAILED"
          overall_status="FAILED"
        fi
      else
        files_status="FAILED"
        overall_status="FAILED"
      fi
      rm -f "$temp_dir/$latest_files"
    else
      files_status="WARNING"
      [[ "$overall_status" != "FAILED" ]] && overall_status="WARNING"
    fi
  fi

  cat <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "type": "$backup_type",
  "mode": "full",
  "status": "$overall_status",
  "results": {
    "db": {
      "status": "$db_status",
      "file": "$db_file",
      "decrypted": $db_verified
    },
    "files": {
      "status": "$files_status",
      "file": "$files_file",
      "verified": $files_verified
    }
  }
}
EOF

  case "$overall_status" in
    PASSED) return 0 ;;
    WARNING) return 2 ;;
    FAILED) return 1 ;;
  esac
}

cli_verify_help() {
  cat <<EOF
Usage: backupd verify [TYPE] [OPTIONS]

Verify backup integrity by checking checksums and optionally decrypting archives.
Requires root privileges. Quick mode checks remote storage without downloading.

Types:
  db, database    Verify database backups only
  files           Verify files backups only
  all, both       Verify both (default)

Options:
  --quick, -q           Quick check: verify checksums exist (default)
  --full, -f            Full test: download, decrypt, and verify
  --passphrase PASS     Encryption passphrase for --full mode (non-interactive)
  --dry-run, -n         Preview what would be verified without running
  --job-id ID           Job ID for progress tracking (used by API)
  --json                Output results in JSON format
  --help, -h            Show this help message

Global Options (can appear before OR after 'verify'):
  --quiet               Suppress non-essential output (note: -q means --quick)

Exit Codes:
  0               All checks passed
  1               One or more checks failed
  2               Warnings (missing checksums)

Examples:
  backupd verify                              # Quick check of all backups
  backupd verify db --quick                   # Quick check of database backups
  backupd verify files                        # Quick check of files backups
  backupd --dry-run verify                    # Preview verification (preferred)
  backupd verify --dry-run                    # Also works (flag after subcommand)
  backupd --json verify                       # JSON output for scripting (preferred)
  backupd verify --json                       # Also works (flag after subcommand)
  backupd verify --json | jq .status          # Get overall status
  backupd verify --full --passphrase "pass"   # Full verification (non-interactive)
  BACKUPD_PASSPHRASE=x backupd verify --full  # Full verify via env var

See also: backup, restore, status
EOF
}

# ---------- Schedule Subcommand ----------

cli_schedule() {
  local action="${1:-list}"
  shift || true

  # Check for --json before action
  if [[ "$action" == "--json" ]]; then
    JSON_OUTPUT=1
    action="${1:-list}"
    shift || true
  fi

  case "$action" in
    list|ls)
      cli_schedule_list "$@"
      ;;
    enable)
      cli_schedule_enable "$@"
      ;;
    disable)
      cli_schedule_disable "$@"
      ;;
    --help|-h)
      cli_schedule_help
      return 0
      ;;
    *)
      print_error "Unknown action: $action"
      cli_schedule_help
      return $EXIT_USAGE
      ;;
  esac
}

cli_schedule_list() {
  if is_json_output; then
    cli_schedule_list_json
  else
    cli_schedule_list_text
  fi
}

cli_schedule_list_text() {
  echo "Backup Schedules"
  echo "================"
  echo

  # Database backup
  if systemctl is-enabled backupd-db.timer &>/dev/null; then
    local db_schedule
    db_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-db.timer 2>/dev/null | cut -d'=' -f2)
    print_success "Database: $db_schedule (enabled)"
  else
    print_warning "Database: NOT SCHEDULED"
  fi

  # Files backup
  if systemctl is-enabled backupd-files.timer &>/dev/null; then
    local files_schedule
    files_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-files.timer 2>/dev/null | cut -d'=' -f2)
    print_success "Files: $files_schedule (enabled)"
  else
    print_warning "Files: NOT SCHEDULED"
  fi

  # Verify (quick)
  if systemctl is-enabled backupd-verify.timer &>/dev/null; then
    local verify_schedule
    verify_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-verify.timer 2>/dev/null | cut -d'=' -f2)
    print_success "Verify (quick): $verify_schedule (enabled)"
  else
    print_warning "Verify (quick): NOT SCHEDULED"
  fi

  # Verify (full)
  if systemctl is-enabled backupd-verify-full.timer &>/dev/null; then
    local verify_full_schedule
    verify_full_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-verify-full.timer 2>/dev/null | cut -d'=' -f2)
    print_success "Verify (full): $verify_full_schedule (enabled)"
  else
    print_warning "Verify (full): NOT SCHEDULED"
  fi

  # Retention policy
  echo
  local retention_desc
  retention_desc="$(get_config_value 'RETENTION_DESC' 2>/dev/null)" || retention_desc=""
  if [[ -n "$retention_desc" ]]; then
    echo "Retention policy: $retention_desc"
  else
    echo "Retention policy: NOT CONFIGURED"
  fi

  # Next runs
  echo
  echo "Next scheduled runs:"
  systemctl list-timers backupd-* --no-pager 2>/dev/null | head -10 || echo "  No timers scheduled"
}

cli_schedule_list_json() {
  local db_enabled=false db_schedule=""
  local files_enabled=false files_schedule=""
  local verify_enabled=false verify_schedule=""
  local verify_full_enabled=false verify_full_schedule=""

  if systemctl is-enabled backupd-db.timer &>/dev/null; then
    db_enabled=true
    db_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-db.timer 2>/dev/null | cut -d'=' -f2)
  fi

  if systemctl is-enabled backupd-files.timer &>/dev/null; then
    files_enabled=true
    files_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-files.timer 2>/dev/null | cut -d'=' -f2)
  fi

  if systemctl is-enabled backupd-verify.timer &>/dev/null; then
    verify_enabled=true
    verify_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-verify.timer 2>/dev/null | cut -d'=' -f2)
  fi

  if systemctl is-enabled backupd-verify-full.timer &>/dev/null; then
    verify_full_enabled=true
    verify_full_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-verify-full.timer 2>/dev/null | cut -d'=' -f2)
  fi

  local retention_desc
  retention_desc="$(get_config_value 'RETENTION_DESC' 2>/dev/null)" || retention_desc=""

  cat <<EOF
{
  "schedules": {
    "db": {"enabled": $db_enabled, "schedule": "$db_schedule"},
    "files": {"enabled": $files_enabled, "schedule": "$files_schedule"},
    "verify_quick": {"enabled": $verify_enabled, "schedule": "$verify_schedule"},
    "verify_full": {"enabled": $verify_full_enabled, "schedule": "$verify_full_schedule"}
  },
  "retention": "$retention_desc"
}
EOF
}

cli_schedule_enable() {
  local timer_type=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      db|database)
        timer_type="db"
        ;;
      files)
        timer_type="files"
        ;;
      verify)
        timer_type="verify"
        ;;
      --help|-h)
        cli_schedule_help
        return 0
        ;;
      *)
        print_error "Unknown option: $1"
        return $EXIT_USAGE
        ;;
    esac
    shift
  done

  if [[ -z "$timer_type" ]]; then
    print_error "Specify timer type: db, files, or verify"
    echo "Usage: backupd schedule enable {db|files|verify}"
    return $EXIT_USAGE
  fi

  # Require root
  if [[ $EUID -ne 0 ]]; then
    print_error "Schedule operations require root privileges."
    return $EXIT_NOPERM
  fi

  local timer_name="backupd-${timer_type}.timer"

  if [[ ! -f "/etc/systemd/system/$timer_name" ]]; then
    print_error "Timer not configured. Use interactive mode to set schedule first."
    echo "Run 'backupd' and go to 'Manage schedules'."
    return $EXIT_NOT_CONFIGURED
  fi

  systemctl enable "$timer_name" 2>/dev/null || true
  systemctl start "$timer_name" 2>/dev/null || true

  print_success "Enabled $timer_name"
}

cli_schedule_disable() {
  local timer_type=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      db|database)
        timer_type="db"
        ;;
      files)
        timer_type="files"
        ;;
      verify)
        timer_type="verify"
        ;;
      --help|-h)
        cli_schedule_help
        return 0
        ;;
      *)
        print_error "Unknown option: $1"
        return $EXIT_USAGE
        ;;
    esac
    shift
  done

  if [[ -z "$timer_type" ]]; then
    print_error "Specify timer type: db, files, or verify"
    echo "Usage: backupd schedule disable {db|files|verify}"
    return $EXIT_USAGE
  fi

  # Require root
  if [[ $EUID -ne 0 ]]; then
    print_error "Schedule operations require root privileges."
    return $EXIT_NOPERM
  fi

  local timer_name="backupd-${timer_type}.timer"

  systemctl stop "$timer_name" 2>/dev/null || true
  systemctl disable "$timer_name" 2>/dev/null || true

  # Also remove cron entries for db/files
  if [[ "$timer_type" == "db" ]]; then
    ( crontab -l 2>/dev/null | grep -Fv "$SCRIPTS_DIR/db_backup.sh" ) | crontab - 2>/dev/null || true
  elif [[ "$timer_type" == "files" ]]; then
    ( crontab -l 2>/dev/null | grep -Fv "$SCRIPTS_DIR/files_backup.sh" ) | crontab - 2>/dev/null || true
  fi

  print_success "Disabled $timer_name"
}

cli_schedule_help() {
  cat <<EOF
Usage: backupd schedule [COMMAND] [TYPE]

Manage systemd timer-based backup schedules. Schedules must first be configured
via the interactive menu before they can be enabled/disabled here.

Commands:
  list              Show current schedules (default)
  enable TYPE       Enable a backup schedule timer
  disable TYPE      Disable a backup schedule timer

Types:
  db, database      Database backup timer
  files             Files backup timer
  verify            Quick integrity check timer

Options:
  --json            Output in JSON format (for list)
  --help, -h        Show this help message

Requires: Root privileges for enable/disable operations.

Examples:
  backupd schedule                  # List all schedules
  backupd schedule list
  backupd schedule --json           # JSON output for monitoring
  backupd schedule enable db        # Enable database backup timer
  backupd schedule disable files    # Disable files backup timer

See also: status, backup, verify
EOF
}

# ---------- Logs Subcommand ----------

cli_logs() {
  local log_type=""
  local lines=50

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lines|-n)
        lines="$2"
        shift
        ;;
      --json)
        JSON_OUTPUT=1
        ;;
      db|database)
        log_type="db"
        ;;
      files)
        log_type="files"
        ;;
      verify)
        log_type="verify"
        ;;
      all)
        log_type="all"
        ;;
      --help|-h)
        cli_logs_help
        return 0
        ;;
      *)
        print_error "Unknown option: $1"
        return $EXIT_USAGE
        ;;
    esac
    shift
  done

  # Default to all logs
  [[ -z "$log_type" ]] && log_type="all"

  local log_dir="$INSTALL_DIR/logs"

  if [[ ! -d "$log_dir" ]]; then
    print_error "Log directory not found: $log_dir"
    return $EXIT_NOINPUT
  fi

  # Route to JSON or text output
  if is_json_output; then
    cli_logs_json "$log_type" "$lines"
    return $?
  fi

  case "$log_type" in
    db|database)
      if [[ -f "$log_dir/db_logfile.log" ]]; then
        [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo "=== Database Backup Log (last $lines lines) ==="
        tail -n "$lines" "$log_dir/db_logfile.log"
      else
        print_warning "No database backup log found."
      fi
      ;;
    files)
      if [[ -f "$log_dir/files_logfile.log" ]]; then
        [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo "=== Files Backup Log (last $lines lines) ==="
        tail -n "$lines" "$log_dir/files_logfile.log"
      else
        print_warning "No files backup log found."
      fi
      ;;
    verify)
      if [[ -f "$log_dir/verify_logfile.log" ]]; then
        [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo "=== Verification Log (last $lines lines) ==="
        tail -n "$lines" "$log_dir/verify_logfile.log"
      else
        print_warning "No verification log found."
      fi
      ;;
    all)
      local found=0
      if [[ -f "$log_dir/db_logfile.log" ]]; then
        echo "=== Database Backup Log (last $lines lines) ==="
        tail -n "$lines" "$log_dir/db_logfile.log"
        echo
        found=1
      fi
      if [[ -f "$log_dir/files_logfile.log" ]]; then
        echo "=== Files Backup Log (last $lines lines) ==="
        tail -n "$lines" "$log_dir/files_logfile.log"
        echo
        found=1
      fi
      if [[ -f "$log_dir/verify_logfile.log" ]]; then
        echo "=== Verification Log (last $lines lines) ==="
        tail -n "$lines" "$log_dir/verify_logfile.log"
        found=1
      fi
      if [[ $found -eq 0 ]]; then
        print_warning "No log files found in $log_dir"
      fi
      ;;
  esac
}

cli_logs_help() {
  cat <<EOF
Usage: backupd logs [TYPE] [OPTIONS]

View backup operation logs stored in /etc/backupd/logs/.
Useful for debugging backup issues or monitoring recent activity.

Types:
  db, database    Database backup log (db_logfile.log)
  files           Files backup log (files_logfile.log)
  verify          Verification log (verify_logfile.log)
  all             All logs (default)

Options:
  --lines N, -n N   Number of lines to show (default: 50)
  --json            Output in JSON format (for API/scripting)
  --help, -h        Show this help message

Global Options:
  --quiet, -q       Suppress log type headers

Examples:
  backupd logs                # Show all logs (last 50 lines each)
  backupd logs db             # Show database backup log
  backupd logs files -n 100   # Show last 100 lines of files log
  backupd logs verify         # Show verification log
  backupd logs db --json      # JSON output for API integration

See also: status, verify, backup
EOF
}

# JSON output for logs command
cli_logs_json() {
  local log_type="$1"
  local lines="$2"
  local log_dir="$INSTALL_DIR/logs"
  local log_file=""
  local type_name=""

  # Determine log file based on type
  case "$log_type" in
    db|database)
      log_file="$log_dir/db_logfile.log"
      type_name="database"
      ;;
    files)
      log_file="$log_dir/files_logfile.log"
      type_name="files"
      ;;
    verify)
      log_file="$log_dir/verify_logfile.log"
      type_name="verify"
      ;;
    all)
      type_name="all"
      ;;
  esac

  echo "{"
  echo "  \"type\": \"$type_name\","
  echo "  \"lines\": $lines,"
  echo "  \"entries\": ["

  local first=1
  local parse_logs

  if [[ "$log_type" == "all" ]]; then
    parse_logs=$(cat "$log_dir"/*.log 2>/dev/null | sort -t' ' -k1,2 | tail -n "$lines")
  else
    [[ ! -f "$log_file" ]] && { echo "  ]"; echo "}"; return 0; }
    parse_logs=$(tail -n "$lines" "$log_file")
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    local timestamp="" level="info" message=""

    if [[ "$line" =~ ^====\ ([0-9]{4}-[0-9]{2}-[0-9]{2})\ ([0-9]{2}:[0-9]{2}:[0-9]{2})\ (START|END) ]]; then
      timestamp="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}Z"
      level="info"
      message="${line//\"/\\\"}"
    elif [[ "$line" =~ ^\[([A-Z]+)\]\ (.*)$ ]]; then
      level="${BASH_REMATCH[1],,}"  # Convert to lowercase
      message="${BASH_REMATCH[2]//\"/\\\"}"
      timestamp="$(date -Iseconds)"
    elif [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})\ ([0-9]{2}:[0-9]{2}:[0-9]{2})\ (.*)$ ]]; then
      timestamp="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}Z"
      message="${BASH_REMATCH[3]//\"/\\\"}"
    else
      message="${line//\"/\\\"}"
      timestamp="$(date -Iseconds)"
    fi

    message="${message//\\/\\\\}"
    message="${message//$'\n'/\\n}"
    message="${message//$'\r'/\\r}"
    message="${message//$'\t'/\\t}"

    [[ $first -eq 0 ]] && echo ","
    echo -n "    {\"timestamp\": \"$timestamp\", \"level\": \"$level\", \"message\": \"$message\"}"
    first=0
  done <<< "$parse_logs"

  echo
  echo "  ]"
  echo "}"
}

# ---------- Notifications Subcommand ----------

cli_notifications() {
  local action="${1:-}"
  shift || true

  case "$action" in
    status)
      cli_notifications_status "$@"
      ;;
    set-pushover)
      cli_notifications_set_pushover "$@"
      ;;
    test|test-pushover)
      cli_notifications_test_pushover "$@"
      ;;
    disable-pushover)
      cli_notifications_disable_pushover "$@"
      ;;
    --help|-h|"")
      cli_notifications_help
      return 0
      ;;
    *)
      print_error "Unknown notifications action: $action"
      cli_notifications_help
      return $EXIT_USAGE
      ;;
  esac
}

cli_notifications_status() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        JSON_OUTPUT=1
        export JSON_OUTPUT
        ;;
    esac
    shift
  done

  local secrets_dir
  secrets_dir="$(get_secrets_dir)"

  if [[ -z "$secrets_dir" ]]; then
    print_error "System not configured. Run 'backupd' to set up first."
    return $EXIT_NOT_CONFIGURED
  fi

  local ntfy_url webhook_url pushover_user pushover_token
  ntfy_url="$(get_secret "$secrets_dir" "$SECRET_NTFY_URL" 2>/dev/null || echo "")"
  webhook_url="$(get_secret "$secrets_dir" "$SECRET_WEBHOOK_URL" 2>/dev/null || echo "")"
  pushover_user="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_USER" 2>/dev/null || echo "")"
  pushover_token="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_TOKEN" 2>/dev/null || echo "")"

  if is_json_output; then
    local ntfy_enabled=false webhook_enabled=false pushover_enabled=false

    [[ -n "$ntfy_url" ]] && ntfy_enabled=true
    [[ -n "$webhook_url" ]] && webhook_enabled=true
    [[ -n "$pushover_user" && -n "$pushover_token" ]] && pushover_enabled=true

    cat <<EOF
{
  "ntfy": {"enabled": $ntfy_enabled},
  "webhook": {"enabled": $webhook_enabled},
  "pushover": {"enabled": $pushover_enabled}
}
EOF
    return 0
  fi

  echo "Notification Status:"
  [[ -n "$ntfy_url" ]] && print_success "ntfy: configured" || echo "  ntfy: not configured"
  [[ -n "$webhook_url" ]] && print_success "webhook: configured" || echo "  webhook: not configured"
  [[ -n "$pushover_user" && -n "$pushover_token" ]] && print_success "pushover: configured" || echo "  pushover: not configured"
}

cli_notifications_set_pushover() {
  local user_key="" api_token=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)
        user_key="$2"
        shift
        ;;
      --user=*)
        user_key="${1#--user=}"
        ;;
      --token)
        api_token="$2"
        shift
        ;;
      --token=*)
        api_token="${1#--token=}"
        ;;
      --help|-h)
        cli_notifications_help
        return 0
        ;;
      *)
        print_error "Unknown option: $1"
        return $EXIT_USAGE
        ;;
    esac
    shift
  done

  # Require root
  if [[ $EUID -ne 0 ]]; then
    print_error "Notification configuration requires root privileges."
    return $EXIT_NOPERM
  fi

  # Require configuration
  local secrets_dir
  secrets_dir="$(get_secrets_dir)"
  if [[ -z "$secrets_dir" ]]; then
    print_error "System not configured. Run 'backupd' to set up first."
    return $EXIT_NOT_CONFIGURED
  fi

  # Validate inputs
  if [[ -z "$user_key" || -z "$api_token" ]]; then
    print_error "Both --user and --token are required."
    echo "Usage: backupd notifications set-pushover --user USER_KEY --token API_TOKEN"
    return $EXIT_USAGE
  fi

  # Validate format (30 alphanumeric characters)
  if [[ ! "$user_key" =~ ^[A-Za-z0-9]{30}$ ]]; then
    print_error "Invalid user key format. Must be 30 alphanumeric characters."
    return $EXIT_USAGE
  fi
  if [[ ! "$api_token" =~ ^[A-Za-z0-9]{30}$ ]]; then
    print_error "Invalid API token format. Must be 30 alphanumeric characters."
    return $EXIT_USAGE
  fi

  # Store secrets
  store_secret "$secrets_dir" "$SECRET_PUSHOVER_USER" "$user_key"
  store_secret "$secrets_dir" "$SECRET_PUSHOVER_TOKEN" "$api_token"

  # Regenerate scripts
  regenerate_scripts_silent

  if is_json_output; then
    echo '{"status": "success", "message": "Pushover configured"}'
  else
    print_success "Pushover configured. Regenerating scripts..."
    print_success "Done. Use 'backupd notifications test-pushover' to verify."
  fi
}

cli_notifications_test_pushover() {
  local secrets_dir
  secrets_dir="$(get_secrets_dir)"

  if [[ -z "$secrets_dir" ]]; then
    print_error "System not configured. Run 'backupd' to set up first."
    return $EXIT_NOT_CONFIGURED
  fi

  local user_key api_token
  user_key="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_USER" 2>/dev/null || echo "")"
  api_token="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_TOKEN" 2>/dev/null || echo "")"

  if [[ -z "$user_key" || -z "$api_token" ]]; then
    print_error "Pushover not configured. Use 'backupd notifications set-pushover' first."
    return $EXIT_NOT_CONFIGURED
  fi

  local hostname timestamp
  hostname="$(hostname -f 2>/dev/null || hostname)"
  timestamp="$(date -Iseconds)"

  [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo -n "Sending test notification to Pushover... "

  local response http_code
  response=$(timeout 15 curl -s -w "\n%{http_code}" \
    --form-string "token=$api_token" \
    --form-string "user=$user_key" \
    --form-string "title=Backupd Test on $hostname" \
    --form-string "message=Test notification sent at $timestamp" \
    --form-string "priority=0" \
    --form-string "sound=pushover" \
    https://api.pushover.net/1/messages.json 2>/dev/null) || response="000"

  http_code=$(echo "$response" | tail -1)

  if is_json_output; then
    if [[ "$http_code" == "200" ]]; then
      echo '{"status": "success", "http_code": 200}'
    else
      echo "{\"status\": \"failed\", \"http_code\": $http_code}"
    fi
    return 0
  fi

  if [[ "$http_code" == "200" ]]; then
    echo -e "${GREEN}OK (HTTP $http_code)${NC}"
    return 0
  else
    echo -e "${RED}FAILED (HTTP $http_code)${NC}"
    return 1
  fi
}

cli_notifications_disable_pushover() {
  # Require root
  if [[ $EUID -ne 0 ]]; then
    print_error "Notification configuration requires root privileges."
    return $EXIT_NOPERM
  fi

  local secrets_dir
  secrets_dir="$(get_secrets_dir)"

  if [[ -z "$secrets_dir" ]]; then
    print_error "System not configured."
    return $EXIT_NOT_CONFIGURED
  fi

  rm -f "$secrets_dir/$SECRET_PUSHOVER_USER" 2>/dev/null || true
  rm -f "$secrets_dir/$SECRET_PUSHOVER_TOKEN" 2>/dev/null || true

  regenerate_scripts_silent

  if is_json_output; then
    echo '{"status": "success", "message": "Pushover disabled"}'
  else
    print_success "Pushover notifications disabled"
  fi
}

cli_notifications_help() {
  cat <<EOF
Usage: backupd notifications [COMMAND] [OPTIONS]

Manage notification settings for backup alerts. Supports ntfy, webhook, and Pushover.
Interactive configuration available via: backupd -> Notifications menu.

Commands:
  status                  Show notification configuration status
  set-pushover            Configure Pushover notifications
  test, test-pushover     Send a test Pushover notification
  disable-pushover        Remove Pushover configuration

Options for set-pushover:
  --user USER_KEY         Pushover User Key (30 characters)
  --token API_TOKEN       Pushover API Token (30 characters)

Global Options:
  --json                  Output in JSON format
  --help, -h              Show this help message

Examples:
  backupd notifications status
  backupd notifications status --json
  backupd notifications set-pushover --user abc123... --token xyz789...
  backupd notifications test-pushover
  backupd notifications disable-pushover

Note: For ntfy and webhook configuration, use the interactive menu:
  sudo backupd -> Notifications

See also: status, backup
EOF
}

# ---------- History Subcommand ----------

cli_history() {
  local history_type="all" lines=20

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) JSON_OUTPUT=1; export JSON_OUTPUT ;;
      --lines|-n) [[ -n "${2:-}" ]] && lines="$2" && shift ;;
      --lines=*) lines="${1#--lines=}" ;;
      db|database) history_type="database" ;;
      files) history_type="files" ;;
      backup|backups) history_type="backup" ;;
      verify|verifications) history_type="verify" ;;
      verify_quick|quick) history_type="verify_quick" ;;
      verify_full|full) history_type="verify_full" ;;
      cleanup|prune) history_type="cleanup" ;;
      all) history_type="all" ;;
      --help|-h) cli_history_help; return 0 ;;
      *) [[ "$1" == -* ]] && print_error "Unknown option: $1" && return $EXIT_USAGE ;;
    esac
    shift
  done

  source "$LIB_DIR/history.sh" 2>/dev/null || { print_error "History module not found"; return 1; }

  if is_json_output; then
    cli_history_json "$history_type" "$lines"
  else
    cli_history_text "$history_type" "$lines"
  fi
}

cli_history_text() {
  local type="$1" lines="$2"
  echo "Backup History"; echo "=============="

  local history_json=$(get_history "$type" "$lines")
  [[ "$history_json" == "[]" ]] && echo "No backup history recorded yet." && return 0

  printf "\n%-10s %-8s %-20s %-10s %-6s\n" "TYPE" "STATUS" "STARTED" "DURATION" "ITEMS"
  printf "%-10s %-8s %-20s %-10s %-6s\n" "----------" "--------" "--------------------" "----------" "------"

  # Parse with jq if available, fallback to grep/sed
  if command -v jq >/dev/null 2>&1; then
    echo "$history_json" | jq -r '.[] | [.type, .status, .started_at, .duration_seconds, .items_count] | @tsv' | \
    while IFS=$'\t' read -r t s st d i; do
      printf "%-10s %-8s %-20s %-10s %-6s\n" "$t" "$s" "${st:0:19}" "$(format_duration $d)" "$i"
    done
  else
    echo "$history_json" | grep -o '{[^}]*}' | while read -r rec; do
      local t=$(echo "$rec" | sed -n 's/.*"type":"\([^"]*\)".*/\1/p')
      local s=$(echo "$rec" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
      local st=$(echo "$rec" | sed -n 's/.*"started_at":"\([^"]*\)".*/\1/p'); st="${st%%+*}"; st="${st/T/ }"
      local d=$(echo "$rec" | sed -n 's/.*"duration_seconds":\([0-9]*\).*/\1/p')
      local i=$(echo "$rec" | sed -n 's/.*"items_count":\([0-9]*\).*/\1/p')
      printf "%-10s %-8s %-20s %-10s %-6s\n" "$t" "$s" "${st:0:19}" "$(format_duration $d)" "$i"
    done
  fi

  echo; echo "Next scheduled operations:"
  local timers=$(systemctl list-timers backupd-*.timer --no-pager 2>/dev/null | grep -E "backupd-(db|files|verify|verify-full).timer")
  if [[ -n "$timers" ]]; then
    local db_t=$(echo "$timers" | grep "backupd-db" | awk '{print $1, $2, $3}')
    local files_t=$(echo "$timers" | grep "backupd-files" | awk '{print $1, $2, $3}')
    local verify_t=$(echo "$timers" | grep "backupd-verify.timer" | awk '{print $1, $2, $3}')
    local verify_full_t=$(echo "$timers" | grep "backupd-verify-full" | awk '{print $1, $2, $3}')
    [[ -n "$db_t" ]] && echo "  Database:     $db_t"
    [[ -n "$files_t" ]] && echo "  Files:        $files_t"
    [[ -n "$verify_t" ]] && echo "  Verify Quick: $verify_t"
    [[ -n "$verify_full_t" ]] && echo "  Verify Full:  $verify_full_t"
  else
    echo "  No timers scheduled"
  fi
}

cli_history_json() {
  local type="$1" lines="$2"
  local hist=$(get_history "$type" "$lines")
  local next=$(get_next_backup_times)
  echo "{\"type\":\"$type\",\"records\":$hist,\"next_scheduled\":$next}"
}

cli_history_help() {
  cat <<'EOF'
Usage: backupd history [TYPE] [OPTIONS]

View operation history including status, duration, and scheduled jobs.

Types (Backups):
  db, database       Database backup history only
  files              Files backup history only
  backup, backups    All backup types (database + files)

Types (Maintenance):
  verify             All verification history (quick + full)
  verify_quick       Quick integrity check history only
  verify_full        Full verification history only
  cleanup, prune     Cleanup/retention history only

Types (Combined):
  all                All operation history (default)

Options:
  --lines N, -n N    Records to show (default: 20)
  --json             JSON output for scripting
  --help, -h         Show this help

Examples:
  backupd history                 # Last 20 operations (all types)
  backupd history db -n 50        # Last 50 database backups
  backupd history verify          # All verification results
  backupd history cleanup         # Retention policy history
  backupd history backup --json   # All backups in JSON format
EOF
}

# ---------- Job Subcommand (v3.1.0) ----------

cli_job() {
  local action="${1:-list}"
  shift || true

  # Load jobs module
  source "$LIB_DIR/jobs.sh" 2>/dev/null || source "$INSTALL_DIR/lib/jobs.sh" 2>/dev/null || {
    print_error "Jobs module not found"
    return 1
  }

  case "$action" in
    list|ls)
      cli_job_list "$@"
      ;;
    show|info)
      cli_job_show "$@"
      ;;
    create|add|new)
      cli_job_create "$@"
      ;;
    delete|rm|remove)
      cli_job_delete "$@"
      ;;
    clone|copy)
      cli_job_clone "$@"
      ;;
    enable)
      cli_job_enable "$@"
      ;;
    disable)
      cli_job_disable "$@"
      ;;
    regenerate|regen)
      cli_job_regenerate "$@"
      ;;
    timers)
      cli_job_timers "$@"
      ;;
    --help|-h|help)
      cli_job_help
      return 0
      ;;
    *)
      print_error "Unknown job action: $action"
      cli_job_help
      return $EXIT_USAGE
      ;;
  esac
}

cli_job_list() {
  local json_output=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json_output="--json"; JSON_OUTPUT=1 ;;
      --help|-h) cli_job_help; return 0 ;;
      *) print_error "Unknown option: $1"; return $EXIT_USAGE ;;
    esac
    shift
  done

  list_jobs_detailed "$json_output"
}

cli_job_show() {
  local job_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) JSON_OUTPUT=1 ;;
      --help|-h) cli_job_help; return 0 ;;
      -*) print_error "Unknown option: $1"; return $EXIT_USAGE ;;
      *) job_name="$1" ;;
    esac
    shift
  done

  if [[ -z "$job_name" ]]; then
    print_error "Job name required"
    echo "Usage: backupd job show <job_name>"
    return $EXIT_USAGE
  fi

  if ! job_exists "$job_name"; then
    print_error "Job '$job_name' does not exist"
    return $EXIT_NOINPUT
  fi

  local job_dir
  job_dir="$(get_job_dir "$job_name")"
  local config_file="$job_dir/job.conf"

  if is_json_output; then
    _job_status_json "$job_name"
    echo
  else
    echo "Job: $job_name"
    echo "===================="
    echo
    echo "Configuration:"
    while IFS='=' read -r key value; do
      [[ -z "$key" || "$key" == \#* ]] && continue
      key="${key//\"/}"
      value="${value//\"/}"
      printf "  %-20s = %s\n" "$key" "$value"
    done < "$config_file"

    echo
    echo "Scripts:"
    local scripts_dir="$job_dir/scripts"
    if [[ -d "$scripts_dir" ]]; then
      for script in "$scripts_dir"/*.sh; do
        [[ -f "$script" ]] && echo "  - $(basename "$script")"
      done
    else
      echo "  (none generated)"
    fi

    echo
    echo "Timers:"
    list_job_timers "$job_name"
  fi
}

cli_job_create() {
  local job_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) JSON_OUTPUT=1 ;;
      --help|-h) cli_job_help; return 0 ;;
      -*) print_error "Unknown option: $1"; return $EXIT_USAGE ;;
      *) job_name="$1" ;;
    esac
    shift
  done

  if [[ -z "$job_name" ]]; then
    print_error "Job name required"
    echo "Usage: backupd job create <job_name>"
    return $EXIT_USAGE
  fi

  # Require root
  if [[ $EUID -ne 0 ]]; then
    print_error "Job creation requires root privileges."
    return $EXIT_NOPERM
  fi

  if create_job "$job_name"; then
    if is_json_output; then
      echo "{\"status\": \"success\", \"job\": \"$job_name\", \"message\": \"Job created\"}"
    fi
    return 0
  else
    if is_json_output; then
      echo "{\"status\": \"error\", \"job\": \"$job_name\", \"message\": \"Failed to create job\"}"
    fi
    return 1
  fi
}

cli_job_delete() {
  local job_name=""
  local force=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force|-f) force="--force" ;;
      --json) JSON_OUTPUT=1 ;;
      --help|-h) cli_job_help; return 0 ;;
      -*) print_error "Unknown option: $1"; return $EXIT_USAGE ;;
      *) job_name="$1" ;;
    esac
    shift
  done

  if [[ -z "$job_name" ]]; then
    print_error "Job name required"
    echo "Usage: backupd job delete <job_name> [--force]"
    return $EXIT_USAGE
  fi

  # Require root
  if [[ $EUID -ne 0 ]]; then
    print_error "Job deletion requires root privileges."
    return $EXIT_NOPERM
  fi

  if delete_job "$job_name" "$force"; then
    if is_json_output; then
      echo "{\"status\": \"success\", \"job\": \"$job_name\", \"message\": \"Job deleted\"}"
    fi
    return 0
  else
    if is_json_output; then
      echo "{\"status\": \"error\", \"job\": \"$job_name\", \"message\": \"Failed to delete job\"}"
    fi
    return 1
  fi
}

cli_job_clone() {
  local src_job="" dst_job=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) JSON_OUTPUT=1 ;;
      --help|-h) cli_job_help; return 0 ;;
      -*) print_error "Unknown option: $1"; return $EXIT_USAGE ;;
      *)
        if [[ -z "$src_job" ]]; then
          src_job="$1"
        elif [[ -z "$dst_job" ]]; then
          dst_job="$1"
        else
          print_error "Too many arguments"
          return $EXIT_USAGE
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$src_job" || -z "$dst_job" ]]; then
    print_error "Source and destination job names required"
    echo "Usage: backupd job clone <source_job> <new_job>"
    return $EXIT_USAGE
  fi

  # Require root
  if [[ $EUID -ne 0 ]]; then
    print_error "Job cloning requires root privileges."
    return $EXIT_NOPERM
  fi

  if clone_job "$src_job" "$dst_job"; then
    if is_json_output; then
      echo "{\"status\": \"success\", \"source\": \"$src_job\", \"destination\": \"$dst_job\"}"
    fi
    return 0
  else
    if is_json_output; then
      echo "{\"status\": \"error\", \"source\": \"$src_job\", \"destination\": \"$dst_job\"}"
    fi
    return 1
  fi
}

cli_job_enable() {
  local job_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) JSON_OUTPUT=1 ;;
      --help|-h) cli_job_help; return 0 ;;
      -*) print_error "Unknown option: $1"; return $EXIT_USAGE ;;
      *) job_name="$1" ;;
    esac
    shift
  done

  if [[ -z "$job_name" ]]; then
    print_error "Job name required"
    echo "Usage: backupd job enable <job_name>"
    return $EXIT_USAGE
  fi

  # Require root
  if [[ $EUID -ne 0 ]]; then
    print_error "Job management requires root privileges."
    return $EXIT_NOPERM
  fi

  if enable_job "$job_name"; then
    if is_json_output; then
      echo "{\"status\": \"success\", \"job\": \"$job_name\", \"enabled\": true}"
    fi
    return 0
  else
    if is_json_output; then
      echo "{\"status\": \"error\", \"job\": \"$job_name\"}"
    fi
    return 1
  fi
}

cli_job_disable() {
  local job_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) JSON_OUTPUT=1 ;;
      --help|-h) cli_job_help; return 0 ;;
      -*) print_error "Unknown option: $1"; return $EXIT_USAGE ;;
      *) job_name="$1" ;;
    esac
    shift
  done

  if [[ -z "$job_name" ]]; then
    print_error "Job name required"
    echo "Usage: backupd job disable <job_name>"
    return $EXIT_USAGE
  fi

  # Require root
  if [[ $EUID -ne 0 ]]; then
    print_error "Job management requires root privileges."
    return $EXIT_NOPERM
  fi

  if disable_job "$job_name"; then
    if is_json_output; then
      echo "{\"status\": \"success\", \"job\": \"$job_name\", \"enabled\": false}"
    fi
    return 0
  else
    if is_json_output; then
      echo "{\"status\": \"error\", \"job\": \"$job_name\"}"
    fi
    return 1
  fi
}

cli_job_regenerate() {
  local job_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all|-a) job_name="__all__" ;;
      --json) JSON_OUTPUT=1 ;;
      --help|-h) cli_job_help; return 0 ;;
      -*) print_error "Unknown option: $1"; return $EXIT_USAGE ;;
      *) job_name="$1" ;;
    esac
    shift
  done

  # Require root
  if [[ $EUID -ne 0 ]]; then
    print_error "Script regeneration requires root privileges."
    return $EXIT_NOPERM
  fi

  # Require configuration
  if ! is_configured; then
    print_error "System not configured. Run 'backupd' to set up first."
    return $EXIT_NOT_CONFIGURED
  fi

  # Source generators
  source "$LIB_DIR/generators.sh" 2>/dev/null || source "$INSTALL_DIR/lib/generators.sh" 2>/dev/null || {
    print_error "Generators module not found"
    return 1
  }

  if [[ "$job_name" == "__all__" ]]; then
    if regenerate_all_job_scripts; then
      if is_json_output; then
        echo "{\"status\": \"success\", \"message\": \"All job scripts regenerated\"}"
      fi
      return 0
    else
      if is_json_output; then
        echo "{\"status\": \"error\", \"message\": \"Some scripts failed to regenerate\"}"
      fi
      return 1
    fi
  elif [[ -n "$job_name" ]]; then
    if generate_job_scripts "$job_name"; then
      if is_json_output; then
        echo "{\"status\": \"success\", \"job\": \"$job_name\"}"
      fi
      return 0
    else
      if is_json_output; then
        echo "{\"status\": \"error\", \"job\": \"$job_name\"}"
      fi
      return 1
    fi
  else
    print_error "Job name required (or use --all)"
    echo "Usage: backupd job regenerate <job_name> | --all"
    return $EXIT_USAGE
  fi
}

cli_job_timers() {
  local job_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) JSON_OUTPUT=1 ;;
      --help|-h) cli_job_help; return 0 ;;
      -*) print_error "Unknown option: $1"; return $EXIT_USAGE ;;
      *) job_name="$1" ;;
    esac
    shift
  done

  if [[ -z "$job_name" ]]; then
    print_error "Job name required"
    echo "Usage: backupd job timers <job_name>"
    return $EXIT_USAGE
  fi

  if ! job_exists "$job_name"; then
    print_error "Job '$job_name' does not exist"
    return $EXIT_NOINPUT
  fi

  if is_json_output; then
    local db_enabled=false files_enabled=false
    local db_schedule="" files_schedule=""
    local db_timer files_timer

    db_timer="$(get_timer_name "$job_name" "db").timer"
    files_timer="$(get_timer_name "$job_name" "files").timer"

    if systemctl is-enabled "$db_timer" &>/dev/null; then
      db_enabled=true
      db_schedule=$(grep -E "^OnCalendar=" "/etc/systemd/system/$db_timer" 2>/dev/null | cut -d'=' -f2)
    fi

    if systemctl is-enabled "$files_timer" &>/dev/null; then
      files_enabled=true
      files_schedule=$(grep -E "^OnCalendar=" "/etc/systemd/system/$files_timer" 2>/dev/null | cut -d'=' -f2)
    fi

    echo "{\"job\": \"$job_name\", \"timers\": {\"db\": {\"enabled\": $db_enabled, \"schedule\": \"$db_schedule\"}, \"files\": {\"enabled\": $files_enabled, \"schedule\": \"$files_schedule\"}}}"
  else
    echo "Timers for job: $job_name"
    echo
    list_job_timers "$job_name"
  fi
}

cli_job_help() {
  cat <<'EOF'
Usage: backupd job [COMMAND] [OPTIONS]

Manage multiple backup jobs. Each job can have its own remote destination,
schedules, and configuration while sharing credentials.

Commands:
  list, ls                    List all configured jobs (default)
  show <name>                 Show job configuration and status
  create <name>               Create a new backup job
  delete <name> [--force]     Delete a job (and its timers)
  clone <src> <dst>           Clone a job configuration
  enable <name>               Enable a disabled job
  disable <name>              Disable a job (stops timers)
  regenerate <name> | --all   Regenerate backup scripts for job(s)
  timers <name>               Show systemd timers for a job

Options:
  --json            Output in JSON format
  --force, -f       Force operation (for delete)
  --all, -a         Apply to all jobs (for regenerate)
  --help, -h        Show this help message

Requires: Root privileges for create/delete/enable/disable/regenerate.

Job naming rules:
  - 2-32 characters
  - Alphanumeric, dash, underscore only
  - Must start with letter or number
  - Reserved names: all, list, help, none, null, undefined

Examples:
  backupd job list                      # List all jobs
  backupd job list --json               # JSON output
  backupd job show production           # Show job details
  backupd job create staging            # Create new job
  backupd job clone production staging  # Clone job
  backupd job delete staging            # Delete job
  backupd job enable production         # Enable job
  backupd job disable production        # Disable job
  backupd job regenerate production     # Regenerate scripts
  backupd job regenerate --all          # Regenerate all jobs
  backupd job timers production         # Show job timers

After creating a job, configure it with the interactive menu:
  sudo backupd

See also: backup, status, schedule
EOF
}
