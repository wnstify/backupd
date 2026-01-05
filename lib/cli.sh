#!/usr/bin/env bash
# ============================================================================
# Backupd - CLI Module
# Subcommand dispatcher for non-interactive CLI usage
# CLIG compliant: https://clig.dev/
# ============================================================================

# ---------- CLI Dispatcher ----------

# Main dispatcher - routes subcommands to handlers
# Returns 0 on success, appropriate exit code on failure
cli_dispatch() {
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
    *)
      print_error "Unknown command: $subcommand"
      echo "Run 'backupd --help' for usage information."
      return $EXIT_USAGE
      ;;
  esac
}

# ---------- Backup Subcommand ----------

cli_backup() {
  local backup_type="${1:-}"

  case "$backup_type" in
    --help|-h|"")
      cli_backup_help
      return 0
      ;;
  esac

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
        bash "$SCRIPTS_DIR/db_backup.sh"
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
        bash "$SCRIPTS_DIR/files_backup.sh"
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
          bash "$SCRIPTS_DIR/db_backup.sh" || exit_code=$?
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
          bash "$SCRIPTS_DIR/files_backup.sh" || exit_code=$?
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
  --help, -h      Show this help message

Global Options:
  --quiet, -q     Suppress non-essential output (ideal for cron)
  --debug         Enable debug logging

Examples:
  backupd backup db              # Backup database now
  backupd backup files           # Backup files now
  backupd backup all             # Backup both
  backupd backup db --dry-run    # Preview database backup
  backupd --quiet backup db      # Silent mode for cron

See also: restore, verify, schedule, status
EOF
}

# ---------- Restore Subcommand ----------

cli_restore() {
  local restore_type="${1:-}"
  local list_only=0
  shift || true

  # Parse flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --list|-l)
        list_only=1
        ;;
      --help|-h)
        cli_restore_help
        return 0
        ;;
      *)
        print_error "Unknown option: $1"
        return $EXIT_USAGE
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
  --list, -l      List available backups without restoring
  --dry-run, -n   Preview what would be executed without running
  --help, -h      Show this help message

Global Options:
  --json          Output backup list in JSON format (with --list)
  --quiet, -q     Suppress non-essential output

Examples:
  backupd restore db --list      # List available database backups
  backupd restore files --list   # List available files backups
  backupd restore db             # Interactive database restore
  backupd restore db --dry-run   # Preview restore operation
  backupd --json restore db -l   # JSON list of backups

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

  # Parse arguments
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

  if [[ $quick_mode -eq 1 ]]; then
    if is_json_output; then
      cli_verify_quick_json "$verify_type"
      return $?
    fi
    [[ "${QUIET_MODE:-0}" -ne 1 ]] && echo "Running quick verification..."
    verify_quick "$verify_type"
    return $?
  elif [[ $full_mode -eq 1 ]]; then
    print_warning "Full verification requires interactive password entry."
    print_info "Use the interactive menu for full verification: backupd"
    return $EXIT_USAGE
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
  --quick, -q     Quick check: verify checksums exist (default)
  --full, -f      Full test: download and verify (interactive only)
  --json          Output results in JSON format
  --help, -h      Show this help message

Exit Codes:
  0               All checks passed
  1               One or more checks failed
  2               Warnings (missing checksums)

Examples:
  backupd verify                  # Quick check of all backups
  backupd verify db --quick       # Quick check of database backups
  backupd verify files            # Quick check of files backups
  backupd verify --json           # JSON output for scripting
  backupd verify --json | jq .status  # Get overall status

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
  --help, -h        Show this help message

Global Options:
  --quiet, -q       Suppress log type headers

Examples:
  backupd logs                # Show all logs (last 50 lines each)
  backupd logs db             # Show database backup log
  backupd logs files -n 100   # Show last 100 lines of files log
  backupd logs verify         # Show verification log

See also: status, verify, backup
EOF
}
