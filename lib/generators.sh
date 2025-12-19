#!/usr/bin/env bash
# ============================================================================
# Backupd - Generators Module
# Script generation functions for backup/restore/verify scripts
# ============================================================================

# ---------- Embedded Crypto Functions Generator ----------

# Generate the crypto functions to embed in scripts
# These are version-aware and support Argon2id + PBKDF2
generate_embedded_crypto() {
  local secrets_dir="$1"
  local version iterations

  version="$(get_crypto_version "$secrets_dir")"
  iterations="$(get_pbkdf2_iterations "$version")"

  cat << 'EMBEDDEDCRYPTOEOF'
# Crypto version and iterations (set at script generation time)
EMBEDDEDCRYPTOEOF

  echo "CRYPTO_VERSION=$version"
  echo "PBKDF2_ITERATIONS=$iterations"

  cat << 'EMBEDDEDCRYPTOEOF'

# Argon2id parameters
ARGON2_TIME=3
ARGON2_MEMORY=16
ARGON2_PARALLEL=4
ARGON2_LENGTH=32

get_machine_id() {
  if [[ -f /etc/machine-id ]]; then
    cat /etc/machine-id
  elif [[ -f /var/lib/dbus/machine-id ]]; then
    cat /var/lib/dbus/machine-id
  else
    echo "$(hostname)$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo 'fallback')"
  fi
}

derive_key_sha256() {
  local secrets_dir="$1"
  local machine_id salt
  machine_id="$(get_machine_id)"
  salt="$(cat "$secrets_dir/.s")"
  echo -n "${machine_id}${salt}" | sha256sum | cut -d' ' -f1
}

derive_key_argon2id() {
  local secrets_dir="$1"
  local machine_id salt
  machine_id="$(get_machine_id)"
  salt="$(cat "$secrets_dir/.s")"
  echo -n "${machine_id}${salt}" | argon2 "${salt:0:16}" -id \
    -t "$ARGON2_TIME" -m "$ARGON2_MEMORY" -p "$ARGON2_PARALLEL" -l "$ARGON2_LENGTH" -r
}

derive_key() {
  local secrets_dir="$1"
  if [[ "$CRYPTO_VERSION" == "3" ]]; then
    if command -v argon2 &>/dev/null; then
      derive_key_argon2id "$secrets_dir"
    else
      echo "[ERROR] Argon2 required but not installed. Run: sudo apt install argon2" >&2
      return 1
    fi
  else
    derive_key_sha256 "$secrets_dir"
  fi
}

get_secret() {
  local secrets_dir="$1" secret_name="$2" key
  [[ ! -f "$secrets_dir/$secret_name" ]] && return 1
  key="$(derive_key "$secrets_dir")" || return 1
  openssl enc -aes-256-cbc -pbkdf2 -iter "$PBKDF2_ITERATIONS" -d -salt -pass "pass:$key" -base64 -in "$secrets_dir/$secret_name" 2>/dev/null || echo ""
}
EMBEDDEDCRYPTOEOF
}

# ---------- Generate All Scripts ----------

generate_all_scripts() {
  local SECRETS_DIR="$1"
  local DO_DATABASE="$2"
  local DO_FILES="$3"
  local RCLONE_REMOTE="$4"
  local RCLONE_DB_PATH="$5"
  local RCLONE_FILES_PATH="$6"
  local RETENTION_MINUTES="${7:-0}"
  local WEB_PATH_PATTERN="${8:-/var/www/*}"
  local WEBROOT_SUBDIR="${9:-.}"

  local LOGS_DIR="$INSTALL_DIR/logs"
  mkdir -p "$LOGS_DIR"

  # Generate database backup script
  if [[ "$DO_DATABASE" == "true" ]]; then
    generate_db_backup_script "$SECRETS_DIR" "$RCLONE_REMOTE" "$RCLONE_DB_PATH" "$LOGS_DIR" "$RETENTION_MINUTES"
    generate_db_restore_script "$SECRETS_DIR" "$RCLONE_REMOTE" "$RCLONE_DB_PATH"
    print_success "Database backup script generated"
    print_success "Database restore script generated"
  fi

  # Generate files backup script
  if [[ "$DO_FILES" == "true" ]]; then
    generate_files_backup_script "$SECRETS_DIR" "$RCLONE_REMOTE" "$RCLONE_FILES_PATH" "$LOGS_DIR" "$RETENTION_MINUTES" "$WEB_PATH_PATTERN" "$WEBROOT_SUBDIR"
    generate_files_restore_script "$RCLONE_REMOTE" "$RCLONE_FILES_PATH"
    print_success "Files backup script generated"
    print_success "Files restore script generated"
  fi
}

# ---------- Generate Database Backup Script ----------

generate_db_backup_script() {
  local SECRETS_DIR="$1"
  local RCLONE_REMOTE="$2"
  local RCLONE_PATH="$3"
  local LOGS_DIR="$4"
  local RETENTION_MINUTES="${5:-0}"

  cat > "$SCRIPTS_DIR/db_backup.sh" << 'DBBACKUPEOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="%%LOGS_DIR%%"
RCLONE_REMOTE="%%RCLONE_REMOTE%%"
RCLONE_PATH="%%RCLONE_PATH%%"
SECRETS_DIR="%%SECRETS_DIR%%"
HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
RETENTION_MINUTES="%%RETENTION_MINUTES%%"

# Lock file in fixed location
LOCK_FILE="/var/lock/backupd-db.lock"

SECRET_PASSPHRASE=".c1"
SECRET_DB_USER=".c2"
SECRET_DB_PASS=".c3"
SECRET_NTFY_TOKEN=".c4"
SECRET_NTFY_URL=".c5"

# Cleanup function
TEMP_DIR=""
MYSQL_AUTH_FILE=""
cleanup() {
  local exit_code=$?
  [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
  [[ -n "$MYSQL_AUTH_FILE" && -f "$MYSQL_AUTH_FILE" ]] && rm -f "$MYSQL_AUTH_FILE"
  exit $exit_code
}
trap cleanup EXIT INT TERM

%%CRYPTO_FUNCTIONS%%

# Acquire lock (fixed location so it works across runs)
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "[INFO] Another database backup is running. Exiting."
  exit 0
fi

# Create temp directory
TEMP_DIR="$(mktemp -d)"

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
STAMP="$(date +%F-%H%M)"
LOG="$LOGS_DIR/db_logfile.log"
mkdir -p "$LOGS_DIR"
rotate_log "$LOG"
touch "$LOG" && chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1
echo "==== $(date +%F' '%T) START per-db backup ===="

# Check disk space (need at least 1GB free in temp)
AVAIL_MB=$(df -m /tmp 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
if [[ "$AVAIL_MB" -lt 1000 ]]; then
  echo "[ERROR] Insufficient disk space in /tmp (${AVAIL_MB}MB available, 1000MB required)"
  exit 3
fi

# Get secrets
PASSPHRASE="$(get_secret "$SECRETS_DIR" "$SECRET_PASSPHRASE")"
[[ -z "$PASSPHRASE" ]] && { echo "[ERROR] No passphrase found"; exit 2; }

NTFY_URL="$(get_secret "$SECRETS_DIR" "$SECRET_NTFY_URL" || echo "")"
NTFY_TOKEN="$(get_secret "$SECRETS_DIR" "$SECRET_NTFY_TOKEN" || echo "")"

send_notification() {
  local title="$1" message="$2"
  [[ -z "$NTFY_URL" ]] && return 0
  # Timeout for notification
  if [[ -n "$NTFY_TOKEN" ]]; then
    timeout 10 curl -s -H "Authorization: Bearer $NTFY_TOKEN" -H "Title: $title" -d "$message" "$NTFY_URL" >/dev/null 2>&1 || true
  else
    timeout 10 curl -s -H "Title: $title" -d "$message" "$NTFY_URL" >/dev/null 2>&1 || true
  fi
}

[[ -n "$NTFY_URL" ]] && send_notification "DB Backup Started on $HOSTNAME" "Starting at $(date)"

# Compressor
if command -v pigz >/dev/null 2>&1; then
  COMPRESSOR="pigz -9 -p $(nproc 2>/dev/null || echo 2)"
else
  COMPRESSOR="gzip -9"
fi

# DB client
if command -v mariadb >/dev/null 2>&1; then
  DB_CLIENT="mariadb"; DB_DUMP="mariadb-dump"
elif command -v mysql >/dev/null 2>&1; then
  DB_CLIENT="mysql"; DB_DUMP="mysqldump"
else
  echo "[ERROR] No database client found"; exit 5
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

EXCLUDE_REGEX='^(information_schema|performance_schema|sys|mysql)$'
DBS="$($DB_CLIENT "${MYSQL_ARGS[@]}" -NBe 'SHOW DATABASES' 2>/dev/null | grep -Ev "$EXCLUDE_REGEX" || true)"

if [[ -z "$DBS" ]]; then
  echo "[ERROR] No databases found or cannot connect to database"
  [[ -n "$NTFY_URL" ]] && send_notification "DB Backup Failed on $HOSTNAME" "No databases found"
  exit 6
fi

DEST="$TEMP_DIR/$STAMP"
mkdir -p "$DEST"

declare -a failures=()
db_count=0
for db in $DBS; do
  echo "  -> Dumping: $db"
  if "$DB_DUMP" "${MYSQL_ARGS[@]}" --databases "$db" --single-transaction --quick \
      --routines --events --triggers --hex-blob --default-character-set=utf8mb4 \
      2>/dev/null | $COMPRESSOR > "$DEST/${db}-${STAMP}.sql.gz"; then
    echo "    OK: $db"
    ((db_count++)) || true
  else
    echo "    FAILED: $db"
    failures+=("$db")
  fi
done

if [[ $db_count -eq 0 ]]; then
  echo "[ERROR] All database dumps failed"
  [[ -n "$NTFY_URL" ]] && send_notification "DB Backup Failed on $HOSTNAME" "All dumps failed"
  exit 7
fi

# Archive + encrypt
ARCHIVE="$TEMP_DIR/${HOSTNAME}-db_backups-${STAMP}.tar.gz.gpg"
echo "Creating encrypted archive..."
tar -C "$TEMP_DIR" -cf - "$STAMP" | $COMPRESSOR | \
  gpg --batch --yes --pinentry-mode=loopback --passphrase "$PASSPHRASE" --symmetric --cipher-algo AES256 -o "$ARCHIVE"

# Verify archive
echo "Verifying archive..."
if ! gpg --batch --quiet --pinentry-mode=loopback --passphrase "$PASSPHRASE" -d "$ARCHIVE" 2>/dev/null | tar -tzf - >/dev/null 2>&1; then
  echo "[ERROR] Archive verification failed"
  [[ -n "$NTFY_URL" ]] && send_notification "DB Backup Failed on $HOSTNAME" "Archive verification failed"
  exit 4
fi
echo "Archive verified."

# Generate checksum
echo "Generating checksum..."
CHECKSUM_FILE="${ARCHIVE}.sha256"
sha256sum "$ARCHIVE" | awk '{print $1}' > "$CHECKSUM_FILE"
echo "Checksum: $(cat "$CHECKSUM_FILE")"

# Upload with timeout and retry
echo "Uploading to remote storage..."
RCLONE_TIMEOUT=1800  # 30 minutes
if ! timeout $RCLONE_TIMEOUT rclone copy "$ARCHIVE" "$RCLONE_REMOTE:$RCLONE_PATH" --retries 3 --low-level-retries 10; then
  echo "[ERROR] Upload failed"
  [[ -n "$NTFY_URL" ]] && send_notification "DB Backup Failed on $HOSTNAME" "Upload failed"
  exit 8
fi

# Upload checksum file
if ! timeout 60 rclone copy "$CHECKSUM_FILE" "$RCLONE_REMOTE:$RCLONE_PATH" --retries 3; then
  echo "[WARNING] Checksum upload failed, but backup succeeded"
fi

# Verify upload
if ! timeout 60 rclone check "$(dirname "$ARCHIVE")" "$RCLONE_REMOTE:$RCLONE_PATH" --one-way --size-only --include "$(basename "$ARCHIVE")" 2>/dev/null; then
  echo "[WARNING] Upload verification could not complete, but upload may have succeeded"
fi

echo "Uploaded to $RCLONE_REMOTE:$RCLONE_PATH"

# Retention cleanup
if [[ "$RETENTION_MINUTES" -gt 0 ]]; then
  echo "Running retention cleanup (keeping backups newer than $RETENTION_MINUTES minutes)..."
  cleanup_count=0
  cleanup_errors=0
  cutoff_time=$(date -d "-$RETENTION_MINUTES minutes" +%s 2>/dev/null || date -v-${RETENTION_MINUTES}M +%s 2>/dev/null || echo 0)

  if [[ "$cutoff_time" -gt 0 ]]; then
    # List remote files and check their age
    while IFS= read -r remote_file; do
      [[ -z "$remote_file" ]] && continue
      # Get file modification time from rclone
      file_time=$(rclone lsl "$RCLONE_REMOTE:$RCLONE_PATH/$remote_file" 2>&1 | awk '{print $2" "$3}' | head -1)
      if [[ -n "$file_time" && ! "$file_time" =~ ^ERROR ]]; then
        file_epoch=$(date -d "$file_time" +%s 2>/dev/null || echo 0)
        if [[ "$file_epoch" -gt 0 && "$file_epoch" -lt "$cutoff_time" ]]; then
          echo "  Deleting old backup: $remote_file"
          delete_output=$(rclone delete "$RCLONE_REMOTE:$RCLONE_PATH/$remote_file" 2>&1)
          if [[ $? -eq 0 ]]; then
            ((cleanup_count++)) || true
            # Also delete corresponding checksum file
            rclone delete "$RCLONE_REMOTE:$RCLONE_PATH/${remote_file}.sha256" 2>/dev/null || true
          else
            echo "  [ERROR] Failed to delete $remote_file: $delete_output"
            ((cleanup_errors++)) || true
          fi
        fi
      fi
    done < <(rclone lsf "$RCLONE_REMOTE:$RCLONE_PATH" --include "*-db_backups-*.tar.gz.gpg" 2>&1)

    if [[ $cleanup_errors -gt 0 ]]; then
      echo "[WARNING] Retention cleanup completed with $cleanup_errors error(s). Removed $cleanup_count old backup(s)."
      [[ -n "$NTFY_URL" ]] && send_notification "DB Retention Cleanup Warning on $HOSTNAME" "Removed: $cleanup_count, Errors: $cleanup_errors"
    elif [[ $cleanup_count -gt 0 ]]; then
      echo "Retention cleanup complete. Removed $cleanup_count old backup(s)."
      [[ -n "$NTFY_URL" ]] && send_notification "DB Retention Cleanup on $HOSTNAME" "Removed $cleanup_count old backup(s)"
    else
      echo "Retention cleanup complete. No old backups to remove."
    fi
  else
    echo "  [WARNING] Could not calculate cutoff time, skipping cleanup"
    [[ -n "$NTFY_URL" ]] && send_notification "DB Retention Cleanup Failed on $HOSTNAME" "Could not calculate cutoff time"
  fi
fi

if ((${#failures[@]})); then
  [[ -n "$NTFY_URL" ]] && send_notification "DB Backup Completed with Errors on $HOSTNAME" "Backed up: $db_count, Failed: ${failures[*]}"
  echo "==== $(date +%F' '%T) END (with errors) ===="
  exit 1
else
  [[ -n "$NTFY_URL" ]] && send_notification "DB Backup Successful on $HOSTNAME" "All $db_count databases backed up"
  echo "==== $(date +%F' '%T) END (success) ===="
fi
DBBACKUPEOF

  # Generate crypto functions and inject them
  local crypto_functions
  crypto_functions="$(generate_embedded_crypto "$SECRETS_DIR")"

  # Create temp file with crypto functions for sed
  local crypto_temp
  crypto_temp="$(mktemp)"
  echo "$crypto_functions" > "$crypto_temp"

  # Replace placeholders
  sed -i \
    -e "s|%%LOGS_DIR%%|$LOGS_DIR|g" \
    -e "s|%%RCLONE_REMOTE%%|$RCLONE_REMOTE|g" \
    -e "s|%%RCLONE_PATH%%|$RCLONE_PATH|g" \
    -e "s|%%SECRETS_DIR%%|$SECRETS_DIR|g" \
    -e "s|%%RETENTION_MINUTES%%|$RETENTION_MINUTES|g" \
    "$SCRIPTS_DIR/db_backup.sh"

  # Replace crypto functions placeholder (multi-line)
  sed -i -e "/%%CRYPTO_FUNCTIONS%%/{r $crypto_temp" -e "d}" "$SCRIPTS_DIR/db_backup.sh"

  rm -f "$crypto_temp"
  chmod +x "$SCRIPTS_DIR/db_backup.sh"
}

# ---------- Generate Database Restore Script ----------

generate_db_restore_script() {
  local SECRETS_DIR="$1"
  local RCLONE_REMOTE="$2"
  local RCLONE_PATH="$3"

  cat > "$SCRIPTS_DIR/db_restore.sh" << 'DBRESTOREEOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077

RCLONE_REMOTE="%%RCLONE_REMOTE%%"
RCLONE_PATH="%%RCLONE_PATH%%"
SECRETS_DIR="%%SECRETS_DIR%%"
LOG_PREFIX="[DB-RESTORE]"

# Use same lock as backup to prevent conflicts
LOCK_FILE="/var/lock/backupd-db.lock"

SECRET_DB_USER=".c2"
SECRET_DB_PASS=".c3"

%%CRYPTO_FUNCTIONS%%

# Acquire lock (wait up to 60 seconds if backup is running)
exec 9>"$LOCK_FILE"
if ! flock -w 60 9; then
  echo "$LOG_PREFIX ERROR: Could not acquire lock. A backup may be running."
  echo "$LOG_PREFIX Please wait for the backup to complete and try again."
  exit 1
fi

echo "========================================================"
echo "           Database Restore Utility"
echo "========================================================"
echo

# DB client
if command -v mariadb >/dev/null 2>&1; then DB_CLIENT="mariadb"
elif command -v mysql >/dev/null 2>&1; then DB_CLIENT="mysql"
else echo "$LOG_PREFIX ERROR: No database client found."; exit 1; fi

# Get DB credentials and create auth file (more secure than command line)
DB_USER="$(get_secret "$SECRETS_DIR" "$SECRET_DB_USER" || echo "")"
DB_PASS="$(get_secret "$SECRETS_DIR" "$SECRET_DB_PASS" || echo "")"
MYSQL_ARGS=()
MYSQL_AUTH_FILE=""

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

# Cleanup function
cleanup_restore() {
  [[ -n "$MYSQL_AUTH_FILE" && -f "$MYSQL_AUTH_FILE" ]] && rm -f "$MYSQL_AUTH_FILE"
}

TEMP_DIR="$(mktemp -d)"
trap "rm -rf '$TEMP_DIR'; cleanup_restore" EXIT

echo "Step 1: Encryption Password"
echo "----------------------------"
read -sp "Enter backup encryption password: " RESTORE_PASSWORD
echo
echo

echo "Step 2: Select Backup"
echo "---------------------"
echo "$LOG_PREFIX Fetching backups from $RCLONE_REMOTE:$RCLONE_PATH..."

declare -a ALL_BACKUPS=()
remote_files="$(rclone lsf "$RCLONE_REMOTE:$RCLONE_PATH" --include "*.tar.gz.gpg" 2>/dev/null | sort -r)" || true
while IFS= read -r f; do [[ -n "$f" ]] && ALL_BACKUPS+=("$f"); done <<< "$remote_files"

echo "$LOG_PREFIX Found ${#ALL_BACKUPS[@]} backup(s)."
[[ ${#ALL_BACKUPS[@]} -eq 0 ]] && { echo "$LOG_PREFIX No backups found."; exit 1; }

echo
for i in "${!ALL_BACKUPS[@]}"; do
  printf "  %2d) %s\n" "$((i+1))" "${ALL_BACKUPS[$i]}"
done
echo
read -p "Select backup [1-${#ALL_BACKUPS[@]}]: " sel
[[ ! "$sel" =~ ^[0-9]+$ ]] && exit 1
SELECTED="${ALL_BACKUPS[$((sel-1))]}"

echo
echo "$LOG_PREFIX Downloading $SELECTED..."
rclone copy "$RCLONE_REMOTE:$RCLONE_PATH/$SELECTED" "$TEMP_DIR/" --progress

# Download and verify checksum if available
CHECKSUM_FILE="${SELECTED}.sha256"
if rclone copy "$RCLONE_REMOTE:$RCLONE_PATH/$CHECKSUM_FILE" "$TEMP_DIR/" 2>/dev/null; then
  echo "$LOG_PREFIX Verifying checksum..."
  STORED_CHECKSUM=$(cat "$TEMP_DIR/$CHECKSUM_FILE")
  CALCULATED_CHECKSUM=$(sha256sum "$TEMP_DIR/$SELECTED" | awk '{print $1}')
  if [[ "$STORED_CHECKSUM" == "$CALCULATED_CHECKSUM" ]]; then
    echo "$LOG_PREFIX Checksum verified"
  else
    echo "$LOG_PREFIX [ERROR] Checksum mismatch! Backup may be corrupted."
    echo "$LOG_PREFIX   Expected: $STORED_CHECKSUM"
    echo "$LOG_PREFIX   Got:      $CALCULATED_CHECKSUM"
    read -p "Continue anyway? (y/N): " continue_anyway
    [[ ! "$continue_anyway" =~ ^[Yy]$ ]] && exit 1
  fi
else
  echo "$LOG_PREFIX [INFO] No checksum file found (backup may predate checksum feature)"
fi

echo "$LOG_PREFIX Decrypting..."
EXTRACT_DIR="$TEMP_DIR/extracted"
mkdir -p "$EXTRACT_DIR"
gpg --batch --quiet --pinentry-mode=loopback --passphrase "$RESTORE_PASSWORD" -d "$TEMP_DIR/$SELECTED" | tar -xzf - -C "$EXTRACT_DIR"

EXTRACTED_DIR="$(find "$EXTRACT_DIR" -maxdepth 1 -type d ! -path "$EXTRACT_DIR" | head -1)"
[[ -z "$EXTRACTED_DIR" ]] && EXTRACTED_DIR="$EXTRACT_DIR"

echo
echo "Step 3: Select Databases"
echo "------------------------"
mapfile -t SQL_FILES < <(find "$EXTRACTED_DIR" -name "*.sql.gz" -type f | sort)
[[ ${#SQL_FILES[@]} -eq 0 ]] && { echo "No databases found in backup."; exit 1; }

for i in "${!SQL_FILES[@]}"; do
  db_name="$(basename "${SQL_FILES[$i]}" | sed -E 's/-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4}\.sql\.gz$//')"
  printf "  %2d) %s\n" "$((i+1))" "$db_name"
done
echo "  A) All databases"
echo "  Q) Quit"
echo
read -p "Selection: " db_sel

[[ "$db_sel" =~ ^[Qq]$ ]] && exit 0

declare -a SELECTED_DBS=()
if [[ "$db_sel" =~ ^[Aa]$ ]]; then
  SELECTED_DBS=("${SQL_FILES[@]}")
else
  IFS=',' read -ra sels <<< "$db_sel"
  for s in "${sels[@]}"; do
    s="$(echo "$s" | tr -d ' ')"
    [[ "$s" =~ ^[0-9]+$ ]] && SELECTED_DBS+=("${SQL_FILES[$((s-1))]}")
  done
fi

echo
echo "Restoring ${#SELECTED_DBS[@]} database(s)..."
read -p "Confirm? (yes/no): " confirm
[[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]] && exit 0

declare -a RESTORED_FILES=()
declare -a RESTORED_NAMES=()

for sql_file in "${SELECTED_DBS[@]}"; do
  db_name="$(basename "$sql_file" | sed -E 's/-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4}\.sql\.gz$//')"
  echo "Restoring: $db_name"
  if gunzip -c "$sql_file" | $DB_CLIENT "${MYSQL_ARGS[@]}" 2>/dev/null; then
    echo "  Success"
    RESTORED_FILES+=("$sql_file")
    RESTORED_NAMES+=("$db_name")
  else
    echo "  Failed"
  fi
done

echo
echo "========================================================"
echo "           IMPORTANT: Verify Your Site"
echo "========================================================"
echo
echo "Database restore completed. Before we clean up the backup"
echo "files, please verify that your website is working correctly."
echo
echo "Check your website now, then return here."
echo
echo "------------------------------------------------------------------------"
echo "If your site is working correctly:"
echo "  Type exactly: Yes, I checked the website"
echo
echo "If your site is NOT working (quick option):"
echo "  Type: N"
echo "  (We will save the SQL files to /root/ for manual recovery)"
echo "------------------------------------------------------------------------"
echo
read -p "Your response: " VERIFY_RESPONSE

if [[ "$VERIFY_RESPONSE" == "Yes, I checked the website" ]]; then
  echo
  echo "$LOG_PREFIX Site verified. Cleaning up backup files..."
  echo "$LOG_PREFIX Restore complete!"
elif [[ "$VERIFY_RESPONSE" =~ ^[Nn]$ ]]; then
  echo
  echo "$LOG_PREFIX Site not working. Saving SQL files for manual recovery..."

  # Create recovery directory
  RECOVERY_DIR="/root/db-restore-recovery-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$RECOVERY_DIR"
  chmod 700 "$RECOVERY_DIR"

  # Copy all restored SQL files
  for sql_file in "${RESTORED_FILES[@]}"; do
    cp "$sql_file" "$RECOVERY_DIR/"
    echo "$LOG_PREFIX   Saved: $(basename "$sql_file")"
  done

  echo
  echo "========================================================"
  echo "           SQL Files Saved"
  echo "========================================================"
  echo
  echo "Your SQL backup files have been saved to:"
  echo "  $RECOVERY_DIR"
  echo
  echo "To manually restore a database:"
  echo "  gunzip -c $RECOVERY_DIR/DBNAME-*.sql.gz | mysql DBNAME"
  echo
  echo "Or to view the SQL without restoring:"
  echo "  gunzip -c $RECOVERY_DIR/DBNAME-*.sql.gz | less"
  echo
  echo "Remember to delete these files after you're done:"
  echo "  rm -rf $RECOVERY_DIR"
  echo
else
  echo
  echo "$LOG_PREFIX Invalid response. Saving SQL files as a precaution..."

  # Create recovery directory
  RECOVERY_DIR="/root/db-restore-recovery-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$RECOVERY_DIR"
  chmod 700 "$RECOVERY_DIR"

  # Copy all restored SQL files
  for sql_file in "${RESTORED_FILES[@]}"; do
    cp "$sql_file" "$RECOVERY_DIR/"
    echo "$LOG_PREFIX   Saved: $(basename "$sql_file")"
  done

  echo
  echo "SQL files saved to: $RECOVERY_DIR"
  echo "Delete after verification: rm -rf $RECOVERY_DIR"
fi

echo
echo "Done."
DBRESTOREEOF

  # Generate crypto functions and inject them
  local crypto_functions
  crypto_functions="$(generate_embedded_crypto "$SECRETS_DIR")"

  local crypto_temp
  crypto_temp="$(mktemp)"
  echo "$crypto_functions" > "$crypto_temp"

  sed -i \
    -e "s|%%RCLONE_REMOTE%%|$RCLONE_REMOTE|g" \
    -e "s|%%RCLONE_PATH%%|$RCLONE_PATH|g" \
    -e "s|%%SECRETS_DIR%%|$SECRETS_DIR|g" \
    "$SCRIPTS_DIR/db_restore.sh"

  # Replace crypto functions placeholder (multi-line)
  sed -i -e "/%%CRYPTO_FUNCTIONS%%/{r $crypto_temp" -e "d}" "$SCRIPTS_DIR/db_restore.sh"

  rm -f "$crypto_temp"
  chmod +x "$SCRIPTS_DIR/db_restore.sh"
}

# ---------- Generate Files Backup Script ----------

generate_files_backup_script() {
  local SECRETS_DIR="$1"
  local RCLONE_REMOTE="$2"
  local RCLONE_PATH="$3"
  local LOGS_DIR="$4"
  local RETENTION_MINUTES="${5:-0}"
  local WEB_PATH_PATTERN="${6:-/var/www/*}"
  local WEBROOT_SUBDIR="${7:-.}"

  cat > "$SCRIPTS_DIR/files_backup.sh" << 'FILESBACKUPEOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="%%LOGS_DIR%%"
RCLONE_REMOTE="%%RCLONE_REMOTE%%"
RCLONE_PATH="%%RCLONE_PATH%%"
SECRETS_DIR="%%SECRETS_DIR%%"
HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
LOG_PREFIX="[FILES-BACKUP]"
WEB_PATH_PATTERN="%%WEB_PATH_PATTERN%%"
WEBROOT_SUBDIR="%%WEBROOT_SUBDIR%%"
RETENTION_MINUTES="%%RETENTION_MINUTES%%"

# Lock file in fixed location
LOCK_FILE="/var/lock/backupd-files.lock"

SECRET_NTFY_TOKEN=".c4"
SECRET_NTFY_URL=".c5"

# Cleanup function
TEMP_DIR=""
cleanup() {
  local exit_code=$?
  [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
  exit $exit_code
}
trap cleanup EXIT INT TERM

%%CRYPTO_FUNCTIONS%%

# Acquire lock (fixed location)
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "$LOG_PREFIX Another backup running. Exiting."
  exit 0
fi

# Create temp directory
TEMP_DIR="$(mktemp -d)"

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

STAMP="$(date +%F-%H%M)"
LOG="$LOGS_DIR/files_logfile.log"
mkdir -p "$LOGS_DIR"
rotate_log "$LOG"
touch "$LOG" && chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1
echo "==== $(date +%F' '%T) START files backup ===="

# Check disk space (need at least 2GB free in temp)
AVAIL_MB=$(df -m /tmp 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
if [[ "$AVAIL_MB" -lt 2000 ]]; then
  echo "$LOG_PREFIX [ERROR] Insufficient disk space in /tmp (${AVAIL_MB}MB available, 2000MB required)"
  exit 3
fi

NTFY_URL="$(get_secret "$SECRETS_DIR" "$SECRET_NTFY_URL" || echo "")"
NTFY_TOKEN="$(get_secret "$SECRETS_DIR" "$SECRET_NTFY_TOKEN" || echo "")"

send_notification() {
  local title="$1" message="$2"
  [[ -z "$NTFY_URL" ]] && return 0
  if [[ -n "$NTFY_TOKEN" ]]; then
    timeout 10 curl -s -H "Authorization: Bearer $NTFY_TOKEN" -H "Title: $title" -d "$message" "$NTFY_URL" >/dev/null 2>&1 || true
  else
    timeout 10 curl -s -H "Title: $title" -d "$message" "$NTFY_URL" >/dev/null 2>&1 || true
  fi
}

[[ -n "$NTFY_URL" ]] && send_notification "Files Backup Started on $HOSTNAME" "Starting at $(date)"

command -v pigz >/dev/null 2>&1 || { echo "$LOG_PREFIX pigz not found"; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "$LOG_PREFIX tar not found"; exit 1; }

sanitize_for_filename() {
  local s="$1"
  s="$(echo -n "$s" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  s="${s//:\/\//__}"; s="${s//\//__}"
  s="$(echo -n "$s" | sed -E 's/[^a-z0-9._-]+/_/g')"
  s="${s%.}"
  [[ -z "$s" ]] && s="unknown-site"
  printf "%s" "$s"
}

# Get site name/URL from various app types
# Priority: WordPress > Laravel > Node.js > nginx config > folder name
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

# Check if we can find any sites matching the pattern
site_dirs=()
for dir in $WEB_PATH_PATTERN; do
  [[ -d "$dir" ]] && site_dirs+=("$dir")
done

if [[ ${#site_dirs[@]} -eq 0 ]]; then
  echo "$LOG_PREFIX [ERROR] No directories found matching pattern: $WEB_PATH_PATTERN"
  [[ -n "$NTFY_URL" ]] && send_notification "Files Backup Failed on $HOSTNAME" "No sites found matching pattern"
  exit 4
fi

declare -a failures=()
success_count=0
site_count=0

for site_path in "${site_dirs[@]}"; do
  [[ ! -d "$site_path" ]] && continue
  site_name="$(basename "$site_path")"

  # Skip common non-site directories
  [[ "$site_name" == "default" || "$site_name" == "html" || "$site_name" == "cgi-bin" ]] && continue

  # Determine the actual web root (where files are)
  # WEBROOT_SUBDIR can be "." (direct), "public_html", "httpdocs", etc.
  if [[ "$WEBROOT_SUBDIR" == "." ]]; then
    webroot="$site_path"
  else
    webroot="$site_path/$WEBROOT_SUBDIR"
    # If webroot subdir doesn't exist, check if files are directly in site_path
    if [[ ! -d "$webroot" ]]; then
      # Fall back to direct path if subdir doesn't exist
      webroot="$site_path"
    fi
  fi

  # Skip if webroot is empty or doesn't contain any files
  if [[ ! -d "$webroot" ]] || [[ -z "$(ls -A "$webroot" 2>/dev/null)" ]]; then
    echo "$LOG_PREFIX [$site_name] Skipping: empty or missing webroot"
    continue
  fi

  ((site_count++)) || true

  owner="$(stat -c '%U' "$site_path" 2>/dev/null || echo "www-data")"
  site_url="$(get_site_name "$webroot" "$owner")"
  base_name="$(sanitize_for_filename "$site_url")"
  archive_path="$TEMP_DIR/${base_name}-${STAMP}.tar.gz"

  echo "$LOG_PREFIX [$site_name] Archiving ($site_url)..."

  # Archive CONTENTS of webroot (not the directory itself)
  # This allows restore to extract INTO existing webroot without replacing it
  # Critical for panels like Enhance that use overlay containers
  #
  # We also create a metadata file that stores the restore path
  metadata_file="$TEMP_DIR/${base_name}.restore-path"

  # Store restore path in metadata
  echo "$webroot" > "$metadata_file"

  # Archive contents of webroot
  if tar --warning=no-file-changed --ignore-failed-read -I pigz -cpf "$archive_path" -C "$webroot" . 2>/dev/null; then
    tar_status=0
  else
    tar_status=$?
  fi

  # tar exit code 1 = files changed during archive (acceptable)
  # tar exit code > 1 = actual error
  [[ $tar_status -gt 1 ]] && { echo "$LOG_PREFIX [$site_name] Archive failed"; failures+=("$site_name"); continue; }
  [[ ! -f "$archive_path" ]] && { echo "$LOG_PREFIX [$site_name] Archive file not created"; failures+=("$site_name"); continue; }

  echo "$LOG_PREFIX [$site_name] Uploading..."

  # Generate checksum
  checksum_file="${archive_path}.sha256"
  sha256sum "$archive_path" | awk '{print $1}' > "$checksum_file"
  echo "$LOG_PREFIX [$site_name] Checksum: $(cat "$checksum_file")"

  if timeout 3600 rclone copy "$archive_path" "$RCLONE_REMOTE:$RCLONE_PATH" --retries 3 --low-level-retries 10; then
    # Upload checksum file
    timeout 60 rclone copy "$checksum_file" "$RCLONE_REMOTE:$RCLONE_PATH" --retries 3 || echo "$LOG_PREFIX [$site_name] Checksum upload failed (backup OK)"
    # Upload restore-path metadata file
    timeout 60 rclone copy "$metadata_file" "$RCLONE_REMOTE:$RCLONE_PATH" --retries 3 || echo "$LOG_PREFIX [$site_name] Metadata upload failed (backup OK)"
    rm -f "$archive_path" "$checksum_file" "$metadata_file"
    ((success_count++)) || true
    echo "$LOG_PREFIX [$site_name] Done"
  else
    echo "$LOG_PREFIX [$site_name] Upload failed"
    rm -f "$checksum_file" "$metadata_file"
    failures+=("$site_name")
  fi
done

if [[ $site_count -eq 0 ]]; then
  echo "$LOG_PREFIX [WARNING] No sites found in $WWW_DIR"
  [[ -n "$NTFY_URL" ]] && send_notification "Files Backup Warning on $HOSTNAME" "No sites found"
  echo "==== $(date +%F' '%T) END (no sites) ===="
  exit 0
fi

# Retention cleanup
if [[ "$RETENTION_MINUTES" -gt 0 ]]; then
  echo "$LOG_PREFIX Running retention cleanup (keeping backups newer than $RETENTION_MINUTES minutes)..."
  cleanup_count=0
  cleanup_errors=0
  cutoff_time=$(date -d "-$RETENTION_MINUTES minutes" +%s 2>/dev/null || date -v-${RETENTION_MINUTES}M +%s 2>/dev/null || echo 0)

  if [[ "$cutoff_time" -gt 0 ]]; then
    # List remote files and check their age
    while IFS= read -r remote_file; do
      [[ -z "$remote_file" ]] && continue
      # Get file modification time from rclone
      file_time=$(rclone lsl "$RCLONE_REMOTE:$RCLONE_PATH/$remote_file" 2>&1 | awk '{print $2" "$3}' | head -1)
      if [[ -n "$file_time" && ! "$file_time" =~ ^ERROR ]]; then
        file_epoch=$(date -d "$file_time" +%s 2>/dev/null || echo 0)
        if [[ "$file_epoch" -gt 0 && "$file_epoch" -lt "$cutoff_time" ]]; then
          echo "$LOG_PREFIX   Deleting old backup: $remote_file"
          delete_output=$(rclone delete "$RCLONE_REMOTE:$RCLONE_PATH/$remote_file" 2>&1)
          if [[ $? -eq 0 ]]; then
            ((cleanup_count++)) || true
            # Also delete corresponding checksum file
            rclone delete "$RCLONE_REMOTE:$RCLONE_PATH/${remote_file}.sha256" 2>/dev/null || true
          else
            echo "$LOG_PREFIX   [ERROR] Failed to delete $remote_file: $delete_output"
            ((cleanup_errors++)) || true
          fi
        fi
      fi
    done < <(rclone lsf "$RCLONE_REMOTE:$RCLONE_PATH" --include "*.tar.gz" --exclude "*.sha256" 2>&1)

    if [[ $cleanup_errors -gt 0 ]]; then
      echo "$LOG_PREFIX [WARNING] Retention cleanup completed with $cleanup_errors error(s). Removed $cleanup_count old backup(s)."
      [[ -n "$NTFY_URL" ]] && send_notification "Files Retention Cleanup Warning on $HOSTNAME" "Removed: $cleanup_count, Errors: $cleanup_errors"
    elif [[ $cleanup_count -gt 0 ]]; then
      echo "$LOG_PREFIX Retention cleanup complete. Removed $cleanup_count old backup(s)."
      [[ -n "$NTFY_URL" ]] && send_notification "Files Retention Cleanup on $HOSTNAME" "Removed $cleanup_count old backup(s)"
    else
      echo "$LOG_PREFIX Retention cleanup complete. No old backups to remove."
    fi
  else
    echo "$LOG_PREFIX [WARNING] Could not calculate cutoff time, skipping cleanup"
    [[ -n "$NTFY_URL" ]] && send_notification "Files Retention Cleanup Failed on $HOSTNAME" "Could not calculate cutoff time"
  fi
fi

if [[ ${#failures[@]} -gt 0 ]]; then
  [[ -n "$NTFY_URL" ]] && send_notification "Files Backup Errors on $HOSTNAME" "Success: $success_count, Failed: ${failures[*]}"
  echo "==== $(date +%F' '%T) END (with errors) ===="
  exit 1
else
  [[ -n "$NTFY_URL" ]] && send_notification "Files Backup Success on $HOSTNAME" "$success_count sites backed up"
  echo "==== $(date +%F' '%T) END (success) ===="
fi
FILESBACKUPEOF

  # Generate crypto functions and inject them
  local crypto_functions
  crypto_functions="$(generate_embedded_crypto "$SECRETS_DIR")"

  local crypto_temp
  crypto_temp="$(mktemp)"
  echo "$crypto_functions" > "$crypto_temp"

  sed -i \
    -e "s|%%LOGS_DIR%%|$LOGS_DIR|g" \
    -e "s|%%RCLONE_REMOTE%%|$RCLONE_REMOTE|g" \
    -e "s|%%RCLONE_PATH%%|$RCLONE_PATH|g" \
    -e "s|%%SECRETS_DIR%%|$SECRETS_DIR|g" \
    -e "s|%%RETENTION_MINUTES%%|$RETENTION_MINUTES|g" \
    -e "s|%%WEB_PATH_PATTERN%%|$WEB_PATH_PATTERN|g" \
    -e "s|%%WEBROOT_SUBDIR%%|$WEBROOT_SUBDIR|g" \
    "$SCRIPTS_DIR/files_backup.sh"

  # Replace crypto functions placeholder (multi-line)
  sed -i -e "/%%CRYPTO_FUNCTIONS%%/{r $crypto_temp" -e "d}" "$SCRIPTS_DIR/files_backup.sh"

  rm -f "$crypto_temp"
  chmod +x "$SCRIPTS_DIR/files_backup.sh"
}

# ---------- Generate Files Restore Script ----------

generate_files_restore_script() {
  local RCLONE_REMOTE="$1"
  local RCLONE_PATH="$2"

  cat > "$SCRIPTS_DIR/files_restore.sh" << 'FILESRESTOREEOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077

RCLONE_REMOTE="%%RCLONE_REMOTE%%"
RCLONE_PATH="%%RCLONE_PATH%%"
LOG_PREFIX="[FILES-RESTORE]"

# Use same lock as backup to prevent conflicts
LOCK_FILE="/var/lock/backupd-files.lock"

# Acquire lock (wait up to 60 seconds if backup is running)
exec 9>"$LOCK_FILE"
if ! flock -w 60 9; then
  echo "$LOG_PREFIX ERROR: Could not acquire lock. A backup may be running."
  echo "$LOG_PREFIX Please wait for the backup to complete and try again."
  exit 1
fi

echo "========================================================"
echo "           Files Restore Utility"
echo "========================================================"
echo

TEMP_DIR="$(mktemp -d)"
trap "rm -rf '$TEMP_DIR'" EXIT

echo "Step 1: Select Site Backup"
echo "--------------------------"
echo "$LOG_PREFIX Fetching backups from $RCLONE_REMOTE:$RCLONE_PATH..."

# Get unique site names from backups (each site has its own archive)
declare -A SITE_BACKUPS=()
declare -a SITE_NAMES=()

remote_files="$(rclone lsf "$RCLONE_REMOTE:$RCLONE_PATH" --include "*.tar.gz" --exclude "*.sha256" 2>/dev/null | sort -r)" || true

# Group backups by site name (format: sitename-YYYY-MM-DD-HHMM.tar.gz)
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  # Extract site name (everything before the timestamp)
  site_name=$(echo "$f" | sed -E 's/-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4}\.tar\.gz$//')
  if [[ -n "$site_name" ]]; then
    if [[ -z "${SITE_BACKUPS[$site_name]:-}" ]]; then
      SITE_NAMES+=("$site_name")
      SITE_BACKUPS[$site_name]="$f"  # Store most recent (already sorted)
    fi
  fi
done <<< "$remote_files"

echo "$LOG_PREFIX Found ${#SITE_NAMES[@]} site(s) with backups."
[[ ${#SITE_NAMES[@]} -eq 0 ]] && { echo "$LOG_PREFIX No backups found."; exit 1; }

echo
echo "Available sites:"
for i in "${!SITE_NAMES[@]}"; do
  site="${SITE_NAMES[$i]}"
  latest="${SITE_BACKUPS[$site]}"
  printf "  %2d) %s\n" "$((i+1))" "$site"
  printf "      Latest: %s\n" "$latest"
done
echo
echo "  A) Restore all sites (latest backup of each)"
echo "  Q) Quit"
echo
read -p "Select site(s) to restore [1-${#SITE_NAMES[@]}, comma-separated, A for all]: " sel
[[ "$sel" =~ ^[Qq]$ ]] && exit 0

declare -a SELECTED_SITES=()
if [[ "$sel" =~ ^[Aa]$ ]]; then
  SELECTED_SITES=("${SITE_NAMES[@]}")
else
  IFS=',' read -ra sels <<< "$sel"
  for s in "${sels[@]}"; do
    s="$(echo "$s" | tr -d ' ')"
    if [[ "$s" =~ ^[0-9]+$ ]] && [[ $s -ge 1 ]] && [[ $s -le ${#SITE_NAMES[@]} ]]; then
      SELECTED_SITES+=("${SITE_NAMES[$((s-1))]}")
    fi
  done
fi

[[ ${#SELECTED_SITES[@]} -eq 0 ]] && { echo "No sites selected."; exit 0; }

echo
echo "Step 2: Confirm Restore"
echo "-----------------------"
echo "Sites to restore:"
for site in "${SELECTED_SITES[@]}"; do
  echo "  - $site (${SITE_BACKUPS[$site]})"
done
echo
read -p "This will OVERWRITE existing sites. Continue? (yes/no): " confirm
[[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]] && exit 0

echo
echo "Step 3: Restoring Sites"
echo "-----------------------"

for site in "${SELECTED_SITES[@]}"; do
  backup_file="${SITE_BACKUPS[$site]}"
  echo
  echo "$LOG_PREFIX Restoring: $site"
  echo "$LOG_PREFIX   Backup: $backup_file"

  # Download backup
  echo "$LOG_PREFIX   Downloading..."
  if ! rclone copy "$RCLONE_REMOTE:$RCLONE_PATH/$backup_file" "$TEMP_DIR/" --progress; then
    echo "$LOG_PREFIX   [ERROR] Download failed"
    continue
  fi

  local_file="$TEMP_DIR/$backup_file"

  # Verify checksum if available
  checksum_file="${backup_file}.sha256"
  if rclone copy "$RCLONE_REMOTE:$RCLONE_PATH/$checksum_file" "$TEMP_DIR/" 2>/dev/null; then
    echo "$LOG_PREFIX   Verifying checksum..."
    stored=$(cat "$TEMP_DIR/$checksum_file")
    calculated=$(sha256sum "$local_file" | awk '{print $1}')
    if [[ "$stored" == "$calculated" ]]; then
      echo "$LOG_PREFIX   Checksum: OK"
    else
      echo "$LOG_PREFIX   [ERROR] Checksum mismatch!"
      echo "$LOG_PREFIX     Expected: $stored"
      echo "$LOG_PREFIX     Got:      $calculated"
      read -p "  Continue with this backup anyway? (y/N): " continue_anyway
      if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        rm -f "$local_file" "$TEMP_DIR/$checksum_file"
        continue
      fi
    fi
    rm -f "$TEMP_DIR/$checksum_file"
  else
    echo "$LOG_PREFIX   [INFO] No checksum file found"
  fi

  # Download restore-path metadata file to determine where to extract
  restore_path_file="${site}.restore-path"
  restore_path=""
  if rclone copy "$RCLONE_REMOTE:$RCLONE_PATH/$restore_path_file" "$TEMP_DIR/" 2>/dev/null; then
    restore_path=$(cat "$TEMP_DIR/$restore_path_file" 2>/dev/null)
    rm -f "$TEMP_DIR/$restore_path_file"
    echo "$LOG_PREFIX   Restore path from metadata: $restore_path"
  fi

  # If no metadata file, try to determine restore path from archive or prompt user
  if [[ -z "$restore_path" ]]; then
    # Check archive structure - old format had directory name, new format has ./
    first_entry=$(tar -tzf "$local_file" 2>/dev/null | head -1)
    if [[ "$first_entry" == "./" || "$first_entry" == "." ]]; then
      # New format: contents only, no metadata - need user input
      echo "$LOG_PREFIX   [INFO] New backup format detected (contents only)"
      echo "$LOG_PREFIX   [WARNING] No restore-path metadata found for this backup."
      echo "$LOG_PREFIX   This backup was made with v1.4.0+ but is missing its metadata file."
      echo ""
      read -p "  Enter full path to restore to (e.g., /var/www/mysite/public_html): " restore_path
      if [[ -z "$restore_path" ]]; then
        echo "$LOG_PREFIX   [ERROR] No restore path provided."
        rm -f "$local_file"
        continue
      fi
      if [[ ! -d "$restore_path" ]]; then
        echo "$LOG_PREFIX   [WARNING] Path does not exist: $restore_path"
        read -p "  Create this directory? (y/N): " create_dir
        if [[ "$create_dir" =~ ^[Yy]$ ]]; then
          mkdir -p "$restore_path" || { echo "$LOG_PREFIX   [ERROR] Could not create directory"; rm -f "$local_file"; continue; }
        else
          rm -f "$local_file"
          continue
        fi
      fi
    else
      # Old format: archive contains directory name - also prompt for base path
      dir_name=$(echo "$first_entry" | cut -d'/' -f1)
      if [[ -z "$dir_name" ]]; then
        echo "$LOG_PREFIX   [ERROR] Could not determine directory name from archive"
        rm -f "$local_file"
        continue
      fi
      echo "$LOG_PREFIX   [INFO] Old backup format detected (directory: $dir_name)"
      echo "$LOG_PREFIX   [INFO] This backup contains the full directory structure."
      echo ""
      read -p "  Enter base path to extract to (default: /var/www): " base_path
      base_path="${base_path:-/var/www}"
      restore_path="$base_path/$dir_name"
      echo "$LOG_PREFIX   Will restore to: $restore_path"
    fi
  fi

  echo "$LOG_PREFIX   Extracting to: $restore_path"

  # For new format (contents only), extract INTO the existing directory
  # For old format, extract the directory itself
  first_entry=$(tar -tzf "$local_file" 2>/dev/null | head -1)
  if [[ "$first_entry" == "./" || "$first_entry" == "." ]]; then
    # NEW FORMAT: Contents only - extract INTO existing directory
    # This preserves the public_html directory itself (important for overlay containers)

    if [[ ! -d "$restore_path" ]]; then
      echo "$LOG_PREFIX   [ERROR] Restore path does not exist: $restore_path"
      rm -f "$local_file"
      continue
    fi

    # Backup existing contents (not the directory itself)
    backup_name=""
    backup_path="${restore_path}.contents-backup-$(date +%Y%m%d-%H%M%S)"
    echo "$LOG_PREFIX   Backing up existing contents..."
    if mkdir -p "$backup_path" && cp -a "$restore_path"/. "$backup_path"/ 2>/dev/null; then
      backup_name="$backup_path"
    else
      echo "$LOG_PREFIX   [WARNING] Could not backup existing contents"
    fi

    # Clear existing contents and extract new ones
    echo "$LOG_PREFIX   Clearing existing contents..."
    find "$restore_path" -mindepth 1 -delete 2>/dev/null || rm -rf "$restore_path"/* "$restore_path"/.[!.]* 2>/dev/null

    if tar -xzf "$local_file" -C "$restore_path" 2>/dev/null; then
      echo "$LOG_PREFIX   Success"
      # Fix ownership - set to directory owner
      dir_owner=$(stat -c '%U:%G' "$restore_path" 2>/dev/null || echo "www-data:www-data")
      chown -R "$dir_owner" "$restore_path" 2>/dev/null || true
      echo "$LOG_PREFIX   Ownership set to: $dir_owner"
      # Remove backup on success
      [[ -n "$backup_name" && -d "$backup_name" ]] && rm -rf "$backup_name"
    else
      echo "$LOG_PREFIX   [ERROR] Extraction failed"
      # Restore backup if we made one
      if [[ -n "$backup_name" && -d "$backup_name" ]]; then
        rm -rf "$restore_path"/* "$restore_path"/.[!.]* 2>/dev/null
        cp -a "$backup_name"/. "$restore_path"/ 2>/dev/null
        rm -rf "$backup_name"
        echo "$LOG_PREFIX   Restored original contents"
      fi
    fi
  else
    # OLD FORMAT: Archive contains full directory - replace entire directory
    dir_name=$(echo "$first_entry" | cut -d'/' -f1)
    # Extract base_path from restore_path (restore_path = base_path/dir_name)
    extract_base_path="$(dirname "$restore_path")"

    # Backup existing directory if it exists
    backup_name=""
    if [[ -d "$restore_path" ]]; then
      backup_name="${dir_name}.pre-restore-$(date +%Y%m%d-%H%M%S)"
      echo "$LOG_PREFIX   Backing up existing to: $backup_name"
      mv "$restore_path" "$extract_base_path/$backup_name"
    fi

    if tar -xzf "$local_file" -C "$extract_base_path" 2>/dev/null; then
      echo "$LOG_PREFIX   Success"
      # Remove temp backup on success
      [[ -n "$backup_name" && -d "$extract_base_path/$backup_name" ]] && rm -rf "$extract_base_path/$backup_name"
    else
      echo "$LOG_PREFIX   [ERROR] Extraction failed"
      # Restore the backup if we made one
      if [[ -n "$backup_name" && -d "$extract_base_path/$backup_name" ]]; then
        mv "$extract_base_path/$backup_name" "$restore_path"
        echo "$LOG_PREFIX   Restored original directory"
      fi
    fi
  fi

  rm -f "$local_file"
done

echo
echo "========================================================"
echo "           Restore Complete!"
echo "========================================================"
FILESRESTOREEOF

  sed -i \
    -e "s|%%RCLONE_REMOTE%%|$RCLONE_REMOTE|g" \
    -e "s|%%RCLONE_PATH%%|$RCLONE_PATH|g" \
    "$SCRIPTS_DIR/files_restore.sh"

  chmod +x "$SCRIPTS_DIR/files_restore.sh"
}

# ---------- Generate Verify Script ----------
# This generates a QUICK verification script for scheduled runs
# It does NOT download backups - only checks file/checksum existence
# For full verification, use the interactive menu

generate_verify_script() {
  local secrets_dir rclone_remote rclone_db_path rclone_files_path
  secrets_dir="$(get_secrets_dir)"
  rclone_remote="$(get_config_value 'RCLONE_REMOTE')"
  rclone_db_path="$(get_config_value 'RCLONE_DB_PATH')"
  rclone_files_path="$(get_config_value 'RCLONE_FILES_PATH')"

  cat > "$SCRIPTS_DIR/verify_backup.sh" << 'VERIFYEOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077

# ============================================================================
# Backupd - Quick Verification Script (Scheduled Mode)
# Checks backup existence and checksums WITHOUT downloading
# For full verification (with decryption test), use: sudo backupd -> Verify
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="%%LOGS_DIR%%"
RCLONE_REMOTE="%%RCLONE_REMOTE%%"
RCLONE_DB_PATH="%%RCLONE_DB_PATH%%"
RCLONE_FILES_PATH="%%RCLONE_FILES_PATH%%"
SECRETS_DIR="%%SECRETS_DIR%%"
HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
LOG_FILE="$LOGS_DIR/verify_logfile.log"

# Full verification tracking
LAST_FULL_VERIFY_FILE="$INSTALL_DIR/.last_full_verify"
FULL_VERIFY_INTERVAL_DAYS=30

SECRET_NTFY_TOKEN=".c4"
SECRET_NTFY_URL=".c5"

%%CRYPTO_FUNCTIONS%%

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

send_notification() {
  local title="$1" body="$2"
  local ntfy_url ntfy_token
  ntfy_url="$(get_secret "$SECRETS_DIR" "$SECRET_NTFY_URL")"
  ntfy_token="$(get_secret "$SECRETS_DIR" "$SECRET_NTFY_TOKEN")"
  [[ -z "$ntfy_url" ]] && return 0
  if [[ -n "$ntfy_token" ]]; then
    curl -s -H "Authorization: Bearer $ntfy_token" -H "Title: $title" -d "$body" "$ntfy_url" -o /dev/null --max-time 10 || true
  else
    curl -s -H "Title: $title" -d "$body" "$ntfy_url" -o /dev/null --max-time 10 || true
  fi
}

# Log rotation
rotate_log() {
  local log_file="$1"
  local max_size=$((10 * 1024 * 1024))  # 10MB
  [[ ! -f "$log_file" ]] && return 0
  local log_size
  log_size=$(stat -c%s "$log_file" 2>/dev/null || stat -f%z "$log_file" 2>/dev/null || echo 0)
  if [[ "$log_size" -gt "$max_size" ]]; then
    [[ -f "${log_file}.5" ]] && rm -f "${log_file}.5"
    for ((i=4; i>=1; i--)); do
      [[ -f "${log_file}.${i}" ]] && mv "${log_file}.${i}" "${log_file}.$((i+1))"
    done
    mv "$log_file" "${log_file}.1"
  fi
}

# Format file size for display
format_size() {
  local size="$1"
  numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size}B"
}

# Check if full verification is due
check_full_verify_due() {
  if [[ ! -f "$LAST_FULL_VERIFY_FILE" ]]; then
    echo "never"
    return 0
  fi

  local last_verify_epoch current_epoch days_since
  last_verify_epoch=$(cat "$LAST_FULL_VERIFY_FILE" 2>/dev/null)
  current_epoch=$(date +%s)

  if [[ -z "$last_verify_epoch" ]] || ! [[ "$last_verify_epoch" =~ ^[0-9]+$ ]]; then
    echo "never"
    return 0
  fi

  days_since=$(( (current_epoch - last_verify_epoch) / 86400 ))
  echo "$days_since"
}

# Main
mkdir -p "$LOGS_DIR"
rotate_log "$LOG_FILE"

log "==== QUICK INTEGRITY CHECK START ===="
log "Mode: Quick (checksum-only, no download)"

db_result="SKIPPED"
db_details=""
files_result="SKIPPED"
files_details=""

# Quick verify database backup (no download)
if [[ -n "$RCLONE_DB_PATH" ]]; then
  log "Checking database backup..."
  latest_db=$(rclone lsf "$RCLONE_REMOTE:$RCLONE_DB_PATH" --include "*-db_backups-*.tar.gz.gpg" 2>/dev/null | sort -r | head -1)

  if [[ -z "$latest_db" ]]; then
    log "[WARNING] No database backups found"
    db_result="FAILED"
    db_details="No backups found"
  else
    log "Latest: $latest_db"

    # Check file exists and get size (no download)
    file_info=$(rclone lsl "$RCLONE_REMOTE:$RCLONE_DB_PATH/$latest_db" 2>/dev/null)
    if [[ -n "$file_info" ]]; then
      file_size=$(echo "$file_info" | awk '{print $1}')

      # Check if checksum file exists
      checksum_file="${latest_db}.sha256"
      if rclone lsf "$RCLONE_REMOTE:$RCLONE_DB_PATH/$checksum_file" &>/dev/null; then
        log "Backup exists: $(format_size "$file_size"), checksum file present"
        db_result="PASSED"
        db_details="$(format_size "$file_size")"
      else
        log "[WARNING] Backup exists but no checksum file"
        db_result="WARNING"
        db_details="no checksum"
      fi
    else
      log "[ERROR] Backup file not accessible"
      db_result="FAILED"
      db_details="File not accessible"
    fi
  fi
fi

# Quick verify files backup (no download)
if [[ -n "$RCLONE_FILES_PATH" ]]; then
  log "Checking files backup..."
  latest_files=$(rclone lsf "$RCLONE_REMOTE:$RCLONE_FILES_PATH" --include "*.tar.gz" --exclude "*.sha256" 2>/dev/null | sort -r | head -1)

  if [[ -z "$latest_files" ]]; then
    log "[WARNING] No files backups found"
    files_result="FAILED"
    files_details="No backups found"
  else
    log "Latest: $latest_files"

    # Check file exists and get size (no download)
    file_info=$(rclone lsl "$RCLONE_REMOTE:$RCLONE_FILES_PATH/$latest_files" 2>/dev/null)
    if [[ -n "$file_info" ]]; then
      file_size=$(echo "$file_info" | awk '{print $1}')

      # Check if checksum file exists
      checksum_file="${latest_files}.sha256"
      if rclone lsf "$RCLONE_REMOTE:$RCLONE_FILES_PATH/$checksum_file" &>/dev/null; then
        log "Backup exists: $(format_size "$file_size"), checksum file present"
        files_result="PASSED"
        files_details="$(format_size "$file_size")"
      else
        log "[WARNING] Backup exists but no checksum file"
        files_result="WARNING"
        files_details="no checksum"
      fi
    else
      log "[ERROR] Backup file not accessible"
      files_result="FAILED"
      files_details="File not accessible"
    fi
  fi
fi

# Check if full verification is overdue
days_since_full=$(check_full_verify_due)
full_verify_reminder=""
if [[ "$days_since_full" == "never" ]]; then
  full_verify_reminder="REMINDER: No full backup test ever performed! Run: sudo backupd -> Verify -> Full test"
  log "[REMINDER] $full_verify_reminder"
elif [[ "$days_since_full" -ge "$FULL_VERIFY_INTERVAL_DAYS" ]]; then
  full_verify_reminder="REMINDER: Last full backup test was $days_since_full days ago. Recommended: Run full test monthly."
  log "[REMINDER] $full_verify_reminder"
fi

# Summary
log "==== SUMMARY ===="
log "Database: $db_result ${db_details:+($db_details)}"
log "Files: $files_result ${files_details:+($files_details)}"
log "==== QUICK INTEGRITY CHECK END ===="

# Send notification
notification_body="DB: $db_result, Files: $files_result (Quick check)"
if [[ -n "$full_verify_reminder" ]]; then
  notification_body="$notification_body. $full_verify_reminder"
fi

if [[ "$db_result" == "FAILED" || "$files_result" == "FAILED" ]]; then
  send_notification "Quick Check FAILED on $HOSTNAME" "$notification_body"
  exit 1
elif [[ "$db_result" == "WARNING" || "$files_result" == "WARNING" ]]; then
  send_notification "Quick Check WARNING on $HOSTNAME" "$notification_body"
  exit 0
else
  # Only notify on success if full verify reminder is needed
  if [[ -n "$full_verify_reminder" ]]; then
    send_notification "Quick Check OK - Full Test Needed on $HOSTNAME" "$notification_body"
  else
    send_notification "Quick Check PASSED on $HOSTNAME" "$notification_body"
  fi
fi

exit 0
VERIFYEOF

  # Generate crypto functions and inject them
  local crypto_functions
  crypto_functions="$(generate_embedded_crypto "$secrets_dir")"

  local crypto_temp
  crypto_temp="$(mktemp)"
  echo "$crypto_functions" > "$crypto_temp"

  # Replace placeholders
  sed -i \
    -e "s|%%LOGS_DIR%%|$INSTALL_DIR/logs|g" \
    -e "s|%%RCLONE_REMOTE%%|$rclone_remote|g" \
    -e "s|%%RCLONE_DB_PATH%%|$rclone_db_path|g" \
    -e "s|%%RCLONE_FILES_PATH%%|$rclone_files_path|g" \
    -e "s|%%SECRETS_DIR%%|$secrets_dir|g" \
    "$SCRIPTS_DIR/verify_backup.sh"

  # Replace crypto functions placeholder (multi-line)
  sed -i -e "/%%CRYPTO_FUNCTIONS%%/{r $crypto_temp" -e "d}" "$SCRIPTS_DIR/verify_backup.sh"

  rm -f "$crypto_temp"
  chmod 700 "$SCRIPTS_DIR/verify_backup.sh"
}
