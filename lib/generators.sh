#!/usr/bin/env bash
# ============================================================================
# Backupd v3.0 - Generators Module (Restic-Based)
# Script generation functions for restic backup/restore/verify scripts
#
# v3.0 Changes:
#   - Removed generate_embedded_crypto() - scripts now source lib/crypto.sh
#   - Replaced tar+gpg backup with restic backup
#   - Changed retention from MINUTES to DAYS (restic uses --keep-within Xd)
#   - Removed legacy restore generators (restic restore handled in restore.sh)
# ============================================================================

# ---------- Generate All Scripts ----------

generate_all_scripts() {
  local SECRETS_DIR="$1"
  local DO_DATABASE="$2"
  local DO_FILES="$3"
  local RCLONE_REMOTE="$4"
  local RCLONE_DB_PATH="$5"
  local RCLONE_FILES_PATH="$6"
  local RETENTION_DAYS="${7:-30}"  # Changed from MINUTES to DAYS
  local WEB_PATH_PATTERN="${8:-/var/www/*}"
  local WEBROOT_SUBDIR="${9:-.}"

  local LOGS_DIR="$INSTALL_DIR/logs"
  mkdir -p "$LOGS_DIR"

  # Generate database backup script (restic-based)
  if [[ "$DO_DATABASE" == "true" ]]; then
    generate_restic_db_backup_script "$SECRETS_DIR" "$RCLONE_REMOTE" "$RCLONE_DB_PATH" "$LOGS_DIR" "$RETENTION_DAYS"
    print_success "Database backup script generated (restic)"
  fi

  # Generate files backup script (restic-based)
  if [[ "$DO_FILES" == "true" ]]; then
    generate_restic_files_backup_script "$SECRETS_DIR" "$RCLONE_REMOTE" "$RCLONE_FILES_PATH" "$LOGS_DIR" "$RETENTION_DAYS" "$WEB_PATH_PATTERN" "$WEBROOT_SUBDIR"
    print_success "Files backup script generated (restic)"
  fi

  # Generate unified restore script (restic-based)
  generate_restic_restore_script "$SECRETS_DIR" "$RCLONE_REMOTE" "$RCLONE_DB_PATH" "$RCLONE_FILES_PATH"
  print_success "Restore script generated (restic)"

  # Generate verification scripts (restic-based)
  generate_restic_verify_script "$SECRETS_DIR" "$RCLONE_REMOTE" "$RCLONE_DB_PATH" "$RCLONE_FILES_PATH"
  print_success "Verify scripts generated (restic)"
}

# ---------- Generate Restic Database Backup Script ----------

generate_restic_db_backup_script() {
  local SECRETS_DIR="$1"
  local RCLONE_REMOTE="$2"
  local RCLONE_PATH="$3"
  local LOGS_DIR="$4"
  local RETENTION_DAYS="${5:-30}"

  cat > "$SCRIPTS_DIR/db_backup.sh" << 'DBBACKUPEOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077

# ============================================================================
# Backupd v3.0 - Restic Database Backup Script
# Uses restic for encrypted, deduplicated backups via rclone backend
# ============================================================================

INSTALL_DIR="/etc/backupd"
source "$INSTALL_DIR/lib/logging.sh"
source "$INSTALL_DIR/lib/debug.sh"
source "$INSTALL_DIR/lib/restic.sh"
source "$INSTALL_DIR/lib/crypto.sh"

# Initialize structured logging (writes to /var/log/backupd.log)
log_init "db_backup"

SECRETS_DIR="%%SECRETS_DIR%%"
RCLONE_REMOTE="%%RCLONE_REMOTE%%"
RCLONE_PATH="%%RCLONE_PATH%%"
LOGS_DIR="%%LOGS_DIR%%"
RETENTION_DAYS="%%RETENTION_DAYS%%"
HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
LOG_PREFIX="[DB-BACKUP]"

# Lock file in fixed location
LOCK_FILE="/var/lock/backupd-db.lock"

# Secret file names
SECRET_PASSPHRASE=".c1"
SECRET_DB_USER=".c2"
SECRET_DB_PASS=".c3"
SECRET_NTFY_TOKEN=".c4"
SECRET_NTFY_URL=".c5"
SECRET_WEBHOOK_URL=".c6"
SECRET_WEBHOOK_TOKEN=".c7"
SECRET_PUSHOVER_USER=".c8"
SECRET_PUSHOVER_TOKEN=".c9"

# Progress tracking for API
PROGRESS_DIR="/var/run/backupd"
JOB_ID="${JOB_ID:-backup-db-$(date +%s)}"
PROGRESS_FILE="$PROGRESS_DIR/$JOB_ID.progress"
STARTED_AT="$(date -Iseconds)"

mkdir -p "$PROGRESS_DIR" 2>/dev/null || true
chmod 755 "$PROGRESS_DIR" 2>/dev/null || true

write_progress() {
  local phase="$1" percent="$2" message="$3" status="${4:-running}"
  cat > "$PROGRESS_FILE" << PROGRESSEOF
{
  "job_id": "$JOB_ID",
  "type": "backup",
  "subtype": "database",
  "engine": "restic",
  "status": "$status",
  "phase": "$phase",
  "percent": $percent,
  "message": "$message",
  "started_at": "$STARTED_AT",
  "updated_at": "$(date -Iseconds)"
}
PROGRESSEOF
  chmod 644 "$PROGRESS_FILE" 2>/dev/null || true
}

write_progress "initializing" 0 "Starting database backup"

# Cleanup function
MYSQL_AUTH_FILE=""
cleanup() {
  local exit_code=$?
  # Update progress to failed if exiting with error
  if [[ $exit_code -ne 0 && -f "$PROGRESS_FILE" ]]; then
    write_progress "error" 0 "Backup failed (exit code: $exit_code)" "failed"
  fi
  [[ -n "$MYSQL_AUTH_FILE" && -f "$MYSQL_AUTH_FILE" ]] && rm -f "$MYSQL_AUTH_FILE"
  log_end 2>/dev/null || true
  exit $exit_code
}
trap cleanup EXIT INT TERM

# Acquire lock (fixed location so it works across runs)
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log_info "Another database backup is running. Exiting."
  exit 0
fi

# Log rotation function
rotate_log() {
  local log_file="$1"
  local max_size=$((10 * 1024 * 1024))  # 10MB
  [[ ! -f "$log_file" ]] && return 0
  local log_size
  log_size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
  if [[ "$log_size" -gt "$max_size" ]]; then
    [[ -f "${log_file}.5" ]] && rm -f "${log_file}.5"
    for ((i=4; i>=1; i--)); do
      [[ -f "${log_file}.${i}" ]] && mv "${log_file}.${i}" "${log_file}.$((i+1))"
    done
    mv "$log_file" "${log_file}.1"
  fi
}

# Logging with rotation
LOG="$LOGS_DIR/db_logfile.log"
mkdir -p "$LOGS_DIR"
rotate_log "$LOG"
touch "$LOG" && chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1
echo "==== $(date +%F' '%T) START restic db backup ===="
write_progress "starting" 5 "Checking prerequisites"

# Get restic repository password from secrets
RESTIC_PASSWORD="$(get_secret "$SECRETS_DIR" "$SECRET_PASSPHRASE")"
[[ -z "$RESTIC_PASSWORD" ]] && { log_error "No repository password found"; exit 2; }

# Get notification credentials
NTFY_URL="$(get_secret "$SECRETS_DIR" "$SECRET_NTFY_URL" || echo "")"
NTFY_TOKEN="$(get_secret "$SECRETS_DIR" "$SECRET_NTFY_TOKEN" || echo "")"
WEBHOOK_URL="$(get_secret "$SECRETS_DIR" "$SECRET_WEBHOOK_URL" || echo "")"
WEBHOOK_TOKEN="$(get_secret "$SECRETS_DIR" "$SECRET_WEBHOOK_TOKEN" || echo "")"
PUSHOVER_USER="$(get_secret "$SECRETS_DIR" "$SECRET_PUSHOVER_USER" || echo "")"
PUSHOVER_TOKEN="$(get_secret "$SECRETS_DIR" "$SECRET_PUSHOVER_TOKEN" || echo "")"

# Notification failure log (ensure it exists with secure permissions)
NOTIFICATION_FAIL_LOG="$LOGS_DIR/notification_failures.log"
touch "$NOTIFICATION_FAIL_LOG" 2>/dev/null && chmod 600 "$NOTIFICATION_FAIL_LOG" 2>/dev/null || true

# Robust ntfy sender with retry (3 attempts, exponential backoff)
send_ntfy() {
  local title="$1" message="$2"
  [[ -z "$NTFY_URL" ]] && return 0

  local attempt=1 max_attempts=3 delay=2 http_code
  while [[ $attempt -le $max_attempts ]]; do
    if [[ -n "$NTFY_TOKEN" ]]; then
      http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $NTFY_TOKEN" -H "Title: $title" \
        -d "$message" "$NTFY_URL" 2>/dev/null) || http_code="000"
    else
      http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
        -H "Title: $title" -d "$message" "$NTFY_URL" 2>/dev/null) || http_code="000"
    fi

    [[ "$http_code" =~ ^2[0-9][0-9]$ ]] && return 0

    if [[ $attempt -lt $max_attempts ]]; then
      sleep $delay
      delay=$((delay * 2))
    fi
    ((attempt++))
  done

  echo "[$(date -Iseconds)] NTFY FAILED: title='$title' http=$http_code attempts=$max_attempts" >> "$NOTIFICATION_FAIL_LOG"
  return 1
}

# Robust webhook sender with retry (3 attempts, exponential backoff)
send_webhook() {
  local title="$1" message="$2" event="${3:-backup}" details="${4:-"{}"}"
  [[ -z "$WEBHOOK_URL" ]] && return 0

  local timestamp json_payload http_code
  timestamp="$(date -Iseconds)"
  json_payload="{\"event\":\"$event\",\"title\":\"$title\",\"hostname\":\"$HOSTNAME\",\"message\":\"$message\",\"timestamp\":\"$timestamp\",\"details\":$details}"

  local attempt=1 max_attempts=3 delay=2
  while [[ $attempt -le $max_attempts ]]; do
    if [[ -n "$WEBHOOK_TOKEN" ]]; then
      http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" \
        -H "Authorization: Bearer $WEBHOOK_TOKEN" -d "$json_payload" 2>/dev/null) || http_code="000"
    else
      http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" \
        -d "$json_payload" 2>/dev/null) || http_code="000"
    fi

    [[ "$http_code" =~ ^2[0-9][0-9]$ ]] && return 0

    if [[ $attempt -lt $max_attempts ]]; then
      sleep $delay
      delay=$((delay * 2))
    fi
    ((attempt++))
  done

  echo "[$(date -Iseconds)] WEBHOOK FAILED: event='$event' http=$http_code attempts=$max_attempts" >> "$NOTIFICATION_FAIL_LOG"
  return 1
}

# Robust Pushover sender with retry (3 attempts, exponential backoff)
send_pushover() {
  local title="$1" message="$2" priority="${3:-0}" sound="${4:-pushover}"
  [[ -z "$PUSHOVER_USER" || -z "$PUSHOVER_TOKEN" ]] && return 0

  local attempt=1 max_attempts=3 delay=2 http_code
  while [[ $attempt -le $max_attempts ]]; do
    http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
      --form-string "token=$PUSHOVER_TOKEN" \
      --form-string "user=$PUSHOVER_USER" \
      --form-string "title=$title" \
      --form-string "message=$message" \
      --form-string "priority=$priority" \
      --form-string "sound=$sound" \
      https://api.pushover.net/1/messages.json 2>/dev/null) || http_code="000"

    [[ "$http_code" == "200" ]] && return 0

    if [[ $attempt -lt $max_attempts ]]; then
      sleep $delay
      delay=$((delay * 2))
    fi
    ((attempt++))
  done

  echo "[$(date -Iseconds)] PUSHOVER FAILED: title='$title' http=$http_code attempts=$max_attempts" >> "$NOTIFICATION_FAIL_LOG"
  return 1
}

# Send to all channels, track failures
send_notification() {
  local title="$1" message="$2" event="${3:-backup}" details="${4:-"{}"}" priority="${5:-0}" sound="${6:-pushover}"
  local ntfy_ok=0 webhook_ok=0 pushover_ok=0

  send_ntfy "$title" "$message" && ntfy_ok=1
  send_webhook "$title" "$message" "$event" "$details" && webhook_ok=1
  send_pushover "$title" "$message" "$priority" "$sound" && pushover_ok=1

  # CRITICAL: All channels failed - log prominently
  if [[ $ntfy_ok -eq 0 && $webhook_ok -eq 0 && $pushover_ok -eq 0 && ( -n "$NTFY_URL" || -n "$WEBHOOK_URL" || -n "$PUSHOVER_USER" ) ]]; then
    echo "[CRITICAL] ALL NOTIFICATION CHANNELS FAILED for: $title" >&2
    echo "[$(date -Iseconds)] CRITICAL: ALL CHANNELS FAILED - title='$title' event='$event'" >> "$NOTIFICATION_FAIL_LOG"
  fi
}

send_notification "DB Backup Started on $HOSTNAME" "Starting restic backup at $(date)" "backup_started" "{}" "-1" "none"

# Build restic repository URL
REPO="$(get_restic_repo "$RCLONE_REMOTE" "$RCLONE_PATH")"
echo "$LOG_PREFIX Repository: $REPO"

# Initialize repo if needed
write_progress "initializing" 10 "Checking repository"
if ! repo_exists "$REPO" "$RESTIC_PASSWORD"; then
  log_info "Initializing restic repository..."
  if ! init_restic_repo "$REPO" "$RESTIC_PASSWORD"; then
    log_error "Failed to initialize repository"
    send_notification "DB Backup Failed on $HOSTNAME" "Repository initialization failed" "backup_failed" "{}" "1" "siren"
    exit 3
  fi
  log_info "Repository initialized"
fi

# Detect DB client
if command -v mariadb >/dev/null 2>&1; then
  DB_CLIENT="mariadb"; DB_DUMP="mariadb-dump"
elif command -v mysql >/dev/null 2>&1; then
  DB_CLIENT="mysql"; DB_DUMP="mysqldump"
else
  log_error "No database client found"
  send_notification "DB Backup Failed on $HOSTNAME" "No database client found" "backup_failed" "{}" "1" "siren"
  exit 5
fi

# Get DB credentials and create auth file (more secure than command line)
DB_USER="$(get_secret "$SECRETS_DIR" "$SECRET_DB_USER" || echo "")"
DB_PASS="$(get_secret "$SECRETS_DIR" "$SECRET_DB_PASS" || echo "")"
MYSQL_ARGS=()

if [[ -n "$DB_USER" && -n "$DB_PASS" ]]; then
  # Use defaults-extra-file to hide password from process list
  MYSQL_AUTH_FILE="$(mktemp)"
  chmod 600 "$MYSQL_AUTH_FILE"
  cat > "$MYSQL_AUTH_FILE" << AUTHEOF
[client]
user=$DB_USER
password=$DB_PASS
AUTHEOF
  MYSQL_ARGS=("--defaults-extra-file=$MYSQL_AUTH_FILE")
fi

# Get databases to backup
EXCLUDE_REGEX='^(information_schema|performance_schema|sys|mysql)$'
DBS="$($DB_CLIENT "${MYSQL_ARGS[@]}" -NBe 'SHOW DATABASES' 2>/dev/null | grep -Ev "$EXCLUDE_REGEX" || true)"

if [[ -z "$DBS" ]]; then
  log_error "No databases found or cannot connect to database"
  send_notification "DB Backup Failed on $HOSTNAME" "No databases found" "backup_failed" "{}" "1" "siren"
  exit 6
fi

# Backup each database using restic
declare -a failures=()
db_count=0
total_dbs=$(echo "$DBS" | wc -w)
write_progress "backing_up" 15 "Backing up $total_dbs databases"

for db in $DBS; do
  echo "$LOG_PREFIX Backing up database: $db"
  progress_pct=$((15 + (db_count * 60 / total_dbs)))
  write_progress "backing_up" $progress_pct "Backing up: $db"

  # Backup database via stdin to restic
  if $DB_DUMP "${MYSQL_ARGS[@]}" --databases "$db" --single-transaction --quick \
      --routines --events --triggers --hex-blob --default-character-set=utf8mb4 2>/dev/null | \
    RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$REPO" backup \
      --retry-lock 2m \
      --stdin \
      --stdin-filename "${db}.sql" \
      --tag "database" \
      --tag "db:${db}" \
      --host "$HOSTNAME" 2>&1; then
    echo "$LOG_PREFIX   OK: $db"
    ((db_count++)) || true
  else
    echo "$LOG_PREFIX   FAILED: $db"
    failures+=("$db")
  fi
done

if [[ $db_count -eq 0 ]]; then
  log_error "All database backups failed"
  send_notification "DB Backup Failed on $HOSTNAME" "All backups failed" "backup_failed" "{}" "1" "siren"
  exit 7
fi

# Apply retention policy
write_progress "retention" 80 "Applying retention policy"
echo "$LOG_PREFIX Applying retention policy (keeping backups within $RETENTION_DAYS days)..."
if RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$REPO" forget \
    --retry-lock 2m \
    --tag "database" \
    --keep-within "${RETENTION_DAYS}d" \
    --prune 2>&1; then
  echo "$LOG_PREFIX Retention policy applied"
else
  echo "$LOG_PREFIX [WARNING] Retention policy failed (backup succeeded)"
fi

# Summary
write_progress "complete" 100 "Backup completed" "completed"
if ((${#failures[@]})); then
  send_notification "DB Backup Completed with Errors on $HOSTNAME" "Backed up: $db_count, Failed: ${failures[*]}" "backup_warning" "{}" "0" "bike"
  write_progress "error" 100 "Backup completed with errors: ${failures[*]}" "failed"
  echo "==== $(date +%F' '%T) END (with errors) ===="
  # Record to history
  ENDED_AT="\$(date -Iseconds)"
  source "\$INSTALL_DIR/lib/history.sh" 2>/dev/null && \
    record_history "database" "partial" "\$STARTED_AT" "\$ENDED_AT" "" "\$db_count" "\${#failures[@]}" "Failed: \${failures[*]}"
  exit 1
else
  send_notification "DB Backup Successful on $HOSTNAME" "All $db_count databases backed up via restic" "backup_complete" "{}" "0" "magic"
  echo "==== $(date +%F' '%T) END (success) ===="
  # Record to history
  ENDED_AT="\$(date -Iseconds)"
  source "\$INSTALL_DIR/lib/history.sh" 2>/dev/null && \
    record_history "database" "success" "\$STARTED_AT" "\$ENDED_AT" "" "\$db_count" "0" ""
fi
DBBACKUPEOF

  # Replace placeholders
  sed -i \
    -e "s|%%SECRETS_DIR%%|$SECRETS_DIR|g" \
    -e "s|%%RCLONE_REMOTE%%|$RCLONE_REMOTE|g" \
    -e "s|%%RCLONE_PATH%%|$RCLONE_PATH|g" \
    -e "s|%%LOGS_DIR%%|$LOGS_DIR|g" \
    -e "s|%%RETENTION_DAYS%%|$RETENTION_DAYS|g" \
    "$SCRIPTS_DIR/db_backup.sh"

  chmod +x "$SCRIPTS_DIR/db_backup.sh"
}

# ---------- Generate Restic Files Backup Script ----------

generate_restic_files_backup_script() {
  local SECRETS_DIR="$1"
  local RCLONE_REMOTE="$2"
  local RCLONE_PATH="$3"
  local LOGS_DIR="$4"
  local RETENTION_DAYS="${5:-30}"
  local WEB_PATH_PATTERN="${6:-/var/www/*}"
  local WEBROOT_SUBDIR="${7:-.}"

  cat > "$SCRIPTS_DIR/files_backup.sh" << 'FILESBACKUPEOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077

# ============================================================================
# Backupd v3.0 - Restic Files Backup Script
# Uses restic for encrypted, deduplicated backups via rclone backend
# ============================================================================

INSTALL_DIR="/etc/backupd"
source "$INSTALL_DIR/lib/logging.sh"
source "$INSTALL_DIR/lib/debug.sh"
source "$INSTALL_DIR/lib/restic.sh"
source "$INSTALL_DIR/lib/crypto.sh"

# Initialize structured logging (writes to /var/log/backupd.log)
log_init "files_backup"

SECRETS_DIR="%%SECRETS_DIR%%"
RCLONE_REMOTE="%%RCLONE_REMOTE%%"
RCLONE_PATH="%%RCLONE_PATH%%"
LOGS_DIR="%%LOGS_DIR%%"
RETENTION_DAYS="%%RETENTION_DAYS%%"
WEB_PATH_PATTERN="%%WEB_PATH_PATTERN%%"
WEBROOT_SUBDIR="%%WEBROOT_SUBDIR%%"
HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
LOG_PREFIX="[FILES-BACKUP]"

# Lock file in fixed location
LOCK_FILE="/var/lock/backupd-files.lock"

# Secret file names
SECRET_PASSPHRASE=".c1"
SECRET_NTFY_TOKEN=".c4"
SECRET_NTFY_URL=".c5"
SECRET_WEBHOOK_URL=".c6"
SECRET_WEBHOOK_TOKEN=".c7"
SECRET_PUSHOVER_USER=".c8"
SECRET_PUSHOVER_TOKEN=".c9"

# Progress tracking for API
PROGRESS_DIR="/var/run/backupd"
JOB_ID="${JOB_ID:-backup-files-$(date +%s)}"
PROGRESS_FILE="$PROGRESS_DIR/$JOB_ID.progress"
STARTED_AT="$(date -Iseconds)"

mkdir -p "$PROGRESS_DIR" 2>/dev/null || true
chmod 755 "$PROGRESS_DIR" 2>/dev/null || true

write_progress() {
  local phase="$1" percent="$2" message="$3" status="${4:-running}"
  cat > "$PROGRESS_FILE" << PROGRESSEOF
{
  "job_id": "$JOB_ID",
  "type": "backup",
  "subtype": "files",
  "engine": "restic",
  "status": "$status",
  "phase": "$phase",
  "percent": $percent,
  "message": "$message",
  "started_at": "$STARTED_AT",
  "updated_at": "$(date -Iseconds)"
}
PROGRESSEOF
  chmod 644 "$PROGRESS_FILE" 2>/dev/null || true
}

write_progress "initializing" 0 "Starting files backup"

# Cleanup function
cleanup() {
  local exit_code=$?
  # Update progress to failed if exiting with error
  if [[ $exit_code -ne 0 && -f "$PROGRESS_FILE" ]]; then
    write_progress "error" 0 "Backup failed (exit code: $exit_code)" "failed"
  fi
  log_end 2>/dev/null || true
  exit $exit_code
}
trap cleanup EXIT INT TERM

# Acquire lock (fixed location)
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log_info "Another files backup is running. Exiting."
  exit 0
fi

# Log rotation function
rotate_log() {
  local log_file="$1"
  local max_size=$((10 * 1024 * 1024))  # 10MB
  [[ ! -f "$log_file" ]] && return 0
  local log_size
  log_size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
  if [[ "$log_size" -gt "$max_size" ]]; then
    [[ -f "${log_file}.5" ]] && rm -f "${log_file}.5"
    for ((i=4; i>=1; i--)); do
      [[ -f "${log_file}.${i}" ]] && mv "${log_file}.${i}" "${log_file}.$((i+1))"
    done
    mv "$log_file" "${log_file}.1"
  fi
}

# Logging with rotation
LOG="$LOGS_DIR/files_logfile.log"
mkdir -p "$LOGS_DIR"
rotate_log "$LOG"
touch "$LOG" && chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1
echo "==== $(date +%F' '%T) START restic files backup ===="
write_progress "starting" 5 "Checking prerequisites"

# Get restic repository password from secrets
RESTIC_PASSWORD="$(get_secret "$SECRETS_DIR" "$SECRET_PASSPHRASE")"
[[ -z "$RESTIC_PASSWORD" ]] && { log_error "No repository password found"; exit 2; }

# Get notification credentials
NTFY_URL="$(get_secret "$SECRETS_DIR" "$SECRET_NTFY_URL" || echo "")"
NTFY_TOKEN="$(get_secret "$SECRETS_DIR" "$SECRET_NTFY_TOKEN" || echo "")"
WEBHOOK_URL="$(get_secret "$SECRETS_DIR" "$SECRET_WEBHOOK_URL" || echo "")"
WEBHOOK_TOKEN="$(get_secret "$SECRETS_DIR" "$SECRET_WEBHOOK_TOKEN" || echo "")"
PUSHOVER_USER="$(get_secret "$SECRETS_DIR" "$SECRET_PUSHOVER_USER" || echo "")"
PUSHOVER_TOKEN="$(get_secret "$SECRETS_DIR" "$SECRET_PUSHOVER_TOKEN" || echo "")"

# Notification failure log (ensure it exists with secure permissions)
NOTIFICATION_FAIL_LOG="$LOGS_DIR/notification_failures.log"
touch "$NOTIFICATION_FAIL_LOG" 2>/dev/null && chmod 600 "$NOTIFICATION_FAIL_LOG" 2>/dev/null || true

# Robust ntfy sender with retry (3 attempts, exponential backoff)
send_ntfy() {
  local title="$1" message="$2"
  [[ -z "$NTFY_URL" ]] && return 0

  local attempt=1 max_attempts=3 delay=2 http_code
  while [[ $attempt -le $max_attempts ]]; do
    if [[ -n "$NTFY_TOKEN" ]]; then
      http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $NTFY_TOKEN" -H "Title: $title" \
        -d "$message" "$NTFY_URL" 2>/dev/null) || http_code="000"
    else
      http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
        -H "Title: $title" -d "$message" "$NTFY_URL" 2>/dev/null) || http_code="000"
    fi

    [[ "$http_code" =~ ^2[0-9][0-9]$ ]] && return 0

    if [[ $attempt -lt $max_attempts ]]; then
      sleep $delay
      delay=$((delay * 2))
    fi
    ((attempt++))
  done

  echo "[$(date -Iseconds)] NTFY FAILED: title='$title' http=$http_code attempts=$max_attempts" >> "$NOTIFICATION_FAIL_LOG"
  return 1
}

# Robust webhook sender with retry (3 attempts, exponential backoff)
send_webhook() {
  local title="$1" message="$2" event="${3:-backup}" details="${4:-"{}"}"
  [[ -z "$WEBHOOK_URL" ]] && return 0

  local timestamp json_payload http_code
  timestamp="$(date -Iseconds)"
  json_payload="{\"event\":\"$event\",\"title\":\"$title\",\"hostname\":\"$HOSTNAME\",\"message\":\"$message\",\"timestamp\":\"$timestamp\",\"details\":$details}"

  local attempt=1 max_attempts=3 delay=2
  while [[ $attempt -le $max_attempts ]]; do
    if [[ -n "$WEBHOOK_TOKEN" ]]; then
      http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" \
        -H "Authorization: Bearer $WEBHOOK_TOKEN" -d "$json_payload" 2>/dev/null) || http_code="000"
    else
      http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" \
        -d "$json_payload" 2>/dev/null) || http_code="000"
    fi

    [[ "$http_code" =~ ^2[0-9][0-9]$ ]] && return 0

    if [[ $attempt -lt $max_attempts ]]; then
      sleep $delay
      delay=$((delay * 2))
    fi
    ((attempt++))
  done

  echo "[$(date -Iseconds)] WEBHOOK FAILED: event='$event' http=$http_code attempts=$max_attempts" >> "$NOTIFICATION_FAIL_LOG"
  return 1
}

# Robust Pushover sender with retry (3 attempts, exponential backoff)
send_pushover() {
  local title="$1" message="$2" priority="${3:-0}" sound="${4:-pushover}"
  [[ -z "$PUSHOVER_USER" || -z "$PUSHOVER_TOKEN" ]] && return 0

  local attempt=1 max_attempts=3 delay=2 http_code
  while [[ $attempt -le $max_attempts ]]; do
    http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
      --form-string "token=$PUSHOVER_TOKEN" \
      --form-string "user=$PUSHOVER_USER" \
      --form-string "title=$title" \
      --form-string "message=$message" \
      --form-string "priority=$priority" \
      --form-string "sound=$sound" \
      https://api.pushover.net/1/messages.json 2>/dev/null) || http_code="000"

    [[ "$http_code" == "200" ]] && return 0

    if [[ $attempt -lt $max_attempts ]]; then
      sleep $delay
      delay=$((delay * 2))
    fi
    ((attempt++))
  done

  echo "[$(date -Iseconds)] PUSHOVER FAILED: title='$title' http=$http_code attempts=$max_attempts" >> "$NOTIFICATION_FAIL_LOG"
  return 1
}

# Send to all channels, track failures
send_notification() {
  local title="$1" message="$2" event="${3:-backup}" details="${4:-"{}"}" priority="${5:-0}" sound="${6:-pushover}"
  local ntfy_ok=0 webhook_ok=0 pushover_ok=0

  send_ntfy "$title" "$message" && ntfy_ok=1
  send_webhook "$title" "$message" "$event" "$details" && webhook_ok=1
  send_pushover "$title" "$message" "$priority" "$sound" && pushover_ok=1

  # CRITICAL: All channels failed - log prominently
  if [[ $ntfy_ok -eq 0 && $webhook_ok -eq 0 && $pushover_ok -eq 0 && ( -n "$NTFY_URL" || -n "$WEBHOOK_URL" || -n "$PUSHOVER_USER" ) ]]; then
    echo "[CRITICAL] ALL NOTIFICATION CHANNELS FAILED for: $title" >&2
    echo "[$(date -Iseconds)] CRITICAL: ALL CHANNELS FAILED - title='$title' event='$event'" >> "$NOTIFICATION_FAIL_LOG"
  fi
}

send_notification "Files Backup Started on $HOSTNAME" "Starting restic backup at $(date)" "backup_started" "{}" "-1" "none"

# Build restic repository URL
REPO="$(get_restic_repo "$RCLONE_REMOTE" "$RCLONE_PATH")"
echo "$LOG_PREFIX Repository: $REPO"

# Initialize repo if needed
write_progress "initializing" 10 "Checking repository"
if ! repo_exists "$REPO" "$RESTIC_PASSWORD"; then
  log_info "Initializing restic repository..."
  if ! init_restic_repo "$REPO" "$RESTIC_PASSWORD"; then
    log_error "Failed to initialize repository"
    send_notification "Files Backup Failed on $HOSTNAME" "Repository initialization failed" "backup_failed" "{}" "1" "siren"
    exit 3
  fi
  log_info "Repository initialized"
fi

# Site name detection functions
sanitize_for_tag() {
  local s="$1"
  s="$(echo -n "$s" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  s="${s//:\/\//__}"; s="${s//\//__}"
  s="$(echo -n "$s" | sed -E 's/[^a-z0-9._-]+/_/g')"
  s="${s%.}"
  [[ -z "$s" ]] && s="unknown-site"
  printf "%s" "$s"
}

# Get site name/URL from various app types
get_site_name() {
  local site_path="$1"
  local owner="${2:-www-data}"
  local name=""

  # 1. WordPress: wp option get siteurl
  if [[ -f "$site_path/wp-config.php" ]]; then
    if su -l -s /bin/bash "$owner" -c "command -v wp >/dev/null 2>&1" 2>/dev/null; then
      name="$(su -l -s /bin/bash "$owner" -c "cd '$site_path' && wp option get siteurl 2>/dev/null" 2>/dev/null || true)"
    fi
    if [[ -z "$name" ]]; then
      name="$(grep -E "define\s*\(\s*['\"]WP_HOME['\"]" "$site_path/wp-config.php" 2>/dev/null | head -1 | sed -E "s/.*['\"]https?:\/\/([^'\"]+)['\"].*/https:\/\/\1/" || true)"
    fi
    [[ -n "$name" ]] && echo "$name" && return 0
  fi

  # 2. Laravel: APP_URL from .env
  if [[ -f "$site_path/.env" ]] && [[ -f "$site_path/artisan" ]]; then
    name="$(grep -E "^APP_URL=" "$site_path/.env" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" || true)"
    [[ -n "$name" ]] && echo "$name" && return 0
  fi

  # 3. Node.js: name from package.json
  if [[ -f "$site_path/package.json" ]]; then
    name="$(grep -E '"name"\s*:' "$site_path/package.json" 2>/dev/null | head -1 | sed -E 's/.*"name"\s*:\s*"([^"]+)".*/\1/' || true)"
    [[ -n "$name" ]] && echo "$name" && return 0
  fi

  # 4. Generic: try to extract from nginx/apache configs
  if [[ -d "/etc/nginx/sites-enabled" ]]; then
    local nginx_name
    nginx_name="$(grep -rh "server_name" /etc/nginx/sites-enabled/ 2>/dev/null | grep -i "$(basename "$site_path")" | head -1 | awk '{print $2}' | tr -d ';' || true)"
    [[ -n "$nginx_name" && "$nginx_name" != "_" ]] && echo "$nginx_name" && return 0
  fi

  # 5. Fallback: use folder name
  echo "$(basename "$site_path")"
}

echo "$LOG_PREFIX Scanning using pattern: $WEB_PATH_PATTERN"
echo "$LOG_PREFIX Webroot subdirectory: $WEBROOT_SUBDIR"

# Find site directories
site_dirs=()
for dir in $WEB_PATH_PATTERN; do
  [[ -d "$dir" ]] && site_dirs+=("$dir")
done

if [[ ${#site_dirs[@]} -eq 0 ]]; then
  log_error "No directories found matching pattern: $WEB_PATH_PATTERN"
  send_notification "Files Backup Failed on $HOSTNAME" "No sites found matching pattern" "backup_failed" "{}" "1" "siren"
  exit 4
fi

declare -a failures=()
success_count=0
site_count=0
total_sites=${#site_dirs[@]}
write_progress "scanning" 15 "Found $total_sites site directories"

for site_path in "${site_dirs[@]}"; do
  [[ ! -d "$site_path" ]] && continue
  site_name="$(basename "$site_path")"

  # Skip common non-site directories
  [[ "$site_name" == "default" || "$site_name" == "html" || "$site_name" == "cgi-bin" ]] && continue

  # Determine the actual web root
  if [[ "$WEBROOT_SUBDIR" == "." ]]; then
    webroot="$site_path"
  else
    webroot="$site_path/$WEBROOT_SUBDIR"
    if [[ ! -d "$webroot" ]]; then
      webroot="$site_path"
    fi
  fi

  # Skip if webroot is empty
  if [[ ! -d "$webroot" ]] || [[ -z "$(ls -A "$webroot" 2>/dev/null)" ]]; then
    echo "$LOG_PREFIX [$site_name] Skipping: empty or missing webroot"
    continue
  fi

  ((site_count++)) || true

  owner="$(stat -c '%U' "$site_path" 2>/dev/null || echo "www-data")"
  site_url="$(get_site_name "$webroot" "$owner")"
  site_tag="$(sanitize_for_tag "$site_url")"

  echo "$LOG_PREFIX [$site_name] Backing up ($site_url)..."
  progress_pct=$((15 + (site_count * 60 / total_sites)))
  write_progress "backing_up" $progress_pct "Backing up: $site_name"

  # Backup site using restic
  if RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$REPO" backup "$webroot" \
      --retry-lock 2m \
      --tag "files" \
      --tag "site:${site_tag}" \
      --host "$HOSTNAME" 2>&1; then
    ((success_count++)) || true
    echo "$LOG_PREFIX [$site_name] Done"
  else
    echo "$LOG_PREFIX [$site_name] FAILED"
    failures+=("$site_name")
  fi
done

if [[ $site_count -eq 0 ]]; then
  echo "$LOG_PREFIX [WARNING] No sites found in pattern"
  send_notification "Files Backup Warning on $HOSTNAME" "No sites found" "backup_warning" "{}" "0" "bike"
  echo "==== $(date +%F' '%T) END (no sites) ===="
  exit 0
fi

# Apply retention policy
write_progress "retention" 80 "Applying retention policy"
echo "$LOG_PREFIX Applying retention policy (keeping backups within $RETENTION_DAYS days)..."
if RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$REPO" forget \
    --retry-lock 2m \
    --tag "files" \
    --keep-within "${RETENTION_DAYS}d" \
    --prune 2>&1; then
  echo "$LOG_PREFIX Retention policy applied"
else
  echo "$LOG_PREFIX [WARNING] Retention policy failed (backup succeeded)"
fi

# Summary
write_progress "complete" 100 "Backup completed" "completed"
if [[ ${#failures[@]} -gt 0 ]]; then
  send_notification "Files Backup Errors on $HOSTNAME" "Success: $success_count, Failed: ${failures[*]}" "backup_warning" "{}" "0" "bike"
  write_progress "error" 100 "Backup completed with errors: ${failures[*]}" "failed"
  echo "==== $(date +%F' '%T) END (with errors) ===="
  # Record to history
  ENDED_AT="\$(date -Iseconds)"
  source "\$INSTALL_DIR/lib/history.sh" 2>/dev/null && \
    record_history "files" "partial" "\$STARTED_AT" "\$ENDED_AT" "" "\$success_count" "\${#failures[@]}" "Failed: \${failures[*]}"
  exit 1
else
  send_notification "Files Backup Success on $HOSTNAME" "$success_count sites backed up via restic" "backup_complete" "{}" "0" "magic"
  echo "==== $(date +%F' '%T) END (success) ===="
  # Record to history
  ENDED_AT="\$(date -Iseconds)"
  source "\$INSTALL_DIR/lib/history.sh" 2>/dev/null && \
    record_history "files" "success" "\$STARTED_AT" "\$ENDED_AT" "" "\$success_count" "0" ""
fi
FILESBACKUPEOF

  # Replace placeholders
  sed -i \
    -e "s|%%SECRETS_DIR%%|$SECRETS_DIR|g" \
    -e "s|%%RCLONE_REMOTE%%|$RCLONE_REMOTE|g" \
    -e "s|%%RCLONE_PATH%%|$RCLONE_PATH|g" \
    -e "s|%%LOGS_DIR%%|$LOGS_DIR|g" \
    -e "s|%%RETENTION_DAYS%%|$RETENTION_DAYS|g" \
    -e "s|%%WEB_PATH_PATTERN%%|$WEB_PATH_PATTERN|g" \
    -e "s|%%WEBROOT_SUBDIR%%|$WEBROOT_SUBDIR|g" \
    "$SCRIPTS_DIR/files_backup.sh"

  chmod +x "$SCRIPTS_DIR/files_backup.sh"
}

# ---------- Generate Restic Restore Script ----------

generate_restic_restore_script() {
  local SECRETS_DIR="$1"
  local RCLONE_REMOTE="$2"
  local RCLONE_DB_PATH="$3"
  local RCLONE_FILES_PATH="$4"

  cat > "$SCRIPTS_DIR/restore.sh" << 'RESTOREEOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077

# ============================================================================
# Backupd v3.0 - Restic Restore Script
# Interactive restore from restic snapshots (database and files)
# ============================================================================

INSTALL_DIR="/etc/backupd"
source "$INSTALL_DIR/lib/logging.sh"
source "$INSTALL_DIR/lib/debug.sh"
source "$INSTALL_DIR/lib/restic.sh"
source "$INSTALL_DIR/lib/crypto.sh"

# Initialize structured logging (writes to /var/log/backupd.log)
log_init "restore_script"

SECRETS_DIR="%%SECRETS_DIR%%"
RCLONE_REMOTE="%%RCLONE_REMOTE%%"
RCLONE_DB_PATH="%%RCLONE_DB_PATH%%"
RCLONE_FILES_PATH="%%RCLONE_FILES_PATH%%"
HOSTNAME="$(hostname -f 2>/dev/null || hostname)"

# Secret file names
SECRET_PASSPHRASE=".c1"
SECRET_DB_USER=".c2"
SECRET_DB_PASS=".c3"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Cleanup function
MYSQL_AUTH_FILE=""
TEMP_SQL_FILE=""
cleanup() {
  local exit_code=$?
  [[ -n "$MYSQL_AUTH_FILE" && -f "$MYSQL_AUTH_FILE" ]] && rm -f "$MYSQL_AUTH_FILE"
  [[ -n "$TEMP_SQL_FILE" && -f "$TEMP_SQL_FILE" ]] && rm -f "$TEMP_SQL_FILE"
  exit $exit_code
}
trap cleanup EXIT INT TERM

# Output helpers
print_header() {
  clear
  echo -e "${CYAN}========================================${NC}"
  echo -e "${CYAN}    Backupd v3.0 - Restore Menu${NC}"
  echo -e "${CYAN}========================================${NC}"
  echo
}

print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_info() { echo -e "${CYAN}[INFO]${NC} $1"; }

press_enter() {
  echo
  read -p "Press Enter to continue..." _
}

# Get restic password
RESTIC_PASSWORD="$(get_secret "$SECRETS_DIR" "$SECRET_PASSPHRASE")"
if [[ -z "$RESTIC_PASSWORD" ]]; then
  print_error "No repository password found in secrets"
  exit 2
fi

# Build repository URLs
DB_REPO=""
FILES_REPO=""
[[ -n "$RCLONE_DB_PATH" ]] && DB_REPO="rclone:${RCLONE_REMOTE}:${RCLONE_DB_PATH}"
[[ -n "$RCLONE_FILES_PATH" ]] && FILES_REPO="rclone:${RCLONE_REMOTE}:${RCLONE_FILES_PATH}"

# ---------- Database Restore Functions ----------

list_db_snapshots_menu() {
  if [[ -z "$DB_REPO" ]]; then
    print_error "Database backups not configured"
    return 1
  fi

  print_info "Fetching database snapshots..."
  echo

  local snapshots_json
  snapshots_json="$(RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$DB_REPO" snapshots --tag database --json 2>/dev/null || echo "[]")"

  if [[ "$snapshots_json" == "[]" || -z "$snapshots_json" ]]; then
    print_warning "No database snapshots found"
    return 1
  fi

  # Parse and display snapshots
  echo -e "${BOLD}Available Database Snapshots:${NC}"
  echo "-------------------------------------------"
  printf "%-10s %-20s %-15s %s\n" "ID" "DATE" "DATABASE" "HOST"
  echo "-------------------------------------------"

  local count=0

  # Use jq if available (reliable), otherwise fall back to portable parsing
  if command -v jq >/dev/null 2>&1; then
    while IFS=$'\t' read -r short_id time hostname db_name; do
      [[ -n "$short_id" ]] && printf "%-10s %-20s %-15s %s\n" "$short_id" "$time" "${db_name:-unknown}" "$hostname"
      ((count++)) || true
    done < <(echo "$snapshots_json" | jq -r '.[] | [
      .short_id,
      (.time | split(".")[0] | gsub("T"; " ")),
      .hostname,
      ((.tags // []) | map(select(startswith("db:"))) | first // "unknown" | ltrimstr("db:"))
    ] | @tsv')
  else
    # Portable approach: extract complete JSON objects using awk
    while IFS= read -r obj; do
      [[ -z "$obj" ]] && continue

      local short_id time hostname db_name tags_str

      # Extract fields from complete JSON object
      short_id="$(echo "$obj" | sed -n 's/.*"short_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
      time="$(echo "$obj" | sed -n 's/.*"time"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
      time="${time%%.*}"; time="${time/T/ }"
      hostname="$(echo "$obj" | sed -n 's/.*"hostname"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
      tags_str="$(echo "$obj" | sed -n 's/.*"tags"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p')"
      db_name="$(echo "$tags_str" | grep -o '"db:[^"]*"' | head -1 | tr -d '"')"
      db_name="${db_name#db:}"

      [[ -n "$short_id" ]] && printf "%-10s %-20s %-15s %s\n" "$short_id" "$time" "${db_name:-unknown}" "$hostname"
      ((count++)) || true
    done < <(echo "$snapshots_json" | awk 'BEGIN{RS="";FS=""}{gsub(/^\[/,"");gsub(/\]$/,"");n=split($0,c,"");d=0;o="";for(i=1;i<=n;i++){if(c[i]=="{"){d++;o=o c[i]}else if(c[i]=="}"){o=o c[i];d--;if(d==0){print o;o=""}}else if(d>0){o=o c[i]}}}')
  fi

  echo "-------------------------------------------"
  echo "Total: $count snapshot(s)"
  echo
}

restore_database_menu() {
  if [[ -z "$DB_REPO" ]]; then
    print_error "Database backups not configured"
    press_enter
    return
  fi

  print_header
  echo "Restore Database from Snapshot"
  echo "==============================="
  echo

  list_db_snapshots_menu || { press_enter; return; }

  echo
  echo "Enter snapshot ID to restore (or 'latest' for most recent):"
  read -p "> " snapshot_input

  [[ -z "$snapshot_input" ]] && { print_warning "No snapshot selected"; press_enter; return; }

  local snapshot_id="$snapshot_input"
  if [[ "$snapshot_input" == "latest" ]]; then
    snapshot_id="$(RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$DB_REPO" snapshots --tag database --json --latest 1 2>/dev/null | grep -o '"short_id":"[^"]*"' | head -1 | cut -d'"' -f4)"
    if [[ -z "$snapshot_id" ]]; then
      print_error "Could not find latest snapshot"
      press_enter
      return
    fi
    print_info "Using latest snapshot: $snapshot_id"
  fi

  # Get database name from snapshot tags
  local snapshot_info db_name
  snapshot_info="$(RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$DB_REPO" snapshots "$snapshot_id" --json 2>/dev/null || echo "[]")"
  db_name="$(echo "$snapshot_info" | grep -o 'db:[^"]*' | head -1)"
  db_name="${db_name#db:}"
  [[ -z "$db_name" ]] && db_name="unknown"

  echo
  echo -e "${YELLOW}WARNING: This will restore database '$db_name' from snapshot $snapshot_id${NC}"
  echo -e "${YELLOW}The existing database will be OVERWRITTEN!${NC}"
  echo
  read -p "Type 'yes' to confirm: " confirm
  [[ "$confirm" != "yes" ]] && { print_warning "Restore cancelled"; press_enter; return; }

  # Detect database client
  local DB_CLIENT DB_IMPORT
  if command -v mariadb >/dev/null 2>&1; then
    DB_CLIENT="mariadb"; DB_IMPORT="mariadb"
  elif command -v mysql >/dev/null 2>&1; then
    DB_CLIENT="mysql"; DB_IMPORT="mysql"
  else
    print_error "No database client found (mysql/mariadb)"
    press_enter
    return
  fi

  # Get database credentials
  local DB_USER DB_PASS MYSQL_ARGS
  DB_USER="$(get_secret "$SECRETS_DIR" "$SECRET_DB_USER" || echo "")"
  DB_PASS="$(get_secret "$SECRETS_DIR" "$SECRET_DB_PASS" || echo "")"
  MYSQL_ARGS=()

  if [[ -n "$DB_USER" && -n "$DB_PASS" ]]; then
    MYSQL_AUTH_FILE="$(mktemp)"
    chmod 600 "$MYSQL_AUTH_FILE"
    cat > "$MYSQL_AUTH_FILE" << AUTHEOF
[client]
user=$DB_USER
password=$DB_PASS
AUTHEOF
    MYSQL_ARGS=("--defaults-extra-file=$MYSQL_AUTH_FILE")
  fi

  # Dump snapshot to temp file
  echo
  print_info "Extracting database from snapshot..."
  TEMP_SQL_FILE="$(mktemp --suffix=.sql)"
  chmod 600 "$TEMP_SQL_FILE"

  if ! RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$DB_REPO" dump "$snapshot_id" "/${db_name}.sql" > "$TEMP_SQL_FILE" 2>/dev/null; then
    print_error "Failed to extract database from snapshot"
    press_enter
    return
  fi

  local sql_size
  sql_size="$(stat -c%s "$TEMP_SQL_FILE" 2>/dev/null || echo 0)"
  if [[ "$sql_size" -lt 100 ]]; then
    print_error "Extracted file too small ($sql_size bytes) - snapshot may be corrupt"
    press_enter
    return
  fi

  print_success "Extracted $(numfmt --to=iec "$sql_size" 2>/dev/null || echo "$sql_size bytes")"

  # Import to database
  print_info "Importing database..."
  if $DB_IMPORT "${MYSQL_ARGS[@]}" < "$TEMP_SQL_FILE" 2>&1; then
    print_success "Database '$db_name' restored successfully!"
  else
    print_error "Database import failed"
  fi

  press_enter
}

# ---------- Files Restore Functions ----------

list_files_snapshots_menu() {
  if [[ -z "$FILES_REPO" ]]; then
    print_error "Files backups not configured"
    return 1
  fi

  print_info "Fetching files snapshots..."
  echo

  local snapshots_json
  snapshots_json="$(RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$FILES_REPO" snapshots --tag files --json 2>/dev/null || echo "[]")"

  if [[ "$snapshots_json" == "[]" || -z "$snapshots_json" ]]; then
    print_warning "No files snapshots found"
    return 1
  fi

  # Parse and display snapshots
  echo -e "${BOLD}Available Files Snapshots:${NC}"
  echo "-------------------------------------------"
  printf "%-10s %-20s %-20s %s\n" "ID" "DATE" "SITE" "HOST"
  echo "-------------------------------------------"

  local count=0

  # Use jq if available (reliable), otherwise fall back to portable parsing
  if command -v jq >/dev/null 2>&1; then
    while IFS=$'\t' read -r short_id time hostname site_name; do
      [[ -n "$short_id" ]] && printf "%-10s %-20s %-20s %s\n" "$short_id" "$time" "${site_name:-unknown}" "$hostname"
      ((count++)) || true
    done < <(echo "$snapshots_json" | jq -r '.[] | [
      .short_id,
      (.time | split(".")[0] | gsub("T"; " ")),
      .hostname,
      ((.tags // []) | map(select(startswith("site:"))) | first // "unknown" | ltrimstr("site:"))
    ] | @tsv')
  else
    # Portable approach: extract complete JSON objects using awk
    while IFS= read -r obj; do
      [[ -z "$obj" ]] && continue

      local short_id time hostname site_name tags_str

      # Extract fields from complete JSON object
      short_id="$(echo "$obj" | sed -n 's/.*"short_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
      time="$(echo "$obj" | sed -n 's/.*"time"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
      time="${time%%.*}"; time="${time/T/ }"
      hostname="$(echo "$obj" | sed -n 's/.*"hostname"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
      tags_str="$(echo "$obj" | sed -n 's/.*"tags"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p')"
      site_name="$(echo "$tags_str" | grep -o '"site:[^"]*"' | head -1 | tr -d '"')"
      site_name="${site_name#site:}"

      [[ -n "$short_id" ]] && printf "%-10s %-20s %-20s %s\n" "$short_id" "$time" "${site_name:-unknown}" "$hostname"
      ((count++)) || true
    done < <(echo "$snapshots_json" | awk 'BEGIN{RS="";FS=""}{gsub(/^\[/,"");gsub(/\]$/,"");n=split($0,c,"");d=0;o="";for(i=1;i<=n;i++){if(c[i]=="{"){d++;o=o c[i]}else if(c[i]=="}"){o=o c[i];d--;if(d==0){print o;o=""}}else if(d>0){o=o c[i]}}}')
  fi

  echo "-------------------------------------------"
  echo "Total: $count snapshot(s)"
  echo
}

restore_files_menu() {
  if [[ -z "$FILES_REPO" ]]; then
    print_error "Files backups not configured"
    press_enter
    return
  fi

  print_header
  echo "Restore Files from Snapshot"
  echo "============================"
  echo

  list_files_snapshots_menu || { press_enter; return; }

  echo
  echo "Enter snapshot ID to restore (or 'latest' for most recent):"
  read -p "> " snapshot_input

  [[ -z "$snapshot_input" ]] && { print_warning "No snapshot selected"; press_enter; return; }

  local snapshot_id="$snapshot_input"
  if [[ "$snapshot_input" == "latest" ]]; then
    snapshot_id="$(RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$FILES_REPO" snapshots --tag files --json --latest 1 2>/dev/null | grep -o '"short_id":"[^"]*"' | head -1 | cut -d'"' -f4)"
    if [[ -z "$snapshot_id" ]]; then
      print_error "Could not find latest snapshot"
      press_enter
      return
    fi
    print_info "Using latest snapshot: $snapshot_id"
  fi

  # Get snapshot paths
  echo
  print_info "Snapshot contents:"
  local snapshot_paths
  snapshot_paths="$(RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$FILES_REPO" ls "$snapshot_id" --json 2>/dev/null | grep -o '"path":"[^"]*"' | cut -d'"' -f4 | head -20 || true)"
  if [[ -n "$snapshot_paths" ]]; then
    echo "$snapshot_paths" | head -10
    echo "..."
  else
    print_warning "Could not list snapshot contents (snapshot may still be valid)"
  fi
  echo

  echo "Restore options:"
  echo "  1) Restore to original location (overwrites existing files)"
  echo "  2) Restore to custom directory"
  echo "  3) Cancel"
  echo
  read -p "Select option [1-3]: " restore_option

  local target_path=""
  case "$restore_option" in
    1)
      target_path="/"
      echo
      echo -e "${YELLOW}WARNING: This will restore files to their ORIGINAL locations!${NC}"
      echo -e "${YELLOW}Existing files will be OVERWRITTEN!${NC}"
      ;;
    2)
      echo
      read -p "Enter target directory path: " target_path
      if [[ -z "$target_path" ]]; then
        print_warning "No path specified"
        press_enter
        return
      fi
      if [[ ! -d "$target_path" ]]; then
        echo "Directory does not exist. Create it? [y/N]: "
        read -r create_dir
        if [[ "$create_dir" =~ ^[Yy] ]]; then
          mkdir -p "$target_path" || { print_error "Failed to create directory"; press_enter; return; }
        else
          press_enter
          return
        fi
      fi
      ;;
    *)
      print_warning "Restore cancelled"
      press_enter
      return
      ;;
  esac

  echo
  read -p "Type 'yes' to confirm restore to '$target_path': " confirm
  [[ "$confirm" != "yes" ]] && { print_warning "Restore cancelled"; press_enter; return; }

  echo
  print_info "Restoring files from snapshot $snapshot_id..."

  if RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$FILES_REPO" restore "$snapshot_id" --target "$target_path" 2>&1; then
    print_success "Files restored successfully to $target_path"
  else
    print_error "Files restore failed"
  fi

  press_enter
}

# ---------- Main Menu ----------

main_menu() {
  while true; do
    print_header

    echo "What would you like to restore?"
    echo
    echo "  1) Restore database"
    echo "  2) Restore files/sites"
    echo "  3) List database snapshots"
    echo "  4) List files snapshots"
    echo "  5) Exit"
    echo
    read -p "Select option [1-5]: " choice

    case "$choice" in
      1) restore_database_menu ;;
      2) restore_files_menu ;;
      3)
        print_header
        echo "Database Snapshots"
        echo "=================="
        echo
        list_db_snapshots_menu
        press_enter
        ;;
      4)
        print_header
        echo "Files Snapshots"
        echo "==============="
        echo
        list_files_snapshots_menu
        press_enter
        ;;
      5|q|"") exit 0 ;;
      *) print_warning "Invalid option" ;;
    esac
  done
}

# Run main menu
main_menu
RESTOREEOF

  # Replace placeholders
  sed -i \
    -e "s|%%SECRETS_DIR%%|$SECRETS_DIR|g" \
    -e "s|%%RCLONE_REMOTE%%|$RCLONE_REMOTE|g" \
    -e "s|%%RCLONE_DB_PATH%%|$RCLONE_DB_PATH|g" \
    -e "s|%%RCLONE_FILES_PATH%%|$RCLONE_FILES_PATH|g" \
    "$SCRIPTS_DIR/restore.sh"

  chmod +x "$SCRIPTS_DIR/restore.sh"
}

# ---------- Generate Restic Verify Scripts ----------
# Creates two verify scripts:
#   - verify_backup.sh: Weekly quick check (restic check)
#   - verify_full_backup.sh: Monthly full check (restic check --read-data)

generate_restic_verify_script() {
  local SECRETS_DIR="$1"
  local RCLONE_REMOTE="$2"
  local RCLONE_DB_PATH="$3"
  local RCLONE_FILES_PATH="$4"

  local LOGS_DIR="$INSTALL_DIR/logs"
  mkdir -p "$LOGS_DIR"

  # ---------- Generate Quick Verify Script (for weekly runs) ----------
  cat > "$SCRIPTS_DIR/verify_backup.sh" << 'VERIFYEOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077

# ============================================================================
# Backupd v3.0 - Restic Quick Verification Script
# Verifies repository integrity using restic check (metadata only)
# Recommended: Run weekly via systemd timer
# ============================================================================

INSTALL_DIR="/etc/backupd"
source "$INSTALL_DIR/lib/logging.sh"
source "$INSTALL_DIR/lib/debug.sh"
source "$INSTALL_DIR/lib/restic.sh"
source "$INSTALL_DIR/lib/crypto.sh"

# Initialize structured logging (writes to /var/log/backupd.log)
log_init "verify_quick"

SECRETS_DIR="%%SECRETS_DIR%%"
RCLONE_REMOTE="%%RCLONE_REMOTE%%"
RCLONE_DB_PATH="%%RCLONE_DB_PATH%%"
RCLONE_FILES_PATH="%%RCLONE_FILES_PATH%%"
LOGS_DIR="%%LOGS_DIR%%"
HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
LOG_PREFIX="[VERIFY-QUICK]"

# Secret file names
SECRET_PASSPHRASE=".c1"
SECRET_NTFY_TOKEN=".c4"
SECRET_NTFY_URL=".c5"
SECRET_WEBHOOK_URL=".c6"
SECRET_WEBHOOK_TOKEN=".c7"
SECRET_PUSHOVER_USER=".c8"
SECRET_PUSHOVER_TOKEN=".c9"

# Log rotation function
rotate_log() {
  local log_file="$1"
  local max_size=$((10 * 1024 * 1024))  # 10MB
  [[ ! -f "$log_file" ]] && return 0
  local log_size
  log_size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
  if [[ "$log_size" -gt "$max_size" ]]; then
    [[ -f "${log_file}.5" ]] && rm -f "${log_file}.5"
    for ((i=4; i>=1; i--)); do
      [[ -f "${log_file}.${i}" ]] && mv "${log_file}.${i}" "${log_file}.$((i+1))"
    done
    mv "$log_file" "${log_file}.1"
  fi
}

# Logging with rotation
LOG="$LOGS_DIR/verify_logfile.log"
mkdir -p "$LOGS_DIR"
rotate_log "$LOG"
touch "$LOG" && chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1
echo "==== $(date +%F' '%T) START quick verification ===="
STARTED_AT="\$(date -Iseconds)"

# Get restic repository password
RESTIC_PASSWORD="$(get_secret "$SECRETS_DIR" "$SECRET_PASSPHRASE")"
if [[ -z "$RESTIC_PASSWORD" ]]; then
  log_error "No repository password found"
  exit 2
fi

# Get notification credentials
NTFY_URL="$(get_secret "$SECRETS_DIR" "$SECRET_NTFY_URL" || echo "")"
NTFY_TOKEN="$(get_secret "$SECRETS_DIR" "$SECRET_NTFY_TOKEN" || echo "")"
WEBHOOK_URL="$(get_secret "$SECRETS_DIR" "$SECRET_WEBHOOK_URL" || echo "")"
WEBHOOK_TOKEN="$(get_secret "$SECRETS_DIR" "$SECRET_WEBHOOK_TOKEN" || echo "")"
PUSHOVER_USER="$(get_secret "$SECRETS_DIR" "$SECRET_PUSHOVER_USER" || echo "")"
PUSHOVER_TOKEN="$(get_secret "$SECRETS_DIR" "$SECRET_PUSHOVER_TOKEN" || echo "")"

# Notification failure log (ensure it exists with secure permissions)
NOTIFICATION_FAIL_LOG="$LOGS_DIR/notification_failures.log"
touch "$NOTIFICATION_FAIL_LOG" 2>/dev/null && chmod 600 "$NOTIFICATION_FAIL_LOG" 2>/dev/null || true

# Send notification function
send_notification() {
  local title="$1" message="$2" event="${3:-verify}"

  # Send ntfy
  if [[ -n "$NTFY_URL" ]]; then
    local attempt=1 max_attempts=3 delay=2 http_code
    while [[ $attempt -le $max_attempts ]]; do
      if [[ -n "$NTFY_TOKEN" ]]; then
        http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
          -H "Authorization: Bearer $NTFY_TOKEN" -H "Title: $title" \
          -d "$message" "$NTFY_URL" 2>/dev/null) || http_code="000"
      else
        http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
          -H "Title: $title" -d "$message" "$NTFY_URL" 2>/dev/null) || http_code="000"
      fi
      [[ "$http_code" =~ ^2[0-9][0-9]$ ]] && break
      sleep $delay; delay=$((delay * 2)); ((attempt++))
    done
  fi

  # Send webhook
  if [[ -n "$WEBHOOK_URL" ]]; then
    local timestamp json_payload
    timestamp="$(date -Iseconds)"
    json_payload="{\"event\":\"$event\",\"title\":\"$title\",\"hostname\":\"$HOSTNAME\",\"message\":\"$message\",\"timestamp\":\"$timestamp\"}"
    local attempt=1 max_attempts=3 delay=2 http_code
    while [[ $attempt -le $max_attempts ]]; do
      if [[ -n "$WEBHOOK_TOKEN" ]]; then
        http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
          -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" \
          -H "Authorization: Bearer $WEBHOOK_TOKEN" -d "$json_payload" 2>/dev/null) || http_code="000"
      else
        http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
          -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" \
          -d "$json_payload" 2>/dev/null) || http_code="000"
      fi
      [[ "$http_code" =~ ^2[0-9][0-9]$ ]] && break
      sleep $delay; delay=$((delay * 2)); ((attempt++))
    done
  fi

  # Send Pushover
  if [[ -n "$PUSHOVER_USER" && -n "$PUSHOVER_TOKEN" ]]; then
    timeout 15 curl -s -o /dev/null \
      --form-string "token=$PUSHOVER_TOKEN" \
      --form-string "user=$PUSHOVER_USER" \
      --form-string "title=$title" \
      --form-string "message=$message" \
      https://api.pushover.net/1/messages.json 2>/dev/null || true
  fi
}

db_result="SKIPPED"
files_result="SKIPPED"
db_details=""
files_details=""

# Verify database repository (quick check)
if [[ -n "$RCLONE_DB_PATH" ]]; then
  REPO="rclone:${RCLONE_REMOTE}:${RCLONE_DB_PATH}"
  echo "$LOG_PREFIX Checking database repository: $REPO"

  if check_output=$(RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$REPO" check --retry-lock 2m 2>&1); then
    # Use || true to prevent pipefail exit when grep finds no matches
    snapshot_count=$(RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$REPO" snapshots --retry-lock 2m --tag database --json 2>/dev/null | grep -c '"short_id"' || true)
    [[ -z "$snapshot_count" ]] && snapshot_count="0"
    db_result="PASSED"
    db_details="OK, $snapshot_count snapshot(s)"
    echo "$LOG_PREFIX   Database: $db_details"
  else
    db_result="FAILED"
    db_details="Check failed"
    echo "$LOG_PREFIX   Database: FAILED"
    echo "$check_output" | head -5
  fi
fi

# Verify files repository (quick check)
if [[ -n "$RCLONE_FILES_PATH" ]]; then
  REPO="rclone:${RCLONE_REMOTE}:${RCLONE_FILES_PATH}"
  echo "$LOG_PREFIX Checking files repository: $REPO"

  if check_output=$(RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$REPO" check --retry-lock 2m 2>&1); then
    # Use || true to prevent pipefail exit when grep finds no matches
    snapshot_count=$(RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$REPO" snapshots --retry-lock 2m --tag files --json 2>/dev/null | grep -c '"short_id"' || true)
    [[ -z "$snapshot_count" ]] && snapshot_count="0"
    files_result="PASSED"
    files_details="OK, $snapshot_count snapshot(s)"
    echo "$LOG_PREFIX   Files: $files_details"
  else
    files_result="FAILED"
    files_details="Check failed"
    echo "$LOG_PREFIX   Files: FAILED"
    echo "$check_output" | head -5
  fi
fi

# Send notification
if [[ "$db_result" == "FAILED" || "$files_result" == "FAILED" ]]; then
  send_notification "Quick Check FAILED on $HOSTNAME" "DB: $db_result, Files: $files_result" "quick_verify_failed"
  echo "==== $(date +%F' '%T) END (FAILED) ===="
  # Record to history
  ENDED_AT="\$(date -Iseconds)"
  source "\$INSTALL_DIR/lib/history.sh" 2>/dev/null && \
    record_history "verify_quick" "failed" "\$STARTED_AT" "\$ENDED_AT" "" "2" "\$([[ \$db_result == FAILED ]] && echo 1 || echo 0)" "DB: \$db_result, Files: \$files_result"
  exit 1
else
  send_notification "Quick Check PASSED on $HOSTNAME" "DB: $db_result ($db_details), Files: $files_result ($files_details)" "quick_verify_passed"
  echo "==== $(date +%F' '%T) END (success) ===="
  # Record to history
  ENDED_AT="\$(date -Iseconds)"
  source "\$INSTALL_DIR/lib/history.sh" 2>/dev/null && \
    record_history "verify_quick" "success" "\$STARTED_AT" "\$ENDED_AT" "" "2" "0" ""
fi
VERIFYEOF

  # Replace placeholders in quick verify script
  sed -i \
    -e "s|%%SECRETS_DIR%%|$SECRETS_DIR|g" \
    -e "s|%%RCLONE_REMOTE%%|$RCLONE_REMOTE|g" \
    -e "s|%%RCLONE_DB_PATH%%|$RCLONE_DB_PATH|g" \
    -e "s|%%RCLONE_FILES_PATH%%|$RCLONE_FILES_PATH|g" \
    -e "s|%%LOGS_DIR%%|$LOGS_DIR|g" \
    "$SCRIPTS_DIR/verify_backup.sh"

  chmod +x "$SCRIPTS_DIR/verify_backup.sh"

  # ---------- Generate Full Verify Script (for monthly runs) ----------
  cat > "$SCRIPTS_DIR/verify_full_backup.sh" << 'FULLVERIFYEOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077

# ============================================================================
# Backupd v3.0 - Restic Full Verification Script
# Verifies repository integrity using restic check --read-data
# Downloads and verifies ALL backup data
# Recommended: Run monthly via systemd timer
# ============================================================================

INSTALL_DIR="/etc/backupd"
source "$INSTALL_DIR/lib/logging.sh"
source "$INSTALL_DIR/lib/debug.sh"
source "$INSTALL_DIR/lib/restic.sh"
source "$INSTALL_DIR/lib/crypto.sh"

# Initialize structured logging (writes to /var/log/backupd.log)
log_init "verify_full"

SECRETS_DIR="%%SECRETS_DIR%%"
RCLONE_REMOTE="%%RCLONE_REMOTE%%"
RCLONE_DB_PATH="%%RCLONE_DB_PATH%%"
RCLONE_FILES_PATH="%%RCLONE_FILES_PATH%%"
LOGS_DIR="%%LOGS_DIR%%"
HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
LOG_PREFIX="[VERIFY-FULL]"

# Secret file names
SECRET_PASSPHRASE=".c1"
SECRET_NTFY_TOKEN=".c4"
SECRET_NTFY_URL=".c5"
SECRET_WEBHOOK_URL=".c6"
SECRET_WEBHOOK_TOKEN=".c7"
SECRET_PUSHOVER_USER=".c8"
SECRET_PUSHOVER_TOKEN=".c9"

# Log rotation function
rotate_log() {
  local log_file="$1"
  local max_size=$((10 * 1024 * 1024))  # 10MB
  [[ ! -f "$log_file" ]] && return 0
  local log_size
  log_size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
  if [[ "$log_size" -gt "$max_size" ]]; then
    [[ -f "${log_file}.5" ]] && rm -f "${log_file}.5"
    for ((i=4; i>=1; i--)); do
      [[ -f "${log_file}.${i}" ]] && mv "${log_file}.${i}" "${log_file}.$((i+1))"
    done
    mv "$log_file" "${log_file}.1"
  fi
}

# Logging with rotation
LOG="$LOGS_DIR/verify_full_logfile.log"
mkdir -p "$LOGS_DIR"
rotate_log "$LOG"
touch "$LOG" && chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1
echo "==== $(date +%F' '%T) START full verification ===="
STARTED_AT="\$(date -Iseconds)"

# Get restic repository password
RESTIC_PASSWORD="$(get_secret "$SECRETS_DIR" "$SECRET_PASSPHRASE")"
if [[ -z "$RESTIC_PASSWORD" ]]; then
  log_error "No repository password found"
  exit 2
fi

# Get notification credentials
NTFY_URL="$(get_secret "$SECRETS_DIR" "$SECRET_NTFY_URL" || echo "")"
NTFY_TOKEN="$(get_secret "$SECRETS_DIR" "$SECRET_NTFY_TOKEN" || echo "")"
WEBHOOK_URL="$(get_secret "$SECRETS_DIR" "$SECRET_WEBHOOK_URL" || echo "")"
WEBHOOK_TOKEN="$(get_secret "$SECRETS_DIR" "$SECRET_WEBHOOK_TOKEN" || echo "")"
PUSHOVER_USER="$(get_secret "$SECRETS_DIR" "$SECRET_PUSHOVER_USER" || echo "")"
PUSHOVER_TOKEN="$(get_secret "$SECRETS_DIR" "$SECRET_PUSHOVER_TOKEN" || echo "")"

# Notification failure log (ensure it exists with secure permissions)
NOTIFICATION_FAIL_LOG="$LOGS_DIR/notification_failures.log"
touch "$NOTIFICATION_FAIL_LOG" 2>/dev/null && chmod 600 "$NOTIFICATION_FAIL_LOG" 2>/dev/null || true

# Send notification function
send_notification() {
  local title="$1" message="$2" event="${3:-verify}" priority="${4:-0}"

  # Send ntfy
  if [[ -n "$NTFY_URL" ]]; then
    local attempt=1 max_attempts=3 delay=2 http_code
    while [[ $attempt -le $max_attempts ]]; do
      if [[ -n "$NTFY_TOKEN" ]]; then
        http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
          -H "Authorization: Bearer $NTFY_TOKEN" -H "Title: $title" \
          -d "$message" "$NTFY_URL" 2>/dev/null) || http_code="000"
      else
        http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
          -H "Title: $title" -d "$message" "$NTFY_URL" 2>/dev/null) || http_code="000"
      fi
      [[ "$http_code" =~ ^2[0-9][0-9]$ ]] && break
      sleep $delay; delay=$((delay * 2)); ((attempt++))
    done
  fi

  # Send webhook
  if [[ -n "$WEBHOOK_URL" ]]; then
    local timestamp json_payload
    timestamp="$(date -Iseconds)"
    json_payload="{\"event\":\"$event\",\"title\":\"$title\",\"hostname\":\"$HOSTNAME\",\"message\":\"$message\",\"timestamp\":\"$timestamp\"}"
    local attempt=1 max_attempts=3 delay=2 http_code
    while [[ $attempt -le $max_attempts ]]; do
      if [[ -n "$WEBHOOK_TOKEN" ]]; then
        http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
          -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" \
          -H "Authorization: Bearer $WEBHOOK_TOKEN" -d "$json_payload" 2>/dev/null) || http_code="000"
      else
        http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
          -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" \
          -d "$json_payload" 2>/dev/null) || http_code="000"
      fi
      [[ "$http_code" =~ ^2[0-9][0-9]$ ]] && break
      sleep $delay; delay=$((delay * 2)); ((attempt++))
    done
  fi

  # Send Pushover (with priority support for failures)
  if [[ -n "$PUSHOVER_USER" && -n "$PUSHOVER_TOKEN" ]]; then
    timeout 15 curl -s -o /dev/null \
      --form-string "token=$PUSHOVER_TOKEN" \
      --form-string "user=$PUSHOVER_USER" \
      --form-string "title=$title" \
      --form-string "message=$message" \
      --form-string "priority=$priority" \
      https://api.pushover.net/1/messages.json 2>/dev/null || true
  fi
}

db_result="SKIPPED"
files_result="SKIPPED"
db_details=""
files_details=""
total_duration=0

# Full verify database repository (downloads all data)
if [[ -n "$RCLONE_DB_PATH" ]]; then
  REPO="rclone:${RCLONE_REMOTE}:${RCLONE_DB_PATH}"
  echo "$LOG_PREFIX Full verification: Database repository"
  echo "$LOG_PREFIX   Repository: $REPO"
  echo "$LOG_PREFIX   This will download and verify all data..."

  start_time=$(date +%s)

  if check_output=$(RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$REPO" check --read-data --retry-lock 2m 2>&1); then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    total_duration=$((total_duration + duration))

    # Use || true to prevent pipefail exit when grep finds no matches
    snapshot_count=$(RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$REPO" snapshots --retry-lock 2m --tag database --json 2>/dev/null | grep -c '"short_id"' || true)
    [[ -z "$snapshot_count" ]] && snapshot_count="0"
    repo_stats=$(RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$REPO" stats --json 2>/dev/null || echo "{}")
    total_size=$(echo "$repo_stats" | grep -o '"total_size":[0-9]*' | cut -d':' -f2 || true)
    total_size_human=$(numfmt --to=iec-i --suffix=B "$total_size" 2>/dev/null || echo "${total_size:-0}B")

    db_result="PASSED"
    db_details="$snapshot_count snapshots, $total_size_human verified in ${duration}s"
    echo "$LOG_PREFIX   Database: PASSED ($db_details)"
  else
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    total_duration=$((total_duration + duration))

    db_result="FAILED"
    db_details="Verification failed after ${duration}s"
    echo "$LOG_PREFIX   Database: FAILED"
    echo "$check_output" | head -10
  fi
fi

# Full verify files repository (downloads all data)
if [[ -n "$RCLONE_FILES_PATH" ]]; then
  REPO="rclone:${RCLONE_REMOTE}:${RCLONE_FILES_PATH}"
  echo "$LOG_PREFIX Full verification: Files repository"
  echo "$LOG_PREFIX   Repository: $REPO"
  echo "$LOG_PREFIX   This will download and verify all data..."

  start_time=$(date +%s)

  if check_output=$(RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$REPO" check --read-data --retry-lock 2m 2>&1); then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    total_duration=$((total_duration + duration))

    # Use || true to prevent pipefail exit when grep finds no matches
    snapshot_count=$(RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$REPO" snapshots --retry-lock 2m --tag files --json 2>/dev/null | grep -c '"short_id"' || true)
    [[ -z "$snapshot_count" ]] && snapshot_count="0"
    repo_stats=$(RESTIC_PASSWORD="$RESTIC_PASSWORD" restic -r "$REPO" stats --json 2>/dev/null || echo "{}")
    total_size=$(echo "$repo_stats" | grep -o '"total_size":[0-9]*' | cut -d':' -f2 || true)
    total_size_human=$(numfmt --to=iec-i --suffix=B "$total_size" 2>/dev/null || echo "${total_size:-0}B")

    files_result="PASSED"
    files_details="$snapshot_count snapshots, $total_size_human verified in ${duration}s"
    echo "$LOG_PREFIX   Files: PASSED ($files_details)"
  else
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    total_duration=$((total_duration + duration))

    files_result="FAILED"
    files_details="Verification failed after ${duration}s"
    echo "$LOG_PREFIX   Files: FAILED"
    echo "$check_output" | head -10
  fi
fi

# Update full verification timestamp
LAST_FULL_VERIFY_FILE="$INSTALL_DIR/.last_full_verify"
if [[ "$db_result" == "PASSED" || "$files_result" == "PASSED" ]]; then
  date +%s > "$LAST_FULL_VERIFY_FILE"
  chmod 600 "$LAST_FULL_VERIFY_FILE" 2>/dev/null
fi

# Send notification
if [[ "$db_result" == "FAILED" || "$files_result" == "FAILED" ]]; then
  send_notification "Full Verification FAILED on $HOSTNAME" "DB: $db_result, Files: $files_result. Total time: ${total_duration}s" "full_verify_failed" "1"
  echo "==== $(date +%F' '%T) END (FAILED, ${total_duration}s total) ===="
  # Record to history
  ENDED_AT="\$(date -Iseconds)"
  source "\$INSTALL_DIR/lib/history.sh" 2>/dev/null && \
    record_history "verify_full" "failed" "\$STARTED_AT" "\$ENDED_AT" "" "2" "\$([[ \$db_result == FAILED ]] && echo 1 || echo 0)" "DB: \$db_result, Files: \$files_result"
  exit 1
else
  send_notification "Full Verification PASSED on $HOSTNAME" "DB: $db_result ($db_details), Files: $files_result ($files_details). Total: ${total_duration}s" "full_verify_passed" "0"
  echo "==== $(date +%F' '%T) END (success, ${total_duration}s total) ===="
  # Record to history
  ENDED_AT="\$(date -Iseconds)"
  source "\$INSTALL_DIR/lib/history.sh" 2>/dev/null && \
    record_history "verify_full" "success" "\$STARTED_AT" "\$ENDED_AT" "" "2" "0" ""
fi
FULLVERIFYEOF

  # Replace placeholders in full verify script
  sed -i \
    -e "s|%%SECRETS_DIR%%|$SECRETS_DIR|g" \
    -e "s|%%RCLONE_REMOTE%%|$RCLONE_REMOTE|g" \
    -e "s|%%RCLONE_DB_PATH%%|$RCLONE_DB_PATH|g" \
    -e "s|%%RCLONE_FILES_PATH%%|$RCLONE_FILES_PATH|g" \
    -e "s|%%LOGS_DIR%%|$LOGS_DIR|g" \
    "$SCRIPTS_DIR/verify_full_backup.sh"

  chmod +x "$SCRIPTS_DIR/verify_full_backup.sh"
}

# ---------- Wrapper for legacy function name ----------
# Called by setup.sh, schedule.sh, notifications.sh without parameters
# Uses global config variables from the sourced config

generate_verify_script() {
  # Load config if not already loaded
  [[ -z "${SECRETS_DIR:-}" ]] && source "$INSTALL_DIR/backupd.conf" 2>/dev/null || true

  # Call the restic verify script generator with config values
  # This generates BOTH verify_backup.sh (quick) and verify_full_backup.sh (full)
  generate_restic_verify_script \
    "${SECRETS_DIR:-}" \
    "${RCLONE_REMOTE:-}" \
    "${RCLONE_DB_PATH:-}" \
    "${RCLONE_FILES_PATH:-}"
}

# Wrapper for full verify script (same function generates both scripts)
generate_full_verify_script() {
  # generate_restic_verify_script creates both quick and full scripts
  # Only regenerate if the full script doesn't exist
  if [[ ! -f "$SCRIPTS_DIR/verify_full_backup.sh" ]]; then
    generate_verify_script
  fi
}
