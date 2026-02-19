#!/usr/bin/env bash
# tests/integration/status.bats — Status command integration tests

setup() {
  load '../test_helper'
}

# ---------- Text output ----------

@test "backupd status exits 0" {
  run_backupd status
  assert_success
}

@test "backupd status shows configuration status" {
  run_backupd status
  assert_output --partial "Configuration"
}

@test "backupd status shows remote type" {
  run_backupd status
  assert_output --partial "Remote"
}

@test "backupd status shows retention" {
  run_backupd status
  assert_output --partial "Retention"
}

@test "backupd status shows backup scripts" {
  run_backupd status
  assert_output --partial "Database backup script"
  assert_output --partial "Files backup script"
}

@test "backupd status shows scheduled backups" {
  run_backupd status
  assert_output --partial "Scheduled Backups"
}

# ---------- JSON output ----------

@test "backupd status --json exits 0" {
  run_backupd status --json
  assert_success
}

@test "backupd status --json produces valid JSON" {
  run_backupd status --json
  assert_valid_json
}

@test "backupd status --json has configured field" {
  run_backupd status --json
  local configured
  configured=$(json_field ".configured")
  [[ "$configured" == "true" || "$configured" == "false" ]]
}

@test "backupd status --json has scripts object" {
  run_backupd status --json
  local db_script
  db_script=$(json_field ".scripts.db_backup")
  [[ "$db_script" == "true" || "$db_script" == "false" ]]
}

@test "backupd status --json has remote field" {
  run_backupd status --json
  local remote
  remote=$(json_field ".remote")
  [[ -n "$remote" ]]
}

@test "backupd status --json has retention field" {
  run_backupd status --json
  local retention
  retention=$(json_field ".retention")
  [[ -n "$retention" ]]
}

@test "backupd status --json has schedules object" {
  run_backupd status --json
  local db_schedule
  db_schedule=$(json_field ".schedules.db")
  [[ -n "$db_schedule" ]]
}
