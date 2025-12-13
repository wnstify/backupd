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
UPDATE_CHECK_FILE="/tmp/.backupd-update-check"
UPDATE_CHECK_INTERVAL=$((24 * 60))  # 24 hours in minutes

# ---------- Version Comparison ----------

# Compare semantic versions (returns: 0 = equal, 1 = v1 > v2, 2 = v1 < v2)
version_compare() {
  local v1="$1"
  local v2="$2"

  # Remove 'v' prefix if present
  v1="${v1#v}"
  v2="${v2#v}"

  if [[ "$v1" == "$v2" ]]; then
    return 0
  fi

  # Split versions into components
  local IFS='.'
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
get_latest_version() {
  local latest=""

  # Try to get latest release from GitHub API
  if command -v curl &>/dev/null; then
    latest=$(curl -s --connect-timeout 5 "$GITHUB_API_URL" 2>/dev/null | grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
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
  if [[ ! -f "$UPDATE_CHECK_FILE" ]]; then
    return 0  # Should check
  fi

  # Check if file is older than UPDATE_CHECK_INTERVAL minutes
  if [[ $(find "$UPDATE_CHECK_FILE" -mmin +${UPDATE_CHECK_INTERVAL} 2>/dev/null) ]]; then
    return 0  # Should check
  fi

  return 1  # Recently checked, skip
}

# Silent update check on startup (non-blocking)
check_for_updates_silent() {
  # Skip if recently checked
  if ! should_check_updates; then
    # Read cached result
    if [[ -f "$UPDATE_CHECK_FILE" ]]; then
      local cached_version
      cached_version=$(cat "$UPDATE_CHECK_FILE" 2>/dev/null)
      if [[ -n "$cached_version" && "$cached_version" != "$VERSION" ]]; then
        if is_update_available "$VERSION" "$cached_version"; then
          echo "$cached_version"
          return 0
        fi
      fi
    fi
    return 1
  fi

  # Check for network connectivity first (quick check)
  if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null && ! ping -c 1 -W 2 1.1.1.1 &>/dev/null; then
    return 1  # No network
  fi

  # Get latest version
  local latest
  latest=$(get_latest_version)

  # Cache the result
  echo "$latest" > "$UPDATE_CHECK_FILE" 2>/dev/null || true

  if [[ -n "$latest" ]] && is_update_available "$VERSION" "$latest"; then
    echo "$latest"
    return 0
  fi

  return 1
}

# Show update banner if available
show_update_banner() {
  local latest_version
  latest_version=$(check_for_updates_silent) || true

  if [[ -n "$latest_version" ]]; then
    echo -e "${YELLOW}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│  Update available: ${VERSION} → ${latest_version}                        │${NC}"
    echo -e "${YELLOW}│  Select 'U' from menu or run: backupd --update           │${NC}"
    echo -e "${YELLOW}└────────────────────────────────────────────────────────┘${NC}"
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

  # Download release archive
  if ! curl -sL --connect-timeout 10 "$release_url" -o "${temp_dir}/update.tar.gz"; then
    print_error "Failed to download update"
    return 1
  fi

  # Download checksum (optional, don't fail if not available)
  local checksum_file="${temp_dir}/SHA256SUMS"
  if curl -sL --connect-timeout 10 "$checksum_url" -o "$checksum_file" 2>/dev/null; then
    print_info "Verifying checksum..."

    # Extract expected checksum for our file
    local expected_checksum
    expected_checksum=$(grep "backup-management-v${version}.tar.gz" "$checksum_file" 2>/dev/null | awk '{print $1}')

    if [[ -n "$expected_checksum" ]]; then
      local actual_checksum
      actual_checksum=$(sha256sum "${temp_dir}/update.tar.gz" | awk '{print $1}')

      if [[ "$expected_checksum" != "$actual_checksum" ]]; then
        print_error "Checksum verification failed!"
        print_error "Expected: $expected_checksum"
        print_error "Got:      $actual_checksum"
        return 1
      fi
      print_success "Checksum verified"
    else
      print_warning "Checksum not found in SHA256SUMS, skipping verification"
    fi
  else
    print_warning "Checksum file not available, skipping verification"
  fi

  return 0
}

# Backup current installation
backup_current_version() {
  local backup_dir="${SCRIPT_DIR}.backup"

  # Remove old backup if exists
  [[ -d "$backup_dir" ]] && rm -rf "$backup_dir"

  # Create backup
  cp -r "$SCRIPT_DIR" "$backup_dir"

  print_success "Current version backed up to: $backup_dir"
}

# Restore from backup (rollback)
rollback_update() {
  local backup_dir="${SCRIPT_DIR}.backup"

  if [[ ! -d "$backup_dir" ]]; then
    print_error "No backup found to restore"
    return 1
  fi

  print_info "Rolling back to previous version..."

  # Remove current (failed) version
  rm -rf "$SCRIPT_DIR"

  # Restore backup
  mv "$backup_dir" "$SCRIPT_DIR"

  print_success "Rollback complete"
}

# Apply update
apply_update() {
  local temp_dir="$1"

  print_info "Applying update..."

  # Extract to temp location first
  local extract_dir="${temp_dir}/extracted"
  mkdir -p "$extract_dir"

  if ! tar -xzf "${temp_dir}/update.tar.gz" -C "$extract_dir"; then
    print_error "Failed to extract update"
    return 1
  fi

  # Find the extracted directory (might be nested)
  local source_dir
  source_dir=$(find "$extract_dir" -maxdepth 2 -name "backupd.sh" -printf '%h\n' 2>/dev/null | head -1)

  if [[ -z "$source_dir" || ! -f "${source_dir}/backupd.sh" ]]; then
    print_error "Invalid update archive structure"
    return 1
  fi

  # Copy new files over existing installation
  # This preserves any files not in the update (like local configs)
  cp -r "${source_dir}/"* "$SCRIPT_DIR/"

  # Ensure scripts are executable
  chmod +x "$SCRIPT_DIR/backupd.sh"
  chmod +x "$SCRIPT_DIR/lib/"*.sh 2>/dev/null || true

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

# ---------- Main Update Function ----------

# Perform the update
do_update() {
  print_header
  echo "Update Backupd"
  echo "=============="
  echo

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
  backup_current_version

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
  rm -f "$UPDATE_CHECK_FILE"

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

  if ! curl -sL --connect-timeout 10 "$url" -o "$dest_path" 2>/dev/null; then
    return 1
  fi

  return 0
}

# Update from development branch (bypasses release system)
do_dev_update() {
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

  # List of files to download
  local main_script="backupd.sh"
  local lib_files=(
    "lib/core.sh"
    "lib/crypto.sh"
    "lib/config.sh"
    "lib/generators.sh"
    "lib/status.sh"
    "lib/backup.sh"
    "lib/verify.sh"
    "lib/restore.sh"
    "lib/schedule.sh"
    "lib/setup.sh"
    "lib/updater.sh"
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

  # Backup current version
  backup_current_version

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

  # Basic syntax check
  if ! bash -n "${SCRIPT_DIR}/backupd.sh" 2>/dev/null; then
    print_error "Syntax error in updated script, rolling back..."
    rollback_update
    rm -rf "$temp_dir"
    press_enter_to_continue
    return 1
  fi

  # Cleanup
  rm -rf "$temp_dir"

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
