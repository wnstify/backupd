#!/usr/bin/env bash
# ============================================================================
# Backupd - Schedule Module
# Backup schedule management functions
# ============================================================================

# BACKUPD-035: Schedule Templates/Presets
# Format: TEMPLATE_NAME="oncalendar|display_name|description"
# These provide consistent, reusable schedule configurations

declare -A SCHEDULE_TEMPLATES=(
  ["hourly"]="hourly|Hourly|Run every hour"
  ["every_2h"]="*-*-* 0/2:00:00|Every 2 Hours|Run every 2 hours"
  ["every_6h"]="*-*-* 0/6:00:00|Every 6 Hours|Run every 6 hours"
  ["daily_midnight"]="*-*-* 00:00:00|Daily at Midnight|Run every day at midnight"
  ["daily_1am"]="*-*-* 01:00:00|Daily at 1 AM|Run every day at 1 AM"
  ["daily_2am"]="*-*-* 02:00:00|Daily at 2 AM|Recommended for backups"
  ["daily_3am"]="*-*-* 03:00:00|Daily at 3 AM|Good for secondary systems"
  ["daily_4am"]="*-*-* 04:00:00|Daily at 4 AM|For critical systems"
  ["weekly_sun_2am"]="Sun *-*-* 02:00:00|Weekly Sunday 2 AM|Run every Sunday at 2 AM"
  ["weekly_sat_3am"]="Sat *-*-* 03:00:00|Weekly Saturday 3 AM|Run every Saturday at 3 AM"
  ["biweekly"]="*-*-01,15 02:00:00|Biweekly|Run on 1st and 15th at 2 AM"
  ["monthly"]="*-*-01 02:00:00|Monthly|Run on 1st of month at 2 AM"
)

# BACKUPD-035: Get template OnCalendar expression by name
# Usage: get_template_schedule "daily_2am"
# Returns: OnCalendar expression or empty if not found
get_template_schedule() {
  local name="$1"
  local template="${SCHEDULE_TEMPLATES[$name]}"
  [[ -n "$template" ]] && echo "$template" | cut -d'|' -f1
}

# BACKUPD-035: Get template display name by name
# Usage: get_template_display "daily_2am"
# Returns: Display name or empty if not found
get_template_display() {
  local name="$1"
  local template="${SCHEDULE_TEMPLATES[$name]}"
  [[ -n "$template" ]] && echo "$template" | cut -d'|' -f2
}

# BACKUPD-035: Get template description by name
# Usage: get_template_description "daily_2am"
# Returns: Description or empty if not found
get_template_description() {
  local name="$1"
  local template="${SCHEDULE_TEMPLATES[$name]}"
  [[ -n "$template" ]] && echo "$template" | cut -d'|' -f3
}

# BACKUPD-035: Detect template name from OnCalendar expression
# Usage: detect_template_name "*-*-* 02:00:00"
# Returns: Template name or empty if no match
detect_template_name() {
  local schedule="$1"
  local name oncalendar

  for name in "${!SCHEDULE_TEMPLATES[@]}"; do
    oncalendar=$(echo "${SCHEDULE_TEMPLATES[$name]}" | cut -d'|' -f1)
    if [[ "$oncalendar" == "$schedule" ]]; then
      echo "$name"
      return 0
    fi
  done
  return 1
}

# BACKUPD-035: List all available templates
# Usage: list_schedule_templates
# Output: name|oncalendar|display|description (one per line)
list_schedule_templates() {
  local name oncalendar display description

  # Sort template names for consistent output
  for name in $(echo "${!SCHEDULE_TEMPLATES[@]}" | tr ' ' '\n' | sort); do
    IFS='|' read -r oncalendar display description <<< "${SCHEDULE_TEMPLATES[$name]}"
    echo "${name}|${oncalendar}|${display}|${description}"
  done
}

# ---------- Manage Schedules ----------

manage_schedules() {
  log_func_enter
  debug_enter "manage_schedules"
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

    # Check systemd timers first, fall back to cron (/etc/cron.d/backupd or legacy user crontab)
    if systemctl is-enabled backupd-db.timer &>/dev/null; then
      local db_schedule
      db_schedule=$(systemctl show backupd-db.timer --property=TimersCalendar 2>/dev/null | cut -d'=' -f2)
      if [[ -z "$db_schedule" ]]; then
        db_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-db.timer 2>/dev/null | cut -d'=' -f2)
      fi
      [[ -z "$db_schedule" ]] && db_schedule="(unknown)"
      print_success "Database (systemd): $db_schedule"
    elif cron_entry_exists "db" "default"; then
      local db_schedule
      db_schedule=$(get_cron_schedule "db" "default")
      print_success "Database (cron): $db_schedule"
    elif crontab -l 2>/dev/null | grep -q "$SCRIPTS_DIR/db_backup.sh"; then
      local db_schedule
      db_schedule=$(crontab -l 2>/dev/null | grep "$SCRIPTS_DIR/db_backup.sh" | awk '{print $1,$2,$3,$4,$5}')
      print_success "Database (cron-legacy): $db_schedule"
    else
      print_warning "Database: NOT SCHEDULED"
    fi

    if systemctl is-enabled backupd-files.timer &>/dev/null; then
      local files_schedule
      files_schedule=$(systemctl show backupd-files.timer --property=TimersCalendar 2>/dev/null | cut -d'=' -f2)
      if [[ -z "$files_schedule" ]]; then
        files_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-files.timer 2>/dev/null | cut -d'=' -f2)
      fi
      [[ -z "$files_schedule" ]] && files_schedule="(unknown)"
      print_success "Files (systemd): $files_schedule"
    elif cron_entry_exists "files" "default"; then
      local files_schedule
      files_schedule=$(get_cron_schedule "files" "default")
      print_success "Files (cron): $files_schedule"
    elif crontab -l 2>/dev/null | grep -q "$SCRIPTS_DIR/files_backup.sh"; then
      local files_schedule
      files_schedule=$(crontab -l 2>/dev/null | grep "$SCRIPTS_DIR/files_backup.sh" | awk '{print $1,$2,$3,$4,$5}')
      print_success "Files (cron-legacy): $files_schedule"
    else
      print_warning "Files: NOT SCHEDULED"
    fi

    # Check quick integrity check timer
    if systemctl is-enabled backupd-verify.timer &>/dev/null; then
      local verify_schedule
      verify_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-verify.timer 2>/dev/null | cut -d'=' -f2)
      print_success "Quick integrity check (systemd): $verify_schedule"
    elif cron_entry_exists "verify" "default"; then
      local verify_schedule
      verify_schedule=$(get_cron_schedule "verify" "default")
      print_success "Quick integrity check (cron): $verify_schedule"
    else
      print_warning "Quick integrity check: NOT SCHEDULED (optional)"
    fi

    # Check monthly full verification timer
    if systemctl is-enabled backupd-verify-full.timer &>/dev/null; then
      local full_verify_schedule
      full_verify_schedule=$(grep -E "^OnCalendar=" /etc/systemd/system/backupd-verify-full.timer 2>/dev/null | cut -d'=' -f2)
      print_success "Monthly full verification (systemd): $full_verify_schedule"
    elif cron_entry_exists "verify-full" "default"; then
      local full_verify_schedule
      full_verify_schedule=$(get_cron_schedule "verify-full" "default")
      print_success "Monthly full verification (cron): $full_verify_schedule"
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
    echo
    echo "J. Manage Job Schedules (multi-job)"
    echo "0. Back to main menu"
    echo
    read -p "Select option [0-9, J]: " schedule_choice

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
      [Jj])
        manage_job_schedules
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
  echo "  1) 7 days"
  echo "  2) 14 days"
  echo "  3) 30 days (recommended)"
  echo "  4) 60 days"
  echo "  5) 90 days"
  echo "  6) 365 days (1 year)"
  echo "  0) Cancel"
  echo
  read -p "Select option [0-6]: " RETENTION_CHOICE

  [[ "$RETENTION_CHOICE" == "0" ]] && return

  local RETENTION_DAYS=30
  local RETENTION_DESC=""
  case "$RETENTION_CHOICE" in
    1) RETENTION_DAYS=7; RETENTION_DESC="7 days" ;;
    2) RETENTION_DAYS=14; RETENTION_DESC="14 days" ;;
    3) RETENTION_DAYS=30; RETENTION_DESC="30 days" ;;
    4) RETENTION_DAYS=60; RETENTION_DESC="60 days" ;;
    5) RETENTION_DAYS=90; RETENTION_DESC="90 days" ;;
    6) RETENTION_DAYS=365; RETENTION_DESC="365 days (1 year)" ;;
    *)
      print_error "Invalid option"
      press_enter_to_continue
      return
      ;;
  esac

  save_config "RETENTION_DAYS" "$RETENTION_DAYS"
  save_config "RETENTION_DESC" "$RETENTION_DESC"

  # Regenerate backup scripts with new retention
  local secrets_dir rclone_remote rclone_db_path rclone_files_path web_path_pattern webroot_subdir
  secrets_dir="$(get_secrets_dir)"
  rclone_remote="$(get_config_value 'RCLONE_REMOTE')"
  rclone_db_path="$(get_config_value 'RCLONE_DB_PATH')"
  rclone_files_path="$(get_config_value 'RCLONE_FILES_PATH')"
  web_path_pattern="$(get_config_value 'WEB_PATH_PATTERN')"
  webroot_subdir="$(get_config_value 'WEBROOT_SUBDIR')"

  local do_database do_files
  do_database="$(get_config_value 'DO_DATABASE')"
  do_files="$(get_config_value 'DO_FILES')"

  echo
  echo "Regenerating backup scripts with new retention policy..."

  generate_all_scripts "$secrets_dir" "$do_database" "$do_files" "$rclone_remote" \
    "$rclone_db_path" "$rclone_files_path" "$RETENTION_DAYS" \
    "${web_path_pattern:-/var/www/*}" "${webroot_subdir:-.}"

  print_success "Backup scripts updated"

  echo
  print_success "Retention policy updated to: $RETENTION_DESC"
  press_enter_to_continue
}

set_systemd_schedule() {
  log_func_enter
  debug_enter "set_systemd_schedule" "$@"
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

  # Choose scheduler based on availability
  if is_systemd_available; then
    # Systemd scheduler: create timer and service units
    cat > "/etc/systemd/system/$timer_name" << EOF
[Unit]
Description=Backupd - $display_name Backup Timer
Requires=$service_name

[Timer]
OnCalendar=$on_calendar
# RandomizedDelaySec: Spread backups to prevent thundering herd
# Note: Use different OnCalendar schedules for db vs files to avoid overlap
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Always regenerate service file to ensure correct paths
    local script_path="$SCRIPTS_DIR/${timer_type}_backup.sh"
    cat > "/etc/systemd/system/$service_name" << EOF
[Unit]
Description=Backupd - $display_name Backup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$script_path
StandardOutput=journal
StandardError=journal
Nice=10
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
EOF

    # Reload and enable
    systemctl daemon-reload
    systemctl enable "$timer_name" 2>/dev/null || true
    systemctl start "$timer_name" 2>/dev/null || true

    # Remove any cron entries for this backup (cleanup)
    remove_cron_entry "$timer_type" "default"

    echo
    print_success "$display_name backup schedule set: $on_calendar"
    print_info "Timer enabled and started (systemd)"

  elif is_cron_available; then
    # Cron fallback: validate cron compatibility first
    if ! is_cron_compatible "$on_calendar"; then
      echo
      print_error "This schedule pattern requires systemd."
      print_info "Please use a simpler pattern (e.g., daily, hourly, *-*-* HH:MM:SS)"
      press_enter_to_continue
      return 1
    fi

    # Create cron entry
    if ! create_cron_entry "$timer_type" "$on_calendar" "default"; then
      print_error "Failed to create cron schedule"
      press_enter_to_continue
      return 1
    fi

    echo
    print_success "$display_name backup schedule set: $on_calendar"
    print_info "Schedule created (cron)"

  else
    # No scheduler available: provide manual instructions
    print_manual_cron_entry "$timer_type" "$on_calendar" "default"
  fi

  press_enter_to_continue
}

disable_schedule() {
  local timer_type="$1"
  local display_name="$2"

  # Use unified scheduler API to disable both systemd and cron
  scheduler_disable "$timer_type" "default"

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

# ---------- Manage Job Schedules (Multi-Job Support) ----------

# Interactive menu to manage schedules for any job
# Usage: manage_job_schedules
manage_job_schedules() {
  while true; do
    print_header
    echo "Manage Job Schedules"
    echo "===================="
    echo

    if ! is_configured; then
      print_error "System not configured. Please run setup first."
      press_enter_to_continue
      return
    fi

    # Get list of jobs
    local jobs=()
    local job
    while IFS= read -r job; do
      [[ -n "$job" ]] && jobs+=("$job")
    done < <(list_jobs)

    if [[ ${#jobs[@]} -eq 0 ]]; then
      print_warning "No jobs configured."
      echo
      echo "Create a job first:"
      echo "  backupd job create <name>"
      echo
      press_enter_to_continue
      return
    fi

    # Display job selection menu
    echo "Select a job to manage schedules:"
    echo
    local i=1
    for job in "${jobs[@]}"; do
      echo "  $i. $job"
      ((i++))
    done
    echo
    echo "  0. Back to schedules menu"
    echo
    read -p "Select job [0-${#jobs[@]}]: " job_choice

    # Validate input
    if [[ "$job_choice" == "0" ]]; then
      return
    fi

    if ! [[ "$job_choice" =~ ^[0-9]+$ ]] || [[ "$job_choice" -lt 1 ]] || [[ "$job_choice" -gt ${#jobs[@]} ]]; then
      print_error "Invalid selection"
      sleep 1
      continue
    fi

    local selected_job="${jobs[$((job_choice-1))]}"
    manage_job_schedule_types "$selected_job"
  done
}

# Submenu for selecting backup type to schedule
# Usage: manage_job_schedule_types "production"
manage_job_schedule_types() {
  local job_name="$1"

  while true; do
    print_header
    echo "Job: $job_name - Schedule Management"
    echo "===================================="
    echo

    # Show current schedules for this job
    echo "Current Schedules:"
    echo
    local types=("db" "files" "verify" "verify-full")
    local config_keys=("SCHEDULE_DB" "SCHEDULE_FILES" "SCHEDULE_VERIFY" "SCHEDULE_VERIFY_FULL")
    local display_names=("Database" "Files" "Quick Verify" "Full Verify")

    local i
    for i in "${!types[@]}"; do
      local schedule
      schedule=$(get_job_config "$job_name" "${config_keys[$i]}")
      local timer_name
      timer_name="$(get_timer_name "$job_name" "${types[$i]}")"
      local status="not scheduled"

      if [[ -n "$schedule" ]]; then
        if systemctl is-active --quiet "$timer_name" 2>/dev/null; then
          status="active"
        else
          status="inactive"
        fi
        printf "  %-12s %s (timer: %s)\n" "${display_names[$i]}:" "$schedule" "$status"
      else
        printf "  %-12s %s\n" "${display_names[$i]}:" "NOT SCHEDULED"
      fi
    done

    echo
    echo "Select backup type to schedule:"
    echo
    echo "  1. Database backup"
    echo "  2. Files backup"
    echo "  3. Quick integrity check"
    echo "  4. Full integrity check"
    echo
    echo "  0. Back to job selection"
    echo
    read -p "Select option [0-4]: " type_choice

    case "$type_choice" in
      1) set_job_schedule "$job_name" "db" "Database" ;;
      2) set_job_schedule "$job_name" "files" "Files" ;;
      3) set_job_schedule "$job_name" "verify" "Quick Verify" ;;
      4) set_job_schedule "$job_name" "verify-full" "Full Verify" ;;
      0) return ;;
      *) print_error "Invalid option" ; sleep 1 ;;
    esac
  done
}

# Set schedule for a specific job and backup type
# Usage: set_job_schedule "production" "db" "Database"
set_job_schedule() {
  local job_name="$1"
  local backup_type="$2"
  local display_name="$3"

  print_header
  echo "Job: $job_name - Schedule $display_name Backup"
  echo "=============================================="
  echo

  # Show current schedule if exists
  local config_key
  case "$backup_type" in
    db) config_key="SCHEDULE_DB" ;;
    files) config_key="SCHEDULE_FILES" ;;
    verify) config_key="SCHEDULE_VERIFY" ;;
    verify-full) config_key="SCHEDULE_VERIFY_FULL" ;;
  esac

  local current_schedule
  current_schedule=$(get_job_config "$job_name" "$config_key")
  if [[ -n "$current_schedule" ]]; then
    echo "Current schedule: $current_schedule"
  else
    echo "Current schedule: NOT SET"
  fi
  echo

  echo "Select schedule option:"
  echo
  echo "  1. Hourly"
  echo "  2. Every 2 hours"
  echo "  3. Every 6 hours"
  echo "  4. Daily at midnight"
  echo "  5. Daily at 2 AM (recommended for backups)"
  echo "  6. Daily at 3 AM"
  echo "  7. Weekly (Sunday at 2 AM)"
  echo "  8. Monthly (1st at 2 AM)"
  echo "  9. Custom schedule"
  echo
  echo "  D. Disable schedule"
  echo "  0. Cancel"
  echo
  read -p "Select option [0-9, D]: " sched_choice

  local on_calendar=""
  case "$sched_choice" in
    1) on_calendar="hourly" ;;
    2) on_calendar="*-*-* 0/2:00:00" ;;
    3) on_calendar="*-*-* 0/6:00:00" ;;
    4) on_calendar="*-*-* 00:00:00" ;;
    5) on_calendar="*-*-* 02:00:00" ;;
    6) on_calendar="*-*-* 03:00:00" ;;
    7) on_calendar="Sun *-*-* 02:00:00" ;;
    8) on_calendar="*-*-01 02:00:00" ;;
    9)
      echo
      echo "Enter systemd OnCalendar expression."
      echo
      echo "Examples:"
      echo "  hourly              - Every hour"
      echo "  daily               - Every day at midnight"
      echo "  *-*-* 02:00:00      - Every day at 2 AM"
      echo "  *-*-* 0/6:00:00     - Every 6 hours"
      echo "  Mon,Fri *-*-* 02:00 - Monday and Friday at 2 AM"
      echo "  Sun *-*-* 03:00:00  - Every Sunday at 3 AM"
      echo "  *-*-01 02:00:00     - First day of month at 2 AM"
      echo
      read -p "OnCalendar: " on_calendar
      if [[ -z "$on_calendar" ]]; then
        print_error "No schedule entered."
        press_enter_to_continue
        return
      fi
      ;;
    [Dd])
      disable_job_schedule "$job_name" "$backup_type" "$display_name"
      return
      ;;
    0)
      return
      ;;
    *)
      print_error "Invalid option"
      press_enter_to_continue
      return
      ;;
  esac

  # Validate the schedule format
  echo
  if ! validate_schedule_format "$on_calendar" 2>/dev/null; then
    print_error "Invalid schedule format: $on_calendar"
    echo
    echo "Hint: Test with: systemd-analyze calendar '$on_calendar'"
    press_enter_to_continue
    return
  fi

  # Create the timer
  echo "Creating timer for $job_name $display_name backup..."
  echo
  if create_job_timer "$job_name" "$backup_type" "$on_calendar" >/dev/null 2>&1; then
    print_success "Schedule set: $on_calendar"
    echo
    local timer_name
    timer_name="$(get_timer_name "$job_name" "$backup_type")"
    print_info "Timer: $timer_name"

    # Check for conflicts (advisory)
    check_schedule_conflicts "$job_name" "$backup_type" "$on_calendar"
  else
    print_error "Failed to create timer"
    echo
    print_info "Ensure backup scripts exist: backupd job regenerate $job_name"
  fi

  press_enter_to_continue
}

# Disable schedule for a specific job and backup type
# Usage: disable_job_schedule "production" "db" "Database"
disable_job_schedule() {
  local job_name="$1"
  local backup_type="$2"
  local display_name="$3"

  local timer_name
  timer_name="$(get_timer_name "$job_name" "$backup_type")"

  echo
  echo "Disabling $display_name schedule for job '$job_name'..."

  systemctl stop "$timer_name" 2>/dev/null || true
  systemctl disable "$timer_name" 2>/dev/null || true

  print_success "$display_name schedule disabled"
  press_enter_to_continue
}
