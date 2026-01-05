#!/usr/bin/env bash
# ============================================================================
# Backupd - Status Module
# Status display and log viewing functions
# ============================================================================

# ---------- Status Display ----------

show_status() {
  print_header
  echo "System Status"
  echo "============="
  echo

  local secrets_dir
  secrets_dir="$(get_secrets_dir)"

  # Check configuration
  if is_configured; then
    print_success "Configuration: COMPLETE"
  else
    print_error "Configuration: NOT CONFIGURED"
    echo
    echo "Run setup to configure the backup system."
    press_enter_to_continue
    return
  fi

  # Check secrets
  if [[ -n "$secrets_dir" ]] && [[ -d "$secrets_dir" ]]; then
    print_success "Secure storage: $secrets_dir"
  else
    print_error "Secure storage: NOT INITIALIZED"
  fi

  # Check scripts
  echo
  echo "Backup Scripts:"
  [[ -f "$SCRIPTS_DIR/db_backup.sh" ]] && print_success "Database backup script" || print_error "Database backup script"
  [[ -f "$SCRIPTS_DIR/files_backup.sh" ]] && print_success "Files backup script" || print_error "Files backup script"

  echo
  echo "Restore Scripts:"
  [[ -f "$SCRIPTS_DIR/db_restore.sh" ]] && print_success "Database restore script" || print_error "Database restore script"
  [[ -f "$SCRIPTS_DIR/files_restore.sh" ]] && print_success "Files restore script" || print_error "Files restore script"

  # Check scheduled backups (systemd timers or cron)
  echo
  echo "Scheduled Backups:"

  # Database backup schedule
  if systemctl is-enabled backupd-db.timer &>/dev/null; then
    local db_schedule
    db_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-db.timer 2>/dev/null | cut -d'=' -f2)
    print_success "Database backup (systemd): $db_schedule"
  elif crontab -l 2>/dev/null | grep -q "$SCRIPTS_DIR/db_backup.sh"; then
    local db_schedule
    db_schedule=$(crontab -l 2>/dev/null | grep "$SCRIPTS_DIR/db_backup.sh" | awk '{print $1,$2,$3,$4,$5}')
    print_success "Database backup (cron): $db_schedule"
  else
    print_warning "Database backup: NOT SCHEDULED"
  fi

  # Files backup schedule
  if systemctl is-enabled backupd-files.timer &>/dev/null; then
    local files_schedule
    files_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-files.timer 2>/dev/null | cut -d'=' -f2)
    print_success "Files backup (systemd): $files_schedule"
  elif crontab -l 2>/dev/null | grep -q "$SCRIPTS_DIR/files_backup.sh"; then
    local files_schedule
    files_schedule=$(crontab -l 2>/dev/null | grep "$SCRIPTS_DIR/files_backup.sh" | awk '{print $1,$2,$3,$4,$5}')
    print_success "Files backup (cron): $files_schedule"
  else
    print_warning "Files backup: NOT SCHEDULED"
  fi

  # Integrity check schedule
  if systemctl is-enabled backupd-verify.timer &>/dev/null; then
    local verify_schedule
    verify_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-verify.timer 2>/dev/null | cut -d'=' -f2)
    print_success "Integrity check (systemd): $verify_schedule"
  else
    echo -e "  ${YELLOW}Integrity check: NOT SCHEDULED (optional)${NC}"
  fi

  # Retention policy
  echo
  echo "Retention Policy:"
  local retention_desc retention_minutes
  retention_desc="$(get_config_value 'RETENTION_DESC')"
  retention_minutes="$(get_config_value 'RETENTION_MINUTES')"
  if [[ -n "$retention_desc" ]]; then
    if [[ "$retention_minutes" -eq 0 ]]; then
      print_warning "Retention: $retention_desc"
    else
      print_success "Retention: $retention_desc"
    fi
  else
    print_warning "Retention: NOT CONFIGURED (no automatic cleanup)"
  fi

  # Check rclone
  echo
  echo "Remote Storage:"
  local rclone_remote rclone_db_path rclone_files_path
  rclone_remote="$(get_config_value 'RCLONE_REMOTE')"
  rclone_db_path="$(get_config_value 'RCLONE_DB_PATH')"
  rclone_files_path="$(get_config_value 'RCLONE_FILES_PATH')"

  if [[ -n "$rclone_remote" ]]; then
    print_success "Remote: $rclone_remote"
    [[ -n "$rclone_db_path" ]] && echo "        Database path: $rclone_db_path"
    [[ -n "$rclone_files_path" ]] && echo "        Files path: $rclone_files_path"
  else
    print_error "Remote storage: NOT CONFIGURED"
  fi

  # Check recent backups
  echo
  echo "Recent Backup Activity:"
  if [[ -f "$INSTALL_DIR/logs/db_logfile.log" ]]; then
    local last_db_backup
    last_db_backup=$(grep "START per-db backup" "$INSTALL_DIR/logs/db_logfile.log" 2>/dev/null | tail -1 | awk '{print $2, $3}')
    [[ -n "$last_db_backup" ]] && echo "  Last DB backup: $last_db_backup"
  fi

  if [[ -f "$INSTALL_DIR/logs/files_logfile.log" ]]; then
    local last_files_backup
    last_files_backup=$(grep "START files backup" "$INSTALL_DIR/logs/files_logfile.log" 2>/dev/null | tail -1 | awk '{print $2, $3}')
    [[ -n "$last_files_backup" ]] && echo "  Last Files backup: $last_files_backup"
  fi

  echo
  echo -e "${CYAN}───────────────────────────────────────────────────────${NC}"
  echo -e "${CYAN}  $AUTHOR | $WEBSITE${NC}"
  echo -e "${CYAN}───────────────────────────────────────────────────────${NC}"

  press_enter_to_continue
}

# ---------- View Logs ----------

view_logs() {
  while true; do
    print_header
    echo "View Logs"
    echo "========="
    echo

    # Show log sizes
    local log_dir="$INSTALL_DIR/logs"
    echo "Available Logs:"
    echo

    if [[ -f "$log_dir/db_logfile.log" ]]; then
      local db_size
      db_size=$(du -h "$log_dir/db_logfile.log" 2>/dev/null | cut -f1)
      echo "  1. Database backup log ($db_size)"
    else
      echo -e "  1. Database backup log ${YELLOW}(not found)${NC}"
    fi

    if [[ -f "$log_dir/files_logfile.log" ]]; then
      local files_size
      files_size=$(du -h "$log_dir/files_logfile.log" 2>/dev/null | cut -f1)
      echo "  2. Files backup log ($files_size)"
    else
      echo -e "  2. Files backup log ${YELLOW}(not found)${NC}"
    fi

    if [[ -f "$log_dir/verify_logfile.log" ]]; then
      local verify_size
      verify_size=$(du -h "$log_dir/verify_logfile.log" 2>/dev/null | cut -f1)
      echo "  3. Verification log ($verify_size)"
    else
      echo -e "  3. Verification log ${YELLOW}(not found)${NC}"
    fi

    if [[ -f "$log_dir/notification_failures.log" ]]; then
      local notif_size notif_count
      notif_size=$(du -h "$log_dir/notification_failures.log" 2>/dev/null | cut -f1)
      notif_count=$(wc -l < "$log_dir/notification_failures.log" 2>/dev/null || echo "0")
      if [[ "$notif_count" -gt 0 ]]; then
        echo -e "  4. Notification failures ${RED}($notif_count entries, $notif_size)${NC}"
      else
        echo "  4. Notification failures (empty)"
      fi
    else
      echo -e "  4. Notification failures ${YELLOW}(not found)${NC}"
    fi

    echo
    echo "  5. View all logs directory"
    echo "  6. Clear old logs"
    echo "  0. Back to main menu"
    echo
    read -p "Select option [0-6]: " log_choice

    case "$log_choice" in
      1)
        if [[ -f "$log_dir/db_logfile.log" ]]; then
          less "$log_dir/db_logfile.log"
        else
          print_error "No database backup log found."
          press_enter_to_continue
        fi
        ;;
      2)
        if [[ -f "$log_dir/files_logfile.log" ]]; then
          less "$log_dir/files_logfile.log"
        else
          print_error "No files backup log found."
          press_enter_to_continue
        fi
        ;;
      3)
        if [[ -f "$log_dir/verify_logfile.log" ]]; then
          less "$log_dir/verify_logfile.log"
        else
          print_error "No verification log found."
          press_enter_to_continue
        fi
        ;;
      4)
        if [[ -f "$log_dir/notification_failures.log" ]]; then
          less "$log_dir/notification_failures.log"
        else
          print_error "No notification failure log found."
          press_enter_to_continue
        fi
        ;;
      5)
        echo
        echo "Log directory: $log_dir"
        echo
        ls -lah "$log_dir" 2>/dev/null || echo "No logs directory found."
        press_enter_to_continue
        ;;
      6)
        clear_old_logs
        ;;
      0|*)
        return
        ;;
    esac
  done
}

# ---------- Clear Old Logs ----------

clear_old_logs() {
  echo
  echo "Clear Old Logs"
  echo "=============="
  echo
  echo "This will clear log files older than 30 days."
  echo
  read -p "Continue? (y/N): " confirm

  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    press_enter_to_continue
    return
  fi

  local log_dir="$INSTALL_DIR/logs"
  local cleared=0

  # Truncate logs if they're too large (> 10MB)
  for log_file in "$log_dir"/*.log; do
    [[ -f "$log_file" ]] || continue
    local size_bytes
    size_bytes=$(stat -c%s "$log_file" 2>/dev/null || stat -f%z "$log_file" 2>/dev/null || echo "0")
    if [[ "$size_bytes" -gt 10485760 ]]; then  # 10MB
      echo "Truncating large log: $(basename "$log_file") ($(numfmt --to=iec-i "$size_bytes" 2>/dev/null || echo "${size_bytes}B"))"
      # Keep last 1000 lines
      tail -1000 "$log_file" > "${log_file}.tmp" && mv "${log_file}.tmp" "$log_file"
      ((cleared++)) || true
    fi
  done

  if [[ $cleared -gt 0 ]]; then
    print_success "Cleared $cleared log file(s)."
  else
    print_info "No logs needed clearing."
  fi
  press_enter_to_continue
}
