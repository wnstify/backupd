#!/usr/bin/env bash
# tests/unit/history.bats — Tests for lib/history.sh pure functions

setup() {
  load '../test_helper'
  export BACKUPD_TRAP_SET=1
  source_modules "exitcodes" "core" "debug" "logging" "history"
}

# ---------- format_duration() ----------

@test "format_duration 0 seconds" {
  run format_duration 0
  assert_output "0s"
}

@test "format_duration 45 seconds" {
  run format_duration 45
  assert_output "45s"
}

@test "format_duration 59 seconds" {
  run format_duration 59
  assert_output "59s"
}

@test "format_duration 60 seconds = 1m 0s" {
  run format_duration 60
  assert_output "1m 0s"
}

@test "format_duration 150 seconds = 2m 30s" {
  run format_duration 150
  assert_output "2m 30s"
}

@test "format_duration 3600 seconds = 1h 0m" {
  run format_duration 3600
  assert_output "1h 0m"
}

@test "format_duration 3665 seconds = 1h 1m" {
  run format_duration 3665
  assert_output "1h 1m"
}

@test "format_duration 7200 seconds = 2h 0m" {
  run format_duration 7200
  assert_output "2h 0m"
}

@test "format_duration 1 second" {
  run format_duration 1
  assert_output "1s"
}
