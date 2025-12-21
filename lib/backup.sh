#!/usr/bin/env bash
# ============================================================================
# Backupd - Backup Module
# Backup execution and cleanup functions
# ============================================================================

# ---------- Run Backup ----------

run_backup() {
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
  print_header
  echo "Run Cleanup Now"
  echo "==============="
  echo

  local retention_minutes retention_desc
  retention_minutes="$(get_config_value 'RETENTION_MINUTES')"
  retention_desc="$(get_config_value 'RETENTION_DESC')"

  if [[ -z "$retention_minutes" ]] || [[ "$retention_minutes" -eq 0 ]]; then
    print_warning "No retention policy configured (automatic cleanup disabled)"
    echo
    echo "To enable cleanup, go to: Manage schedules > Change retention policy"
    press_enter_to_continue
    return
  fi

  echo "Current retention policy: $retention_desc"
  echo
  echo "This will delete backups older than $retention_minutes minutes."
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

  local cutoff_time cleanup_count=0 cleanup_errors=0
  cutoff_time=$(date -d "-$retention_minutes minutes" +%s 2>/dev/null || date -v-${retention_minutes}M +%s 2>/dev/null || echo 0)

  if [[ "$cutoff_time" -eq 0 ]]; then
    print_error "Could not calculate cutoff time"
    press_enter_to_continue
    return
  fi

  echo
  echo "Cutoff time: $(date -d "@$cutoff_time" 2>/dev/null || date -r "$cutoff_time" 2>/dev/null)"
  echo

  # Cleanup database backups
  if [[ -n "$rclone_db_path" ]]; then
    echo "Checking database backups at $rclone_remote:$rclone_db_path..."
    while IFS= read -r remote_file; do
      [[ -z "$remote_file" ]] && continue
      file_time=$(rclone lsl "$rclone_remote:$rclone_db_path/$remote_file" 2>&1 | awk '{print $2" "$3}' | head -1)
      if [[ -n "$file_time" && ! "$file_time" =~ ^ERROR ]]; then
        file_epoch=$(date -d "$file_time" +%s 2>/dev/null || echo 0)
        if [[ "$file_epoch" -gt 0 && "$file_epoch" -lt "$cutoff_time" ]]; then
          echo "  Deleting: $remote_file ($(date -d "@$file_epoch" +"%Y-%m-%d %H:%M" 2>/dev/null))"
          delete_output=$(rclone delete "$rclone_remote:$rclone_db_path/$remote_file" 2>&1)
          if [[ $? -eq 0 ]]; then
            ((cleanup_count++)) || true
            # Also delete corresponding checksum file
            rclone delete "$rclone_remote:$rclone_db_path/${remote_file}.sha256" 2>/dev/null || true
          else
            print_error "  Failed to delete $remote_file: $delete_output"
            ((cleanup_errors++)) || true
          fi
        fi
      fi
    done < <(rclone lsf "$rclone_remote:$rclone_db_path" --include "*-db_backups-*.tar.gz.gpg" 2>&1)
  fi

  # Cleanup files backups
  if [[ -n "$rclone_files_path" ]]; then
    echo "Checking files backups at $rclone_remote:$rclone_files_path..."
    while IFS= read -r remote_file; do
      [[ -z "$remote_file" ]] && continue
      file_time=$(rclone lsl "$rclone_remote:$rclone_files_path/$remote_file" 2>&1 | awk '{print $2" "$3}' | head -1)
      if [[ -n "$file_time" && ! "$file_time" =~ ^ERROR ]]; then
        file_epoch=$(date -d "$file_time" +%s 2>/dev/null || echo 0)
        if [[ "$file_epoch" -gt 0 && "$file_epoch" -lt "$cutoff_time" ]]; then
          echo "  Deleting: $remote_file ($(date -d "@$file_epoch" +"%Y-%m-%d %H:%M" 2>/dev/null))"
          delete_output=$(rclone delete "$rclone_remote:$rclone_files_path/$remote_file" 2>&1)
          if [[ $? -eq 0 ]]; then
            ((cleanup_count++)) || true
            # Also delete corresponding checksum file
            rclone delete "$rclone_remote:$rclone_files_path/${remote_file}.sha256" 2>/dev/null || true
          else
            print_error "  Failed to delete $remote_file: $delete_output"
            ((cleanup_errors++)) || true
          fi
        fi
      fi
    done < <(rclone lsf "$rclone_remote:$rclone_files_path" --include "*.tar.gz" --exclude "*.sha256" 2>&1)
  fi

  echo
  if [[ $cleanup_errors -gt 0 ]]; then
    print_warning "Cleanup completed with $cleanup_errors error(s). Removed $cleanup_count old backup(s)."
  else
    print_success "Cleanup complete. Removed $cleanup_count old backup(s)."
  fi
  press_enter_to_continue
}
