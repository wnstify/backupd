#!/usr/bin/env bash
# ============================================================================
# Backupd v3.0 - Restic Module
# Core restic operations for backup/restore/verify
#
# This module provides centralized restic functions for:
#   - Repository configuration and initialization
#   - Database backups via stdin (piped from mysqldump)
#   - File backups with deduplication
#   - Restore operations (database dump, file extraction)
#   - Retention policy management (forget + prune)
#   - Repository verification (quick and full)
#   - Snapshot listing and statistics
#
# Restic uses rclone as the storage backend, supporting all rclone remotes.
# Repository password is stored in secure credential storage (.c1)
# ============================================================================

# ---------- Repository Configuration ----------

# Get restic repository URL (rclone backend)
# Usage: get_restic_repo "remote_name" "path"
# Returns: "rclone:remote_name:path"
get_restic_repo() {
  local rclone_remote="$1"
  local rclone_path="$2"
  echo "rclone:${rclone_remote}:${rclone_path}"
}

# Initialize restic repository
# Creates new repository structure at the given location
# Returns: 0 on success, non-zero on failure
init_restic_repo() {
  local repo="$1"
  local password="$2"
  local json_output="${3:-false}"

  if [[ "$json_output" == "true" ]]; then
    RESTIC_PASSWORD="$password" restic -r "$repo" init --json 2>/dev/null
  else
    RESTIC_PASSWORD="$password" restic -r "$repo" init 2>/dev/null
  fi
}

# Check if repository exists and is accessible
# Returns: 0 if repository exists and is valid, 1 otherwise
repo_exists() {
  local repo="$1"
  local password="$2"

  RESTIC_PASSWORD="$password" restic -r "$repo" snapshots --quiet 2>/dev/null
}

# Unlock a repository (remove stale locks)
# Use with caution - only when sure no other process is using the repo
unlock_repo() {
  local repo="$1"
  local password="$2"

  RESTIC_PASSWORD="$password" restic -r "$repo" unlock 2>/dev/null
}

# ---------- Backup Operations ----------

# Backup database via stdin (mysqldump piped to restic)
# Streams database dump directly to restic without temp files
# Tags: database, db:<dbname>
backup_database_stdin() {
  local repo="$1"
  local password="$2"
  local db_name="$3"
  local db_dump_cmd="$4"  # e.g., "mysqldump --single-transaction dbname"
  local hostname="${5:-$(hostname -f 2>/dev/null || hostname)}"
  local json_output="${6:-false}"

  local restic_args=(
    -r "$repo"
    backup
    --stdin
    --stdin-filename "${db_name}.sql"
    --tag "database"
    --tag "db:${db_name}"
    --host "$hostname"
  )

  if [[ "$json_output" == "true" ]]; then
    restic_args+=(--json)
  fi

  $db_dump_cmd | RESTIC_PASSWORD="$password" restic "${restic_args[@]}"
}

# Backup files directory
# Performs incremental backup with deduplication
# Tags: files, site:<sitename>
backup_files() {
  local repo="$1"
  local password="$2"
  local source_path="$3"
  local site_name="$4"
  local hostname="${5:-$(hostname -f 2>/dev/null || hostname)}"
  local json_output="${6:-false}"
  local exclude_file="${7:-}"

  local restic_args=(
    -r "$repo"
    backup "$source_path"
    --tag "files"
    --tag "site:${site_name}"
    --host "$hostname"
  )

  if [[ "$json_output" == "true" ]]; then
    restic_args+=(--json)
  fi

  if [[ -n "$exclude_file" && -f "$exclude_file" ]]; then
    restic_args+=(--exclude-file "$exclude_file")
  fi

  RESTIC_PASSWORD="$password" restic "${restic_args[@]}"
}

# Backup with custom tags
# Generic backup function for flexibility
backup_with_tags() {
  local repo="$1"
  local password="$2"
  local source_path="$3"
  local hostname="$4"
  shift 4
  local tags=("$@")

  local restic_args=(
    -r "$repo"
    backup "$source_path"
    --host "$hostname"
  )

  for tag in "${tags[@]}"; do
    restic_args+=(--tag "$tag")
  done

  RESTIC_PASSWORD="$password" restic "${restic_args[@]}"
}

# ---------- Restore Operations ----------

# Restore database from snapshot
# Dumps SQL content from snapshot to a file for mysql import
restore_database() {
  local repo="$1"
  local password="$2"
  local snapshot_id="$3"
  local target_file="$4"
  local db_filename="${5:-}"  # Optional: specific .sql file in snapshot

  if [[ -n "$db_filename" ]]; then
    # Dump specific file from snapshot
    RESTIC_PASSWORD="$password" restic -r "$repo" dump "$snapshot_id" "/$db_filename" > "$target_file"
  else
    # Dump root (for stdin backups, the file is at /)
    RESTIC_PASSWORD="$password" restic -r "$repo" dump "$snapshot_id" / > "$target_file"
  fi
}

# Restore files from snapshot
# Extracts files to target path, preserving permissions
restore_files() {
  local repo="$1"
  local password="$2"
  local snapshot_id="$3"
  local target_path="$4"
  local include_path="${5:-}"  # Optional: restore only specific path within snapshot

  local restic_args=(
    -r "$repo"
    restore "$snapshot_id"
    --target "$target_path"
  )

  if [[ -n "$include_path" ]]; then
    restic_args+=(--include "$include_path")
  fi

  RESTIC_PASSWORD="$password" restic "${restic_args[@]}"
}

# Restore to original location
# Convenience function that restores to the original paths
restore_files_in_place() {
  local repo="$1"
  local password="$2"
  local snapshot_id="$3"

  RESTIC_PASSWORD="$password" restic -r "$repo" restore "$snapshot_id" --target /
}

# ---------- Retention Operations ----------

# Apply retention policy using restic forget
# Removes old snapshots and prunes unused data
apply_retention() {
  local repo="$1"
  local password="$2"
  local keep_daily="${3:-7}"
  local keep_weekly="${4:-4}"
  local keep_monthly="${5:-6}"
  local tag_filter="${6:-}"
  local json_output="${7:-false}"

  local restic_args=(
    -r "$repo"
    forget
    --keep-daily "$keep_daily"
    --keep-weekly "$keep_weekly"
    --keep-monthly "$keep_monthly"
    --prune
  )

  if [[ -n "$tag_filter" ]]; then
    restic_args+=(--tag "$tag_filter")
  fi

  if [[ "$json_output" == "true" ]]; then
    restic_args+=(--json)
  fi

  RESTIC_PASSWORD="$password" restic "${restic_args[@]}"
}

# Apply retention with keep-within (days-based)
# Simpler retention: keep all snapshots within N days
apply_retention_days() {
  local repo="$1"
  local password="$2"
  local keep_days="${3:-30}"
  local tag_filter="${4:-}"
  local json_output="${5:-false}"

  local restic_args=(
    -r "$repo"
    forget
    --keep-within "${keep_days}d"
    --prune
  )

  if [[ -n "$tag_filter" ]]; then
    restic_args+=(--tag "$tag_filter")
  fi

  if [[ "$json_output" == "true" ]]; then
    restic_args+=(--json)
  fi

  RESTIC_PASSWORD="$password" restic "${restic_args[@]}"
}

# Prune repository without forgetting snapshots
# Removes unreferenced data from repository
prune_repo() {
  local repo="$1"
  local password="$2"
  local json_output="${3:-false}"

  if [[ "$json_output" == "true" ]]; then
    RESTIC_PASSWORD="$password" restic -r "$repo" prune --json
  else
    RESTIC_PASSWORD="$password" restic -r "$repo" prune
  fi
}

# ---------- Verification Operations ----------

# Quick check (metadata only)
# Fast verification that checks repository structure
verify_quick() {
  local repo="$1"
  local password="$2"
  local json_output="${3:-false}"

  if [[ "$json_output" == "true" ]]; then
    RESTIC_PASSWORD="$password" restic -r "$repo" check --json 2>&1
  else
    RESTIC_PASSWORD="$password" restic -r "$repo" check 2>&1
  fi
}

# Full check (downloads and verifies data)
# Comprehensive verification that reads all data
verify_full() {
  local repo="$1"
  local password="$2"
  local json_output="${3:-false}"

  if [[ "$json_output" == "true" ]]; then
    RESTIC_PASSWORD="$password" restic -r "$repo" check --read-data --json 2>&1
  else
    RESTIC_PASSWORD="$password" restic -r "$repo" check --read-data 2>&1
  fi
}

# Partial data check (subset of packs)
# Compromise between quick and full - checks percentage of data
verify_partial() {
  local repo="$1"
  local password="$2"
  local percentage="${3:-10}"

  RESTIC_PASSWORD="$password" restic -r "$repo" check --read-data-subset "${percentage}%" 2>&1
}

# ---------- Snapshot Listing ----------

# List all snapshots
# Returns JSON array of snapshots for parsing
list_snapshots() {
  local repo="$1"
  local password="$2"
  local tag_filter="${3:-}"

  if [[ -n "$tag_filter" ]]; then
    RESTIC_PASSWORD="$password" restic -r "$repo" snapshots --tag "$tag_filter" --json
  else
    RESTIC_PASSWORD="$password" restic -r "$repo" snapshots --json
  fi
}

# List snapshots (human-readable format)
list_snapshots_human() {
  local repo="$1"
  local password="$2"
  local tag_filter="${3:-}"

  if [[ -n "$tag_filter" ]]; then
    RESTIC_PASSWORD="$password" restic -r "$repo" snapshots --tag "$tag_filter"
  else
    RESTIC_PASSWORD="$password" restic -r "$repo" snapshots
  fi
}

# List database snapshots
list_db_snapshots() {
  local repo="$1"
  local password="$2"

  list_snapshots "$repo" "$password" "database"
}

# List files snapshots
list_files_snapshots() {
  local repo="$1"
  local password="$2"

  list_snapshots "$repo" "$password" "files"
}

# Get latest snapshot ID for a tag
get_latest_snapshot() {
  local repo="$1"
  local password="$2"
  local tag_filter="${3:-}"

  local snapshots
  snapshots="$(list_snapshots "$repo" "$password" "$tag_filter")"

  # Parse JSON to get latest snapshot ID
  echo "$snapshots" | grep -o '"short_id":"[^"]*"' | tail -1 | cut -d'"' -f4
}

# List files in a snapshot
list_snapshot_files() {
  local repo="$1"
  local password="$2"
  local snapshot_id="$3"
  local path="${4:-/}"

  RESTIC_PASSWORD="$password" restic -r "$repo" ls "$snapshot_id" "$path"
}

# ---------- Statistics ----------

# Get repository statistics
get_repo_stats() {
  local repo="$1"
  local password="$2"

  RESTIC_PASSWORD="$password" restic -r "$repo" stats --json
}

# Get repository statistics (human-readable)
get_repo_stats_human() {
  local repo="$1"
  local password="$2"

  RESTIC_PASSWORD="$password" restic -r "$repo" stats
}

# Get diff between two snapshots
get_snapshot_diff() {
  local repo="$1"
  local password="$2"
  local snapshot_a="$3"
  local snapshot_b="$4"

  RESTIC_PASSWORD="$password" restic -r "$repo" diff "$snapshot_a" "$snapshot_b"
}

# ---------- Utility Functions ----------

# Check restic binary availability and version
check_restic() {
  if ! command -v restic &>/dev/null; then
    echo "ERROR: restic not found"
    return 1
  fi

  local version
  version="$(restic version 2>/dev/null | head -1)"
  echo "$version"
  return 0
}

# Get restic version number only
get_restic_version() {
  restic version 2>/dev/null | awk '{print $2}'
}

# Build repository URL from config values
build_repo_url() {
  local rclone_remote="$1"
  local rclone_path="$2"

  # Validate inputs
  if [[ -z "$rclone_remote" || -z "$rclone_path" ]]; then
    return 1
  fi

  echo "rclone:${rclone_remote}:${rclone_path}"
}

# Get repository password from secrets
# Wrapper for crypto.sh get_secret function
get_repo_password() {
  local secrets_dir="$1"

  if [[ -z "$secrets_dir" ]]; then
    secrets_dir="$(get_secrets_dir)"
  fi

  if [[ -z "$secrets_dir" || ! -d "$secrets_dir" ]]; then
    return 1
  fi

  get_secret "$secrets_dir" ".c1"
}

# Run restic command with proper environment
# Generic wrapper for running restic with password set
run_restic() {
  local repo="$1"
  local password="$2"
  shift 2

  RESTIC_PASSWORD="$password" restic -r "$repo" "$@"
}

# ---------- Caching ----------

# Enable cache (default location: ~/.cache/restic)
# Speeds up repeated operations on large repositories
enable_cache() {
  # Cache is enabled by default in restic
  # This function documents the cache location
  local cache_dir="${HOME}/.cache/restic"
  echo "$cache_dir"
}

# Clear restic cache
clear_cache() {
  local repo="$1"
  local password="$2"

  RESTIC_PASSWORD="$password" restic -r "$repo" cache --cleanup
}

# ---------- Locking ----------

# Check for stale locks
check_locks() {
  local repo="$1"
  local password="$2"

  RESTIC_PASSWORD="$password" restic -r "$repo" list locks --json 2>/dev/null
}

# Remove stale locks (use with caution)
remove_stale_locks() {
  local repo="$1"
  local password="$2"

  RESTIC_PASSWORD="$password" restic -r "$repo" unlock
}
