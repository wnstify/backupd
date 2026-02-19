#!/usr/bin/env bash
# ============================================================================
# Backupd - Core Module
# Core functions: colors, printing, validation, and helper utilities
# ============================================================================

# Colors for output (CLIG compliant - respects NO_COLOR env variable)
# See: https://no-color.org/
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    NC=''
fi

# CLIG globals for output control
QUIET_MODE=${QUIET_MODE:-0}
JSON_OUTPUT=${JSON_OUTPUT:-0}
DRY_RUN=${DRY_RUN:-0}

# ---------- Signal Handling & Cleanup ----------

# Track child processes for cleanup
declare -a BACKUPD_CHILD_PIDS=()

# Cleanup function called on exit/interrupt
# Terminates any child processes (restic, rclone) to prevent orphaned locks
backupd_cleanup() {
    local exit_code=$?

    # Kill any tracked child processes
    for pid in "${BACKUPD_CHILD_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null
            # Give process time to cleanup gracefully
            sleep 0.5
            # Force kill if still running
            kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
        fi
    done

    # Kill any restic processes spawned by this script
    pkill -P $$ restic 2>/dev/null
    pkill -P $$ rclone 2>/dev/null

    return $exit_code
}

# Register cleanup handler (only if not already registered)
if [[ -z "${BACKUPD_TRAP_SET:-}" ]]; then
    trap backupd_cleanup EXIT
    trap 'exit 130' INT   # Exit code 130 = interrupted by Ctrl+C
    trap 'exit 143' TERM  # Exit code 143 = terminated
    BACKUPD_TRAP_SET=1
fi

# Helper to run a command and track its PID for cleanup
# Usage: run_tracked_command restic check -r "$repo"
run_tracked_command() {
    "$@" &
    local pid=$!
    BACKUPD_CHILD_PIDS+=("$pid")
    wait "$pid"
    local exit_code=$?
    # Remove PID from tracking array
    BACKUPD_CHILD_PIDS=("${BACKUPD_CHILD_PIDS[@]/$pid/}")
    return $exit_code
}

# ---------- Package Manager Functions ----------

# Package manager detection (cached)
PKG_MANAGER="${PKG_MANAGER:-}"
PKG_UPDATED="${PKG_UPDATED:-false}"

# Detect the system's package manager based on OS distribution
detect_package_manager() {
    if [[ -n "$PKG_MANAGER" ]]; then
        echo "$PKG_MANAGER"
        return
    fi

    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        case "$ID" in
            debian|ubuntu|linuxmint|pop|elementary|zorin|kali|raspbian)
                PKG_MANAGER="apt"
                ;;
            rhel|centos|fedora|almalinux|rocky|ol|amzn)
                if command -v dnf &>/dev/null; then
                    PKG_MANAGER="dnf"
                else
                    PKG_MANAGER="yum"
                fi
                ;;
            arch|manjaro|endeavouros|artix)
                PKG_MANAGER="pacman"
                ;;
            alpine)
                PKG_MANAGER="apk"
                ;;
            opensuse*|sles|suse)
                PKG_MANAGER="zypper"
                ;;
            *)
                PKG_MANAGER="unknown"
                ;;
        esac
    elif [[ -f /etc/redhat-release ]]; then
        if command -v dnf &>/dev/null; then
            PKG_MANAGER="dnf"
        else
            PKG_MANAGER="yum"
        fi
    elif [[ -f /etc/debian_version ]]; then
        PKG_MANAGER="apt"
    elif [[ -f /etc/arch-release ]]; then
        PKG_MANAGER="pacman"
    elif [[ -f /etc/alpine-release ]]; then
        PKG_MANAGER="apk"
    else
        PKG_MANAGER="unknown"
    fi

    echo "$PKG_MANAGER"
}

# Update package manager cache (runs only once per session)
pkg_update() {
    if [[ "$PKG_UPDATED" == "true" ]]; then
        return 0
    fi

    local pm
    pm=$(detect_package_manager)

    case "$pm" in
        apt)
            apt-get update -qq 2>/dev/null || true
            ;;
        pacman)
            pacman -Sy --noconfirm &>/dev/null || true
            ;;
        apk)
            apk update &>/dev/null || true
            ;;
        zypper)
            zypper refresh -q &>/dev/null || true
            ;;
        dnf|yum)
            # dnf/yum auto-refresh metadata, no update needed
            ;;
        *)
            # Unknown package manager, skip update
            ;;
    esac

    PKG_UPDATED=true
}

# Install a package using the detected package manager
pkg_install() {
    local package="$1"
    local pm
    pm=$(detect_package_manager)

    case "$pm" in
        apt)
            apt-get install -y -qq "$package" 2>/dev/null
            ;;
        dnf)
            dnf install -y -q "$package" 2>/dev/null
            ;;
        yum)
            yum install -y -q "$package" 2>/dev/null
            ;;
        pacman)
            pacman -S --noconfirm --needed "$package" &>/dev/null
            ;;
        apk)
            apk add --quiet "$package" 2>/dev/null
            ;;
        zypper)
            zypper install -y -q "$package" 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Get the install command hint for user-facing error messages
get_install_hint() {
    local package="$1"
    local pm
    pm=$(detect_package_manager)

    case "$pm" in
        apt)
            echo "sudo apt install $package"
            ;;
        dnf)
            echo "sudo dnf install $package"
            ;;
        yum)
            echo "sudo yum install $package"
            ;;
        pacman)
            echo "sudo pacman -S $package"
            ;;
        apk)
            echo "sudo apk add $package"
            ;;
        zypper)
            echo "sudo zypper install $package"
            ;;
        *)
            echo "Install '$package' using your system's package manager"
            ;;
    esac
}

# ---------- Print Functions ----------

print_header() {
  [[ "${QUIET_MODE:-0}" -eq 1 ]] && return
  clear
  echo -e "${BLUE}========================================================${NC}"
  echo -e "${BLUE}              Backupd v${VERSION}${NC}"
  echo -e "${CYAN}                  by ${AUTHOR}${NC}"
  echo -e "${BLUE}========================================================${NC}"
  echo
}

print_disclaimer() {
  [[ "${QUIET_MODE:-0}" -eq 1 ]] && return
  echo -e "${YELLOW}┌────────────────────────────────────────────────────────┐${NC}"
  echo -e "${YELLOW}│                      DISCLAIMER                        │${NC}"
  echo -e "${YELLOW}├────────────────────────────────────────────────────────┤${NC}"
  echo -e "${YELLOW}│ This tool is provided \"as is\" without warranty.        │${NC}"
  echo -e "${YELLOW}│ The author is NOT responsible for any damages or       │${NC}"
  echo -e "${YELLOW}│ data loss. Always create a server SNAPSHOT before      │${NC}"
  echo -e "${YELLOW}│ running backup/restore operations. Use at your risk.   │${NC}"
  echo -e "${YELLOW}└────────────────────────────────────────────────────────┘${NC}"
  echo
}

print_success() {
  [[ "${QUIET_MODE:-0}" -eq 1 ]] && return
  echo -e "${GREEN}✓ $1${NC}"
}

# Errors always print (even in quiet mode) and log to file
print_error() {
  echo -e "${RED}✗ $1${NC}" >&2
  # Log if logging module is loaded (core.sh sourced before logging.sh)
  type log_error &>/dev/null && log_error "$1"
}

print_warning() {
  [[ "${QUIET_MODE:-0}" -eq 1 ]] && return
  echo -e "${YELLOW}! $1${NC}"
  # Log if logging module is loaded (core.sh sourced before logging.sh)
  type log_warn &>/dev/null && log_warn "$1"
}

print_info() {
  [[ "${QUIET_MODE:-0}" -eq 1 ]] && return
  echo -e "${BLUE}→ $1${NC}"
}

press_enter_to_continue() {
  [[ "${QUIET_MODE:-0}" -eq 1 ]] && return
  echo
  read -p "Press Enter to continue..."
}

# ---------- JSON Output Functions ----------

# Output JSON object - usage: json_output '{"key": "value"}'
json_output() {
  echo "$1"
}

# Build simple JSON key-value pair - usage: json_kv "key" "value"
json_kv() {
  local key="$1"
  local value="$2"
  # Escape special characters in value
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '"%s": "%s"' "$key" "$value"
}

# Check if JSON output mode is enabled
is_json_output() {
  [[ "${JSON_OUTPUT:-0}" -eq 1 ]]
}

# ---------- Dry-Run Functions ----------

# Check if dry-run mode is enabled
is_dry_run() {
  [[ "${DRY_RUN:-0}" -eq 1 ]]
}

# Print dry-run message - shows what would be executed
dry_run_msg() {
  local action="$1"
  echo -e "${CYAN}[DRY-RUN]${NC} Would execute: $action"
}

# ---------- Input Validation Functions ----------

# Validate path input - prevent shell injection
validate_path() {
  local path="$1"
  local name="${2:-path}"

  # Check for empty
  if [[ -z "$path" ]]; then
    print_error "$name cannot be empty"
    return 1
  fi

  # Check for dangerous characters (shell metacharacters)
  # Note: [] allowed - valid in filenames, not dangerous when paths are quoted
  if [[ "$path" =~ [\'\"$\`\;\|\&\>\<\(\)\{\}\\] ]]; then
    print_error "$name contains invalid characters"
    return 1
  fi

  # Check for path traversal attempts
  if [[ "$path" =~ \.\. ]]; then
    print_error "$name cannot contain '..'"
    return 1
  fi

  return 0
}

# Validate URL input
validate_url() {
  local url="$1"
  local name="${2:-URL}"

  if [[ -z "$url" ]]; then
    print_error "$name cannot be empty"
    return 1
  fi

  # Basic URL format check
  if [[ ! "$url" =~ ^https?:// ]]; then
    print_error "$name must start with http:// or https://"
    return 1
  fi

  # Check for dangerous characters
  if [[ "$url" =~ [\'\"$\`\;\|\&\>\<\(\)\{\}\\] ]]; then
    print_error "$name contains invalid characters"
    return 1
  fi

  return 0
}

# Display password requirements
show_password_requirements() {
  echo -e "${CYAN}Password Requirements:${NC}"
  echo "  - At least 12 characters long"
  echo "  - At least 2 special characters (!@#\$%^&*()_+-=[]{}|;':\",./<>?\`~)"
  echo
}

# Count special characters in a string
count_special_chars() {
  local str="$1"
  # Count characters that are NOT alphanumeric
  local special_only
  special_only=$(printf '%s' "$str" | tr -d 'a-zA-Z0-9')
  printf '%s' "${#special_only}"
}

# Validate password strength
# Requirements: minimum 12 characters, at least 2 special characters
validate_password() {
  local password="$1"
  local min_length="${2:-12}"
  local min_special="${3:-2}"
  local show_help="${4:-true}"

  if [[ -z "$password" ]]; then
    print_error "Password cannot be empty"
    [[ "$show_help" == "true" ]] && show_password_requirements
    return 1
  fi

  # Check minimum length
  if [[ ${#password} -lt $min_length ]]; then
    print_error "Password must be at least $min_length characters (yours: ${#password})"
    [[ "$show_help" == "true" ]] && show_password_requirements
    return 1
  fi

  # Check special characters
  local special_count
  special_count=$(count_special_chars "$password")
  if [[ $special_count -lt $min_special ]]; then
    print_error "Password must contain at least $min_special special characters (yours: $special_count)"
    [[ "$show_help" == "true" ]] && show_password_requirements
    return 1
  fi

  return 0
}

# ---------- System Check Functions ----------

# Check available disk space (in MB)
check_disk_space() {
  local path="$1"
  local required_mb="${2:-1000}"  # Default 1GB

  local available_mb
  available_mb=$(df -m "$path" 2>/dev/null | awk 'NR==2 {print $4}')

  if [[ -z "$available_mb" ]]; then
    print_warning "Could not check disk space - proceeding anyway"
    log_warn "df output could not be parsed for path: $path"
    return 0
  fi

  if [[ "$available_mb" -lt "$required_mb" ]]; then
    print_error "Insufficient disk space. Available: ${available_mb}MB, Required: ${required_mb}MB"
    return 1
  fi

  return 0
}

# Check network connectivity (supports curl/wget fallback)
# BACKUPD-007 FIX: Add wget fallback for systems without curl
check_network() {
  local host="${1:-1.1.1.1}"
  local timeout="${2:-5}"

  # Try curl first (ICMP often blocked on servers)
  if command -v curl &>/dev/null; then
    if curl -s --connect-timeout "$timeout" "https://www.google.com" &>/dev/null; then
      return 0
    fi
  elif command -v wget &>/dev/null; then
    if wget -q --timeout="$timeout" -O /dev/null "https://www.google.com" 2>/dev/null; then
      return 0
    fi
  fi

  # Fallback to ping
  if ! ping -c 1 -W "$timeout" "$host" &>/dev/null; then
    print_error "No network connectivity"
    return 1
  fi

  return 0
}

# Download file with curl/wget fallback
# Usage: download_to_file URL OUTPUT_FILE [TIMEOUT]
# BACKUPD-007 FIX: Support both curl and wget for maximum compatibility
download_to_file() {
  local url="$1"
  local output="$2"
  local timeout="${3:-30}"

  if command -v curl &>/dev/null; then
    curl -sfL --proto '=https' --connect-timeout 10 --max-time "$timeout" "$url" -o "$output" 2>/dev/null
  elif command -v wget &>/dev/null; then
    wget -q --timeout="$timeout" -O "$output" "$url" 2>/dev/null
  else
    return 1
  fi
}

# Fetch URL content to stdout with curl/wget fallback
# Usage: fetch_url URL [TIMEOUT]
# BACKUPD-007 FIX: Support both curl and wget for maximum compatibility
fetch_url() {
  local url="$1"
  local timeout="${2:-10}"

  if command -v curl &>/dev/null; then
    curl -sfL --proto '=https' --connect-timeout 10 --max-time "$timeout" "$url" 2>/dev/null
  elif command -v wget &>/dev/null; then
    wget -q --timeout="$timeout" -O - "$url" 2>/dev/null
  else
    return 1
  fi
}

# ---------- MySQL Helper Functions ----------

# Create MySQL credentials file (more secure than command line)
create_mysql_auth_file() {
  local user="$1"
  local pass="$2"
  local auth_file

  auth_file="$(mktemp)"
  chmod 600 "$auth_file"

  cat > "$auth_file" << EOF
[client]
user=$user
password=$pass
EOF

  echo "$auth_file"
}

# ---------- Logging Functions ----------

# Maximum log file size (10MB)
MAX_LOG_SIZE=$((10 * 1024 * 1024))

# Rotate log file if it exceeds max size
rotate_log() {
  local log_file="$1"
  local max_backups="${2:-5}"

  [[ ! -f "$log_file" ]] && return 0

  local log_size
  log_size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)

  if [[ "$log_size" -gt "$MAX_LOG_SIZE" ]]; then
    # Remove oldest backup
    [[ -f "${log_file}.${max_backups}" ]] && rm -f "${log_file}.${max_backups}"

    # Rotate existing backups
    for ((i=max_backups-1; i>=1; i--)); do
      [[ -f "${log_file}.${i}" ]] && mv "${log_file}.${i}" "${log_file}.$((i+1))"
    done

    # Rotate current log
    mv "$log_file" "${log_file}.1"
    touch "$log_file"
    chmod 600 "$log_file"
  fi
}

# ---------- Secure File Operations ----------

# Secure temp directory creation (prevent symlink attacks)
create_secure_temp() {
  local prefix="${1:-backupd}"
  local temp_dir

  # Create temp dir with restricted permissions
  temp_dir="$(mktemp -d -t "${prefix}.XXXXXXXXXX")"

  # Verify it's actually a directory and owned by us
  if [[ ! -d "$temp_dir" ]] || [[ ! -O "$temp_dir" ]]; then
    print_error "Failed to create secure temp directory"
    return 1
  fi

  # Set restrictive permissions
  chmod 700 "$temp_dir"

  echo "$temp_dir"
}

# Safe file write (atomic)
safe_write_file() {
  local target="$1"
  local content="$2"
  local temp_file

  temp_file="$(mktemp "${target}.XXXXXXXXXX")"

  if echo "$content" > "$temp_file" 2>/dev/null; then
    chmod 600 "$temp_file"
    mv "$temp_file" "$target"
    return 0
  else
    rm -f "$temp_file"
    return 1
  fi
}

# ---------- Panel Detection Functions ----------

# Panel definitions: name|pattern|webroot_subdir|detection_method
# webroot_subdir: subdirectory containing web files (empty = direct)
declare -A PANEL_DEFINITIONS=(
  ["enhance"]="Enhance|/var/www/*/public_html|public_html|service"
  ["xcloud"]="xCloud|/var/www/*|.|user"
  ["runcloud"]="RunCloud|/home/*/webapps/*|.|user"
  ["ploi"]="Ploi|/home/*/*|.|user"
  ["cpanel"]="cPanel|/home/*/public_html|.|file"
  ["plesk"]="Plesk|/var/www/vhosts/*/httpdocs|.|service"
  ["cloudpanel"]="CloudPanel|/home/*/htdocs/*|.|service"
  ["cyberpanel"]="CyberPanel|/home/*/public_html|.|service"
  ["aapanel"]="aaPanel|/www/wwwroot/*|.|service"
  ["hestia"]="HestiaCP|/home/*/web/*/public_html|public_html|service"
  ["flashpanel"]="FlashPanel|/home/flashpanel/*|.|service"
  ["flashpanel-isolated"]="FlashPanel (Isolated)|/home/*/*|.|service"
  ["virtualmin"]="Virtualmin|/home/*/public_html|.|file"
  ["custom"]="Custom|/var/www/*|.|none"
)

# Check if a service is running
is_service_running() {
  local service_name="$1"
  systemctl is-active --quiet "$service_name" 2>/dev/null
}

# Check if a file/directory pattern exists
# Requires Bash (uses compgen builtin)
pattern_exists() {
  local pattern="$1"
  compgen -G "$pattern" >/dev/null 2>&1
}

# Detect panel by checking services
detect_panel_by_service() {
  # Enhance panel - runs appcd.service
  if is_service_running "appcd" || [[ -d "/var/local/enhance" ]]; then
    echo "enhance"
    return 0
  fi

  # Plesk
  if is_service_running "psa" || is_service_running "plesk-web-configurator"; then
    echo "plesk"
    return 0
  fi

  # CloudPanel
  if is_service_running "clp" || [[ -f "/home/clp-data/credentials" ]]; then
    echo "cloudpanel"
    return 0
  fi

  # CyberPanel
  if is_service_running "lscpd" || [[ -d "/usr/local/CyberCP" ]]; then
    echo "cyberpanel"
    return 0
  fi

  # aaPanel (BaoTa)
  if is_service_running "bt" || [[ -d "/www/server/panel" ]]; then
    echo "aapanel"
    return 0
  fi

  # HestiaCP
  if is_service_running "hestia" || [[ -d "/usr/local/hestia" ]]; then
    echo "hestia"
    return 0
  fi

  # FlashPanel
  if is_service_running "flashpanel" || [[ -f "/root/.flashpanel/agent/flashpanel" ]]; then
    detect_flashpanel_isolation_mode
    return 0
  fi

  return 1
}

# Check if a system user exists (in /etc/passwd)
user_exists() {
  local username="$1"
  getent passwd "$username" >/dev/null 2>&1
}

# Detect panel by checking user patterns
detect_panel_by_user() {
  # xCloud - has xcloud user in /etc/passwd (no service to detect)
  if user_exists "xcloud"; then
    echo "xcloud"
    return 0
  fi

  # RunCloud - has runcloud user in /etc/passwd
  if user_exists "runcloud"; then
    echo "runcloud"
    return 0
  fi

  # Ploi - has ploi user in /etc/passwd
  if user_exists "ploi"; then
    echo "ploi"
    return 0
  fi

  return 1
}

# Detect panel by checking file patterns
detect_panel_by_files() {
  # cPanel - WHM/cPanel specific files
  if [[ -f "/usr/local/cpanel/cpanel" ]] || [[ -d "/usr/local/cpanel" ]]; then
    echo "cpanel"
    return 0
  fi

  # Virtualmin - Webmin with Virtualmin
  if [[ -d "/etc/webmin/virtual-server" ]]; then
    echo "virtualmin"
    return 0
  fi

  return 1
}

# Detect FlashPanel isolation mode
# Returns 'flashpanel' for non-isolated (sites in /home/flashpanel/)
# Returns 'flashpanel-isolated' for isolated (sites in /home/{user}/)
detect_flashpanel_isolation_mode() {
  # Check if /home/flashpanel/ exists and has site subdirectories
  if [[ -d "/home/flashpanel" ]] && compgen -G "/home/flashpanel/*" >/dev/null 2>&1; then
    echo "flashpanel"
  else
    echo "flashpanel-isolated"
  fi
}

# Auto-detect installed panel
detect_panel() {
  local detected=""

  # Try service detection first (most reliable)
  detected=$(detect_panel_by_service)
  [[ -n "$detected" ]] && echo "$detected" && return 0

  # Try user-based detection
  detected=$(detect_panel_by_user)
  [[ -n "$detected" ]] && echo "$detected" && return 0

  # Try file-based detection
  detected=$(detect_panel_by_files)
  [[ -n "$detected" ]] && echo "$detected" && return 0

  # Fallback: check common paths
  if pattern_exists "/var/www/*/public_html"; then
    echo "enhance"  # Most likely Enhance-style
    return 0
  fi

  if pattern_exists "/home/*/webapps/*"; then
    echo "runcloud"
    return 0
  fi

  if pattern_exists "/home/*/public_html"; then
    echo "cpanel"  # Generic cPanel-style
    return 0
  fi

  # Default to custom with /var/www
  echo "custom"
  return 0
}

# Get panel info by key
get_panel_info() {
  local panel_key="$1"
  local field="$2"  # name, pattern, webroot_subdir, detection_method

  local panel_data="${PANEL_DEFINITIONS[$panel_key]:-}"
  [[ -z "$panel_data" ]] && return 1

  case "$field" in
    name)
      echo "$panel_data" | cut -d'|' -f1
      ;;
    pattern)
      echo "$panel_data" | cut -d'|' -f2
      ;;
    webroot_subdir)
      echo "$panel_data" | cut -d'|' -f3
      ;;
    detection_method)
      echo "$panel_data" | cut -d'|' -f4
      ;;
    *)
      return 1
      ;;
  esac
}

# Get all panel keys
get_all_panel_keys() {
  echo "${!PANEL_DEFINITIONS[@]}" | tr ' ' '\n' | sort
}

# Count sites for a given pattern
count_sites_for_pattern() {
  local pattern="$1"
  local count=0

  for dir in $pattern; do
    [[ -d "$dir" ]] && { ((count++)) || true; }
  done

  echo "$count"
}

# ---------- Site Naming Functions ----------

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

  # 4. Generic: try to extract from nginx/apache configs in common locations
  # Check for server_name in nginx configs
  if [[ -d "/etc/nginx/sites-enabled" ]]; then
    local nginx_name
    nginx_name="$(grep -rh "server_name" /etc/nginx/sites-enabled/ 2>/dev/null | grep -i "$(basename "$site_path")" | head -1 | awk '{print $2}' | tr -d ';' || true)"
    [[ -n "$nginx_name" && "$nginx_name" != "_" ]] && echo "$nginx_name" && return 0
  fi

  # 5. Fallback: use folder name
  echo "$(basename "$site_path")"
}

# Sanitize name for use as filename
sanitize_for_filename() {
  local s="$1"
  s="$(echo -n "$s" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  s="${s//:\/\//__}"; s="${s//\//__}"
  s="$(echo -n "$s" | sed -E 's/[^a-z0-9._-]+/_/g')"
  s="${s%.}"
  [[ -z "$s" ]] && s="unknown-site"
  printf "%s" "$s"
}

# ---------- Dependency Installation ----------

# Install rclone with SHA256 verification
# Downloads from GitHub releases with checksum verification for security
# NOTE: This function is also in install.sh (standalone installer).
#       Keep both copies synchronized when making changes.
install_rclone_verified() {
  local arch
  local os="linux"

  # Detect architecture
  case "$(uname -m)" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
    armv7l)  arch="arm-v7" ;;
    armv6l)  arch="arm" ;;
    i686)    arch="386" ;;
    *)
      print_warning "Unsupported architecture: $(uname -m)"
      print_info "Please install rclone manually: https://rclone.org/install/"
      return 1
      ;;
  esac

  # Get latest version from GitHub API (uses fetch_url for curl/wget fallback)
  local latest_version
  latest_version=$(fetch_url "https://api.github.com/repos/rclone/rclone/releases/latest" 10 | \
    grep '"tag_name"' | head -1 | sed -E 's/.*"v([^"]+)".*/\1/')

  if [[ -z "$latest_version" ]]; then
    print_warning "Could not determine latest rclone version"
    print_info "Please install rclone manually: https://rclone.org/install/"
    return 1
  fi

  echo "  Latest version: v${latest_version}"

  local filename="rclone-v${latest_version}-${os}-${arch}.zip"
  local download_url="https://github.com/rclone/rclone/releases/download/v${latest_version}/${filename}"
  local checksum_url="https://github.com/rclone/rclone/releases/download/v${latest_version}/SHA256SUMS"

  local temp_dir
  temp_dir=$(mktemp -d)
  trap "rm -rf '$temp_dir'" RETURN

  # Download the archive (uses download_to_file for curl/wget fallback)
  echo "  Downloading ${filename}..."
  if ! download_to_file "$download_url" "${temp_dir}/${filename}" 300; then
    print_error "Failed to download rclone"
    return 1
  fi

  # Verify download is not empty
  if [[ ! -s "${temp_dir}/${filename}" ]]; then
    print_error "Downloaded file is empty"
    return 1
  fi

  # Download checksum file (uses download_to_file for curl/wget fallback)
  echo "  Verifying checksum..."
  if ! download_to_file "$checksum_url" "${temp_dir}/SHA256SUMS" 60; then
    print_error "Could not download checksum file"
    print_error "Aborting - install rclone manually for security"
    return 1
  fi

  # Extract expected checksum
  local expected_checksum
  expected_checksum=$(grep "${filename}" "${temp_dir}/SHA256SUMS" 2>/dev/null | awk '{print $1}')

  if [[ -z "$expected_checksum" ]]; then
    print_error "Checksum not found for ${filename}"
    print_error "Aborting - install rclone manually for security"
    return 1
  fi

  # Calculate actual checksum
  local actual_checksum
  actual_checksum=$(sha256sum "${temp_dir}/${filename}" | awk '{print $1}')

  if [[ "$expected_checksum" != "$actual_checksum" ]]; then
    print_error "Checksum verification FAILED!"
    print_error "Expected: ${expected_checksum}"
    print_error "Got:      ${actual_checksum}"
    print_error "The download may be corrupted or tampered with"
    return 1
  fi

  print_success "Checksum verified"

  # Extract and install
  echo "  Installing..."
  if ! unzip -q "${temp_dir}/${filename}" -d "${temp_dir}" 2>/dev/null; then
    print_warning "Failed to extract (is unzip installed?)"
    # Try to install unzip and retry (skip on unsupported distros)
    local pm
    pm=$(detect_package_manager)
    if [[ "$pm" != "unknown" ]]; then
      pkg_install unzip || true
    fi
    if ! unzip -q "${temp_dir}/${filename}" -d "${temp_dir}" 2>/dev/null; then
      if [[ "$pm" == "unknown" ]]; then
        print_warning "unzip not found - please install manually"
      else
        print_error "Failed to extract rclone"
      fi
      return 1
    fi
  fi

  # Copy binary to /usr/bin
  local rclone_binary="${temp_dir}/rclone-v${latest_version}-${os}-${arch}/rclone"
  if [[ -f "$rclone_binary" ]]; then
    cp "$rclone_binary" /usr/bin/rclone
    chmod 755 /usr/bin/rclone
    print_success "rclone v${latest_version} installed successfully"
    return 0
  else
    print_error "Could not find rclone binary in archive"
    return 1
  fi
}
