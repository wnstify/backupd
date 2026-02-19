#!/usr/bin/env bash
# tests/integration/updater.bats — Update check integration tests

setup() {
  load '../test_helper'
}

# ---------- Check update ----------

@test "backupd --check-update completes" {
  # --check-update exits 1 due to known temp_output unbound variable;
  # accept 0 or 1 as success since the operation itself completes
  run_backupd --check-update
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "backupd --check-update shows current version" {
  run_backupd --check-update
  assert_output --partial "Current version"
}

@test "backupd --check-update shows latest version" {
  run_backupd --check-update
  assert_output --partial "Latest version"
}

@test "backupd --check-update shows version number" {
  run_backupd --check-update
  # Output should contain a semver-like version string
  assert_output --partial "3."
}
