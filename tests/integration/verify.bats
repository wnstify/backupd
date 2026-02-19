#!/usr/bin/env bash
# tests/integration/verify.bats — Verify command integration tests

setup() {
  load '../test_helper'
}

# ---------- Quick verify ----------

@test "backupd verify --quick exits 0" {
  run_backupd verify --quick
  assert_success
}

@test "backupd verify --quick shows repository status" {
  run_backupd verify --quick
  assert_output --partial "Repository OK"
}

@test "backupd verify db exits 0" {
  run_backupd verify db
  assert_success
}

@test "backupd verify db shows database repository" {
  run_backupd verify db
  assert_output --partial "Database repository"
}

@test "backupd verify files exits 0" {
  run_backupd verify files
  assert_success
}

@test "backupd verify files shows files repository" {
  run_backupd verify files
  assert_output --partial "Files repository"
}

# ---------- JSON output ----------

@test "backupd verify --json produces valid JSON" {
  run_backupd verify --json
  # verify --json may exit 1 when status is FAILED (no checksums)
  assert_valid_json
}

@test "backupd verify --json has status field" {
  run_backupd verify --json
  local status
  status=$(json_field ".status")
  [[ "$status" == "PASSED" || "$status" == "WARNING" || "$status" == "FAILED" ]]
}

@test "backupd verify --json has results object" {
  run_backupd verify --json
  json_field ".results" | jq . >/dev/null
}

@test "backupd verify --json results contain db and files" {
  run_backupd verify --json
  local db_status files_status
  db_status=$(json_field ".results.db.status")
  files_status=$(json_field ".results.files.status")
  [[ -n "$db_status" && -n "$files_status" ]]
}

# ---------- Dry run ----------

@test "backupd verify --dry-run exits 0" {
  run_backupd verify --dry-run
  assert_success
}

@test "backupd verify --dry-run shows preview" {
  run_backupd verify --dry-run
  assert_output --partial "DRY-RUN"
}

# ---------- Help ----------

@test "backupd verify --help exits 0" {
  run_backupd verify --help
  assert_success
}

@test "backupd verify --help shows usage" {
  run_backupd verify --help
  assert_output --partial "Usage:"
  assert_output --partial "verify"
}
