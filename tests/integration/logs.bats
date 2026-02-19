#!/usr/bin/env bash
# tests/integration/logs.bats — Logs command integration tests

setup() {
  load '../test_helper'
}

# ---------- Text output ----------

@test "backupd logs exits 0" {
  run_backupd logs
  assert_success
}

@test "backupd logs shows log headers" {
  run_backupd logs
  assert_output --partial "Backup Log"
}

@test "backupd logs db exits 0" {
  run_backupd logs db
  assert_success
}

@test "backupd logs db shows database log" {
  run_backupd logs db
  assert_output --partial "Database Backup Log"
}

@test "backupd logs files exits 0" {
  run_backupd logs files
  assert_success
}

@test "backupd logs files shows files log" {
  run_backupd logs files
  assert_output --partial "Files Backup Log"
}

@test "backupd logs --lines 10 limits output" {
  run_backupd logs --lines 10
  assert_success
  assert_output --partial "last 10 lines"
}

# ---------- JSON output ----------

@test "backupd logs --json produces valid JSON" {
  run_backupd logs --json
  assert_success
  assert_valid_json
}

@test "backupd logs --json has entries array" {
  run_backupd logs --json
  json_field ".entries" | jq . >/dev/null
}

@test "backupd logs --json has type field" {
  run_backupd logs --json
  local type
  type=$(json_field ".type")
  [[ -n "$type" ]]
}

# ---------- Help ----------

@test "backupd logs --help exits 0" {
  run_backupd logs --help
  assert_success
}

@test "backupd logs --help shows usage" {
  run_backupd logs --help
  assert_output --partial "Usage:"
  assert_output --partial "logs"
}
