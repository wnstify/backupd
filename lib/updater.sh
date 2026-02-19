#!/usr/bin/env bash
# ============================================================================
# Backupd - Updater Module
# Auto-update functionality with GitHub releases
# ============================================================================

# GitHub repository details
GITHUB_REPO="wnstify/backupd"
GITHUB_API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
GITHUB_RELEASE_URL="https://github.com/${GITHUB_REPO}/releases/download"

# Update check cache (check once per 24 hours)
# BUG-004 FIX: Use user-specific cache directory to prevent symlink attacks
get_update_cache_file() {
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/backupd"
  if [[ ! -d "$cache_dir" ]]; then
    mkdir -p "$cache_dir" 2>/dev/null && chmod 700 "$cache_dir" 2>/dev/null
  fi
  echo "${cache_dir}/update-check"
}

UPDATE_CHECK_INTERVAL=$((24 * 60))  # 24 hours in minutes

# Retry wrapper for curl commands with wget fallback (handles transient network failures)
# BUG-012 FIX: Add retry logic to downloads
# BACKUPD-007 FIX: Add wget fallback for systems without curl
curl_with_retry() {
  local max_retries=3
  local retry=0
  local delay=2

  # Try curl first if available
  if command -v curl &>/dev/null; then
    while ((retry < max_retries)); do
      if curl "$@"; then
        return 0
      fi
      ((retry++))
      if ((retry < max_retries)); then
        sleep $((delay * retry))
      fi
    done
  fi

  # Fallback to wget if curl failed or unavailable
  if command -v wget &>/dev/null; then
    # Convert curl args to wget: extract URL and output file
    local url="" output="" args=("$@")
    local i=0
    while ((i < ${#args[@]})); do
      case "${args[i]}" in
        -o) ((i++)); output="${args[i]}" ;;
        -s|-f|-L|--proto=*|--proto|--tlsv1.2|--connect-timeout|--max-time)
          # Skip curl-specific flags
          [[ "${args[i]}" == "--proto" || "${args[i]}" == "--connect-timeout" || "${args[i]}" == "--max-time" ]] && ((i++))
          ;;
        http://*|https://*) url="${args[i]}" ;;
      esac
      ((i++))
    done

    if [[ -n "$url" ]]; then
      retry=0
      while ((retry < max_retries)); do
        if [[ -n "$output" ]]; then
          if wget -q --timeout=30 -O "$output" "$url" 2>/dev/null; then
            return 0
          fi
        else
          if wget -q --timeout=30 -O - "$url" 2>/dev/null; then
            return 0
          fi
        fi
        ((retry++))
        if ((retry < max_retries)); then
          sleep $((delay * retry))
        fi
      done
    fi
  fi

  return 1
}

# ---------- Version Comparison ----------

# Compare semantic versions (returns: 0 = equal, 1 = v1 > v2, 2 = v1 < v2)
version_compare() {
  local v1="$1"
  local v2="$2"

  # Remove 'v' prefix if present
  v1="${v1#v}"
  v2="${v2#v}"

  # BUG-017 FIX: Validate inputs - empty versions are invalid
  if [[ -z "$v1" ]] || [[ -z "$v2" ]]; then
    log_warn "version_compare: empty version string (v1='$v1', v2='$v2')" 2>/dev/null || true
    return 3  # Invalid input
  fi

  # BUG-007 FIX: Remove pre-release suffix (e.g., -alpha, -beta, -rc1)
  v1="${v1%%-*}"
  v2="${v2%%-*}"

  if [[ "$v1" == "$v2" ]]; then
    return 0
  fi

  # Split versions into components
  local IFS='.'
  # shellcheck disable=SC2206  # Intentional: word splitting to populate arrays
  local i v1_parts=($v1) v2_parts=($v2)

  # Compare each component
  for ((i=0; i<${#v1_parts[@]} || i<${#v2_parts[@]}; i++)); do
    local n1="${v1_parts[i]:-0}"
    local n2="${v2_parts[i]:-0}"

    if ((n1 > n2)); then
      return 1
    elif ((n1 < n2)); then
      return 2
    fi
  done

  return 0
}

# Check if update is available (returns 0 if update available)
is_update_available() {
  local current="$1"
  local latest="$2"

  version_compare "$current" "$latest"
  local result=$?

  [[ $result -eq 2 ]]  # Current is less than latest
}

# ---------- Update Check Functions ----------

# Check GitHub for latest version
# BACKUPD-007 FIX: Add wget fallback for systems without curl
get_latest_version() {
  local latest=""
  local response=""

  # Try to get latest release from GitHub API
  # BUG-009 FIX: Add --tlsv1.2 to enforce minimum TLS version
  if command -v curl &>/dev/null; then
    response=$(curl -s --proto '=https' --tlsv1.2 --connect-timeout 5 "$GITHUB_API_URL" 2>/dev/null) || true
  elif command -v wget &>/dev/null; then
    response=$(wget -q --timeout=5 -O - "$GITHUB_API_URL" 2>/dev/null) || true
  fi

  if [[ -z "$response" ]]; then
    log_debug "Failed to fetch latest version from GitHub API" 2>/dev/null || true
    echo ""
    return 1
  fi

  # BUG-013 FIX: Use jq for robust JSON parsing if available, fallback to grep/sed
  if command -v jq &>/dev/null; then
    latest=$(echo "$response" | jq -r '.tag_name // empty' 2>/dev/null)
  else
    latest=$(echo "$response" | grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
  fi

  # Remove 'v' prefix if present
  latest="${latest#v}"

  echo "$latest"
}

# Get release download URL for specific version
get_release_url() {
  local version="$1"
  echo "${GITHUB_RELEASE_URL}/v${version}/backupd-v${version}.tar.gz"
}

# Get checksum URL for specific version
get_checksum_url() {
  local version="$1"
  echo "${GITHUB_RELEASE_URL}/v${version}/SHA256SUMS"
}

# Should we check for updates? (respects 24h cache)
should_check_updates() {
  # Skip if no network check file or file is old
  if [[ ! -f "$(get_update_cache_file)" ]]; then
    return 0  # Should check
  fi

  # Check if file is older than UPDATE_CHECK_INTERVAL minutes
  if [[ $(find "$(get_update_cache_file)" -mmin +${UPDATE_CHECK_INTERVAL} 2>/dev/null) ]]; then
    return 0  # Should check
  fi

  return 1  # Recently checked, skip
}

# Silent update check on startup (non-blocking)
check_for_updates_silent() {
  # BUG-015 FIX: Use flock to prevent race conditions with multiple instances
  # The subshell with flock ensures only one instance checks at a time
  local lock_file="$(get_update_cache_file).lock"
  local result

  result=$(
    # Try to acquire lock non-blocking (-n), exit if already held
    if command -v flock &>/dev/null; then
      exec 200>"$lock_file"
      flock -n 200 || exit 1
    fi

    # Skip if recently checked
    if ! should_check_updates; then
      # Read cached result
      if [[ -f "$(get_update_cache_file)" ]]; then
        local cached_version
        cached_version=$(cat "$(get_update_cache_file)" 2>/dev/null)
        if [[ -n "$cached_version" && "$cached_version" != "$VERSION" ]]; then
          if is_update_available "$VERSION" "$cached_version"; then
            echo "$cached_version"
            exit 0
          fi
        fi
      fi
      exit 1
    fi

    # BUG-006 FIX: Check network using HTTP (ICMP often blocked in containers/firewalls)
    if ! curl -sfI --proto '=https' --tlsv1.2 --connect-timeout 2 "https://api.github.com" &>/dev/null; then
      exit 1  # No network or GitHub unreachable
    fi

    # Get latest version
    local latest
    latest=$(get_latest_version)

    # Cache the result
    echo "$latest" > "$(get_update_cache_file)" 2>/dev/null || true

    if [[ -n "$latest" ]] && is_update_available "$VERSION" "$latest"; then
      echo "$latest"
      exit 0
    fi

    exit 1
  )
  local exit_code=$?

  if [[ $exit_code -eq 0 && -n "$result" ]]; then
    echo "$result"
    return 0
  fi
  return 1
}

# Show update banner if available
show_update_banner() {
  log_func_enter 2>/dev/null || true
  debug_enter "show_update_banner" 2>/dev/null || true
  # Skip update banner for non-main branch installations
  local installed_branch
  installed_branch=$(get_installed_branch 2>/dev/null || echo "main")
  if [[ "$installed_branch" != "main" ]]; then
    return 0
  fi

  local latest_version
  latest_version=$(check_for_updates_silent) || true

  if [[ -n "$latest_version" ]]; then
    echo -e "${YELLOW}Update available: ${VERSION} → ${latest_version}${NC}"
    echo -e "${YELLOW}Run 'backupd --update' or select 'U' from menu${NC}"
    echo
  fi
  return 0
}

# ---------- Update Execution Functions ----------

# Download and verify update
download_update() {
  local version="$1"
  local temp_dir="$2"

  local release_url
  release_url=$(get_release_url "$version")

  local checksum_url
  checksum_url=$(get_checksum_url "$version")

  print_info "Downloading version ${version}..."

  # Download release archive with strict security options
  # -s: silent, -f: fail on HTTP errors, -L: follow redirects
  # --proto '=https': only allow HTTPS protocol
  # BUG-009 FIX: Add --tlsv1.2 for minimum TLS version
  # BUG-012 FIX: Use curl_with_retry for transient network failures
  if ! curl_with_retry -sfL --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 300 "$release_url" -o "${temp_dir}/update.tar.gz"; then
    print_error "Failed to download update"
    return 1
  fi

  # Verify download is not empty
  if [[ ! -s "${temp_dir}/update.tar.gz" ]]; then
    print_error "Downloaded file is empty"
    return 1
  fi

  # Download and verify checksum (REQUIRED for security)
  local checksum_file="${temp_dir}/SHA256SUMS"
  print_info "Downloading checksum..."

  # BUG-009+012+014 FIX: Add --tlsv1.2, --max-time, and use curl_with_retry
  if ! curl_with_retry -sfL --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 60 "$checksum_url" -o "$checksum_file" 2>/dev/null; then
    print_error "Failed to download checksum file"
    print_error "Updates require SHA256 verification for security"
    return 1
  fi

  # Verify checksum file is not empty
  if [[ ! -s "$checksum_file" ]]; then
    print_error "Checksum file is empty or invalid"
    return 1
  fi

  print_info "Verifying checksum..."

  # Extract expected checksum for our file
  local expected_checksum
  # BUG-008 FIX: Use grep -F for fixed string matching (prevents regex injection)
  expected_checksum=$(grep -F "backupd-v${version}.tar.gz" "$checksum_file" 2>/dev/null | awk '{print $1}')

  if [[ -z "$expected_checksum" ]]; then
    print_error "Checksum for backupd-v${version}.tar.gz not found in SHA256SUMS"
    print_error "This may indicate a corrupted or tampered release"
    return 1
  fi

  local actual_checksum
  actual_checksum=$(sha256sum "${temp_dir}/update.tar.gz" | awk '{print $1}')

  if [[ "$expected_checksum" != "$actual_checksum" ]]; then
    print_error "Checksum verification failed!"
    print_error "Expected: $expected_checksum"
    print_error "Got:      $actual_checksum"
    print_error "The download may be corrupted or tampered with"
    return 1
  fi

  print_success "Checksum verified"
  return 0
}

# Backup current installation
backup_current_version() {
  log_func_enter 2>/dev/null || true
  debug_enter "backup_current_version" 2>/dev/null || true
  local backup_dir="${SCRIPT_DIR}.backup"

  # Remove old backup if exists
  [[ -d "$backup_dir" ]] && rm -rf "$backup_dir"

  # BUG-005 FIX: Check backup success (could fail due to disk full or permissions)
  if ! cp -r "$SCRIPT_DIR" "$backup_dir"; then
    print_error "Failed to backup current version (disk full or permission denied)"
    return 1
  fi

  print_success "Current version backed up to: $backup_dir"
  return 0
}

# Restore from backup (rollback)
rollback_update() {
  log_func_enter 2>/dev/null || true
  debug_enter "rollback_update" 2>/dev/null || true
  log_warn "Rolling back update"
  local backup_dir="${SCRIPT_DIR}.backup"
  local failed_dir="${SCRIPT_DIR}.failed"

  if [[ ! -d "$backup_dir" ]]; then
    print_error "No backup found to restore"
    return 1
  fi

  print_info "Rolling back to previous version..."

  # BUG-011 FIX: Safe rollback using rename instead of delete
  # This prevents having no installation if mv fails

  # Step 1: Rename current (failed) version to .failed
  if [[ -d "$SCRIPT_DIR" ]]; then
    rm -rf "$failed_dir" 2>/dev/null || true  # Clean up any previous failed attempt
    if ! mv "$SCRIPT_DIR" "$failed_dir"; then
      print_error "Failed to move current installation aside"
      return 1
    fi
  fi

  # Step 2: Restore backup
  if ! mv "$backup_dir" "$SCRIPT_DIR"; then
    print_error "Failed to restore backup"
    # Try to recover by moving failed version back
    if [[ -d "$failed_dir" ]]; then
      mv "$failed_dir" "$SCRIPT_DIR" 2>/dev/null || true
    fi
    return 1
  fi

  # Step 3: Only delete failed version after successful restore
  rm -rf "$failed_dir" 2>/dev/null || true

  print_success "Rollback complete"
  return 0
}

# Apply update
apply_update() {
  log_func_enter 2>/dev/null || true
  debug_enter "apply_update" 2>/dev/null || true
  local temp_dir="$1"

  print_info "Applying update..."

  # Extract to temp location first
  local extract_dir="${temp_dir}/extracted"
  mkdir -p "$extract_dir"

  # BUG-002 FIX: Security check for path traversal attacks before extraction
  if tar -tzf "${temp_dir}/update.tar.gz" 2>/dev/null | grep -qE '(^/|^\.\./|/\.\./|/\.\.$)'; then
    print_error "Archive contains suspicious paths (possible path traversal attack)"
    return 1
  fi

  if ! tar -xzf "${temp_dir}/update.tar.gz" -C "$extract_dir"; then
    print_error "Failed to extract update"
    return 1
  fi

  # Find the extracted directory (might be nested)
  # Use portable find syntax (works on both GNU and BSD)
  local source_dir
  local found_script
  found_script=$(find "$extract_dir" -maxdepth 2 -name "backupd.sh" 2>/dev/null | head -1)
  source_dir=$(dirname "$found_script" 2>/dev/null)

  if [[ -z "$source_dir" || ! -f "${source_dir}/backupd.sh" ]]; then
    print_error "Invalid update archive structure"
    return 1
  fi

  # BUG-010 FIX: Atomic update using staging directory
  # This prevents partial updates if copy fails mid-way
  local staging_dir="${SCRIPT_DIR}.staging"
  local old_dir="${SCRIPT_DIR}.old"

  # Step 1: Create staging directory with copy of current installation
  rm -rf "$staging_dir" 2>/dev/null || true
  if ! cp -r "$SCRIPT_DIR" "$staging_dir"; then
    print_error "Failed to create staging directory"
    return 1
  fi

  # Step 2: Apply new files to staging
  if ! cp -r "${source_dir}/"* "$staging_dir/"; then
    print_error "Failed to apply update to staging"
    rm -rf "$staging_dir"
    return 1
  fi

  # Step 3: Verify staging (syntax check)
  chmod +x "$staging_dir/backupd.sh"
  chmod +x "$staging_dir/lib/"*.sh 2>/dev/null || true

  if ! bash -n "$staging_dir/backupd.sh" 2>/dev/null; then
    print_error "Syntax error in staged update"
    rm -rf "$staging_dir"
    return 1
  fi

  # Step 4: Atomic swap - move current to old, staging to current
  rm -rf "$old_dir" 2>/dev/null || true
  if ! mv "$SCRIPT_DIR" "$old_dir"; then
    print_error "Failed to move current installation aside"
    rm -rf "$staging_dir"
    return 1
  fi

  if ! mv "$staging_dir" "$SCRIPT_DIR"; then
    print_error "Failed to install staged update"
    # Try to recover
    mv "$old_dir" "$SCRIPT_DIR" 2>/dev/null || true
    return 1
  fi

  # Step 5: Clean up old version only after successful swap
  rm -rf "$old_dir" 2>/dev/null || true

  return 0
}

# Verify update was successful
verify_update() {
  local expected_version="$1"

  # Source the new version to get VERSION
  local new_version
  new_version=$(grep '^VERSION=' "$SCRIPT_DIR/backupd.sh" 2>/dev/null | cut -d'"' -f2)

  if [[ "$new_version" != "$expected_version" ]]; then
    print_error "Version mismatch after update"
    print_error "Expected: $expected_version, Got: $new_version"
    return 1
  fi

  # Basic syntax check
  if ! bash -n "$SCRIPT_DIR/backupd.sh" 2>/dev/null; then
    print_error "Syntax error in updated script"
    return 1
  fi

  return 0
}

# ---------- Branch Detection ----------

# Get installed branch (default: main)
get_installed_branch() {
  local branch_file="${INSTALL_DIR}/.installed_branch"
  if [[ -f "$branch_file" ]]; then
    cat "$branch_file" 2>/dev/null | tr -d '[:space:]'
  else
    echo "main"
  fi
}

# ---------- Main Update Function ----------

# Perform the update
do_update() {
  log_func_enter 2>/dev/null || true
  debug_enter "do_update" 2>/dev/null || true
  log_info "Starting update process"
  print_header
  echo "Update Backupd"
  echo "=============="
  echo

  # Check if installed from non-main branch
  local installed_branch
  installed_branch=$(get_installed_branch)

  if [[ "$installed_branch" != "main" ]]; then
    print_warning "This installation is from the '${installed_branch}' branch."
    echo
    echo "Regular updates download from GitHub releases (main branch)."
    echo "To update from '${installed_branch}' branch, use:"
    echo
    echo "  backupd --dev-update"
    echo
    read -p "Continue with release update anyway? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Update cancelled. Use --dev-update for branch updates."
      press_enter_to_continue
      return 0
    fi
    echo
  fi

  # Check current version
  print_info "Current version: ${VERSION}"

  # Check for latest version
  print_info "Checking for updates..."

  local latest_version
  latest_version=$(get_latest_version)

  if [[ -z "$latest_version" ]]; then
    print_error "Failed to check for updates. Please check your internet connection."
    press_enter_to_continue
    return 1
  fi

  print_info "Latest version:  ${latest_version}"
  echo

  # Compare versions
  if ! is_update_available "$VERSION" "$latest_version"; then
    print_success "You are already running the latest version!"
    press_enter_to_continue
    return 0
  fi

  # Confirm update
  echo -e "${YELLOW}Update available: ${VERSION} → ${latest_version}${NC}"
  echo
  echo "This will:"
  echo "  - Download the new version from GitHub"
  echo "  - Backup your current installation"
  echo "  - Replace script files (NOT your configuration)"
  echo "  - Your settings and credentials will be preserved"
  echo
  read -p "Proceed with update? [y/N]: " confirm

  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Update cancelled."
    press_enter_to_continue
    return 0
  fi

  echo

  # Create temp directory
  local temp_dir
  temp_dir=$(create_secure_temp "backupd-update")

  # Download update
  if ! download_update "$latest_version" "$temp_dir"; then
    rm -rf "$temp_dir"
    press_enter_to_continue
    return 1
  fi

  # Backup current version
  # BUG-005 FIX: Check backup return value before proceeding
  if ! backup_current_version; then
    print_error "Cannot proceed without backup"
    rm -rf "$temp_dir"
    press_enter_to_continue
    return 1
  fi

  # Apply update
  if ! apply_update "$temp_dir"; then
    print_error "Update failed, rolling back..."
    rollback_update
    rm -rf "$temp_dir"
    press_enter_to_continue
    return 1
  fi

  # Verify update
  if ! verify_update "$latest_version"; then
    print_error "Update verification failed, rolling back..."
    rollback_update
    rm -rf "$temp_dir"
    press_enter_to_continue
    return 1
  fi

  # Cleanup
  rm -rf "$temp_dir"

  # Clear update check cache
  rm -f "$(get_update_cache_file)"

  # Auto-regenerate backup scripts to include new features
  print_info "Regenerating backup scripts..."
  source "$LIB_DIR/notifications.sh" 2>/dev/null || true
  if type regenerate_scripts_silent &>/dev/null; then
    regenerate_scripts_silent && print_success "Backup scripts regenerated" || print_warning "Script regeneration skipped"
  fi

  echo
  print_success "Update complete! Version: ${latest_version}"
  echo
  print_info "Please restart the tool to use the new version."
  echo

  press_enter_to_continue

  # Exit to force restart with new version
  exit 0
}

# Check for updates (verbose, for menu)
check_for_updates_verbose() {
  log_func_enter 2>/dev/null || true
  debug_enter "check_for_updates_verbose" 2>/dev/null || true
  print_header
  echo "Check for Updates"
  echo "================="
  echo

  print_info "Current version: ${VERSION}"
  print_info "Checking GitHub for latest release..."
  echo

  local latest_version
  latest_version=$(get_latest_version)

  if [[ -z "$latest_version" ]]; then
    print_error "Failed to check for updates."
    print_info "Please check your internet connection."
    press_enter_to_continue
    return 1
  fi

  print_info "Latest version:  ${latest_version}"
  echo

  if is_update_available "$VERSION" "$latest_version"; then
    print_warning "Update available!"
    echo
    echo "Run 'backupd --update' or select Update from the menu."
  else
    print_success "You are running the latest version."
  fi

  press_enter_to_continue
}

# ---------- Development Branch Update ----------

# GitHub raw content URL for branch-based updates
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}"

# Download file from GitHub branch
download_from_branch() {
  local branch="$1"
  local file_path="$2"
  local dest_path="$3"

  local url="${GITHUB_RAW_URL}/${branch}/${file_path}"

  # Use strict curl options for security
  # BUG-009+012+014 FIX: Add --tlsv1.2, --max-time, and use curl_with_retry
  if ! curl_with_retry -sfL --proto '=https' --tlsv1.2 --connect-timeout 10 --max-time 120 "$url" -o "$dest_path" 2>/dev/null; then
    return 1
  fi

  # Verify file is not empty
  if [[ ! -s "$dest_path" ]]; then
    return 1
  fi

  return 0
}

# Update from development branch (bypasses release system)
do_dev_update() {
  log_func_enter 2>/dev/null || true
  debug_enter "do_dev_update" "$@" 2>/dev/null || true
  log_info "Starting development branch update"
  local branch="${1:-develop}"

  print_header
  echo "Development Branch Update"
  echo "========================="
  echo

  print_warning "This updates from the '${branch}' branch directly."
  print_warning "This is intended for testing only, NOT production use."
  echo

  print_info "Current version: ${VERSION}"
  print_info "Target branch:   ${branch}"
  echo

  # Confirm update
  echo "This will:"
  echo "  - Download the latest code from '${branch}' branch"
  echo "  - Backup your current installation"
  echo "  - Replace script files (NOT your configuration)"
  echo "  - Your settings and credentials will be preserved"
  echo
  read -p "Proceed with development update? [y/N]: " confirm

  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Update cancelled."
    return 0
  fi

  echo

  # Create temp directory
  local temp_dir
  temp_dir=$(create_secure_temp "backupd-dev-update")

  # List of files to download (must match all lib files in backupd.sh source order)
  local main_script="backupd.sh"
  # BUG-001 FIX: Include all lib modules sourced by backupd.sh
  local lib_files=(
    "lib/core.sh"
    "lib/exitcodes.sh"
    "lib/debug.sh"
    "lib/logging.sh"
    "lib/crypto.sh"
    "lib/restic.sh"       # Added: restic backup engine (v3.0)
    "lib/config.sh"
    "lib/generators.sh"
    "lib/status.sh"
    "lib/backup.sh"
    "lib/verify.sh"
    "lib/restore.sh"
    "lib/schedule.sh"
    "lib/scheduler.sh"    # Added: cron fallback scheduler (v3.2.2)
    "lib/setup.sh"
    "lib/updater.sh"
    "lib/notifications.sh"
    "lib/cli.sh"
    "lib/history.sh"      # Added: backup history tracking (v3.1.0)
    "lib/jobs.sh"         # Added: multi-job management (v3.1.0)
    "lib/migration.sh"    # Added: legacy config migration (v3.1.0)
  )

  # Download main script
  print_info "Downloading ${main_script}..."
  if ! download_from_branch "$branch" "$main_script" "${temp_dir}/${main_script}"; then
    print_error "Failed to download ${main_script}"
    rm -rf "$temp_dir"
    press_enter_to_continue
    return 1
  fi

  # Download lib files
  mkdir -p "${temp_dir}/lib"
  for lib_file in "${lib_files[@]}"; do
    print_info "Downloading ${lib_file}..."
    if ! download_from_branch "$branch" "$lib_file" "${temp_dir}/${lib_file}"; then
      print_error "Failed to download ${lib_file}"
      rm -rf "$temp_dir"
      press_enter_to_continue
      return 1
    fi
  done

  print_success "All files downloaded"
  echo

  # Validate downloaded files BEFORE installing
  print_info "Validating downloaded files..."

  # Check shebang on all .sh files
  for check_file in "${temp_dir}/${main_script}" "${temp_dir}"/lib/*.sh; do
    [[ -f "$check_file" ]] || continue
    local first_line
    first_line=$(head -1 "$check_file")
    if [[ "$first_line" != "#!/usr/bin/env bash" && "$first_line" != "#!/bin/bash" ]]; then
      print_error "Invalid shebang in $(basename "$check_file"): $first_line"
      print_error "File may be corrupted or truncated"
      rm -rf "$temp_dir"
      press_enter_to_continue
      return 1
    fi
  done

  # Minimum size check (catches truncated downloads)
  for check_file in "${temp_dir}"/lib/*.sh; do
    [[ -f "$check_file" ]] || continue
    local file_size
    file_size=$(stat -c%s "$check_file" 2>/dev/null || echo 0)
    if [[ "$file_size" -lt 100 ]]; then
      print_error "File too small ($(basename "$check_file"): ${file_size} bytes)"
      print_error "Download may be truncated"
      rm -rf "$temp_dir"
      press_enter_to_continue
      return 1
    fi
  done

  # Syntax check on temp files (before install, not after)
  for check_file in "${temp_dir}"/lib/*.sh; do
    [[ -f "$check_file" ]] || continue
    if ! bash -n "$check_file" 2>/dev/null; then
      print_error "Syntax error in $(basename "$check_file")"
      rm -rf "$temp_dir"
      press_enter_to_continue
      return 1
    fi
  done

  if ! bash -n "${temp_dir}/${main_script}" 2>/dev/null; then
    print_error "Syntax error in ${main_script}"
    rm -rf "$temp_dir"
    press_enter_to_continue
    return 1
  fi

  print_success "All files validated"
  echo

  # Backup current version
  # BUG-005 FIX: Check backup return value before proceeding
  if ! backup_current_version; then
    print_error "Cannot proceed without backup"
    rm -rf "$temp_dir"
    press_enter_to_continue
    return 1
  fi

  # Apply the update
  print_info "Applying update..."

  # Copy main script
  cp "${temp_dir}/${main_script}" "${SCRIPT_DIR}/${main_script}"
  chmod +x "${SCRIPT_DIR}/${main_script}"

  # Copy lib files
  for lib_file in "${lib_files[@]}"; do
    cp "${temp_dir}/${lib_file}" "${SCRIPT_DIR}/${lib_file}"
    chmod +x "${SCRIPT_DIR}/${lib_file}"
  done

  # Cleanup
  rm -rf "$temp_dir"

  # Save branch for future updates
  echo "$branch" > "${INSTALL_DIR}/.installed_branch"

  # Get new version from downloaded script
  local new_version
  new_version=$(grep '^VERSION=' "${SCRIPT_DIR}/backupd.sh" 2>/dev/null | cut -d'"' -f2)

  echo
  print_success "Development update complete!"
  print_info "Updated from branch: ${branch}"
  print_info "New version: ${new_version:-unknown}"
  echo
  print_info "Please restart the tool to use the new version."
  echo

  press_enter_to_continue

  # Exit to force restart with new version
  exit 0
}
