#!/usr/bin/env bash
# ============================================================================
# Backupd - Backup Module
# Backup execution and cleanup functions
# ============================================================================

# ---------- Check Running Backups ----------

# Display any currently running backup jobs with progress
show_running_backups() {
  local progress_dir="/var/run/backupd"
  local found_running=false

  [[ ! -d "$progress_dir" ]] && return 0

  for progress_file in "$progress_dir"/*.progress; do
    [[ ! -f "$progress_file" ]] && continue

    # Read progress file (JSON format)
    local status percent message subtype updated_at
    status=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$progress_file" 2>/dev/null | cut -d'"' -f4)

    # Skip if not running
    [[ "$status" != "running" ]] && continue

    percent=$(grep -o '"percent"[[:space:]]*:[[:space:]]*[0-9]*' "$progress_file" 2>/dev/null | grep -o '[0-9]*$')
    message=$(grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' "$progress_file" 2>/dev/null | cut -d'"' -f4)
    subtype=$(grep -o '"subtype"[[:space:]]*:[[:space:]]*"[^"]*"' "$progress_file" 2>/dev/null | cut -d'"' -f4)
    updated_at=$(grep -o '"updated_at"[[:space:]]*:[[:space:]]*"[^"]*"' "$progress_file" 2>/dev/null | cut -d'"' -f4)

    # Skip stale entries (older than 1 hour) - likely orphaned from failed backups
    if [[ -n "$updated_at" ]]; then
      local now updated_epoch
      now=$(date +%s)
      updated_epoch=$(date -d "$updated_at" +%s 2>/dev/null || echo 0)
      if [[ $((now - updated_epoch)) -gt 3600 ]]; then
        continue
      fi
    fi

    found_running=true

    # Format display
    local type_label
    case "$subtype" in
      database) type_label="Database" ;;
      files) type_label="Files" ;;
      *) type_label="Backup" ;;
    esac

    echo -e "${YELLOW}>>> $type_label backup RUNNING: ${percent:-0}% - ${message:-working}${NC}"
    if [[ -n "$updated_at" ]]; then
      echo -e "${YELLOW}    Last update: $updated_at${NC}"
    fi
    echo
  done

  # Also check for lock files as a fallback
  if [[ "$found_running" == "false" ]]; then
    if [[ -f "/var/lock/backupd-db.lock" ]]; then
      if ! flock -n 200 200>/var/lock/backupd-db.lock 2>/dev/null; then
        echo -e "${YELLOW}>>> Database backup is running (no progress info available)${NC}"
        echo
        found_running=true
      fi
    fi

    if [[ -f "/var/lock/backupd-files.lock" ]]; then
      if ! flock -n 200 200>/var/lock/backupd-files.lock 2>/dev/null; then
        echo -e "${YELLOW}>>> Files backup is running (no progress info available)${NC}"
        echo
        found_running=true
      fi
    fi
  fi

  [[ "$found_running" == "true" ]] && return 0 || return 1
}

# ---------- Run Backup ----------

run_backup() {
  log_func_enter
  debug_enter "run_backup"
  print_header

  # Show any running backups with progress (ignore return code - not an error if none running)
  show_running_backups || true

  echo "Run Backup"
  echo "=========="
  echo

  if ! is_configured; then
    print_error "System not configured. Please run setup first."
    press_enter_to_continue
    return
  fi

  echo "1. Run database backup"
  echo "2. Run files backup"
  echo "3. Run both (database + files)"
  echo "4. Run cleanup now (remove old backups)"
  echo "0. Back to main menu"
  echo
  read -p "Select option [0-4]: " backup_choice

  case "$backup_choice" in
    1)
      if [[ -f "$SCRIPTS_DIR/db_backup.sh" ]]; then
        echo
        print_info "Starting database backup..."
        echo
        bash "$SCRIPTS_DIR/db_backup.sh"
        press_enter_to_continue
      else
        print_error "Database backup script not found."
        press_enter_to_continue
      fi
      ;;
    2)
      if [[ -f "$SCRIPTS_DIR/files_backup.sh" ]]; then
        echo
        print_info "Starting files backup..."
        echo
        bash "$SCRIPTS_DIR/files_backup.sh"
        press_enter_to_continue
      else
        print_error "Files backup script not found."
        press_enter_to_continue
      fi
      ;;
    3)
      echo
      if [[ -f "$SCRIPTS_DIR/db_backup.sh" ]]; then
        print_info "Starting database backup..."
        echo
        bash "$SCRIPTS_DIR/db_backup.sh"
        echo
      else
        print_error "Database backup script not found."
      fi

      if [[ -f "$SCRIPTS_DIR/files_backup.sh" ]]; then
        print_info "Starting files backup..."
        echo
        bash "$SCRIPTS_DIR/files_backup.sh"
      else
        print_error "Files backup script not found."
      fi
      press_enter_to_continue
      ;;
    4)
      run_cleanup_now
      ;;
    0|*)
      return
      ;;
  esac
}

# ---------- Run Cleanup Now ----------

run_cleanup_now() {
  log_func_enter
  debug_enter "run_cleanup_now"
  print_header
  echo "Run Cleanup Now"
  echo "==============="
  echo

  local retention_days retention_desc
  retention_days="$(get_config_value 'RETENTION_DAYS')"
  retention_desc="$(get_config_value 'RETENTION_DESC')"

  if [[ -z "$retention_days" ]] || [[ "$retention_days" -eq 0 ]]; then
    print_warning "No retention policy configured"
    echo
    echo "To configure, go to: Manage schedules > Change retention policy"
    press_enter_to_continue
    return
  fi

  echo "Current retention policy: $retention_desc"
  echo
  echo "This will remove snapshots older than $retention_days days and prune unused data."
  echo
  read -p "Continue? (y/N): " confirm

  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    press_enter_to_continue
    return
  fi

  local rclone_remote rclone_db_path rclone_files_path
  rclone_remote="$(get_config_value 'RCLONE_REMOTE')"
  rclone_db_path="$(get_config_value 'RCLONE_DB_PATH')"
  rclone_files_path="$(get_config_value 'RCLONE_FILES_PATH')"

  # Get restic password from secrets
  local secrets_dir restic_password
  secrets_dir="$(get_secrets_dir)"
  restic_password="$(get_secret "$secrets_dir" ".c1" 2>/dev/null || echo "")"

  if [[ -z "$restic_password" ]]; then
    print_error "Could not retrieve repository password"
    press_enter_to_continue
    return
  fi

  local cleanup_errors=0

  # Cleanup database repository
  if [[ -n "$rclone_db_path" ]]; then
    local db_repo="rclone:${rclone_remote}:${rclone_db_path}"
    echo
    echo "Cleaning up database repository..."
    echo "Repository: $db_repo"
    echo "Retention: Keep snapshots within $retention_days days"
    echo

    if apply_retention_days "$db_repo" "$restic_password" "$retention_days" "" "false"; then
      print_success "Database repository cleanup complete"
    else
      print_error "Database repository cleanup failed"
      ((cleanup_errors++)) || true
    fi
  fi

  # Cleanup files repository
  if [[ -n "$rclone_files_path" ]]; then
    local files_repo="rclone:${rclone_remote}:${rclone_files_path}"
    echo
    echo "Cleaning up files repository..."
    echo "Repository: $files_repo"
    echo "Retention: Keep snapshots within $retention_days days"
    echo

    if apply_retention_days "$files_repo" "$restic_password" "$retention_days" "" "false"; then
      print_success "Files repository cleanup complete"
    else
      print_error "Files repository cleanup failed"
      ((cleanup_errors++)) || true
    fi
  fi

  echo
  if [[ $cleanup_errors -gt 0 ]]; then
    print_warning "Cleanup completed with $cleanup_errors error(s)"
  else
    print_success "Cleanup complete"
  fi
  press_enter_to_continue
}
