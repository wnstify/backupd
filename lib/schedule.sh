#!/usr/bin/env bash
# ============================================================================
# Backupd - Schedule Module
# Backup schedule management functions
# ============================================================================

# ---------- Manage Schedules ----------

manage_schedules() {
  while true; do
    print_header
    echo "Manage Backup Schedules"
    echo "======================="
    echo

    if ! is_configured; then
      print_error "System not configured. Please run setup first."
      press_enter_to_continue
      return
    fi

    # Show current schedules
    echo "Current Schedules:"
    echo

    # Check systemd timers first, fall back to cron
    if systemctl is-enabled backupd-db.timer &>/dev/null; then
      local db_schedule
      db_schedule=$(systemctl show backupd-db.timer --property=TimersCalendar 2>/dev/null | cut -d'=' -f2)
      if [[ -z "$db_schedule" ]]; then
        db_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-db.timer 2>/dev/null | cut -d'=' -f2)
      fi
      print_success "Database (systemd): $db_schedule"
    elif crontab -l 2>/dev/null | grep -q "$SCRIPTS_DIR/db_backup.sh"; then
      local db_schedule
      db_schedule=$(crontab -l 2>/dev/null | grep "$SCRIPTS_DIR/db_backup.sh" | awk '{print $1,$2,$3,$4,$5}')
      print_success "Database (cron): $db_schedule"
    else
      print_warning "Database: NOT SCHEDULED"
    fi

    if systemctl is-enabled backupd-files.timer &>/dev/null; then
      local files_schedule
      files_schedule=$(systemctl show backupd-files.timer --property=TimersCalendar 2>/dev/null | cut -d'=' -f2)
      if [[ -z "$files_schedule" ]]; then
        files_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-files.timer 2>/dev/null | cut -d'=' -f2)
      fi
      print_success "Files (systemd): $files_schedule"
    elif crontab -l 2>/dev/null | grep -q "$SCRIPTS_DIR/files_backup.sh"; then
      local files_schedule
      files_schedule=$(crontab -l 2>/dev/null | grep "$SCRIPTS_DIR/files_backup.sh" | awk '{print $1,$2,$3,$4,$5}')
      print_success "Files (cron): $files_schedule"
    else
      print_warning "Files: NOT SCHEDULED"
    fi

    # Check quick integrity check timer
    if systemctl is-enabled backupd-verify.timer &>/dev/null; then
      local verify_schedule
      verify_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-verify.timer 2>/dev/null | cut -d'=' -f2)
      print_success "Quick integrity check (systemd): $verify_schedule"
    else
      print_warning "Quick integrity check: NOT SCHEDULED (optional)"
    fi

    # Check monthly full verification timer
    if systemctl is-enabled backupd-verify-full.timer &>/dev/null; then
      local full_verify_schedule
      full_verify_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-verify-full.timer 2>/dev/null | cut -d'=' -f2)
      print_success "Monthly full verification (systemd): $full_verify_schedule"
    else
      print_warning "Monthly full verification: DISABLED (recommended to enable)"
    fi

    # Show retention policy
    echo
    local retention_desc
    retention_desc="$(get_config_value 'RETENTION_DESC')"
    if [[ -n "$retention_desc" ]]; then
      print_success "Retention policy: $retention_desc"
    else
      print_warning "Retention policy: NOT CONFIGURED"
    fi

    echo
    echo "Options:"
    echo "1. Set/change database backup schedule"
    echo "2. Set/change files backup schedule"
    echo "3. Disable database backup schedule"
    echo "4. Disable files backup schedule"
    echo "5. Change retention policy"
    echo "6. Set/change quick integrity check schedule"
    echo "7. Disable quick integrity check schedule"
    echo "8. Enable/disable monthly full verification"
    echo "9. View timer status"
    echo "0. Back to main menu"
    echo
    read -p "Select option [0-9]: " schedule_choice

    case "$schedule_choice" in
      1)
        set_systemd_schedule "db" "Database"
        ;;
      2)
        set_systemd_schedule "files" "Files"
        ;;
      3)
        disable_schedule "db" "Database"
        ;;
      4)
        disable_schedule "files" "Files"
        ;;
      5)
        change_retention_policy
        ;;
      6)
        set_integrity_check_schedule
        ;;
      7)
        disable_schedule "verify" "Quick integrity check"
        ;;
      8)
        manage_full_verification_timer
        ;;
      9)
        view_timer_status
        ;;
      0|*)
        return
        ;;
    esac
  done
}

change_retention_policy() {
  print_header
  echo "Change Retention Policy"
  echo "======================="
  echo

  local current_retention
  current_retention="$(get_config_value 'RETENTION_DESC')"
  if [[ -n "$current_retention" ]]; then
    echo "Current retention: $current_retention"
  else
    echo "Current retention: NOT CONFIGURED"
  fi

  echo
  echo "Select new retention period:"
  echo
  echo "  1) 1 minute (TESTING ONLY)"
  echo "  2) 1 hour (TESTING)"
  echo "  3) 7 days"
  echo "  4) 14 days"
  echo "  5) 30 days"
  echo "  6) 60 days"
  echo "  7) 90 days"
  echo "  8) 365 days (1 year)"
  echo "  9) No automatic cleanup"
  echo "  0) Cancel"
  echo
  read -p "Select option [0-9]: " RETENTION_CHOICE

  [[ "$RETENTION_CHOICE" == "0" ]] && return

  local RETENTION_MINUTES=0
  local RETENTION_DESC=""
  case "$RETENTION_CHOICE" in
    1) RETENTION_MINUTES=1; RETENTION_DESC="1 minute (TESTING)" ;;
    2) RETENTION_MINUTES=60; RETENTION_DESC="1 hour (TESTING)" ;;
    3) RETENTION_MINUTES=$((7 * 24 * 60)); RETENTION_DESC="7 days" ;;
    4) RETENTION_MINUTES=$((14 * 24 * 60)); RETENTION_DESC="14 days" ;;
    5) RETENTION_MINUTES=$((30 * 24 * 60)); RETENTION_DESC="30 days" ;;
    6) RETENTION_MINUTES=$((60 * 24 * 60)); RETENTION_DESC="60 days" ;;
    7) RETENTION_MINUTES=$((90 * 24 * 60)); RETENTION_DESC="90 days" ;;
    8) RETENTION_MINUTES=$((365 * 24 * 60)); RETENTION_DESC="365 days" ;;
    9) RETENTION_MINUTES=0; RETENTION_DESC="No automatic cleanup" ;;
    *)
      print_error "Invalid option"
      press_enter_to_continue
      return
      ;;
  esac

  save_config "RETENTION_MINUTES" "$RETENTION_MINUTES"
  save_config "RETENTION_DESC" "$RETENTION_DESC"

  # Regenerate backup scripts with new retention
  local secrets_dir rclone_remote rclone_db_path rclone_files_path
  secrets_dir="$(get_secrets_dir)"
  rclone_remote="$(get_config_value 'RCLONE_REMOTE')"
  rclone_db_path="$(get_config_value 'RCLONE_DB_PATH')"
  rclone_files_path="$(get_config_value 'RCLONE_FILES_PATH')"

  echo
  echo "Regenerating backup scripts with new retention policy..."

  if [[ -f "$SCRIPTS_DIR/db_backup.sh" ]] && [[ -n "$rclone_db_path" ]]; then
    generate_db_backup_script "$secrets_dir" "$rclone_remote" "$rclone_db_path" "$INSTALL_DIR/logs" "$RETENTION_MINUTES"
    print_success "Database backup script updated"
  fi

  if [[ -f "$SCRIPTS_DIR/files_backup.sh" ]] && [[ -n "$rclone_files_path" ]]; then
    generate_files_backup_script "$secrets_dir" "$rclone_remote" "$rclone_files_path" "$INSTALL_DIR/logs" "$RETENTION_MINUTES"
    print_success "Files backup script updated"
  fi

  echo
  print_success "Retention policy updated to: $RETENTION_DESC"
  press_enter_to_continue
}

set_systemd_schedule() {
  local timer_type="$1"
  local display_name="$2"
  local timer_name="backupd-${timer_type}.timer"
  local service_name="backupd-${timer_type}.service"

  echo
  echo "Select schedule for $display_name backup:"
  echo "1. Hourly"
  echo "2. Every 2 hours"
  echo "3. Every 6 hours"
  echo "4. Daily at midnight"
  echo "5. Daily at 3 AM (recommended for files)"
  echo "6. Weekly (Sunday at midnight)"
  echo "7. Custom schedule"
  echo
  read -p "Select option [1-7]: " freq_choice

  local on_calendar
  case "$freq_choice" in
    1) on_calendar="hourly" ;;
    2) on_calendar="*-*-* 0/2:00:00" ;;
    3) on_calendar="*-*-* 0/6:00:00" ;;
    4) on_calendar="*-*-* 00:00:00" ;;
    5) on_calendar="*-*-* 03:00:00" ;;
    6) on_calendar="Sun *-*-* 00:00:00" ;;
    7)
      echo
      echo "Enter systemd OnCalendar expression."
      echo "Examples:"
      echo "  hourly              - Every hour"
      echo "  daily               - Every day at midnight"
      echo "  *-*-* 03:00:00      - Every day at 3 AM"
      echo "  Mon,Fri *-*-* 02:00 - Monday and Friday at 2 AM"
      echo "  *-*-* *:0/30:00     - Every 30 minutes"
      echo
      read -p "OnCalendar: " on_calendar
      ;;
    *)
      print_error "Invalid selection."
      press_enter_to_continue
      return
      ;;
  esac

  # Update the timer file
  cat > "/etc/systemd/system/$timer_name" << EOF
[Unit]
Description=Backupd - $display_name Backup Timer
Requires=$service_name

[Timer]
OnCalendar=$on_calendar
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
EOF

  # Ensure service file exists
  if [[ ! -f "/etc/systemd/system/$service_name" ]]; then
    local script_path="$SCRIPTS_DIR/${timer_type}_backup.sh"
    cat > "/etc/systemd/system/$service_name" << EOF
[Unit]
Description=Backupd - $display_name Backup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$script_path
StandardOutput=append:$INSTALL_DIR/logs/${timer_type}_logfile.log
StandardError=append:$INSTALL_DIR/logs/${timer_type}_logfile.log
Nice=10
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
EOF
  fi

  # Reload and enable
  systemctl daemon-reload
  systemctl enable "$timer_name" 2>/dev/null || true
  systemctl start "$timer_name" 2>/dev/null || true

  # Remove any cron entries for this backup
  if [[ "$timer_type" == "db" ]]; then
    ( crontab -l 2>/dev/null | grep -Fv "$SCRIPTS_DIR/db_backup.sh" ) | crontab - 2>/dev/null || true
  else
    ( crontab -l 2>/dev/null | grep -Fv "$SCRIPTS_DIR/files_backup.sh" ) | crontab - 2>/dev/null || true
  fi

  echo
  print_success "$display_name backup schedule set: $on_calendar"
  print_info "Timer enabled and started"
  press_enter_to_continue
}

disable_schedule() {
  local timer_type="$1"
  local display_name="$2"
  local timer_name="backupd-${timer_type}.timer"

  # Disable systemd timer
  systemctl stop "$timer_name" 2>/dev/null || true
  systemctl disable "$timer_name" 2>/dev/null || true

  # Also remove cron entries (for db/files only, not verify)
  if [[ "$timer_type" == "db" ]]; then
    ( crontab -l 2>/dev/null | grep -Fv "$SCRIPTS_DIR/db_backup.sh" ) | crontab - 2>/dev/null || true
  elif [[ "$timer_type" == "files" ]]; then
    ( crontab -l 2>/dev/null | grep -Fv "$SCRIPTS_DIR/files_backup.sh" ) | crontab - 2>/dev/null || true
  fi
  # verify type has no cron fallback, just systemd

  print_success "$display_name schedule disabled."
  press_enter_to_continue
}

set_integrity_check_schedule() {
  print_header
  echo "Schedule Integrity Check"
  echo "========================"
  echo
  echo "This will schedule automatic backup verification."
  echo "It downloads the latest backup and verifies:"
  echo "  - SHA256 checksum"
  echo "  - Decryption (using stored passphrase)"
  echo "  - Archive contents"
  echo
  echo "Results are logged and sent via notification (if configured)."
  echo

  echo "Select schedule for integrity check:"
  echo "1. Weekly (Sunday at 2 AM) - recommended"
  echo "2. Weekly (Saturday at 3 AM)"
  echo "3. Every 2 weeks (1st and 15th at 2 AM)"
  echo "4. Monthly (1st day at 2 AM)"
  echo "5. Daily at 4 AM (for critical systems)"
  echo "6. Custom schedule"
  echo "7. Cancel"
  echo
  read -p "Select option [1-7]: " verify_choice

  local on_calendar
  case "$verify_choice" in
    1) on_calendar="Sun *-*-* 02:00:00" ;;
    2) on_calendar="Sat *-*-* 03:00:00" ;;
    3) on_calendar="*-*-01,15 02:00:00" ;;
    4) on_calendar="*-*-01 02:00:00" ;;
    5) on_calendar="*-*-* 04:00:00" ;;
    6)
      echo
      echo "Enter systemd OnCalendar expression."
      echo "Examples:"
      echo "  Sun *-*-* 02:00:00     - Every Sunday at 2 AM"
      echo "  *-*-01 02:00:00        - First day of month at 2 AM"
      echo "  Mon,Thu *-*-* 03:00:00 - Monday and Thursday at 3 AM"
      echo
      read -p "OnCalendar expression: " on_calendar
      if [[ -z "$on_calendar" ]]; then
        print_error "No schedule entered."
        press_enter_to_continue
        return
      fi
      ;;
    7|*)
      return
      ;;
  esac

  echo
  echo "Generating verification script..."

  # Generate the verification script
  generate_verify_script

  # Create systemd service
  cat > /etc/systemd/system/backupd-verify.service << EOF
[Unit]
Description=Backupd - Integrity Verification
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPTS_DIR/verify_backup.sh
StandardOutput=journal
StandardError=journal
Nice=19
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
EOF

  # Create systemd timer
  cat > /etc/systemd/system/backupd-verify.timer << EOF
[Unit]
Description=Backupd - Weekly Integrity Verification

[Timer]
OnCalendar=$on_calendar
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

  # Enable and start timer
  systemctl daemon-reload
  systemctl enable backupd-verify.timer
  systemctl start backupd-verify.timer

  echo
  print_success "Integrity check scheduled: $on_calendar"
  print_info "Script location: $SCRIPTS_DIR/verify_backup.sh"
  print_info "Log location: $INSTALL_DIR/logs/verify_logfile.log"
  press_enter_to_continue
}

view_timer_status() {
  print_header
  echo "Systemd Timer Status"
  echo "===================="
  echo

  echo -e "${CYAN}Database Backup Timer:${NC}"
  systemctl status backupd-db.timer --no-pager 2>/dev/null || echo "  Not installed or not running"
  echo

  echo -e "${CYAN}Files Backup Timer:${NC}"
  systemctl status backupd-files.timer --no-pager 2>/dev/null || echo "  Not installed or not running"
  echo

  echo -e "${CYAN}Quick Integrity Check Timer:${NC}"
  systemctl status backupd-verify.timer --no-pager 2>/dev/null || echo "  Not installed or not running"
  echo

  echo -e "${CYAN}Monthly Full Verification Timer:${NC}"
  systemctl status backupd-verify-full.timer --no-pager 2>/dev/null || echo "  Not installed or not running"
  echo

  echo -e "${CYAN}Next scheduled runs:${NC}"
  systemctl list-timers backupd-* --no-pager 2>/dev/null || echo "  No timers scheduled"

  press_enter_to_continue
}

# ---------- Manage Monthly Full Verification Timer ----------

manage_full_verification_timer() {
  print_header
  echo "Monthly Full Verification"
  echo "========================="
  echo
  echo "This downloads and fully verifies your backups every 30 days."
  echo "It tests decryption and archive integrity to confirm backups"
  echo "are actually restorable - not just that files exist."
  echo

  local is_enabled=false
  if systemctl is-enabled backupd-verify-full.timer &>/dev/null; then
    is_enabled=true
    local current_schedule
    current_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-verify-full.timer 2>/dev/null | cut -d'=' -f2)
    print_success "Status: ENABLED (Schedule: $current_schedule)"
  else
    print_warning "Status: DISABLED"
  fi

  echo
  echo "Options:"
  echo "1. Enable monthly full verification (recommended)"
  echo "2. Disable monthly full verification"
  echo "3. Back"
  echo
  read -p "Select option [1-3]: " full_verify_choice

  case "$full_verify_choice" in
    1)
      enable_full_verification_timer
      ;;
    2)
      disable_full_verification_timer
      ;;
    3|*)
      return
      ;;
  esac
}

# Enable the monthly full verification timer
enable_full_verification_timer() {
  echo
  echo "Generating full verification script..."

  # Generate the full verification script
  generate_full_verify_script

  # Create systemd service
  cat > /etc/systemd/system/backupd-verify-full.service << EOF
[Unit]
Description=Backupd - Monthly Full Backup Verification
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPTS_DIR/verify_full_backup.sh
StandardOutput=journal
StandardError=journal
Nice=19
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
EOF

  # Create systemd timer (runs on 1st of each month at 3 AM)
  cat > /etc/systemd/system/backupd-verify-full.timer << EOF
[Unit]
Description=Backupd - Monthly Full Backup Verification Timer

[Timer]
OnCalendar=*-*-01 03:00:00
Persistent=true
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
EOF

  # Enable and start timer
  systemctl daemon-reload
  systemctl enable backupd-verify-full.timer
  systemctl start backupd-verify-full.timer

  echo
  print_success "Monthly full verification enabled"
  print_info "Schedule: 1st of each month at 3 AM"
  print_info "Script: $SCRIPTS_DIR/verify_full_backup.sh"
  print_info "Log: $INSTALL_DIR/logs/verify_full_logfile.log"
  echo
  print_info "Run manually anytime: systemctl start backupd-verify-full"
  press_enter_to_continue
}

# Disable the monthly full verification timer (with warning)
disable_full_verification_timer() {
  echo
  echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}                     ⚠️  WARNING ⚠️${NC}"
  echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
  echo
  echo "Disabling monthly full verification means:"
  echo
  echo "  • You will NOT automatically test if backups are restorable"
  echo "  • Backup corruption may go undetected for months"
  echo "  • When disaster strikes, you might find backups unusable"
  echo
  echo -e "${CYAN}Best Practice:${NC}"
  echo "  Keep monthly verification enabled. It runs once per month,"
  echo "  downloads one backup of each type, and confirms you can"
  echo "  actually restore from it. This is essential backup hygiene."
  echo
  echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
  echo

  read -p "Are you sure you want to disable monthly verification? (yes/no): " confirm

  if [[ "$confirm" == "yes" ]]; then
    systemctl stop backupd-verify-full.timer 2>/dev/null || true
    systemctl disable backupd-verify-full.timer 2>/dev/null || true
    echo
    print_warning "Monthly full verification DISABLED"
    echo
    echo "To re-enable: sudo backupd → Manage schedules → Enable monthly full verification"
  else
    echo
    print_info "Monthly full verification remains enabled (good choice!)"
  fi

  press_enter_to_continue
}
