#!/usr/bin/env bash
# tests/integration/history.bats — History command integration tests

setup() {
  load '../test_helper'
}

# ---------- Text output ----------

@test "backupd history exits 0" {
  run_backupd history
  assert_success
}

@test "backupd history shows table header" {
  run_backupd history
  assert_output --partial "TYPE"
  assert_output --partial "STATUS"
}

@test "backupd history db exits 0" {
  run_backupd history db
  assert_success
}

@test "backupd history db shows only database entries" {
  run_backupd history db
  assert_output --partial "database"
}

@test "backupd history files exits 0" {
  run_backupd history files
  assert_success
}

@test "backupd history files shows only files entries" {
  run_backupd history files
  assert_output --partial "files"
}

# ---------- JSON output ----------

@test "backupd history --json produces valid JSON" {
  run_backupd history --json
  assert_success
  assert_valid_json
}

@test "backupd history --json has records array" {
  run_backupd history --json
  json_field ".records" | jq . >/dev/null
}

@test "backupd history --json records have expected fields" {
  run_backupd history --json
  local first_type first_status
  first_type=$(json_field ".records[0].type")
  first_status=$(json_field ".records[0].status")
  [[ -n "$first_type" && -n "$first_status" ]]
}

# ---------- Lines limit ----------

@test "backupd history --lines 5 limits output" {
  run_backupd history --lines 5
  assert_success
}

# ---------- Help ----------

@test "backupd history --help exits 0" {
  run_backupd history --help
  assert_success
}

@test "backupd history --help shows usage" {
  run_backupd history --help
  assert_output --partial "Usage:"
  assert_output --partial "history"
}
