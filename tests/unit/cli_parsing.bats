#!/usr/bin/env bash
# tests/unit/cli_parsing.bats — Tests for CLI argument parsing and routing

setup() {
  load '../test_helper'
}

# ---------- --version ----------

@test "backupd --version outputs version string" {
  run bash "$PROJECT_ROOT/backupd.sh" --version 2>/dev/null
  assert_output --partial "Backupd v"
}

@test "backupd -v outputs version string" {
  run bash "$PROJECT_ROOT/backupd.sh" -v 2>/dev/null
  assert_output --partial "Backupd v"
}

# ---------- --help ----------

@test "backupd --help shows usage" {
  run bash "$PROJECT_ROOT/backupd.sh" --help 2>/dev/null
  assert_output --partial "Usage:"
  assert_output --partial "Commands:"
}

@test "backupd -h shows usage" {
  run bash "$PROJECT_ROOT/backupd.sh" -h 2>/dev/null
  assert_output --partial "Usage:"
}

# ---------- Subcommand help ----------
# Note: history, job, notifications --help require root and are excluded.
# Subcommand --help produces stderr noise from logging (permission denied),
# so we redirect stderr inside the run command.

@test "backupd backup --help shows backup usage" {
  run bash -c "bash '$PROJECT_ROOT/backupd.sh' backup --help 2>/dev/null"
  assert_success
  assert_output --partial "backup"
}

@test "backupd restore --help shows restore usage" {
  run bash -c "bash '$PROJECT_ROOT/backupd.sh' restore --help 2>/dev/null"
  assert_success
  assert_output --partial "restore"
}

@test "backupd status --help shows status usage" {
  run bash -c "bash '$PROJECT_ROOT/backupd.sh' status --help 2>/dev/null"
  assert_success
  assert_output --partial "status"
}

@test "backupd verify --help shows verify usage" {
  run bash -c "bash '$PROJECT_ROOT/backupd.sh' verify --help 2>/dev/null"
  assert_success
  assert_output --partial "verify"
}

@test "backupd schedule --help shows schedule usage" {
  run bash -c "bash '$PROJECT_ROOT/backupd.sh' schedule --help 2>/dev/null"
  assert_success
  assert_output --partial "schedule"
}

@test "backupd logs --help shows logs usage" {
  run bash -c "bash '$PROJECT_ROOT/backupd.sh' logs --help 2>/dev/null"
  assert_success
  assert_output --partial "logs"
}
