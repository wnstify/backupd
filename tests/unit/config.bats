#!/usr/bin/env bash
# tests/unit/config.bats — Tests for lib/config.sh

setup() {
  load '../test_helper'
  export BACKUPD_TRAP_SET=1

  # Create temp config file for testing
  TEST_CONFIG_DIR=$(mktemp -d)
  export CONFIG_FILE="$TEST_CONFIG_DIR/.config"
  export INSTALL_DIR="$TEST_CONFIG_DIR"

  source_modules "exitcodes" "core" "config"
}

teardown() {
  rm -rf "$TEST_CONFIG_DIR"
}

# ---------- get_config_value() ----------

@test "get_config_value reads existing key" {
  echo 'RCLONE_REMOTE="b2"' > "$CONFIG_FILE"
  run get_config_value "RCLONE_REMOTE"
  assert_output "b2"
}

@test "get_config_value returns empty for missing key" {
  echo 'RCLONE_REMOTE="b2"' > "$CONFIG_FILE"
  run get_config_value "MISSING_KEY"
  assert_output ""
}

@test "get_config_value returns empty when config file missing" {
  rm -f "$CONFIG_FILE"
  run get_config_value "RCLONE_REMOTE"
  assert_output ""
}

@test "get_config_value handles value with equals sign" {
  echo 'SOME_KEY="val=ue"' > "$CONFIG_FILE"
  run get_config_value "SOME_KEY"
  assert_output "val=ue"
}

@test "get_config_value strips quotes from value" {
  echo 'KEY="quoted value"' > "$CONFIG_FILE"
  run get_config_value "KEY"
  assert_output "quoted value"
}

# ---------- save_config() ----------

@test "save_config writes new key" {
  run save_config "MY_KEY" "my_value"
  assert_success
  run get_config_value "MY_KEY"
  assert_output "my_value"
}

@test "save_config updates existing key" {
  save_config "MY_KEY" "old_value"
  save_config "MY_KEY" "new_value"
  run get_config_value "MY_KEY"
  assert_output "new_value"
}

@test "save_config rejects invalid key name" {
  run save_config "invalid-key" "value"
  assert_failure
}

@test "save_config rejects key starting with number" {
  run save_config "1INVALID" "value"
  assert_failure
}

@test "save_config accepts underscore in key" {
  run save_config "MY_KEY_NAME" "value"
  assert_success
}

# ---------- is_configured() ----------

@test "is_configured returns true when both files exist" {
  touch "$CONFIG_FILE"
  touch "$INSTALL_DIR/.secrets_location"
  run is_configured
  assert_success
}

@test "is_configured returns false when config missing" {
  rm -f "$CONFIG_FILE"
  touch "$INSTALL_DIR/.secrets_location"
  run is_configured
  assert_failure
}

@test "is_configured returns false when secrets_location missing" {
  touch "$CONFIG_FILE"
  rm -f "$INSTALL_DIR/.secrets_location"
  run is_configured
  assert_failure
}
