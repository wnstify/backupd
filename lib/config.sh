#!/usr/bin/env bash
# ============================================================================
# Backupd - Config Module
# Configuration file read/write functions
# ============================================================================

# ---------- Configuration Check ----------

is_configured() {
  [[ -f "$CONFIG_FILE" ]] && [[ -f "$INSTALL_DIR/.secrets_location" ]]
}

get_config_value() {
  local key="$1"
  if [[ -f "$CONFIG_FILE" ]]; then
    grep "^${key}=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true
  fi
}

save_config() {
  local key="$1"
  local value="$2"

  # Validate key (alphanumeric and underscore only)
  if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    print_error "Invalid config key: $key"
    return 1
  fi

  # Escape double quotes and backslashes in value to prevent injection
  value="${value//\\/\\\\}"  # Escape backslashes first
  value="${value//\"/\\\"}"  # Escape double quotes
  value="${value//$'\n'/}"   # Remove newlines

  if [[ -f "$CONFIG_FILE" ]]; then
    # Remove existing key if present
    grep -v "^${key}=" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" 2>/dev/null || true
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  fi

  echo "${key}=\"${value}\"" >> "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}
