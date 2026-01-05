#!/usr/bin/env bash
# ============================================================================
# Backupd - Debug Module
# Secure debug logging for troubleshooting (no sensitive data)
#
# Usage:
#   BACKUPD_DEBUG=1 backupd          # Enable via environment
#   backupd --debug                   # Enable via CLI flag
#   backupd --debug-export            # Export sanitized debug log
# ============================================================================

# Debug configuration
DEBUG_ENABLED="${BACKUPD_DEBUG:-0}"
DEBUG_LOG_FILE="${BACKUPD_DEBUG_LOG:-/etc/backupd/logs/debug.log}"
DEBUG_MAX_SIZE=$((5 * 1024 * 1024))  # 5MB max before rotation

# Session ID for correlating log entries
DEBUG_SESSION_ID=""

# Ensure log directory exists before any writes (safe to call during install)
_ensure_debug_log_dir() {
  local log_dir
  log_dir="$(dirname "$DEBUG_LOG_FILE")"
  [[ -d "$log_dir" ]] || mkdir -p "$log_dir" 2>/dev/null || true
}

# ---------- Core Debug Functions ----------

# Initialize debug logging for this session
debug_init() {
  if [[ "$DEBUG_ENABLED" != "1" ]]; then
    return 0
  fi

  # Ensure log directory exists
  local log_dir
  log_dir="$(dirname "$DEBUG_LOG_FILE")"
  mkdir -p "$log_dir" 2>/dev/null || true

  # Generate session ID
  DEBUG_SESSION_ID="$(date +%Y%m%d-%H%M%S)-$$"

  # Rotate if too large
  if [[ -f "$DEBUG_LOG_FILE" ]]; then
    local file_size
    file_size=$(stat -c%s "$DEBUG_LOG_FILE" 2>/dev/null || stat -f%z "$DEBUG_LOG_FILE" 2>/dev/null || echo 0)
    if [[ "$file_size" -gt "$DEBUG_MAX_SIZE" ]]; then
      mv "$DEBUG_LOG_FILE" "${DEBUG_LOG_FILE}.1" 2>/dev/null || true
    fi
  fi

  # Write session header
  {
    echo ""
    echo "============================================================"
    echo "DEBUG SESSION: $DEBUG_SESSION_ID"
    echo "Started: $(date -Iseconds 2>/dev/null || date)"
    echo "Version: ${VERSION:-unknown}"
    echo "Command: $0 $*"
    echo "============================================================"
  } >> "$DEBUG_LOG_FILE" 2>/dev/null || true

  # Log system info
  debug_log_system_info

  return 0
}

# Main debug log function - NEVER logs sensitive data
debug_log() {
  if [[ "$DEBUG_ENABLED" != "1" ]]; then
    return 0
  fi

  # Ensure log directory exists
  _ensure_debug_log_dir

  local timestamp
  timestamp=$(date '+%H:%M:%S.%3N' 2>/dev/null || date '+%H:%M:%S')

  # Sanitize the message before logging
  local message
  message="$(debug_sanitize "$*")"

  echo "[$timestamp] $message" >> "$DEBUG_LOG_FILE" 2>/dev/null || true
}

# Log with level prefix
debug_log_level() {
  local level="$1"
  shift
  debug_log "[$level] $*"
}

# Convenience functions for different log levels
debug_info()  { debug_log_level "INFO" "$@"; }
debug_warn()  { debug_log_level "WARN" "$@"; }
debug_error() { debug_log_level "ERROR" "$@"; }
debug_trace() { debug_log_level "TRACE" "$@"; }

# ---------- Sanitization Functions ----------

# Sanitize sensitive data from strings - CRITICAL for security
debug_sanitize() {
  local input="$*"

  # Return empty if input is empty
  [[ -z "$input" ]] && return 0

  echo "$input" | sed -E \
    -e 's/(password|passwd|pass|token|secret|key|apikey|api_key|credential|auth)[=:]["'"'"']?[^"'"'"' ]*/\1=[REDACTED]/gi' \
    -e 's/\/etc\/\.[a-zA-Z0-9]{8,}[^/]*/\/etc\/[SECRET_DIR]/g' \
    -e 's/(machine-id|machine_id)[=:][^ ]*/\1=[REDACTED]/gi' \
    -e 's/[a-f0-9]{32,}/<HASH>/gi' \
    -e 's/(Bearer|Basic) [^ ]+/\1 [REDACTED]/gi'
}

# Sanitize a file path (hide secrets directory name)
debug_sanitize_path() {
  local path="$1"
  echo "$path" | sed -E 's/\/etc\/\.[a-zA-Z0-9]{8,}[^/]*/\/etc\/[SECRET_DIR]/g'
}

# ---------- System Information (Safe) ----------

debug_log_system_info() {
  if [[ "$DEBUG_ENABLED" != "1" ]]; then
    return 0
  fi

  {
    echo "--- System Information ---"

    # OS Info
    if [[ -f /etc/os-release ]]; then
      local os_name
      os_name=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
      echo "OS: ${os_name:-unknown}"
    fi
    echo "Kernel: $(uname -r 2>/dev/null || echo 'unknown')"
    echo "Arch: $(uname -m 2>/dev/null || echo 'unknown')"
    echo "Hostname: $(hostname 2>/dev/null || echo 'unknown')"

    # Shell info
    echo "Bash: ${BASH_VERSION:-unknown}"
    echo "User: $(whoami 2>/dev/null || echo 'unknown') (EUID: ${EUID:-unknown})"

    # Tool versions
    echo "--- Installed Tools ---"
    echo "openssl: $(openssl version 2>/dev/null | head -1 || echo 'not found')"
    echo "gpg: $(gpg --version 2>/dev/null | head -1 || echo 'not found')"
    echo "rclone: $(rclone version 2>/dev/null | head -1 || echo 'not found')"
    echo "pigz: $(pigz --version 2>/dev/null 2>&1 | head -1 || echo 'not found')"
    echo "argon2: $(command -v argon2 &>/dev/null && echo 'installed' || echo 'not found')"
    echo "tar: $(tar --version 2>/dev/null | head -1 || echo 'not found')"
    echo "systemctl: $(command -v systemctl &>/dev/null && echo 'installed' || echo 'not found')"

    # Backupd configuration (safe values only)
    echo "--- Backupd Configuration ---"
    echo "Install dir: ${INSTALL_DIR:-/etc/backupd}"
    if [[ -f "${INSTALL_DIR:-/etc/backupd}/.config" ]]; then
      echo "Config file: exists"
      # Log only non-sensitive config keys
      echo "Config keys: $(grep -E '^[A-Z_]+=' "${INSTALL_DIR:-/etc/backupd}/.config" 2>/dev/null | cut -d= -f1 | tr '\n' ' ')"
    else
      echo "Config file: not found"
    fi

    # Encryption status (version only, no secrets)
    echo "--- Encryption Status ---"
    local secrets_location="${INSTALL_DIR:-/etc/backupd}/.secrets_location"
    if [[ -f "$secrets_location" ]]; then
      echo "Secrets configured: yes"
      local secrets_dir
      secrets_dir=$(cat "$secrets_location" 2>/dev/null)
      if [[ -n "$secrets_dir" ]] && [[ -d "$secrets_dir" ]]; then
        echo "Secrets dir exists: yes"
        if [[ -f "$secrets_dir/.algo" ]]; then
          echo "Crypto version: $(cat "$secrets_dir/.algo" 2>/dev/null || echo 'unknown')"
        else
          echo "Crypto version: 1 (legacy, no .algo file)"
        fi
        # List which secret files exist (not their contents!)
        local secret_files=""
        [[ -f "$secrets_dir/.s" ]] && secret_files+=".s "
        [[ -f "$secrets_dir/.algo" ]] && secret_files+=".algo "
        [[ -f "$secrets_dir/.c1" ]] && secret_files+=".c1 "
        [[ -f "$secrets_dir/.c2" ]] && secret_files+=".c2 "
        [[ -f "$secrets_dir/.c3" ]] && secret_files+=".c3 "
        [[ -f "$secrets_dir/.c4" ]] && secret_files+=".c4 "
        [[ -f "$secrets_dir/.c5" ]] && secret_files+=".c5 "
        echo "Secret files present: ${secret_files:-none}"
      else
        echo "Secrets dir exists: no"
      fi
    else
      echo "Secrets configured: no"
    fi

    # Systemd status
    echo "--- Systemd Timers ---"
    if command -v systemctl &>/dev/null; then
      systemctl is-enabled backupd-db.timer 2>/dev/null && echo "backupd-db.timer: enabled" || echo "backupd-db.timer: disabled/missing"
      systemctl is-enabled backupd-files.timer 2>/dev/null && echo "backupd-files.timer: enabled" || echo "backupd-files.timer: disabled/missing"
      systemctl is-enabled backupd-verify.timer 2>/dev/null && echo "backupd-verify.timer: enabled" || echo "backupd-verify.timer: disabled/missing"
    else
      echo "systemctl not available"
    fi

    echo "--- End System Information ---"
  } >> "$DEBUG_LOG_FILE" 2>/dev/null || true
}

# ---------- Function Tracing ----------

# Log function entry
debug_enter() {
  local func_name="$1"
  shift
  local args=""
  if [[ $# -gt 0 ]]; then
    args=" args=($(debug_sanitize "$*"))"
  fi
  debug_trace "ENTER $func_name$args"
}

# Log function exit
debug_exit() {
  local func_name="$1"
  local exit_code="${2:-0}"
  debug_trace "EXIT $func_name (code=$exit_code)"
}

# Log a command before execution (sanitized)
debug_cmd() {
  debug_trace "CMD: $(debug_sanitize "$*")"
}

# ---------- Error Logging ----------

# Log an error with context
debug_log_error() {
  local error_msg="$1"
  local context="${2:-}"

  debug_error "$(debug_sanitize "$error_msg")"
  if [[ -n "$context" ]]; then
    debug_error "  Context: $(debug_sanitize "$context")"
  fi

  # Log call stack if available
  if [[ ${#FUNCNAME[@]} -gt 1 ]]; then
    debug_error "  Call stack:"
    for ((i=1; i<${#FUNCNAME[@]}; i++)); do
      debug_error "    ${FUNCNAME[$i]}() at ${BASH_SOURCE[$i]:-unknown}:${BASH_LINENO[$((i-1))]:-?}"
    done
  fi
}

# ---------- Export Functions ----------

# Export debug log for sharing (extra sanitization pass)
debug_export() {
  local export_file="${1:-/tmp/backupd-debug-export.log}"

  if [[ ! -f "$DEBUG_LOG_FILE" ]]; then
    echo "No debug log found at $DEBUG_LOG_FILE"
    echo "Enable debug mode with: BACKUPD_DEBUG=1 backupd"
    return 1
  fi

  echo "Exporting sanitized debug log..."

  # Extra sanitization pass for sharing
  sed -E \
    -e 's/\/etc\/\.[a-zA-Z0-9]+/\/etc\/[REDACTED]/g' \
    -e 's/Hostname: .*/Hostname: [REDACTED]/g' \
    -e 's/[a-f0-9]{32,}/<HASH>/gi' \
    -e 's/(password|passwd|pass|token|secret|key|credential)[=:][^ ]*/\1=[REDACTED]/gi' \
    "$DEBUG_LOG_FILE" > "$export_file"

  echo "Exported to: $export_file"
  echo ""
  echo "Please review the file before sharing to ensure no sensitive data remains."
  echo "File size: $(du -h "$export_file" | cut -f1)"

  return 0
}

# Show debug log location and status
debug_status() {
  echo "Debug Logging Status"
  echo "===================="
  echo ""
  echo "Enabled: $([ "$DEBUG_ENABLED" = "1" ] && echo "Yes" || echo "No")"
  echo "Log file: $DEBUG_LOG_FILE"

  if [[ -f "$DEBUG_LOG_FILE" ]]; then
    echo "Log exists: Yes"
    echo "Log size: $(du -h "$DEBUG_LOG_FILE" | cut -f1)"
    echo "Last modified: $(stat -c %y "$DEBUG_LOG_FILE" 2>/dev/null || stat -f %Sm "$DEBUG_LOG_FILE" 2>/dev/null || echo 'unknown')"
    echo ""
    echo "To enable debug mode:"
    echo "  BACKUPD_DEBUG=1 backupd"
    echo ""
    echo "To export for sharing:"
    echo "  backupd --debug-export"
  else
    echo "Log exists: No"
    echo ""
    echo "To enable debug mode:"
    echo "  BACKUPD_DEBUG=1 backupd"
  fi
}

# ---------- Session End ----------

# Log session end
debug_end() {
  if [[ "$DEBUG_ENABLED" != "1" ]]; then
    return 0
  fi

  {
    echo "============================================================"
    echo "DEBUG SESSION ENDED: $DEBUG_SESSION_ID"
    echo "Ended: $(date -Iseconds 2>/dev/null || date)"
    echo "============================================================"
    echo ""
  } >> "$DEBUG_LOG_FILE" 2>/dev/null || true
}
