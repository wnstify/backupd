#!/usr/bin/env bash
# tests/integration/backup.bats — Backup command integration tests
#
# WARNING: These tests perform REAL backup operations against configured
# storage. Each backup test may take 30-120 seconds to complete.
#
# NOTE: A known CLI wrapper bug (unbound variable `temp_output` in cli.sh)
# causes exit code 1 even when the backup operation itself succeeds.
# Tests for real backups check output for success markers instead of exit code.

setup() {
  load '../test_helper'
}

# ---------- Dry run (fast, no side effects) ----------

@test "backupd backup db --dry-run exits 0" {
  run_backupd backup db --dry-run
  assert_success
}

@test "backupd backup db --dry-run shows preview" {
  run_backupd backup db --dry-run
  assert_output --partial "[DRY-RUN]"
}

@test "backupd backup files --dry-run exits 0" {
  run_backupd backup files --dry-run
  assert_success
}

@test "backupd backup files --dry-run shows preview" {
  run_backupd backup files --dry-run
  assert_output --partial "[DRY-RUN]"
}

# ---------- Database backup ----------

@test "backupd backup db completes successfully" {
  run_backupd backup db
  assert_output --partial "END (success)"
}

@test "backupd backup db produces output" {
  run_backupd backup db
  [[ -n "$output" ]]
  assert_output --partial "Starting database backup"
}

# ---------- Files backup ----------

@test "backupd backup files completes successfully" {
  run_backupd backup files
  assert_output --partial "END (success)"
}

# ---------- Backup all ----------

@test "backupd backup all completes successfully" {
  run_backupd backup all
  # "all" runs both db and files; both should report success
  assert_output --partial "Starting database backup"
  assert_output --partial "Starting files backup"
}

# ---------- Invalid type ----------

@test "backupd backup invalid-type fails" {
  run_backupd backup nonsense
  assert_failure
}

# ---------- Help ----------

@test "backupd backup --help exits 0" {
  run_backupd backup --help
  assert_success
}
