#!/usr/bin/env bash
# tests/integration/restore.bats — Restore command integration tests

setup() {
  load '../test_helper'
}

# ---------- Help ----------

@test "backupd restore --help exits 0" {
  run_backupd restore --help
  assert_success
}

@test "backupd restore --help shows usage" {
  run_backupd restore --help
  assert_output --partial "Usage:"
  assert_output --partial "restore"
}

# ---------- No type shows help ----------

@test "backupd restore without type shows usage" {
  run_backupd restore
  assert_output --partial "Usage:"
}

# ---------- Invalid type ----------

@test "backupd restore invalid-type fails" {
  run_backupd restore nonsense
  assert_failure
  assert_output --partial "Unknown restore type"
}

# ---------- List mode ----------

@test "backupd restore db --list shows available backups" {
  run_backupd restore db --list
  assert_success
  assert_output --partial "snapshot"
}

@test "backupd restore files --list shows available backups" {
  run_backupd restore files --list
  assert_success
  assert_output --partial "snapshot"
}

# ---------- JSON list ----------

@test "backupd restore db --list --json produces valid JSON" {
  run_backupd restore db --list --json
  assert_success
  assert_valid_json
}

@test "backupd restore db --list --json has snapshots array" {
  run_backupd restore db --list --json
  local snap_count
  snap_count=$(json_field ".snapshots | length")
  [[ "$snap_count" -gt 0 ]]
}

@test "backupd restore db --list --json has type field" {
  run_backupd restore db --list --json
  local type
  type=$(json_field ".type")
  [[ "$type" == "db" ]]
}

# ---------- Dry run ----------

@test "backupd restore db --dry-run exits 0" {
  run_backupd restore db --dry-run
  assert_success
}

@test "backupd restore db --dry-run shows preview" {
  run_backupd restore db --dry-run
  assert_output --partial "DRY-RUN"
}
