#!/usr/bin/env bash
# tests/integration/notifications.bats — Notification command integration tests

setup() {
  load '../test_helper'
}

# ---------- Help ----------

@test "backupd notifications --help exits 0" {
  run_backupd notifications --help
  assert_success
}

@test "backupd notifications --help shows usage" {
  run_backupd notifications --help
  assert_output --partial "Usage:"
  assert_output --partial "notifications"
}

@test "backupd notifications --help lists subcommands" {
  run_backupd notifications --help
  assert_output --partial "status"
  assert_output --partial "test"
  assert_output --partial "set-pushover"
  assert_output --partial "disable-pushover"
}

# ---------- Status (text) ----------

@test "backupd notifications status exits 0" {
  run_backupd notifications status
  assert_success
}

@test "backupd notifications status shows provider status" {
  run_backupd notifications status
  assert_output --partial "ntfy"
  assert_output --partial "webhook"
  assert_output --partial "pushover"
}

# ---------- Status (JSON) ----------

@test "backupd notifications status --json exits 0" {
  run_backupd notifications status --json
  assert_success
}

@test "backupd notifications status --json produces valid JSON" {
  run_backupd notifications status --json
  assert_valid_json
}

@test "backupd notifications status --json has ntfy field" {
  run_backupd notifications status --json
  local ntfy_enabled
  ntfy_enabled=$(json_field ".ntfy.enabled")
  [[ "$ntfy_enabled" == "true" || "$ntfy_enabled" == "false" ]]
}

@test "backupd notifications status --json has webhook field" {
  run_backupd notifications status --json
  local webhook_enabled
  webhook_enabled=$(json_field ".webhook.enabled")
  [[ "$webhook_enabled" == "true" || "$webhook_enabled" == "false" ]]
}

@test "backupd notifications status --json has pushover field" {
  run_backupd notifications status --json
  local pushover_enabled
  pushover_enabled=$(json_field ".pushover.enabled")
  [[ "$pushover_enabled" == "true" || "$pushover_enabled" == "false" ]]
}

@test "backupd --json notifications status produces valid JSON" {
  run_backupd --json notifications status
  assert_success
  assert_valid_json
}

# ---------- Test notification ----------

@test "backupd notifications test fails when pushover not configured" {
  run_backupd notifications test
  # Exit 78 = EX_CONFIG (not configured)
  [[ "$status" -eq 78 ]]
  assert_output --partial "not configured"
}
