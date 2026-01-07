#!/usr/bin/env bash
# ============================================================================
# Backupd - History Module
# Backup history recording and retrieval functions
# ============================================================================

HISTORY_FILE="${INSTALL_DIR:-/etc/backupd}/history.jsonl"
HISTORY_MAX_RECORDS="${HISTORY_MAX_RECORDS:-50}"

# Record a backup result to history
# Usage: record_history "database" "success" "$STARTED_AT" "$ENDED_AT" "$SNAPSHOT_ID" 5 0 ""
record_history() {
  local type="$1" status="$2" started_at="$3" ended_at="$4"
  local snapshot_id="${5:-}" items_count="${6:-0}" items_failed="${7:-0}" error="${8:-}"
  local job_id="${JOB_ID:-backup-$type-$(date +%s)}"
  local hostname="${HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}"

  # Calculate duration
  local start_epoch end_epoch duration_seconds
  start_epoch=$(date -d "$started_at" +%s 2>/dev/null || echo 0)
  end_epoch=$(date -d "$ended_at" +%s 2>/dev/null || echo 0)
  duration_seconds=$((end_epoch - start_epoch))
  [[ $duration_seconds -lt 0 ]] && duration_seconds=0

  # Escape error for JSON
  error="${error//\\/\\\\}"; error="${error//\"/\\\"}"; error="${error//$'\n'/\\n}"

  # Create JSON record
  local record="{\"id\":\"$job_id\",\"type\":\"$type\",\"status\":\"$status\",\"started_at\":\"$started_at\",\"ended_at\":\"$ended_at\",\"duration_seconds\":$duration_seconds,\"snapshot_id\":\"$snapshot_id\",\"items_count\":$items_count,\"items_failed\":$items_failed,\"error\":\"$error\",\"hostname\":\"$hostname\"}"

  echo "$record" >> "$HISTORY_FILE"
  chmod 600 "$HISTORY_FILE" 2>/dev/null || true
  rotate_history
}

# Get history records (returns JSON array)
# Supports type filtering with prefix matching for grouped types
get_history() {
  local type="${1:-all}" limit="${2:-20}"
  [[ ! -f "$HISTORY_FILE" ]] && echo "[]" && return 0

  local records
  case "$type" in
    all)
      records=$(tail -n "$limit" "$HISTORY_FILE" | tac)
      ;;
    backup|backups)
      # Match database and files
      records=$(grep -E '"type":"(database|files)"' "$HISTORY_FILE" | tail -n "$limit" | tac)
      ;;
    verify|verifications)
      # Match verify_quick and verify_full
      records=$(grep -E '"type":"verify_(quick|full)"' "$HISTORY_FILE" | tail -n "$limit" | tac)
      ;;
    *)
      records=$(grep "\"type\":\"$type\"" "$HISTORY_FILE" | tail -n "$limit" | tac)
      ;;
  esac

  echo "["; local first=1
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ $first -eq 0 ]] && echo ","
    echo "  $line"; first=0
  done <<< "$records"
  echo "]"
}

# Rotate history to keep max records
rotate_history() {
  [[ ! -f "$HISTORY_FILE" ]] && return 0
  local count=$(wc -l < "$HISTORY_FILE" 2>/dev/null || echo 0)
  if [[ $count -gt $HISTORY_MAX_RECORDS ]]; then
    tail -n "$HISTORY_MAX_RECORDS" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp"
    mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
    chmod 600 "$HISTORY_FILE" 2>/dev/null || true
  fi
}

# Format duration for display (e.g., "2m 15s")
format_duration() {
  local s="$1"
  if [[ $s -lt 60 ]]; then echo "${s}s"
  elif [[ $s -lt 3600 ]]; then echo "$((s/60))m $((s%60))s"
  else echo "$((s/3600))h $(((s%3600)/60))m"
  fi
}

# Get next scheduled times for all operations (returns JSON)
get_next_backup_times() {
  local timer_out=$(systemctl list-timers backupd-* --no-pager 2>/dev/null || echo "")
  local db_next=$(echo "$timer_out" | grep "backupd-db.timer" | awk '{print $1, $2, $3}')
  local files_next=$(echo "$timer_out" | grep "backupd-files.timer" | awk '{print $1, $2, $3}')
  local verify_next=$(echo "$timer_out" | grep "backupd-verify.timer" | awk '{print $1, $2, $3}')
  local verify_full_next=$(echo "$timer_out" | grep "backupd-verify-full.timer" | awk '{print $1, $2, $3}')
  echo "{\"database\":\"${db_next:-not scheduled}\",\"files\":\"${files_next:-not scheduled}\",\"verify_quick\":\"${verify_next:-not scheduled}\",\"verify_full\":\"${verify_full_next:-not scheduled}\"}"
}
