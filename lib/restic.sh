#!/usr/bin/env bash
# ============================================================================
# Backupd v3.0 - Restic Module
# Shared restic helpers used by setup and the generated backup scripts.
#
# The generated scripts (db_backup.sh, files_backup.sh, verify_*, restore.sh)
# call the `restic` binary directly; only repository setup/retention is shared
# here. Restic uses rclone as the storage backend (rclone:<remote>:<path>).
# Repository password is stored in secure credential storage (.c1).
# ============================================================================

# ---------- Cache Configuration ----------
# Set default cache directory for systemd compatibility (no $HOME in services)
export RESTIC_CACHE_DIR="${RESTIC_CACHE_DIR:-/var/cache/backupd/restic}"
mkdir -p "$RESTIC_CACHE_DIR" 2>/dev/null || true

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
# Uses 'cat config' to avoid lock conflicts (snapshots requires lock)
repo_exists() {
  local repo="$1"
  local password="$2"

  # Use 'cat config' which doesn't require a lock, unlike 'snapshots'
  RESTIC_PASSWORD="$password" restic -r "$repo" cat config &>/dev/null
}

# ---------- Retention Operations ----------

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
    --retry-lock "5m"
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
