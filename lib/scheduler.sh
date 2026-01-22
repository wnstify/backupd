#!/usr/bin/env bash
# ============================================================================
# Backupd - Scheduler Abstraction Module
# Provides unified API for systemd and cron scheduling with automatic fallback
# ============================================================================

# Scheduler type cache (systemd | cron | none)
SCHEDULER_TYPE=""

# Cron file location for centralized management
CRON_FILE="/etc/cron.d/backupd"

# ---------- Scheduler Detection ----------

# Detect available scheduler (cached)
# Returns: "systemd" | "cron" | "none"
detect_scheduler() {
  if [[ -n "$SCHEDULER_TYPE" ]]; then
    echo "$SCHEDULER_TYPE"
    return 0
  fi

  # Check for running systemd (not just installed)
  if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
    SCHEDULER_TYPE="systemd"
  elif command -v crontab &>/dev/null; then
    SCHEDULER_TYPE="cron"
  else
    SCHEDULER_TYPE="none"
  fi

  echo "$SCHEDULER_TYPE"
}

# Check if systemd is available and running
is_systemd_available() {
  [[ "$(detect_scheduler)" == "systemd" ]]
}

# Check if cron is available (always check, even on systemd systems for cleanup)
is_cron_available() {
  command -v crontab &>/dev/null
}

# ---------- OnCalendar to Cron Conversion ----------

# Day-of-week mapping (systemd to cron)
declare -A DOW_MAP=(
  [Mon]=1 [Tue]=2 [Wed]=3 [Thu]=4 [Fri]=5 [Sat]=6 [Sun]=0
  [Monday]=1 [Tuesday]=2 [Wednesday]=3 [Thursday]=4 [Friday]=5 [Saturday]=6 [Sunday]=0
)

# Convert systemd OnCalendar expression to cron format
# Usage: oncalendar_to_cron "*-*-* 02:00:00"
# Returns: cron expression or error (exit 1)
oncalendar_to_cron() {
  local oncalendar="$1"
  local minute hour dom month dow

  # Handle keyword shortcuts
  case "$oncalendar" in
    hourly)  echo "0 * * * *"; return 0 ;;
    daily)   echo "0 0 * * *"; return 0 ;;
    weekly)  echo "0 0 * * 0"; return 0 ;;
    monthly) echo "0 0 1 * *"; return 0 ;;
  esac

  # Parse OnCalendar format: [DOW] YYYY-MM-DD HH:MM[:SS]
  local dow_prefix="" date_part="" time_part=""

  # Check for day-of-week prefix (e.g., "Mon *-*-* 02:00")
  if [[ "$oncalendar" =~ ^([A-Za-z,]+)[[:space:]]+ ]]; then
    dow_prefix="${BASH_REMATCH[1]}"
    oncalendar="${oncalendar#"$dow_prefix"}"
    oncalendar="${oncalendar# }"  # Trim leading space
  fi

  # Split remaining into date and time parts
  if [[ "$oncalendar" =~ ^([^[:space:]]+)[[:space:]]+(.+)$ ]]; then
    date_part="${BASH_REMATCH[1]}"
    time_part="${BASH_REMATCH[2]}"
  else
    echo "Error: Cannot parse OnCalendar expression" >&2
    return 1
  fi

  # Parse time (HH:MM:SS or HH:MM or H/N:MM:SS for intervals)
  local time_hour time_min
  if [[ "$time_part" =~ ^([0-9*/]+):([0-9]+) ]]; then
    time_hour="${BASH_REMATCH[1]}"
    time_min="${BASH_REMATCH[2]}"
  else
    echo "Error: Cannot parse time part: $time_part" >&2
    return 1
  fi

  # Convert hour format (handle 0/6 -> */6 for cron)
  if [[ "$time_hour" =~ ^0/([0-9]+)$ ]]; then
    hour="*/${BASH_REMATCH[1]}"
  elif [[ "$time_hour" =~ ^\*/([0-9]+)$ ]]; then
    hour="$time_hour"
  else
    # Remove leading zeros for cron compatibility
    hour=$((10#$time_hour))
  fi

  # Convert minute (remove leading zeros)
  minute=$((10#$time_min))

  # Parse date part (*-*-* or *-*-DD)
  if [[ "$date_part" =~ ^\*-\*-([0-9*]+)$ ]]; then
    local day_val="${BASH_REMATCH[1]}"
    if [[ "$day_val" == "*" ]]; then
      dom="*"
    elif [[ "$day_val" =~ , ]]; then
      # Multiple days (e.g., 01,15) - not supported in standard cron
      echo "Error: Multiple day-of-month values not supported in cron (use systemd)" >&2
      return 1
    else
      dom=$((10#$day_val))
    fi
    month="*"
  elif [[ "$date_part" == "*-*-*" ]]; then
    dom="*"
    month="*"
  else
    echo "Error: Unsupported date pattern: $date_part (use systemd)" >&2
    return 1
  fi

  # Convert day-of-week prefix
  if [[ -n "$dow_prefix" ]]; then
    local cron_dow=""
    local IFS=','
    for day in $dow_prefix; do
      local dow_num="${DOW_MAP[$day]:-}"
      if [[ -z "$dow_num" ]]; then
        echo "Error: Invalid day-of-week: $day" >&2
        return 1
      fi
      if [[ -n "$cron_dow" ]]; then
        cron_dow="$cron_dow,$dow_num"
      else
        cron_dow="$dow_num"
      fi
    done
    dow="$cron_dow"
  else
    dow="*"
  fi

  echo "$minute $hour $dom $month $dow"
}

# Validate cron format (basic sanity check)
validate_cron_format() {
  local cron="$1"
  local fields
  IFS=' ' read -ra fields <<< "$cron"

  if [[ ${#fields[@]} -ne 5 ]]; then
    return 1
  fi

  # Basic pattern validation for each field
  local field_pattern='^[0-9*,/-]+$'
  for field in "${fields[@]}"; do
    if [[ ! "$field" =~ $field_pattern ]]; then
      return 1
    fi
  done

  return 0
}

# ---------- Cron File Management ----------

# Ensure cron file exists with proper header
ensure_cron_file() {
  if [[ ! -f "$CRON_FILE" ]]; then
    cat > "$CRON_FILE" << 'EOF'
# Backupd cron schedules
# Managed by backupd - do not edit manually
# Format: MIN HR DOM MON DOW USER COMMAND # backupd-{job}-{type}
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

EOF
    chmod 644 "$CRON_FILE"
  fi
}

# Create a cron entry for a backup
# Usage: create_cron_entry "db" "*-*-* 02:00:00" "default"
create_cron_entry() {
  local backup_type="$1"
  local oncalendar="$2"
  local job_name="${3:-default}"

  local cron_schedule
  cron_schedule="$(oncalendar_to_cron "$oncalendar")" || return 1

  # Determine script path based on job
  local script_path
  if [[ "$job_name" == "default" ]]; then
    script_path="${SCRIPTS_DIR:-/etc/backupd/scripts}/${backup_type}_backup.sh"
  else
    script_path="${JOBS_DIR:-/etc/backupd/jobs}/${job_name}/scripts/${backup_type}_backup.sh"
  fi

  # Verify script exists
  if [[ ! -f "$script_path" ]]; then
    echo "Error: Backup script not found: $script_path" >&2
    return 1
  fi

  # Build cron ID marker for identification
  local cron_id
  if [[ "$job_name" == "default" ]]; then
    cron_id="backupd-${backup_type}"
  else
    cron_id="backupd-${job_name}-${backup_type}"
  fi

  # Remove any existing entry for this backup
  remove_cron_entry "$backup_type" "$job_name" 2>/dev/null || true

  ensure_cron_file

  # Build environment variables
  local env_vars="BACKUPD_CRON=1"
  if [[ "$job_name" != "default" ]]; then
    env_vars="$env_vars JOB_NAME=$job_name"
  fi

  # Add entry (with trailing newline for busybox cron compatibility)
  echo "$cron_schedule root nice -n 10 ionice -c3 $env_vars $script_path # $cron_id" >> "$CRON_FILE"
  echo "" >> "$CRON_FILE"

  return 0
}

# Remove a cron entry for a backup
# Usage: remove_cron_entry "db" "default"
remove_cron_entry() {
  local backup_type="$1"
  local job_name="${2:-default}"

  [[ ! -f "$CRON_FILE" ]] && return 0

  local cron_id
  if [[ "$job_name" == "default" ]]; then
    cron_id="backupd-${backup_type}"
  else
    cron_id="backupd-${job_name}-${backup_type}"
  fi

  # Remove matching lines (preserve other entries)
  local temp_file
  temp_file=$(mktemp)
  grep -v "# ${cron_id}$" "$CRON_FILE" > "$temp_file" 2>/dev/null || true
  mv "$temp_file" "$CRON_FILE"
  chmod 644 "$CRON_FILE"

  # Clean up empty file (only header remains)
  if [[ $(grep -c "^[^#]" "$CRON_FILE" 2>/dev/null || echo 0) -eq 0 ]]; then
    rm -f "$CRON_FILE"
  fi
}

# Get cron schedule for a backup
# Usage: get_cron_schedule "db" "default"
# Returns: cron schedule string or empty
get_cron_schedule() {
  local backup_type="$1"
  local job_name="${2:-default}"

  [[ ! -f "$CRON_FILE" ]] && return 0

  local cron_id
  if [[ "$job_name" == "default" ]]; then
    cron_id="backupd-${backup_type}"
  else
    cron_id="backupd-${job_name}-${backup_type}"
  fi

  grep "# ${cron_id}$" "$CRON_FILE" 2>/dev/null | awk '{print $1,$2,$3,$4,$5}'
}

# Check if cron entry exists for a backup
# Usage: cron_entry_exists "db" "default"
cron_entry_exists() {
  local backup_type="$1"
  local job_name="${2:-default}"

  [[ ! -f "$CRON_FILE" ]] && return 1

  local cron_id
  if [[ "$job_name" == "default" ]]; then
    cron_id="backupd-${backup_type}"
  else
    cron_id="backupd-${job_name}-${backup_type}"
  fi

  grep -q "# ${cron_id}$" "$CRON_FILE" 2>/dev/null
}

# ---------- Unified API ----------

# Disable a scheduled backup (both systemd and cron)
# Usage: scheduler_disable "db" "default"
scheduler_disable() {
  local backup_type="$1"
  local job_name="${2:-default}"

  # Determine timer names
  local timer_name service_name
  if [[ "$job_name" == "default" ]]; then
    timer_name="backupd-${backup_type}.timer"
    service_name="backupd-${backup_type}.service"
  else
    timer_name="backupd-${job_name}-${backup_type}.timer"
    service_name="backupd-${job_name}-${backup_type}.service"
  fi

  # Stop/disable systemd timer (if exists)
  if is_systemd_available; then
    systemctl stop "$timer_name" 2>/dev/null || true
    systemctl disable "$timer_name" 2>/dev/null || true
  fi

  # Remove cron entry (always, for cleanup)
  remove_cron_entry "$backup_type" "$job_name"

  # Also clean legacy user crontab entries
  if is_cron_available; then
    local script_name="${backup_type}_backup.sh"
    ( crontab -l 2>/dev/null | grep -Fv "$script_name" ) | crontab - 2>/dev/null || true
  fi
}

# Print manual crontab entry when no scheduler available
# Usage: print_manual_cron_entry "db" "*-*-* 02:00:00" "default"
print_manual_cron_entry() {
  local backup_type="$1"
  local oncalendar="$2"
  local job_name="${3:-default}"

  local cron_schedule
  cron_schedule="$(oncalendar_to_cron "$oncalendar" 2>/dev/null)" || cron_schedule="0 2 * * *"

  local script_path
  if [[ "$job_name" == "default" ]]; then
    script_path="${SCRIPTS_DIR:-/etc/backupd/scripts}/${backup_type}_backup.sh"
  else
    script_path="${JOBS_DIR:-/etc/backupd/jobs}/${job_name}/scripts/${backup_type}_backup.sh"
  fi

  echo
  print_warning "No scheduler available (neither systemd nor cron found)"
  echo "To manually schedule, add this entry to your crontab:"
  echo
  echo "  $cron_schedule root nice -n 10 ionice -c3 $script_path"
  echo
}

# Check if a schedule pattern is cron-compatible
# Usage: is_cron_compatible "*-*-* 02:00:00"
# Returns: 0 if compatible, 1 if systemd-only
is_cron_compatible() {
  local oncalendar="$1"
  oncalendar_to_cron "$oncalendar" &>/dev/null
}
