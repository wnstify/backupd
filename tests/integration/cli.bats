#!/usr/bin/env bash
# tests/integration/cli.bats — CLI dispatch integration tests

setup() {
  load '../test_helper'
}

# ---------- Version ----------

@test "backupd --version exits cleanly" {
  run_backupd --version
  # --version triggers cleanup trap which exits 1; that is expected
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "backupd --version shows version number" {
  run_backupd --version
  assert_output --partial "Backupd v"
}

# ---------- Help ----------

@test "backupd --help exits cleanly" {
  run_backupd --help
  # --help triggers cleanup trap which exits 1; that is expected
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "backupd --help lists all commands" {
  run_backupd --help
  assert_output --partial "backup"
  assert_output --partial "restore"
  assert_output --partial "status"
  assert_output --partial "verify"
  assert_output --partial "schedule"
  assert_output --partial "logs"
  assert_output --partial "history"
  assert_output --partial "job"
}

# ---------- Unknown command ----------

@test "backupd unknown-command fails" {
  run_backupd "nonexistent"
  assert_failure
}

@test "backupd unknown-command shows error message" {
  run_backupd "nonexistent"
  assert_output --partial "Unknown option"
}

# ---------- Backup subcommand dispatch ----------

@test "backupd backup without type shows usage" {
  run_backupd backup
  assert_output --partial "Usage:"
}

@test "backupd backup invalid-type fails with exit 2" {
  run_backupd backup nonsense
  [[ "$status" -eq 2 ]]
}

@test "backupd backup --help exits 0" {
  run_backupd backup --help
  assert_success
}

@test "backupd backup --help shows subcommands" {
  run_backupd backup --help
  assert_output --partial "db"
  assert_output --partial "files"
  assert_output --partial "all"
}
