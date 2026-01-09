#!/usr/bin/env bash
# ============================================================================
# Backupd - Jobs Module
# Multi-job management: create, delete, clone, configure backup jobs
#
# v3.1.0: Initial implementation of multi-job support
#
# Job Structure:
#   /etc/backupd/jobs/{jobname}/
#     job.conf     - Job-specific configuration
#     scripts/     - Generated backup/restore scripts
# ============================================================================

# Job directory constants
JOBS_DIR="${INSTALL_DIR:-/etc/backupd}/jobs"
DEFAULT_JOB_NAME="default"

# Job configuration file name
JOB_CONFIG_FILE="job.conf"

# ---------- Job Name Validation ----------

# Validate job name format
# Rules: alphanumeric, dash, underscore; 2-32 chars; no leading dash
# Usage: validate_job_name "production" || exit 1
validate_job_name() {
  local name="$1"
  local quiet="${2:-false}"

  # Check empty
  if [[ -z "$name" ]]; then
    [[ "$quiet" != "true" ]] && print_error "Job name cannot be empty"
    return 1
  fi

  # Check length (2-32 characters)
  if [[ ${#name} -lt 2 || ${#name} -gt 32 ]]; then
    [[ "$quiet" != "true" ]] && print_error "Job name must be 2-32 characters (got ${#name})"
    return 1
  fi

  # Check format: alphanumeric, dash, underscore only
  if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
    [[ "$quiet" != "true" ]] && print_error "Job name must start with alphanumeric and contain only letters, numbers, dash, underscore"
    return 1
  fi

  # Disallow reserved names
  local reserved_names=("all" "list" "help" "none" "null" "undefined")
  local reserved
  for reserved in "${reserved_names[@]}"; do
    if [[ "${name,,}" == "$reserved" ]]; then
      [[ "$quiet" != "true" ]] && print_error "Job name '$name' is reserved"
      return 1
    fi
  done

  return 0
}

# ---------- Job Existence Checks ----------

# Check if job exists
# Usage: job_exists "production" && echo "exists"
job_exists() {
  local job_name="$1"
  [[ -d "$JOBS_DIR/$job_name" && -f "$JOBS_DIR/$job_name/$JOB_CONFIG_FILE" ]]
}

# Get job directory path
# Usage: job_dir=$(get_job_dir "production")
get_job_dir() {
  local job_name="$1"
  echo "$JOBS_DIR/$job_name"
}

# Get job scripts directory path
# Usage: scripts_dir=$(get_job_scripts_dir "production")
get_job_scripts_dir() {
  local job_name="$1"
  echo "$JOBS_DIR/$job_name/scripts"
}

# Get job config file path
# Usage: config_file=$(get_job_config_file "production")
get_job_config_file() {
  local job_name="$1"
  echo "$JOBS_DIR/$job_name/$JOB_CONFIG_FILE"
}

# ---------- Job Listing ----------

# List all job names (one per line)
# Usage: list_jobs
list_jobs() {
  [[ ! -d "$JOBS_DIR" ]] && return 0

  local job_dir
  for job_dir in "$JOBS_DIR"/*/; do
    [[ ! -d "$job_dir" ]] && continue
    local job_name
    job_name="$(basename "$job_dir")"
    # Only list if job.conf exists
    [[ -f "$job_dir/$JOB_CONFIG_FILE" ]] && echo "$job_name"
  done
}

# List all jobs with detailed status
# Usage: list_jobs_detailed [--json]
list_jobs_detailed() {
  local json_output="${1:-}"
  local jobs=()

  [[ ! -d "$JOBS_DIR" ]] && {
    [[ "$json_output" == "--json" ]] && echo "[]" || echo "No jobs configured"
    return 0
  }

  local job_dir
  for job_dir in "$JOBS_DIR"/*/; do
    [[ ! -d "$job_dir" ]] && continue
    local job_name
    job_name="$(basename "$job_dir")"
    [[ -f "$job_dir/$JOB_CONFIG_FILE" ]] && jobs+=("$job_name")
  done

  if [[ ${#jobs[@]} -eq 0 ]]; then
    [[ "$json_output" == "--json" ]] && echo "[]" || echo "No jobs configured"
    return 0
  fi

  if [[ "$json_output" == "--json" ]]; then
    echo "["
    local first=1
    for job_name in "${jobs[@]}"; do
      [[ $first -eq 0 ]] && echo ","
      _job_status_json "$job_name"
      first=0
    done
    echo "]"
  else
    printf "%-15s %-8s %-10s %-10s %s\n" "NAME" "ENABLED" "DATABASE" "FILES" "REMOTE"
    printf "%-15s %-8s %-10s %-10s %s\n" "---------------" "--------" "----------" "----------" "--------------------"
    for job_name in "${jobs[@]}"; do
      _job_status_text "$job_name"
    done
  fi
}

# Internal: Get job status as JSON line
_job_status_json() {
  local job_name="$1"
  local config_file="$JOBS_DIR/$job_name/$JOB_CONFIG_FILE"

  local enabled do_db do_files rclone_remote created_at
  enabled="$(get_job_config "$job_name" "JOB_ENABLED")"
  enabled="${enabled:-true}"
  do_db="$(get_job_config "$job_name" "DO_DATABASE")"
  do_db="${do_db:-false}"
  do_files="$(get_job_config "$job_name" "DO_FILES")"
  do_files="${do_files:-false}"
  rclone_remote="$(get_job_config "$job_name" "RCLONE_REMOTE")"
  rclone_remote="${rclone_remote:-}"
  created_at="$(get_job_config "$job_name" "JOB_CREATED")"
  created_at="${created_at:-}"

  # Escape for JSON
  rclone_remote="${rclone_remote//\"/\\\"}"

  echo -n "  {\"name\": \"$job_name\", \"enabled\": $enabled, \"database\": $do_db, \"files\": $do_files, \"remote\": \"$rclone_remote\", \"created\": \"$created_at\"}"
}

# Internal: Print job status as text line
_job_status_text() {
  local job_name="$1"

  local enabled do_db do_files rclone_remote
  enabled="$(get_job_config "$job_name" "JOB_ENABLED")"
  enabled="${enabled:-true}"
  do_db="$(get_job_config "$job_name" "DO_DATABASE")"
  do_files="$(get_job_config "$job_name" "DO_FILES")"
  rclone_remote="$(get_job_config "$job_name" "RCLONE_REMOTE")"

  local enabled_display db_display files_display
  [[ "$enabled" == "true" ]] && enabled_display="yes" || enabled_display="no"
  [[ "$do_db" == "true" ]] && db_display="yes" || db_display="no"
  [[ "$do_files" == "true" ]] && files_display="yes" || files_display="no"

  printf "%-15s %-8s %-10s %-10s %s\n" "$job_name" "$enabled_display" "$db_display" "$files_display" "${rclone_remote:-<none>}"
}

# ---------- Job Configuration ----------

# Get job config value
# Usage: value=$(get_job_config "production" "RCLONE_REMOTE")
get_job_config() {
  local job_name="$1"
  local key="$2"
  local config_file="$JOBS_DIR/$job_name/$JOB_CONFIG_FILE"

  if [[ -f "$config_file" ]]; then
    grep "^${key}=" "$config_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true
  fi
}

# Save job config value
# Usage: save_job_config "production" "RCLONE_REMOTE" "myremote"
save_job_config() {
  local job_name="$1"
  local key="$2"
  local value="$3"
  local config_file="$JOBS_DIR/$job_name/$JOB_CONFIG_FILE"

  # Validate key (alphanumeric and underscore only)
  if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    print_error "Invalid config key: $key"
    return 1
  fi

  # Escape double quotes and backslashes in value
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/}"

  # Create job directory if needed
  mkdir -p "$JOBS_DIR/$job_name"

  # Create or update config file
  if [[ -f "$config_file" ]]; then
    # Remove existing key if present
    grep -v "^${key}=" "$config_file" > "${config_file}.tmp" 2>/dev/null || true
    mv "${config_file}.tmp" "$config_file"
  fi

  echo "${key}=\"${value}\"" >> "$config_file"
  chmod 600 "$config_file"
}

# Validate job configuration has required fields
# Usage: validate_job_config "production" || exit 1
validate_job_config() {
  local job_name="$1"
  local errors=0

  # Required fields
  local required=("RCLONE_REMOTE")
  local field

  for field in "${required[@]}"; do
    local value
    value="$(get_job_config "$job_name" "$field")"
    if [[ -z "$value" ]]; then
      print_error "Job '$job_name' missing required config: $field"
      ((errors++)) || true
    fi
  done

  # At least one backup type must be enabled
  local do_db do_files
  do_db="$(get_job_config "$job_name" "DO_DATABASE")"
  do_files="$(get_job_config "$job_name" "DO_FILES")"

  if [[ "$do_db" != "true" && "$do_files" != "true" ]]; then
    print_error "Job '$job_name' must have DO_DATABASE=true or DO_FILES=true"
    ((errors++)) || true
  fi

  # Validate paths if specified
  if [[ "$do_db" == "true" ]]; then
    local db_path
    db_path="$(get_job_config "$job_name" "RCLONE_DB_PATH")"
    if [[ -z "$db_path" ]]; then
      print_error "Job '$job_name' has DO_DATABASE=true but no RCLONE_DB_PATH"
      ((errors++)) || true
    fi
  fi

  if [[ "$do_files" == "true" ]]; then
    local files_path
    files_path="$(get_job_config "$job_name" "RCLONE_FILES_PATH")"
    if [[ -z "$files_path" ]]; then
      print_error "Job '$job_name' has DO_FILES=true but no RCLONE_FILES_PATH"
      ((errors++)) || true
    fi
  fi

  [[ $errors -eq 0 ]]
}

# ---------- Job CRUD Operations ----------

# Create a new job
# Usage: create_job "production" [--from-config]
create_job() {
  local job_name="$1"
  local from_config="${2:-}"

  # Validate name
  validate_job_name "$job_name" || return 1

  # Check if already exists
  if job_exists "$job_name"; then
    print_error "Job '$job_name' already exists"
    return 1
  fi

  # Create job directory structure
  local job_dir="$JOBS_DIR/$job_name"
  mkdir -p "$job_dir/scripts"
  chmod 700 "$job_dir"
  chmod 700 "$job_dir/scripts"

  # Create initial job.conf
  local created_at
  created_at="$(date -Iseconds)"

  cat > "$job_dir/$JOB_CONFIG_FILE" << EOF
# Job Configuration: $job_name
# Created: $created_at

# Job Metadata
JOB_NAME="$job_name"
JOB_ENABLED="true"
JOB_CREATED="$created_at"

# What to backup (set during job configuration)
DO_DATABASE="false"
DO_FILES="false"

# Source paths (files backup)
WEB_PATH_PATTERN="/var/www/*"
WEBROOT_SUBDIR="."

# Remote destination (must be configured)
RCLONE_REMOTE=""
RCLONE_DB_PATH=""
RCLONE_FILES_PATH=""

# Retention
RETENTION_DAYS="30"
RETENTION_DESC="30 days"

# Schedules (Phase 2)
SCHEDULE_DB=""
SCHEDULE_FILES=""
EOF

  chmod 600 "$job_dir/$JOB_CONFIG_FILE"

  print_success "Created job '$job_name'"
  print_info "Configure with: backupd job configure $job_name"

  return 0
}

# Delete a job
# Usage: delete_job "production" [--force]
delete_job() {
  local job_name="$1"
  local force="${2:-}"

  # Validate name
  validate_job_name "$job_name" || return 1

  # Cannot delete default job
  if [[ "$job_name" == "$DEFAULT_JOB_NAME" && "$force" != "--force" ]]; then
    print_error "Cannot delete the default job (use --force to override)"
    return 1
  fi

  # Check if exists
  if ! job_exists "$job_name"; then
    print_error "Job '$job_name' does not exist"
    return 1
  fi

  # Disable timers first
  disable_job_timers "$job_name"

  # Remove job directory
  local job_dir="$JOBS_DIR/$job_name"
  rm -rf "$job_dir"

  print_success "Deleted job '$job_name'"
  return 0
}

# Clone a job
# Usage: clone_job "production" "staging"
clone_job() {
  local src_job="$1"
  local dst_job="$2"

  # Validate names
  validate_job_name "$src_job" || return 1
  validate_job_name "$dst_job" || return 1

  # Check source exists
  if ! job_exists "$src_job"; then
    print_error "Source job '$src_job' does not exist"
    return 1
  fi

  # Check destination does not exist
  if job_exists "$dst_job"; then
    print_error "Destination job '$dst_job' already exists"
    return 1
  fi

  # Create destination directory
  local src_dir="$JOBS_DIR/$src_job"
  local dst_dir="$JOBS_DIR/$dst_job"

  mkdir -p "$dst_dir/scripts"
  chmod 700 "$dst_dir"
  chmod 700 "$dst_dir/scripts"

  # Copy and update config
  cp "$src_dir/$JOB_CONFIG_FILE" "$dst_dir/$JOB_CONFIG_FILE"
  chmod 600 "$dst_dir/$JOB_CONFIG_FILE"

  # Update job name and created timestamp in config
  local created_at
  created_at="$(date -Iseconds)"

  sed -i \
    -e "s/^JOB_NAME=.*/JOB_NAME=\"$dst_job\"/" \
    -e "s/^JOB_CREATED=.*/JOB_CREATED=\"$created_at\"/" \
    "$dst_dir/$JOB_CONFIG_FILE"

  # Clear schedules (clone starts with no schedules)
  sed -i \
    -e "s/^SCHEDULE_DB=.*/SCHEDULE_DB=\"\"/" \
    -e "s/^SCHEDULE_FILES=.*/SCHEDULE_FILES=\"\"/" \
    "$dst_dir/$JOB_CONFIG_FILE"

  print_success "Cloned job '$src_job' to '$dst_job'"
  print_info "Configure remote paths for the new job"

  return 0
}

# ---------- Timer Management ----------

# Get systemd timer name for a job
# Usage: timer_name=$(get_timer_name "production" "db")
get_timer_name() {
  local job_name="$1"
  local backup_type="$2"

  # Default job uses original names for backward compatibility
  if [[ "$job_name" == "$DEFAULT_JOB_NAME" ]]; then
    echo "backupd-${backup_type}"
  else
    echo "backupd-${job_name}-${backup_type}"
  fi
}

# Validate OnCalendar schedule format
# Usage: validate_schedule_format "*-*-* 02:00:00"
# Returns: 0 if valid, 1 if invalid
validate_schedule_format() {
  local schedule="$1"
  local error_output

  if [[ -z "$schedule" ]]; then
    echo "Error: Schedule expression is required" >&2
    return 1
  fi

  # Use systemd-analyze to validate the OnCalendar expression
  if ! error_output=$(systemd-analyze calendar "$schedule" --iterations=1 2>&1); then
    echo "Error: Invalid schedule format: $error_output" >&2
    return 1
  fi

  return 0
}

# Check for schedule conflicts across jobs
# Usage: check_schedule_conflicts "production" "db" "*-*-* 02:00:00"
# Returns: 0 always (advisory only, does not block)
# Outputs warnings to stderr if conflicts found
# BACKUPD-033: Now includes auto-suggest alternative times
check_schedule_conflicts() {
  local job_name="$1"
  local backup_type="$2"
  local schedule="$3"

  # Get the config key for this backup type
  local config_key
  case "$backup_type" in
    db) config_key="SCHEDULE_DB" ;;
    files) config_key="SCHEDULE_FILES" ;;
    verify) config_key="SCHEDULE_VERIFY" ;;
    verify-full) config_key="SCHEDULE_VERIFY_FULL" ;;
    *) return 0 ;;  # Unknown type, skip check
  esac

  # Track if any conflicts found
  local has_conflict=false
  local conflict_time=""

  # Loop through all jobs looking for conflicts
  local other_job other_schedule
  while IFS= read -r other_job; do
    # Skip the current job being configured
    [[ "$other_job" == "$job_name" ]] && continue

    # Get the schedule for the same backup type in the other job
    other_schedule=$(get_job_config "$other_job" "$config_key")

    # Check for exact string match (same type, same schedule)
    if [[ -n "$other_schedule" && "$other_schedule" == "$schedule" ]]; then
      echo "Warning: Job '$other_job' also has $backup_type backup at $schedule" >&2
      has_conflict=true
      conflict_time=$(parse_simple_oncalendar "$schedule")
    fi
  done < <(list_jobs)

  # BACKUPD-033: If conflicts found, suggest alternative times
  if [[ "$has_conflict" == true && -n "$conflict_time" && "$conflict_time" != "hourly" ]]; then
    local suggestions
    suggestions=$(suggest_alternative_times "$conflict_time" "$backup_type" "$job_name")
    if [[ -n "$suggestions" ]]; then
      echo "Suggested alternatives:" >&2
      while IFS= read -r suggestion; do
        echo "  - $suggestion" >&2
      done <<< "$suggestions"
    fi
  fi

  return 0
}

# BACKUPD-033: Parse simple OnCalendar expressions to extract hour and minute
# Usage: parse_simple_oncalendar "*-*-* 02:30:00"
# Returns: "02:30" for simple patterns, empty for complex patterns
# Only handles: *-*-* HH:MM:SS or *-*-* HH:MM patterns
parse_simple_oncalendar() {
  local schedule="$1"

  # Handle special keywords
  case "$schedule" in
    hourly) echo "hourly"; return 0 ;;
    daily) echo "00:00"; return 0 ;;
  esac

  # Match simple daily pattern: *-*-* HH:MM:SS or *-*-* HH:MM
  if [[ "$schedule" =~ ^\*-\*-\*[[:space:]]+([0-9]{1,2}):([0-9]{2})(:[0-9]{2})?$ ]]; then
    printf "%02d:%02d" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  # Complex pattern (day-specific, intervals, etc.) - return empty
  return 1
}

# BACKUPD-033: Find all time slots used by a backup type across all jobs
# Usage: find_used_time_slots "db" "exclude_job_name"
# Returns: Newline-separated list of used times (HH:MM format)
find_used_time_slots() {
  local backup_type="$1"
  local exclude_job="$2"

  local config_key
  case "$backup_type" in
    db) config_key="SCHEDULE_DB" ;;
    files) config_key="SCHEDULE_FILES" ;;
    verify) config_key="SCHEDULE_VERIFY" ;;
    verify-full) config_key="SCHEDULE_VERIFY_FULL" ;;
    *) return 0 ;;
  esac

  local job_name schedule time_slot
  while IFS= read -r job_name; do
    [[ "$job_name" == "$exclude_job" ]] && continue
    schedule=$(get_job_config "$job_name" "$config_key")
    [[ -z "$schedule" ]] && continue

    time_slot=$(parse_simple_oncalendar "$schedule")
    [[ -n "$time_slot" && "$time_slot" != "hourly" ]] && echo "$time_slot"
  done < <(list_jobs)
}

# BACKUPD-033: Suggest alternative schedule times when conflicts detected
# Usage: suggest_alternative_times "02:00" "db"
# Returns: JSON array of suggested OnCalendar expressions
# Suggests: ±30min, ±1hr, ±2hr from conflict time
suggest_alternative_times() {
  local conflict_time="$1"
  local backup_type="$2"
  local exclude_job="$3"

  # Skip if hourly or complex pattern
  [[ "$conflict_time" == "hourly" || -z "$conflict_time" ]] && return 0

  # Parse hour and minute
  local hour minute
  hour=$(echo "$conflict_time" | cut -d: -f1 | sed 's/^0//')
  minute=$(echo "$conflict_time" | cut -d: -f2 | sed 's/^0//')

  # Get all used time slots
  local used_slots
  used_slots=$(find_used_time_slots "$backup_type" "$exclude_job" | sort -u)

  # Generate candidate times: -2h, -1h, -30m, +30m, +1h, +2h
  local candidates=()
  local h m candidate

  # -2 hours
  h=$(( (hour + 22) % 24 ))
  candidate=$(printf "%02d:%02d" "$h" "$minute")
  candidates+=("$candidate")

  # -1 hour
  h=$(( (hour + 23) % 24 ))
  candidate=$(printf "%02d:%02d" "$h" "$minute")
  candidates+=("$candidate")

  # -30 minutes
  if [[ $minute -ge 30 ]]; then
    m=$((minute - 30))
    h=$hour
  else
    m=$((minute + 30))
    h=$(( (hour + 23) % 24 ))
  fi
  candidate=$(printf "%02d:%02d" "$h" "$m")
  candidates+=("$candidate")

  # +30 minutes
  if [[ $minute -lt 30 ]]; then
    m=$((minute + 30))
    h=$hour
  else
    m=$((minute - 30))
    h=$(( (hour + 1) % 24 ))
  fi
  candidate=$(printf "%02d:%02d" "$h" "$m")
  candidates+=("$candidate")

  # +1 hour
  h=$(( (hour + 1) % 24 ))
  candidate=$(printf "%02d:%02d" "$h" "$minute")
  candidates+=("$candidate")

  # +2 hours
  h=$(( (hour + 2) % 24 ))
  candidate=$(printf "%02d:%02d" "$h" "$minute")
  candidates+=("$candidate")

  # Filter out used times and output suggestions
  local suggestions=()
  for candidate in "${candidates[@]}"; do
    # Check if this time is already used
    if ! echo "$used_slots" | grep -q "^${candidate}$"; then
      suggestions+=("*-*-* ${candidate}:00")
    fi
  done

  # Return up to 4 unique suggestions
  local count=0
  for suggestion in "${suggestions[@]}"; do
    [[ $count -ge 4 ]] && break
    echo "$suggestion"
    ((count++))
  done
}

# List all schedules across all jobs
# Usage: list_all_job_schedules
# Output format: job_name|backup_type|schedule|timer_status (one per line)
# timer_status: active, inactive, or unknown
list_all_job_schedules() {
  local job_name backup_type schedule timer_name timer_status
  local types=("db" "files" "verify" "verify-full")
  local config_keys=("SCHEDULE_DB" "SCHEDULE_FILES" "SCHEDULE_VERIFY" "SCHEDULE_VERIFY_FULL")

  while IFS= read -r job_name; do
    for i in "${!types[@]}"; do
      backup_type="${types[$i]}"
      schedule=$(get_job_config "$job_name" "${config_keys[$i]}")

      # Only output if schedule is configured
      if [[ -n "$schedule" ]]; then
        timer_name="$(get_timer_name "$job_name" "$backup_type").timer"

        # Get timer status
        if systemctl is-active --quiet "$timer_name" 2>/dev/null; then
          timer_status="active"
        elif systemctl list-unit-files "$timer_name" 2>/dev/null | grep -q "$timer_name"; then
          timer_status="inactive"
        else
          timer_status="unknown"
        fi

        echo "${job_name}|${backup_type}|${schedule}|${timer_status}"
      fi
    done
  done < <(list_jobs)
}

# BACKUPD-034: Create schedule for all jobs (bulk operation)
# Usage: create_all_job_schedules "db" "*-*-* 02:00:00"
# Returns: 0 if all succeed, 1 if any fail, 2 if no jobs configured
# Follows pattern from regenerate_all_job_scripts()
create_all_job_schedules() {
  local backup_type="$1"
  local schedule="$2"

  # Validate backup_type
  case "$backup_type" in
    db|files|verify|verify-full) ;;
    *)
      print_error "Invalid backup type: $backup_type"
      return 1
      ;;
  esac

  # Validate schedule format once before loop
  if ! validate_schedule_format "$schedule"; then
    return 1
  fi

  local job_name
  local success_count=0
  local fail_count=0
  local skip_count=0
  local results=()

  while IFS= read -r job_name; do
    [[ -z "$job_name" ]] && continue

    # Check if backup script exists for this job/type
    local scripts_dir script_path
    scripts_dir="$(get_job_scripts_dir "$job_name")"
    script_path="$scripts_dir/${backup_type}_backup.sh"

    if [[ ! -f "$script_path" ]]; then
      # Job doesn't have this backup type configured - skip it
      ((skip_count++)) || true
      results+=("$job_name:skipped")
      continue
    fi

    if create_job_timer "$job_name" "$backup_type" "$schedule" >/dev/null 2>&1; then
      ((success_count++)) || true
      results+=("$job_name:success")
    else
      ((fail_count++)) || true
      results+=("$job_name:failed")
    fi
  done < <(list_jobs)

  # Return results as pipe-delimited string for caller to parse
  printf '%s\n' "${results[@]}"

  if [[ $fail_count -gt 0 ]]; then
    return 1
  elif [[ $success_count -eq 0 ]]; then
    return 2  # No jobs configured for this backup type
  fi

  return 0
}

# BACKUPD-034: Disable schedule for all jobs (bulk operation)
# Usage: disable_all_job_schedules "db"
# Returns: 0 if all succeed, 1 if any fail
disable_all_job_schedules() {
  local backup_type="$1"

  # Validate backup_type
  case "$backup_type" in
    db|files|verify|verify-full) ;;
    *)
      print_error "Invalid backup type: $backup_type"
      return 1
      ;;
  esac

  local job_name timer_name
  local success_count=0
  local fail_count=0
  local results=()

  while IFS= read -r job_name; do
    [[ -z "$job_name" ]] && continue

    timer_name="$(get_timer_name "$job_name" "$backup_type").timer"

    # Stop and disable the timer
    if systemctl stop "$timer_name" 2>/dev/null && \
       systemctl disable "$timer_name" 2>/dev/null; then
      ((success_count++)) || true
      results+=("$job_name:disabled")
    else
      # Timer might not exist, check if that's the case
      if ! systemctl list-unit-files "$timer_name" 2>/dev/null | grep -q "$timer_name"; then
        results+=("$job_name:not_configured")
      else
        ((fail_count++)) || true
        results+=("$job_name:failed")
      fi
    fi
  done < <(list_jobs)

  # Return results
  printf '%s\n' "${results[@]}"

  if [[ $fail_count -gt 0 ]]; then
    return 1
  elif [[ $success_count -eq 0 ]]; then
    return 2  # No jobs found or no timers to disable
  fi

  return 0
}

# Create systemd timer for a job
# Usage: create_job_timer "production" "db" "*-*-* 02:00:00"
create_job_timer() {
  local job_name="$1"
  local backup_type="$2"
  local schedule="$3"

  validate_job_name "$job_name" || return 1

  # Validate schedule format before proceeding
  if ! validate_schedule_format "$schedule"; then
    return 1
  fi

  if ! job_exists "$job_name"; then
    print_error "Job '$job_name' does not exist"
    return 1
  fi

  local timer_base
  timer_base="$(get_timer_name "$job_name" "$backup_type")"
  local timer_name="${timer_base}.timer"
  local service_name="${timer_base}.service"

  local scripts_dir
  scripts_dir="$(get_job_scripts_dir "$job_name")"
  local script_path="$scripts_dir/${backup_type}_backup.sh"

  # Verify script exists
  if [[ ! -f "$script_path" ]]; then
    print_error "Backup script not found: $script_path"
    print_info "Generate scripts first: backupd job regenerate $job_name"
    return 1
  fi

  # Create service unit
  cat > "/etc/systemd/system/$service_name" << EOF
[Unit]
Description=Backupd - $job_name ${backup_type^} Backup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment="JOB_NAME=$job_name"
ExecStart=$script_path
StandardOutput=journal
StandardError=journal
Nice=10
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
EOF

  # Create timer unit
  cat > "/etc/systemd/system/$timer_name" << EOF
[Unit]
Description=Backupd - $job_name ${backup_type^} Backup Timer
Requires=$service_name

[Timer]
OnCalendar=$schedule
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
EOF

  # Reload and enable
  systemctl daemon-reload
  systemctl enable "$timer_name" 2>/dev/null || true
  systemctl start "$timer_name" 2>/dev/null || true

  # Save schedule to job config
  local schedule_key="SCHEDULE_${backup_type^^}"
  save_job_config "$job_name" "$schedule_key" "$schedule"

  print_success "Timer created: $timer_name"
  print_info "Schedule: $schedule"

  return 0
}

# Disable all timers for a job
# Usage: disable_job_timers "production"
disable_job_timers() {
  local job_name="$1"

  validate_job_name "$job_name" "true" || return 0

  local backup_types=("db" "files" "verify" "verify-full")
  local backup_type

  for backup_type in "${backup_types[@]}"; do
    local timer_base
    timer_base="$(get_timer_name "$job_name" "$backup_type")"
    local timer_name="${timer_base}.timer"
    local service_name="${timer_base}.service"

    # Stop and disable timer
    systemctl stop "$timer_name" 2>/dev/null || true
    systemctl disable "$timer_name" 2>/dev/null || true

    # Remove unit files (except for default job - those are managed globally)
    if [[ "$job_name" != "$DEFAULT_JOB_NAME" ]]; then
      rm -f "/etc/systemd/system/$timer_name" 2>/dev/null || true
      rm -f "/etc/systemd/system/$service_name" 2>/dev/null || true
    fi
  done

  systemctl daemon-reload 2>/dev/null || true

  return 0
}

# List all timers for a job
# Usage: list_job_timers "production"
list_job_timers() {
  local job_name="$1"

  validate_job_name "$job_name" || return 1

  local pattern
  if [[ "$job_name" == "$DEFAULT_JOB_NAME" ]]; then
    # Default job uses legacy timer names (backupd-db, backupd-files, etc.)
    pattern="backupd-(db|files|verify|verify-full)\."
  else
    pattern="backupd-${job_name}-(db|files|verify)\."
  fi

  systemctl list-timers --all 2>/dev/null | grep -E "$pattern" || echo "No timers scheduled for job '$job_name'"
}

# ---------- Job Enable/Disable ----------

# Enable a job
# Usage: enable_job "production"
enable_job() {
  local job_name="$1"

  validate_job_name "$job_name" || return 1

  if ! job_exists "$job_name"; then
    print_error "Job '$job_name' does not exist"
    return 1
  fi

  save_job_config "$job_name" "JOB_ENABLED" "true"
  print_success "Enabled job '$job_name'"

  # Recreate timers from stored schedule config
  local types=("db" "files" "verify" "verify-full")
  local config_keys=("SCHEDULE_DB" "SCHEDULE_FILES" "SCHEDULE_VERIFY" "SCHEDULE_VERIFY_FULL")
  local i schedule

  for i in "${!types[@]}"; do
    schedule="$(get_job_config "$job_name" "${config_keys[$i]}")"
    if [[ -n "$schedule" ]]; then
      # Suppress output during re-enable, just recreate the timer
      if create_job_timer "$job_name" "${types[$i]}" "$schedule" >/dev/null 2>&1; then
        print_info "Recreated timer for ${types[$i]} backup"
      fi
    fi
  done

  return 0
}

# Disable a job (stops timers, marks disabled)
# Usage: disable_job "production"
disable_job() {
  local job_name="$1"

  validate_job_name "$job_name" || return 1

  if ! job_exists "$job_name"; then
    print_error "Job '$job_name' does not exist"
    return 1
  fi

  # Stop timers
  disable_job_timers "$job_name"

  # Mark as disabled
  save_job_config "$job_name" "JOB_ENABLED" "false"
  print_success "Disabled job '$job_name'"

  return 0
}

# Check if a job is enabled
# Usage: is_job_enabled "production" && echo "enabled"
is_job_enabled() {
  local job_name="$1"

  if ! job_exists "$job_name"; then
    return 1
  fi

  local enabled
  enabled="$(get_job_config "$job_name" "JOB_ENABLED")"
  [[ "$enabled" == "true" ]]
}

# ---------- Job Count and Defaults ----------

# Count number of configured jobs
# Usage: count=$(count_jobs)
count_jobs() {
  local count=0
  local job_dir

  [[ ! -d "$JOBS_DIR" ]] && echo "0" && return 0

  for job_dir in "$JOBS_DIR"/*/; do
    [[ ! -d "$job_dir" ]] && continue
    [[ -f "$job_dir/$JOB_CONFIG_FILE" ]] && ((count++)) || true
  done

  echo "$count"
}

# Get the default job name (or first available)
# Usage: job=$(get_default_job)
get_default_job() {
  # If default job exists, use it
  if job_exists "$DEFAULT_JOB_NAME"; then
    echo "$DEFAULT_JOB_NAME"
    return 0
  fi

  # Otherwise return first job
  list_jobs | head -1
}

# Check if we're in multi-job mode (more than one job configured)
# Usage: is_multi_job && echo "multiple jobs"
is_multi_job() {
  local count
  count="$(count_jobs)"
  [[ $count -gt 1 ]]
}
