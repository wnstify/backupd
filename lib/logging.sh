#!/usr/bin/env bash
# ============================================================================
# Backupd - Logging Module
# Comprehensive structured logging with function instrumentation
#
# Features:
#   - Structured log format suitable for GitHub Issues
#   - FUNCNAME/BASH_SOURCE/BASH_LINENO stack traces
#   - Comprehensive auto-redaction of sensitive data
#   - Function entry/exit instrumentation with timing
#   - Multiple log levels (ERROR, WARN, INFO, DEBUG, TRACE)
#   - System info collection for debugging
#   - Integration with existing --quiet and --json flags
# ============================================================================

# ---------- Logging Configuration ----------

# Log levels (higher = more verbose)
readonly LOG_LEVEL_ERROR=0
readonly LOG_LEVEL_WARN=1
readonly LOG_LEVEL_INFO=2
readonly LOG_LEVEL_DEBUG=3
readonly LOG_LEVEL_TRACE=4

# Current log level (default: INFO, increased by --verbose)
LOG_LEVEL="${LOG_LEVEL:-$LOG_LEVEL_INFO}"

# Log file path (set via --log-file or environment)
# Default: /var/log/backupd.log (automatic error logging)
LOG_FILE="${LOG_FILE:-${BACKUPD_LOG_FILE:-/var/log/backupd.log}}"

# Verbosity level (0=normal, 1=verbose, 2=very verbose)
VERBOSE_LEVEL="${VERBOSE_LEVEL:-0}"

# Session ID for correlating log entries
LOG_SESSION_ID=""

# Function timing stack (for nested function calls)
declare -a _LOG_FUNC_START_TIMES=()
declare -a _LOG_FUNC_NAMES=()

# ---------- Log Level Names ----------

_log_level_name() {
  local level="$1"
  # shellcheck disable=SC2254  # Intentional: match against variable values, not literals
  case "$level" in
    $LOG_LEVEL_ERROR) echo "ERROR" ;;
    $LOG_LEVEL_WARN)  echo "WARN" ;;
    $LOG_LEVEL_INFO)  echo "INFO" ;;
    $LOG_LEVEL_DEBUG) echo "DEBUG" ;;
    $LOG_LEVEL_TRACE) echo "TRACE" ;;
    *) echo "UNKNOWN" ;;
  esac
}

# ---------- Initialization ----------

# Initialize logging system
log_init() {
  # Generate session ID
  LOG_SESSION_ID="$(date +%Y%m%d-%H%M%S)-$$"

  # Create log directory if needed
  if [[ -n "$LOG_FILE" ]]; then
    local log_dir
    log_dir="$(dirname "$LOG_FILE")"
    [[ -d "$log_dir" ]] || mkdir -p "$log_dir" 2>/dev/null || true
  fi

  # Log session start
  if [[ -n "$LOG_FILE" ]]; then
    {
      echo ""
      echo "================================================================================"
      echo "LOG SESSION: $LOG_SESSION_ID"
      echo "Started: $(date -Iseconds 2>/dev/null || date)"
      echo "Version: ${VERSION:-unknown}"
      echo "Command: $0 $(redact_cmdline_args "$*")"
      echo "Log Level: $(_log_level_name "$LOG_LEVEL")"
      echo "================================================================================"
    } >> "$LOG_FILE" 2>/dev/null || true
  fi

  # Log system info at DEBUG level
  if [[ "$LOG_LEVEL" -ge "$LOG_LEVEL_DEBUG" ]]; then
    _log_system_info
  fi
}

# End logging session
log_end() {
  if [[ -n "$LOG_FILE" && -n "$LOG_SESSION_ID" ]]; then
    {
      echo "================================================================================"
      echo "LOG SESSION ENDED: $LOG_SESSION_ID"
      echo "Ended: $(date -Iseconds 2>/dev/null || date)"
      echo "================================================================================"
      echo ""
    } >> "$LOG_FILE" 2>/dev/null || true
  fi
}

# ---------- Comprehensive Redaction ----------

# Redact command-line arguments containing sensitive values
# This handles patterns like: --passphrase VALUE where VALUE is a separate argument
# CRITICAL: Must be used for any logging of command-line arguments
redact_cmdline_args() {
  local input="$*"
  [[ -z "$input" ]] && return 0

  # Redact --passphrase VALUE (value as separate argument after flag)
  # Handles: --passphrase VALUE, --passphrase=VALUE
  input=$(echo "$input" | sed -E 's/(--passphrase)[= ]+[^ ]+/\1 [REDACTED]/g')

  # Redact BACKUPD_PASSPHRASE=value in arguments
  input=$(echo "$input" | sed -E 's/(BACKUPD_PASSPHRASE=)[^ ]+/\1[REDACTED]/g')

  # Redact -p VALUE patterns (short form password flags)
  input=$(echo "$input" | sed -E "s/(-p)[= ]+[^ ]+/\1 [REDACTED]/g")

  echo "$input"
}

# Redact sensitive data from strings
# This is CRITICAL for security - prevents credential leakage in logs
log_redact() {
  local input="$*"

  # Return empty if input is empty
  [[ -z "$input" ]] && return 0

  # Enhanced: Handle quoted values with spaces (e.g., password="my secret pass")
  echo "$input" | sed -E \
    -e 's/(password|passwd|pass|passphrase)[=:]"[^"]*"/\1=[REDACTED]/gi' \
    -e "s/(password|passwd|pass|passphrase)[=:]'[^']*'/\1=[REDACTED]/gi" \
    -e 's/(password|passwd|pass|passphrase)[=:][^"'"'"' \t\n]*/\1=[REDACTED]/gi' \
    -e 's/(token|secret|key|apikey|api_key|api-key|credential|auth)[=:]"[^"]*"/\1=[REDACTED]/gi' \
    -e "s/(token|secret|key|apikey|api_key|api-key|credential|auth)[=:]'[^']*'/\1=[REDACTED]/gi" \
    -e 's/(token|secret|key|apikey|api_key|api-key|credential|auth)[=:][^"'"'"' \t\n]*/\1=[REDACTED]/gi' \
    -e 's/(Bearer|Basic) [A-Za-z0-9_-]+/\1 [REDACTED]/gi' \
    -e 's/(Authorization:) [^ \t\n]+/\1 [REDACTED]/gi' \
    -e "s/-p'[^']*'/-p'[REDACTED]'/g" \
    -e 's/-p"[^"]*"/-p"[REDACTED]"/g' \
    -e 's/-p[^ \t'"'"'"]+/-p[REDACTED]/g' \
    -e 's/--pass[= ]["'"'"']?[^"'"'"' \t]+/--pass=[REDACTED]/g' \
    -e 's/--password[= ]["'"'"']?[^"'"'"' \t]+/--password=[REDACTED]/g' \
    -e 's/(ntfy_token|NTFY_TOKEN)[=:]["'"'"']?[^"'"'"' \t\n]*/\1=[REDACTED]/gi' \
    -e 's/(webhook_token|WEBHOOK_TOKEN)[=:]["'"'"']?[^"'"'"' \t\n]*/\1=[REDACTED]/gi' \
    -e 's/(db_pass|DB_PASS|mysql_pass|MYSQL_PASS)[=:]["'"'"']?[^"'"'"' \t\n]*/\1=[REDACTED]/gi' \
    -e 's/\/etc\/\.[a-zA-Z0-9]{8,}[^\/]*/\/etc\/[SECRET_DIR]/g' \
    -e 's/\/home\/[a-zA-Z0-9_-]+/\/home\/[USER]/g' \
    -e 's/(machine-id|machine_id)[=:][^ \t\n]*/\1=[REDACTED]/gi' \
    -e 's/sk_[a-zA-Z0-9_]+/[API_KEY]/gi' \
    -e 's/tk_[a-zA-Z0-9_]+/[TOKEN]/gi' \
    -e 's/[a-f0-9]{64}/<SHA256>/gi' \
    -e 's/[a-f0-9]{32}/<HASH32>/gi' \
    -e 's/rclone_remote[=:]["'"'"']?[^"'"'"' \t\n]*/rclone_remote=[REDACTED_REMOTE]/gi'
}

# Redact a file path (hide secrets directory and usernames)
log_redact_path() {
  local path="$1"
  echo "$path" | sed -E \
    -e 's/\/etc\/\.[a-zA-Z0-9]{8,}[^\/]*/\/etc\/[SECRET_DIR]/g' \
    -e 's/\/home\/[a-zA-Z0-9_-]+/\/home\/[USER]/g'
}

# ---------- Core Logging Functions ----------

# Main log function - writes to file and optionally stdout
_log_write() {
  local level="$1"
  local level_name="$2"
  shift 2
  local message="$*"

  # Check if we should log at this level
  [[ "$level" -gt "$LOG_LEVEL" ]] && return 0

  # Get caller info (skip internal functions)
  local caller_func="${FUNCNAME[2]:-main}"
  local caller_file="${BASH_SOURCE[2]:-unknown}"
  local caller_line="${BASH_LINENO[1]:-0}"

  # Extract just filename from path
  caller_file="${caller_file##*/}"

  # Format timestamp
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')

  # Redact sensitive data
  message="$(log_redact "$message")"

  # Format log entry
  local log_entry="[$timestamp] [$level_name] [$caller_func@$caller_file:$caller_line] $message"

  # Write to log file if configured
  if [[ -n "$LOG_FILE" ]]; then
    echo "$log_entry" >> "$LOG_FILE" 2>/dev/null || true
  fi

  # Write to stderr for ERROR/WARN (unless quiet mode)
  if [[ "$level" -le "$LOG_LEVEL_WARN" && "${QUIET_MODE:-0}" -ne 1 ]]; then
    echo "$log_entry" >&2
  fi

  # Write to stdout for DEBUG/TRACE in verbose mode
  if [[ "$VERBOSE_LEVEL" -ge 1 && "$level" -ge "$LOG_LEVEL_DEBUG" ]]; then
    echo "$log_entry"
  fi
}

# Log at ERROR level (always logged)
log_error() {
  _log_write "$LOG_LEVEL_ERROR" "ERROR" "$@"

  # Automatically log stack trace for errors
  if [[ -n "$LOG_FILE" ]]; then
    _log_stack_trace >> "$LOG_FILE" 2>/dev/null || true
  fi
}

# Log at WARN level
log_warn() {
  _log_write "$LOG_LEVEL_WARN" "WARN" "$@"
}

# Log at INFO level
log_info() {
  _log_write "$LOG_LEVEL_INFO" "INFO" "$@"
}

# Log at DEBUG level
log_debug() {
  _log_write "$LOG_LEVEL_DEBUG" "DEBUG" "$@"
}

# Log at TRACE level (most verbose)
log_trace() {
  _log_write "$LOG_LEVEL_TRACE" "TRACE" "$@"
}

# ---------- Stack Trace Functions ----------

# Generate stack trace from FUNCNAME/BASH_SOURCE/BASH_LINENO arrays
_log_stack_trace() {
  echo "--- Stack Trace ---"
  local i
  for ((i=2; i<${#FUNCNAME[@]}; i++)); do
    local func="${FUNCNAME[$i]}"
    local file="${BASH_SOURCE[$i]:-unknown}"
    local line="${BASH_LINENO[$((i-1))]:-?}"

    # Extract just filename
    file="${file##*/}"

    echo "  at ${func}() in ${file}:${line}"
  done
  echo "--- End Stack Trace ---"
}

# Log error with full context (for critical errors)
log_error_full() {
  local error_msg="$1"
  local exit_code="${2:-1}"

  log_error "$error_msg (exit_code=$exit_code)"

  if [[ -n "$LOG_FILE" ]]; then
    {
      _log_stack_trace
      echo "--- Error Context ---"
      echo "Exit Code: $exit_code"
      echo "Working Directory: $(pwd 2>/dev/null || echo 'unknown')"
      echo "User: $(whoami 2>/dev/null || echo 'unknown')"
      echo "--- End Error Context ---"
    } >> "$LOG_FILE" 2>/dev/null || true
  fi
}

# ---------- Function Instrumentation ----------

# Record function entry with timing
# Usage: log_func_enter at the start of a function
log_func_enter() {
  [[ "$LOG_LEVEL" -lt "$LOG_LEVEL_TRACE" ]] && return 0

  local func_name="${FUNCNAME[1]:-unknown}"
  local start_time
  start_time=$(date +%s%N 2>/dev/null || date +%s)

  # Push to timing stack
  _LOG_FUNC_NAMES+=("$func_name")
  _LOG_FUNC_START_TIMES+=("$start_time")

  # Log entry with redacted arguments
  local args=""
  if [[ $# -gt 0 ]]; then
    args=" args=($(log_redact "$*"))"
  fi

  log_trace "ENTER ${func_name}${args}"
}

# Record function exit with timing
# Usage: log_func_exit at the end of a function (or use trap)
log_func_exit() {
  [[ "$LOG_LEVEL" -lt "$LOG_LEVEL_TRACE" ]] && return 0

  local exit_code="${1:-0}"
  local func_name="${FUNCNAME[1]:-unknown}"

  # Pop from timing stack
  local duration_ms=""
  if [[ ${#_LOG_FUNC_START_TIMES[@]} -gt 0 ]]; then
    if [[ "${_LOG_FUNC_NAMES[-1]}" != "$func_name" ]]; then
      log_trace "Function exit mismatch: expected ${_LOG_FUNC_NAMES[-1]}, got $func_name"
    fi
    local start_time="${_LOG_FUNC_START_TIMES[-1]}"
    local end_time
    end_time=$(date +%s%N 2>/dev/null || date +%s)

    # Calculate duration (handle both nanosecond and second precision)
    if [[ ${#start_time} -gt 10 ]]; then
      duration_ms=$(( (end_time - start_time) / 1000000 ))
    else
      duration_ms=$(( (end_time - start_time) * 1000 ))
    fi

    # Remove from stack
    unset '_LOG_FUNC_START_TIMES[-1]'
    unset '_LOG_FUNC_NAMES[-1]'
  fi

  log_trace "EXIT ${func_name} (code=$exit_code${duration_ms:+, ${duration_ms}ms})"
}

# Trap-based function instrumentation (auto exit logging)
# Usage: Place at start of function: log_func_trap
log_func_trap() {
  local func_name="${FUNCNAME[1]:-unknown}"
  local start_time
  start_time=$(date +%s%N 2>/dev/null || date +%s)

  _LOG_FUNC_NAMES+=("$func_name")
  _LOG_FUNC_START_TIMES+=("$start_time")

  # Log entry
  log_trace "ENTER ${func_name}"

  # Set trap for function exit
  trap 'log_func_exit $?' RETURN
}

# ---------- System Information ----------

# Log system information (for debugging/GitHub Issues)
_log_system_info() {
  [[ -z "$LOG_FILE" ]] && return 0

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

    # Bash version
    echo "Bash: ${BASH_VERSION:-unknown}"
    echo "User: $(whoami 2>/dev/null || echo 'unknown') (EUID: ${EUID:-unknown})"

    # Tool versions (important for debugging)
    echo "--- Tool Versions ---"
    echo "openssl: $(openssl version 2>/dev/null | head -1 || echo 'not found')"
    echo "gpg: $(gpg --version 2>/dev/null | head -1 || echo 'not found')"
    echo "rclone: $(rclone version 2>/dev/null | head -1 || echo 'not found')"
    echo "restic: $(restic version 2>/dev/null | head -1 || echo 'not found')"
    echo "argon2: $(command -v argon2 &>/dev/null && echo 'installed' || echo 'not found')"
    echo "tar: $(tar --version 2>/dev/null | head -1 || echo 'not found')"
    echo "curl: $(curl --version 2>/dev/null | head -1 || echo 'not found')"
    echo "systemctl: $(command -v systemctl &>/dev/null && echo 'installed' || echo 'not found')"

    # Backupd configuration (safe values only)
    echo "--- Backupd Configuration ---"
    echo "Install dir: ${INSTALL_DIR:-/etc/backupd}"
    if [[ -f "${INSTALL_DIR:-/etc/backupd}/.config" ]]; then
      echo "Config file: exists"
      echo "Config keys: $(grep -E '^[A-Z_]+=' "${INSTALL_DIR:-/etc/backupd}/.config" 2>/dev/null | cut -d= -f1 | tr '\n' ' ')"
    else
      echo "Config file: not found"
    fi

    echo "--- End System Information ---"
  } >> "$LOG_FILE" 2>/dev/null || true
}

# Generate system info suitable for GitHub Issues
log_generate_issue_info() {
  local output=""

  output+="## System Information\n\n"
  output+="\`\`\`\n"

  # OS
  if [[ -f /etc/os-release ]]; then
    local os_name
    os_name=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    output+="OS: ${os_name:-unknown}\n"
  fi
  output+="Kernel: $(uname -r 2>/dev/null || echo 'unknown')\n"
  output+="Arch: $(uname -m 2>/dev/null || echo 'unknown')\n"
  output+="Bash: ${BASH_VERSION:-unknown}\n"
  output+="Backupd: ${VERSION:-unknown}\n"

  # Key tool versions
  output+="\n"
  output+="openssl: $(openssl version 2>/dev/null | head -1 || echo 'not found')\n"
  output+="rclone: $(rclone version 2>/dev/null | head -1 || echo 'not found')\n"
  output+="gpg: $(gpg --version 2>/dev/null | head -1 || echo 'not found')\n"
  output+="\`\`\`\n"

  echo -e "$output"
}

# ---------- Command Logging ----------

# Log a command before execution (sanitized)
log_cmd() {
  log_debug "CMD: $(log_redact "$*")"
}

# Log command execution with result
log_cmd_result() {
  local exit_code="$1"
  local cmd="$2"

  if [[ "$exit_code" -eq 0 ]]; then
    log_debug "CMD OK: $(log_redact "$cmd")"
  else
    log_warn "CMD FAILED (code=$exit_code): $(log_redact "$cmd")"
  fi
}

# ---------- Export Log for GitHub Issues ----------

# Export sanitized log suitable for GitHub issue submission
log_export_for_issue() {
  local export_file="${1:-/tmp/backupd-issue-log.txt}"

  if [[ -z "$LOG_FILE" || ! -f "$LOG_FILE" ]]; then
    echo "No log file available."
    echo "Enable logging with: backupd --log-file /path/to/log.txt"
    return 1
  fi

  echo "Exporting sanitized log for GitHub issue..."

  {
    echo "# Backupd Debug Log"
    echo "# Generated: $(date -Iseconds 2>/dev/null || date)"
    echo "# Version: ${VERSION:-unknown}"
    echo ""
    echo "## System Information"
    echo ""
    log_generate_issue_info
    echo ""
    echo "## Log Entries"
    echo ""
    echo '```'

    # Extra sanitization pass for sharing
    sed -E \
      -e 's/\/etc\/\.[a-zA-Z0-9]+/\/etc\/[REDACTED]/g' \
      -e 's/\/home\/[a-zA-Z0-9_-]+/\/home\/[USER]/g' \
      -e 's/Hostname: .*/Hostname: [REDACTED]/g' \
      -e 's/[a-f0-9]{32,}/<HASH>/gi' \
      -e 's/(password|passwd|pass|token|secret|key|credential)[=:][^ \t\n]*/\1=[REDACTED]/gi' \
      "$LOG_FILE"

    echo '```'
  } > "$export_file"

  echo "Exported to: $export_file"
  echo ""
  echo "Please review the file before sharing to ensure no sensitive data remains."
  echo "File size: $(du -h "$export_file" | cut -f1)"

  return 0
}

# ---------- Verbosity Control ----------

# Increase verbosity level
log_increase_verbosity() {
  VERBOSE_LEVEL=$((VERBOSE_LEVEL + 1))
  if [[ "$VERBOSE_LEVEL" -eq 1 ]]; then
    LOG_LEVEL=$LOG_LEVEL_DEBUG
  elif [[ "$VERBOSE_LEVEL" -ge 2 ]]; then
    LOG_LEVEL=$LOG_LEVEL_TRACE
  fi
}

# Set log file path
log_set_file() {
  LOG_FILE="$1"
  export LOG_FILE
}

# ---------- Integration with Quiet/JSON modes ----------

# Check if logging should produce output
log_should_output() {
  # In quiet mode, only errors go to stderr
  [[ "${QUIET_MODE:-0}" -eq 1 ]] && return 1
  return 0
}

# Log message respecting quiet mode
log_msg() {
  log_should_output && echo "$@"
  log_info "$@"
}
