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
