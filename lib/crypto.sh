#!/usr/bin/env bash
# ============================================================================
# Backupd - Crypto Module
# Secure credential storage with machine-bound encryption
# ============================================================================

# Secret file names (obscured)
SECRET_PASSPHRASE=".c1"
SECRET_DB_USER=".c2"
SECRET_DB_PASS=".c3"
SECRET_NTFY_TOKEN=".c4"
SECRET_NTFY_URL=".c5"

# ---------- Secure Credential Storage Functions ----------

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

  head -c 64 /dev/urandom | base64 > "$secrets_dir/.s"
  chmod 600 "$secrets_dir/.s"

  echo "$secrets_dir" > "$INSTALL_DIR/.secrets_location"
  chmod 600 "$INSTALL_DIR/.secrets_location"

  echo "$secrets_dir"
}

derive_key() {
  local secrets_dir="$1"
  local machine_id salt

  if [[ -f /etc/machine-id ]]; then
    machine_id="$(cat /etc/machine-id)"
  elif [[ -f /var/lib/dbus/machine-id ]]; then
    machine_id="$(cat /var/lib/dbus/machine-id)"
  else
    machine_id="$(hostname)$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo 'fallback')"
  fi

  salt="$(cat "$secrets_dir/.s")"
  echo -n "${machine_id}${salt}" | sha256sum | cut -d' ' -f1
}

store_secret() {
  local secrets_dir="$1"
  local secret_name="$2"
  local secret_value="$3"
  local key

  key="$(derive_key "$secrets_dir")"

  chattr -i "$secrets_dir/$secret_name" 2>/dev/null || true

  echo -n "$secret_value" | openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -pass "pass:$key" -base64 > "$secrets_dir/$secret_name"

  chmod 600 "$secrets_dir/$secret_name"
  chattr +i "$secrets_dir/$secret_name" 2>/dev/null || true
}

get_secret() {
  local secrets_dir="$1"
  local secret_name="$2"
  local key

  if [[ ! -f "$secrets_dir/$secret_name" ]]; then
    echo ""
    return 1
  fi

  key="$(derive_key "$secrets_dir")"
  openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -d -salt -pass "pass:$key" -base64 -in "$secrets_dir/$secret_name" 2>/dev/null || echo ""
}

secret_exists() {
  local secrets_dir="$1"
  local secret_name="$2"
  [[ -f "$secrets_dir/$secret_name" ]]
}

lock_secrets() {
  local secrets_dir="$1"
  # Only lock our specific secret files, not all files in directory
  local secret_files=(".s" ".c1" ".c2" ".c3" ".c4" ".c5")
  for f in "${secret_files[@]}"; do
    [[ -f "$secrets_dir/$f" ]] && chattr +i "$secrets_dir/$f" 2>/dev/null || true
  done
  chattr +i "$secrets_dir" 2>/dev/null || true
}

unlock_secrets() {
  local secrets_dir="$1"
  chattr -i "$secrets_dir" 2>/dev/null || true
  # Only unlock our specific secret files, not all files in directory
  local secret_files=(".s" ".c1" ".c2" ".c3" ".c4" ".c5")
  for f in "${secret_files[@]}"; do
    [[ -f "$secrets_dir/$f" ]] && chattr -i "$secrets_dir/$f" 2>/dev/null || true
  done
}
