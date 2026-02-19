#!/usr/bin/env bash
# tests/integration/schedule.bats — Schedule command integration tests

setup() {
  load '../test_helper'
}

# ---------- List ----------

@test "backupd schedule list exits 0" {
  run_backupd schedule list
  assert_success
}

@test "backupd schedule list shows schedules" {
  run_backupd schedule list
  assert_output --partial "Database"
}

@test "backupd schedule list shows retention" {
  run_backupd schedule list
  assert_output --partial "Retention"
}

# ---------- JSON output (global --json flag) ----------

@test "backupd schedule --json produces valid JSON" {
  run_backupd schedule --json
  assert_success
  assert_valid_json
}

@test "backupd schedule --json has schedules object" {
  run_backupd schedule --json
  json_field ".schedules" | jq . >/dev/null
}

@test "backupd schedule --json has db schedule" {
  run_backupd schedule --json
  local db_enabled
  db_enabled=$(json_field ".schedules.db.enabled")
  [[ "$db_enabled" == "true" || "$db_enabled" == "false" ]]
}

@test "backupd schedule --json has retention field" {
  run_backupd schedule --json
  local retention
  retention=$(json_field ".retention")
  [[ -n "$retention" ]]
}

# ---------- Templates ----------

@test "backupd schedule templates list exits 0" {
  run_backupd schedule templates list
  assert_success
}

@test "backupd schedule templates list shows template names" {
  run_backupd schedule templates list
  assert_output --partial "hourly"
  assert_output --partial "daily_2am"
}

@test "backupd --json schedule templates list produces valid JSON" {
  run_backupd --json schedule templates list
  assert_success
  assert_valid_json
}

@test "backupd --json schedule templates list has templates array" {
  run_backupd --json schedule templates list
  local count
  count=$(json_field ".templates | length")
  [[ "$count" -gt 0 ]]
}

# ---------- Help ----------

@test "backupd schedule --help exits 0" {
  run_backupd schedule --help
  assert_success
}

@test "backupd schedule --help shows usage" {
  run_backupd schedule --help
  assert_output --partial "Usage:"
  assert_output --partial "schedule"
}
