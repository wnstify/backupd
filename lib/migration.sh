#!/usr/bin/env bash
# ============================================================================
# Backupd - Migration Module
# Handles migration from legacy single-config to multi-job structure
#
# v3.1.0: Initial implementation
#
# Migration Flow:
#   1. Check if migration needed (has .config but no jobs/)
#   2. Create jobs/default/ directory
#   3. Copy relevant config values to job.conf
#   4. Move scripts to jobs/default/scripts/
#   5. Create .migrated marker
#   6. Existing timers continue working (default job uses same names)
# ============================================================================

# Migration marker file
MIGRATION_MARKER="${INSTALL_DIR:-/etc/backupd}/.migrated"
MIGRATION_VERSION="3.1.0"

# ---------- Migration Checks ----------

# Check if migration from legacy config is needed
# Returns 0 if migration needed, 1 if not needed
needs_migration() {
  local install_dir="${INSTALL_DIR:-/etc/backupd}"

  # Already migrated
  [[ -f "$MIGRATION_MARKER" ]] && return 1

  # No legacy config exists - fresh install, no migration needed
  [[ ! -f "$install_dir/.config" ]] && return 1

  # Legacy config exists but no jobs directory - needs migration
  [[ ! -d "$install_dir/jobs" ]] && return 0

  # Jobs directory exists but no default job - needs migration
  [[ ! -f "$install_dir/jobs/default/job.conf" ]] && return 0

  # Already set up with multi-job
  return 1
}

# Check if system is using multi-job structure
is_multi_job_enabled() {
  local install_dir="${INSTALL_DIR:-/etc/backupd}"
  [[ -f "$MIGRATION_MARKER" || -d "$install_dir/jobs" ]]
}

# ---------- Migration Functions ----------

# Migrate legacy .config to jobs/default/
# Usage: migrate_to_default_job
migrate_to_default_job() {
  local install_dir="${INSTALL_DIR:-/etc/backupd}"
  local config_file="$install_dir/.config"
  local scripts_dir="$install_dir/scripts"
  local jobs_dir="$install_dir/jobs"
  local default_job_dir="$jobs_dir/default"

  # Safety check
  if [[ ! -f "$config_file" ]]; then
    print_warning "No legacy config found, skipping migration"
    return 0
  fi

  print_info "Migrating to multi-job structure..."

  # Create default job directory
  mkdir -p "$default_job_dir/scripts"
  chmod 700 "$default_job_dir"
  chmod 700 "$default_job_dir/scripts"

  # Extract values from legacy config
  local rclone_remote rclone_db_path rclone_files_path
  local retention_days retention_desc
  local web_path_pattern webroot_subdir panel_key
  local do_database do_files

  rclone_remote="$(grep "^RCLONE_REMOTE=" "$config_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"')" || rclone_remote=""
  rclone_db_path="$(grep "^RCLONE_DB_PATH=" "$config_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"')" || rclone_db_path=""
  rclone_files_path="$(grep "^RCLONE_FILES_PATH=" "$config_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"')" || rclone_files_path=""
  retention_days="$(grep "^RETENTION_DAYS=" "$config_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"')" || retention_days="30"
  retention_desc="$(grep "^RETENTION_DESC=" "$config_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"')" || retention_desc="30 days"
  web_path_pattern="$(grep "^WEB_PATH_PATTERN=" "$config_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"')" || web_path_pattern="/var/www/*"
  webroot_subdir="$(grep "^WEBROOT_SUBDIR=" "$config_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"')" || webroot_subdir="."
  panel_key="$(grep "^PANEL_KEY=" "$config_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"')" || panel_key=""
  do_database="$(grep "^DO_DATABASE=" "$config_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"')" || do_database="false"
  do_files="$(grep "^DO_FILES=" "$config_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"')" || do_files="false"

  # Extract schedules from systemd timers if they exist
  local schedule_db="" schedule_files=""
  if [[ -f "/etc/systemd/system/backupd-db.timer" ]]; then
    schedule_db="$(grep "^OnCalendar=" /etc/systemd/system/backupd-db.timer 2>/dev/null | cut -d'=' -f2)" || schedule_db=""
  fi
  if [[ -f "/etc/systemd/system/backupd-files.timer" ]]; then
    schedule_files="$(grep "^OnCalendar=" /etc/systemd/system/backupd-files.timer 2>/dev/null | cut -d'=' -f2)" || schedule_files=""
  fi

  # Create job.conf for default job
  local created_at
  created_at="$(date -Iseconds)"

  cat > "$default_job_dir/job.conf" << EOF
# Job Configuration: default
# Migrated from legacy config: $created_at

# Job Metadata
JOB_NAME="default"
JOB_ENABLED="true"
JOB_CREATED="$created_at"
JOB_MIGRATED="true"

# What to backup
DO_DATABASE="$do_database"
DO_FILES="$do_files"

# Source paths (files backup)
WEB_PATH_PATTERN="$web_path_pattern"
WEBROOT_SUBDIR="$webroot_subdir"
PANEL_KEY="$panel_key"

# Remote destination
RCLONE_REMOTE="$rclone_remote"
RCLONE_DB_PATH="$rclone_db_path"
RCLONE_FILES_PATH="$rclone_files_path"

# Retention
RETENTION_DAYS="$retention_days"
RETENTION_DESC="$retention_desc"

# Schedules (preserved from existing timers)
SCHEDULE_DB="$schedule_db"
SCHEDULE_FILES="$schedule_files"
EOF

  chmod 600 "$default_job_dir/job.conf"

  # Copy existing scripts to job scripts directory
  # (for default job, we can symlink or leave in place since timers use same names)
  if [[ -d "$scripts_dir" ]]; then
    # Create symlinks from job scripts dir to global scripts
    # This preserves backward compatibility - timers still point to global scripts
    local script_name
    for script_name in db_backup.sh files_backup.sh verify_backup.sh verify_full_backup.sh restore.sh; do
      if [[ -f "$scripts_dir/$script_name" ]]; then
        ln -sf "$scripts_dir/$script_name" "$default_job_dir/scripts/$script_name" 2>/dev/null || true
      fi
    done
  fi

  # Create migration marker
  cat > "$MIGRATION_MARKER" << EOF
# Backupd Migration Marker
# DO NOT DELETE - indicates migration has completed
MIGRATION_VERSION="$MIGRATION_VERSION"
MIGRATION_DATE="$created_at"
MIGRATED_FROM="legacy-single-config"
EOF

  chmod 600 "$MIGRATION_MARKER"

  print_success "Migration complete"
  print_info "Legacy config preserved at: $config_file"
  print_info "Default job created at: $default_job_dir"

  return 0
}

# Rollback migration (restore single-config operation)
# Usage: rollback_migration [--force]
rollback_migration() {
  local force="${1:-}"
  local install_dir="${INSTALL_DIR:-/etc/backupd}"
  local jobs_dir="$install_dir/jobs"

  # Check if migrated
  if [[ ! -f "$MIGRATION_MARKER" ]]; then
    print_warning "System was not migrated, nothing to rollback"
    return 0
  fi

  # Count jobs - only allow rollback if only default job exists
  local job_count=0
  local job_dir
  for job_dir in "$jobs_dir"/*/; do
    [[ ! -d "$job_dir" ]] && continue
    [[ -f "$job_dir/job.conf" ]] && ((job_count++)) || true
  done

  if [[ $job_count -gt 1 && "$force" != "--force" ]]; then
    print_error "Multiple jobs exist. Remove extra jobs first or use --force"
    return 1
  fi

  print_info "Rolling back to single-config mode..."

  # Stop all job-specific timers (non-default)
  if [[ -d "$jobs_dir" ]]; then
    for job_dir in "$jobs_dir"/*/; do
      [[ ! -d "$job_dir" ]] && continue
      local job_name
      job_name="$(basename "$job_dir")"
      [[ "$job_name" == "default" ]] && continue

      # Remove job-specific timers
      local timer_type
      for timer_type in db files verify verify-full; do
        local timer_name="backupd-${job_name}-${timer_type}.timer"
        local service_name="backupd-${job_name}-${timer_type}.service"
        systemctl stop "$timer_name" 2>/dev/null || true
        systemctl disable "$timer_name" 2>/dev/null || true
        rm -f "/etc/systemd/system/$timer_name" 2>/dev/null || true
        rm -f "/etc/systemd/system/$service_name" 2>/dev/null || true
      done
    done
    systemctl daemon-reload 2>/dev/null || true
  fi

  # Remove jobs directory
  rm -rf "$jobs_dir"

  # Remove migration marker
  rm -f "$MIGRATION_MARKER"

  print_success "Rollback complete"
  print_info "System restored to single-config mode"
  print_info "Legacy config preserved at: $install_dir/.config"

  return 0
}

# ---------- Migration Status ----------

# Show migration status
# Usage: show_migration_status
show_migration_status() {
  local install_dir="${INSTALL_DIR:-/etc/backupd}"

  echo "Migration Status"
  echo "================"
  echo

  if [[ -f "$MIGRATION_MARKER" ]]; then
    local version date from
    version="$(grep "^MIGRATION_VERSION=" "$MIGRATION_MARKER" 2>/dev/null | cut -d'"' -f2)" || version="unknown"
    date="$(grep "^MIGRATION_DATE=" "$MIGRATION_MARKER" 2>/dev/null | cut -d'"' -f2)" || date="unknown"
    from="$(grep "^MIGRATED_FROM=" "$MIGRATION_MARKER" 2>/dev/null | cut -d'"' -f2)" || from="unknown"

    print_success "Multi-job mode: ENABLED"
    echo "  Version: $version"
    echo "  Date: $date"
    echo "  From: $from"
  else
    print_warning "Multi-job mode: NOT ENABLED"
    if [[ -f "$install_dir/.config" ]]; then
      echo "  Legacy config exists"
      if needs_migration; then
        print_info "Migration available: run 'backupd' to migrate"
      fi
    else
      echo "  No configuration found"
    fi
  fi

  echo

  # Count jobs
  local job_count=0
  if [[ -d "$install_dir/jobs" ]]; then
    local job_dir
    for job_dir in "$install_dir/jobs"/*/; do
      [[ ! -d "$job_dir" ]] && continue
      [[ -f "$job_dir/job.conf" ]] && ((job_count++)) || true
    done
  fi

  echo "Jobs configured: $job_count"
  if [[ $job_count -gt 0 ]]; then
    echo
    echo "Job list:"
    for job_dir in "$install_dir/jobs"/*/; do
      [[ ! -d "$job_dir" ]] && continue
      [[ -f "$job_dir/job.conf" ]] || continue
      local job_name
      job_name="$(basename "$job_dir")"
      local enabled
      enabled="$(grep "^JOB_ENABLED=" "$job_dir/job.conf" 2>/dev/null | cut -d'"' -f2)" || enabled="unknown"
      echo "  - $job_name (enabled: $enabled)"
    done
  fi
}

# ---------- Auto-Migration Hook ----------

# Run migration if needed (called at startup)
# Usage: auto_migrate_if_needed
auto_migrate_if_needed() {
  if needs_migration; then
    echo
    print_info "Upgrading to multi-job configuration..."
    migrate_to_default_job
    echo
  fi
}
