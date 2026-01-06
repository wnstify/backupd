#!/usr/bin/env bash
# ============================================================================
# Backupd - Backup Module
# Backup execution and cleanup functions
# ============================================================================

# ---------- Run Backup ----------

run_backup() {
  log_func_enter
  debug_enter "run_backup"
  print_header
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
