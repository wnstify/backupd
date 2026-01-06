#!/usr/bin/env bash
# ============================================================================
# Backupd - Crypto Module
# Secure credential storage with machine-bound encryption
#
# Encryption Versions:
#   v1 (legacy):  SHA256 key derivation + PBKDF2 100k iterations
#   v2 (fallback): SHA256 key derivation + PBKDF2 800k iterations
#   v3 (default):  Argon2id key derivation + PBKDF2 100k iterations
# ============================================================================

# Secret file names (obscured)
SECRET_PASSPHRASE=".c1"
SECRET_DB_USER=".c2"
SECRET_DB_PASS=".c3"
SECRET_NTFY_TOKEN=".c4"
SECRET_NTFY_URL=".c5"
SECRET_WEBHOOK_URL=".c6"
SECRET_WEBHOOK_TOKEN=".c7"
SECRET_PUSHOVER_USER=".c8"
SECRET_PUSHOVER_TOKEN=".c9"

# ---------- Encryption Constants ----------

# Crypto versions
readonly CRYPTO_VERSION_LEGACY=1
readonly CRYPTO_VERSION_PBKDF2=2
readonly CRYPTO_VERSION_ARGON2ID=3

# PBKDF2 iterations by version
readonly PBKDF2_ITER_V1=100000
readonly PBKDF2_ITER_V2=800000
readonly PBKDF2_ITER_V3=100000  # Lower because Argon2id does heavy lifting

# Argon2id parameters (OWASP recommended)
readonly ARGON2_TIME=3        # iterations (time cost)
readonly ARGON2_MEMORY=16     # 2^16 = 64MB memory
readonly ARGON2_PARALLEL=4    # parallel threads
readonly ARGON2_LENGTH=32     # 32 bytes = 256 bits output

# ---------- Algorithm Detection ----------

# Check if Argon2 CLI is available
argon2_available() {
  command -v argon2 &>/dev/null
}

# Get current crypto version from secrets directory
get_crypto_version() {
  local secrets_dir="$1"
  local algo_file="$secrets_dir/.algo"

  if [[ -f "$algo_file" ]]; then
    cat "$algo_file"
  else
    echo "$CRYPTO_VERSION_LEGACY"  # Backward compatibility
  fi
}

# Set crypto version in secrets directory
set_crypto_version() {
  local secrets_dir="$1"
  local version="$2"
  local algo_file="$secrets_dir/.algo"

  # Unlock if needed
  chattr -i "$algo_file" 2>/dev/null || true

  echo "$version" > "$algo_file"
  chmod 600 "$algo_file"

  # Lock the file
  chattr +i "$algo_file" 2>/dev/null || true
}

# Get best available crypto version for new installations
get_best_crypto_version() {
  if argon2_available; then
    echo "$CRYPTO_VERSION_ARGON2ID"
  else
    echo "$CRYPTO_VERSION_PBKDF2"
  fi
}

# Get human-readable algorithm name
get_crypto_name() {
  local version="$1"
  case "$version" in
    "$CRYPTO_VERSION_LEGACY")   echo "PBKDF2-SHA256 (100k iterations) [legacy]" ;;
    "$CRYPTO_VERSION_PBKDF2")   echo "PBKDF2-SHA256 (800k iterations)" ;;
    "$CRYPTO_VERSION_ARGON2ID") echo "Argon2id (64MB, 3 iterations)" ;;
    *) echo "Unknown" ;;
  esac
}

# Get PBKDF2 iterations for a given version
get_pbkdf2_iterations() {
  local version="$1"
  case "$version" in
    "$CRYPTO_VERSION_LEGACY")   echo "$PBKDF2_ITER_V1" ;;
    "$CRYPTO_VERSION_PBKDF2")   echo "$PBKDF2_ITER_V2" ;;
    "$CRYPTO_VERSION_ARGON2ID") echo "$PBKDF2_ITER_V3" ;;
    *) echo "$PBKDF2_ITER_V1" ;;
  esac
}

# ---------- Key Derivation Functions ----------

# Get machine identifier (consistent across functions)
get_machine_id() {
  if [[ -f /etc/machine-id ]]; then
    cat /etc/machine-id
  elif [[ -f /var/lib/dbus/machine-id ]]; then
    cat /var/lib/dbus/machine-id
  else
    echo "$(hostname)$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo 'fallback')"
  fi
}

# Derive key using SHA256 (v1/v2)
derive_key_sha256() {
  local secrets_dir="$1"
  local machine_id salt

  machine_id="$(get_machine_id)"
  salt="$(cat "$secrets_dir/.s")"

  echo -n "${machine_id}${salt}" | sha256sum | cut -d' ' -f1
}

# Derive key using Argon2id (v3)
derive_key_argon2id() {
  local secrets_dir="$1"
  local machine_id salt

  machine_id="$(get_machine_id)"
  salt="$(cat "$secrets_dir/.s")"

  # Use first 16 chars of salt for argon2 (it needs shorter salt)
  # Full entropy preserved by including full salt in the input
  echo -n "${machine_id}${salt}" | argon2 "${salt:0:16}" -id \
    -t "$ARGON2_TIME" \
    -m "$ARGON2_MEMORY" \
    -p "$ARGON2_PARALLEL" \
    -l "$ARGON2_LENGTH" \
    -r
}

# Main key derivation - uses algorithm based on version
derive_key() {
  local secrets_dir="$1"
  local version

  version="$(get_crypto_version "$secrets_dir")"

  case "$version" in
    "$CRYPTO_VERSION_ARGON2ID")
      if argon2_available; then
        derive_key_argon2id "$secrets_dir"
      else
        # Critical error - can't decrypt without argon2
        print_error "Argon2 required but not installed"
        return 1
      fi
      ;;
    "$CRYPTO_VERSION_LEGACY"|"$CRYPTO_VERSION_PBKDF2"|*)
      derive_key_sha256 "$secrets_dir"
      ;;
  esac
}

# Derive key for a specific version (used during migration)
derive_key_for_version() {
  local secrets_dir="$1"
  local version="$2"

  case "$version" in
    "$CRYPTO_VERSION_ARGON2ID")
      derive_key_argon2id "$secrets_dir"
      ;;
    *)
      derive_key_sha256 "$secrets_dir"
      ;;
  esac
}

# ---------- Secure Storage Functions ----------

generate_random_id() {
  head -c 32 /dev/urandom | md5sum | head -c 12
}

get_secrets_dir() {
  local config_file="$INSTALL_DIR/.secrets_location"
  if [[ -f "$config_file" ]]; then
    cat "$config_file"
  else
    echo ""
  fi
}

init_secure_storage() {
  local existing_dir
  existing_dir="$(get_secrets_dir)"

  if [[ -n "$existing_dir" && -d "$existing_dir" ]]; then
    echo "$existing_dir"
    return 0
  fi

  local random_name=".$(generate_random_id)"
  local secrets_dir="/etc/$random_name"

  mkdir -p "$secrets_dir"
  chmod 700 "$secrets_dir"

  # Generate salt
  head -c 64 /dev/urandom | base64 > "$secrets_dir/.s"
  chmod 600 "$secrets_dir/.s"

  # Set best available crypto version
  local best_version
  best_version="$(get_best_crypto_version)"
  set_crypto_version "$secrets_dir" "$best_version"

  echo "$secrets_dir" > "$INSTALL_DIR/.secrets_location"
  chmod 600 "$INSTALL_DIR/.secrets_location"

  echo "$secrets_dir"
}

store_secret() {
  log_func_enter
  debug_enter "store_secret" "$1" "$2" "[REDACTED]"
  local secrets_dir="$1"
  local secret_name="$2"
  local secret_value="$3"
  local key version iterations

  version="$(get_crypto_version "$secrets_dir")"
  iterations="$(get_pbkdf2_iterations "$version")"
  key="$(derive_key "$secrets_dir")" || return 1

  # Unlock directory and file for writing
  chattr -i "$secrets_dir" 2>/dev/null || true
  chattr -i "$secrets_dir/$secret_name" 2>/dev/null || true

  printf '%s' "$secret_value" | openssl enc -aes-256-cbc -pbkdf2 -iter "$iterations" -salt -pass "pass:$key" -base64 > "$secrets_dir/$secret_name"

  chmod 600 "$secrets_dir/$secret_name"
  chattr +i "$secrets_dir/$secret_name" 2>/dev/null || true
  chattr +i "$secrets_dir" 2>/dev/null || true
}

get_secret() {
  log_func_enter
  debug_enter "get_secret" "$1" "$2"
  local secrets_dir="$1"
  local secret_name="$2"
  local key version iterations

  if [[ ! -f "$secrets_dir/$secret_name" ]]; then
    log_debug "Secret file not found: $secret_name"
    echo ""
    return 1
  fi

  version="$(get_crypto_version "$secrets_dir")"
  iterations="$(get_pbkdf2_iterations "$version")"
  key="$(derive_key "$secrets_dir")" || return 1

  openssl enc -aes-256-cbc -pbkdf2 -iter "$iterations" -d -salt -pass "pass:$key" -base64 -in "$secrets_dir/$secret_name" 2>/dev/null || echo ""
}

# Get secret using specific version (for migration)
get_secret_with_version() {
  local secrets_dir="$1"
  local secret_name="$2"
  local version="$3"
  local key iterations

  if [[ ! -f "$secrets_dir/$secret_name" ]]; then
    echo ""
    return 1
  fi

  iterations="$(get_pbkdf2_iterations "$version")"
  key="$(derive_key_for_version "$secrets_dir" "$version")" || return 1

  openssl enc -aes-256-cbc -pbkdf2 -iter "$iterations" -d -salt -pass "pass:$key" -base64 -in "$secrets_dir/$secret_name" 2>/dev/null || echo ""
}

# Store secret using specific version (for migration)
store_secret_with_version() {
  local secrets_dir="$1"
  local secret_name="$2"
  local secret_value="$3"
  local version="$4"
  local key iterations

  iterations="$(get_pbkdf2_iterations "$version")"
  key="$(derive_key_for_version "$secrets_dir" "$version")" || return 1

  chattr -i "$secrets_dir/$secret_name" 2>/dev/null || true

  printf '%s' "$secret_value" | openssl enc -aes-256-cbc -pbkdf2 -iter "$iterations" -salt -pass "pass:$key" -base64 > "$secrets_dir/$secret_name"

  chmod 600 "$secrets_dir/$secret_name"
  chattr +i "$secrets_dir/$secret_name" 2>/dev/null || true
}

secret_exists() {
  local secrets_dir="$1"
  local secret_name="$2"
  [[ -f "$secrets_dir/$secret_name" ]]
}

lock_secrets() {
  local secrets_dir="$1"
  local secret_files=(".s" ".c1" ".c2" ".c3" ".c4" ".c5" ".c6" ".c7" ".c8" ".c9" ".algo")
  for f in "${secret_files[@]}"; do
    [[ -f "$secrets_dir/$f" ]] && chattr +i "$secrets_dir/$f" 2>/dev/null || true
  done
  chattr +i "$secrets_dir" 2>/dev/null || true
}

unlock_secrets() {
  local secrets_dir="$1"
  chattr -i "$secrets_dir" 2>/dev/null || true
  local secret_files=(".s" ".c1" ".c2" ".c3" ".c4" ".c5" ".c6" ".c7" ".c8" ".c9" ".algo")
  for f in "${secret_files[@]}"; do
    [[ -f "$secrets_dir/$f" ]] && chattr -i "$secrets_dir/$f" 2>/dev/null || true
  done
}

# ---------- Migration Functions ----------

# Migrate secrets from one version to another
migrate_secrets() {
  local secrets_dir="$1"
  local from_version="$2"
  local to_version="$3"
  local secret_files=(".c1" ".c2" ".c3" ".c4" ".c5" ".c6" ".c7" ".c8" ".c9")
  local secrets_data=()
  local failed=0

  # Check if target version is available
  if [[ "$to_version" == "$CRYPTO_VERSION_ARGON2ID" ]] && ! argon2_available; then
    print_error "Argon2 is not installed. Install with: sudo apt install argon2"
    return 1
  fi

  echo "Migrating from $(get_crypto_name "$from_version") to $(get_crypto_name "$to_version")..."

  # Unlock all secrets
  unlock_secrets "$secrets_dir"

  # Read all secrets with old version
  echo "  Reading secrets with current algorithm..."
  for secret_name in "${secret_files[@]}"; do
    if [[ -f "$secrets_dir/$secret_name" ]]; then
      local value
      value="$(get_secret_with_version "$secrets_dir" "$secret_name" "$from_version")"
      if [[ -n "$value" ]]; then
        secrets_data+=("$secret_name:$value")
        echo "    ✓ Read $secret_name"
      else
        echo "    ⚠ Could not read $secret_name (may be empty)"
      fi
    fi
  done

  # Update version marker
  echo "  Updating algorithm marker..."
  set_crypto_version "$secrets_dir" "$to_version"

  # Re-encrypt all secrets with new version
  echo "  Re-encrypting secrets with new algorithm..."
  for entry in "${secrets_data[@]}"; do
    local secret_name="${entry%%:*}"
    local secret_value="${entry#*:}"

    if store_secret_with_version "$secrets_dir" "$secret_name" "$secret_value" "$to_version"; then
      echo "    ✓ Encrypted $secret_name"
    else
      echo "    ✗ Failed to encrypt $secret_name"
      ((failed++)) || true
    fi
  done

  # Lock secrets again
  lock_secrets "$secrets_dir"

  if [[ $failed -gt 0 ]]; then
    echo "WARNING: $failed secrets failed to migrate"
    return 1
  fi

  echo "Migration complete!"
  return 0
}

# Check if migration is recommended
migration_recommended() {
  local secrets_dir="$1"
  local current_version best_version

  current_version="$(get_crypto_version "$secrets_dir")"
  best_version="$(get_best_crypto_version)"

  [[ "$current_version" -lt "$best_version" ]]
}

# Get migration recommendation message
get_migration_recommendation() {
  local secrets_dir="$1"
  local current_version best_version

  current_version="$(get_crypto_version "$secrets_dir")"
  best_version="$(get_best_crypto_version)"

  if [[ "$current_version" -lt "$best_version" ]]; then
    echo "Encryption upgrade available: $(get_crypto_name "$current_version") → $(get_crypto_name "$best_version")"
    echo "Run 'backupd --migrate-encryption' to upgrade"
  fi
}
