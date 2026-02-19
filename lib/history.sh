#!/usr/bin/env bash
# ============================================================================
# Backupd - History Module
# Backup history recording and retrieval functions
#
# v3.1.0: Added job_name field for multi-job support
# ============================================================================

HISTORY_FILE="${INSTALL_DIR:-/etc/backupd}/history.jsonl"
HISTORY_MAX_RECORDS="${HISTORY_MAX_RECORDS:-50}"

# Record a backup result to history
# Usage: record_history "database" "success" "$STARTED_AT" "$ENDED_AT" "$SNAPSHOT_ID" 5 0 ""
# Environment: JOB_NAME - job name for multi-job tracking (default: "default")
record_history() {
  local type="$1" status="$2" started_at="$3" ended_at="$4"
  local snapshot_id="${5:-}" items_count="${6:-0}" items_failed="${7:-0}" error="${8:-}"
  local job_id="${JOB_ID:-backup-$type-$(date +%s)}"
  local job_name="${JOB_NAME:-default}"
  local hostname="${HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}"

  # Calculate duration (cross-platform date parsing)
  get_epoch() {
    local ts="$1"
    date -d "$ts" +%s 2>/dev/null || \
    python3 -c "import datetime; print(int(datetime.datetime.fromisoformat('$ts'.replace('Z','+00:00')).timestamp()))" 2>/dev/null || \
    echo 0
  }
  local start_epoch end_epoch duration_seconds
  start_epoch=$(get_epoch "$started_at")
  end_epoch=$(get_epoch "$ended_at")
  duration_seconds=$((end_epoch - start_epoch))
  [[ $duration_seconds -lt 0 ]] && duration_seconds=0

  # Escape all JSON string values
  escape_json() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; s="${s//$'\r'/\\r}"; echo "$s"; }
  job_name=$(escape_json "$job_name")
  snapshot_id=$(escape_json "$snapshot_id")
  hostname=$(escape_json "$hostname")
  error=$(escape_json "$error")

  # Create JSON record (includes job_name for multi-job tracking)
  local record="{\"id\":\"$job_id\",\"job\":\"$job_name\",\"type\":\"$type\",\"status\":\"$status\",\"started_at\":\"$started_at\",\"ended_at\":\"$ended_at\",\"duration_seconds\":$duration_seconds,\"snapshot_id\":\"$snapshot_id\",\"items_count\":$items_count,\"items_failed\":$items_failed,\"error\":\"$error\",\"hostname\":\"$hostname\"}"

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

# Rotate history to keep max records (with flock to prevent race condition)
rotate_history() {
  [[ ! -f "$HISTORY_FILE" ]] && return 0
  (
    flock -n 9 || return 0
    local count=$(wc -l < "$HISTORY_FILE" 2>/dev/null || echo 0)
    if [[ $count -gt $HISTORY_MAX_RECORDS ]]; then
      tail -n "$HISTORY_MAX_RECORDS" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp"
      mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
      chmod 600 "$HISTORY_FILE" 2>/dev/null || true
    fi
  ) 9>"${HISTORY_FILE}.lock"
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

# Get history records filtered by job name (v3.1.0)
# Usage: get_job_history "production" "all" 20
get_job_history() {
  local job_name="${1:-default}" type="${2:-all}" limit="${3:-20}"
  [[ ! -f "$HISTORY_FILE" ]] && echo "[]" && return 0

  local records
  # Filter by job name first
  local job_filtered
  job_filtered=$(grep "\"job\":\"$job_name\"" "$HISTORY_FILE" 2>/dev/null || echo "")

  [[ -z "$job_filtered" ]] && echo "[]" && return 0

  case "$type" in
    all)
      records=$(echo "$job_filtered" | tail -n "$limit" | tac)
      ;;
    backup|backups)
      records=$(echo "$job_filtered" | grep -E '"type":"(database|files)"' | tail -n "$limit" | tac)
      ;;
    verify|verifications)
      records=$(echo "$job_filtered" | grep -E '"type":"verify_(quick|full)"' | tail -n "$limit" | tac)
      ;;
    *)
      records=$(echo "$job_filtered" | grep "\"type\":\"$type\"" | tail -n "$limit" | tac)
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

# Get history summary by job (v3.1.0)
# Returns summary stats for each job
get_history_by_jobs() {
  [[ ! -f "$HISTORY_FILE" ]] && echo "{}" && return 0

  # Get unique job names from history
  local jobs
  jobs=$(grep -oE '"job":"[^"]*"' "$HISTORY_FILE" 2>/dev/null | sort -u | cut -d'"' -f4)

  echo "{"
  local first=1
  while IFS= read -r job; do
    [[ -z "$job" ]] && continue
    [[ $first -eq 0 ]] && echo ","
    first=0

    local total success failed
    total=$(grep "\"job\":\"$job\"" "$HISTORY_FILE" | wc -l)
    success=$(grep "\"job\":\"$job\"" "$HISTORY_FILE" | grep '"status":"success"' | wc -l)
    failed=$(grep "\"job\":\"$job\"" "$HISTORY_FILE" | grep '"status":"failed"' | wc -l)

    local last_backup
    last_backup=$(grep "\"job\":\"$job\"" "$HISTORY_FILE" | grep -E '"type":"(database|files)"' | tail -1 | grep -oE '"started_at":"[^"]*"' | cut -d'"' -f4)

    echo -n "  \"$job\": {\"total\": $total, \"success\": $success, \"failed\": $failed, \"last_backup\": \"${last_backup:-never}\"}"
  done <<< "$jobs"
  echo
  echo "}"
}
