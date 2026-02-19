#!/usr/bin/env bash
# tests/unit/exitcodes.bats — Tests for lib/exitcodes.sh

setup() {
  load '../test_helper'
  source_module "exitcodes"
}

# ---------- Exit Code Constants ----------

@test "EXIT_OK is 0" {
  [[ "$EXIT_OK" -eq 0 ]]
}

@test "EXIT_ERROR is 1" {
  [[ "$EXIT_ERROR" -eq 1 ]]
}

@test "EXIT_USAGE is 2" {
  [[ "$EXIT_USAGE" -eq 2 ]]
}

@test "EXIT_CMDLINE is 64" {
  [[ "$EXIT_CMDLINE" -eq 64 ]]
}

@test "EXIT_CONFIG is 78" {
  [[ "$EXIT_CONFIG" -eq 78 ]]
}

@test "EXIT_NOPERM is 77" {
  [[ "$EXIT_NOPERM" -eq 77 ]]
}

# ---------- Backupd-Specific Mappings ----------

@test "EXIT_BACKUP_FAILED maps to EXIT_IOERR (74)" {
  [[ "$EXIT_BACKUP_FAILED" -eq 74 ]]
}

@test "EXIT_NOT_ROOT maps to EXIT_NOPERM (77)" {
  [[ "$EXIT_NOT_ROOT" -eq 77 ]]
}

@test "EXIT_NOT_CONFIGURED maps to EXIT_CONFIG (78)" {
  [[ "$EXIT_NOT_CONFIGURED" -eq 78 ]]
}

@test "EXIT_MISSING_DEP maps to EXIT_UNAVAILABLE (69)" {
  [[ "$EXIT_MISSING_DEP" -eq 69 ]]
}

# ---------- exit_code_description() ----------

@test "exit_code_description 0 returns Success" {
  run exit_code_description 0
  assert_output "Success"
}

@test "exit_code_description 1 returns General error" {
  run exit_code_description 1
  assert_output "General error"
}

@test "exit_code_description 77 returns Permission denied" {
  run exit_code_description 77
  assert_output "Permission denied"
}

@test "exit_code_description 78 returns Configuration error" {
  run exit_code_description 78
  assert_output "Configuration error"
}

@test "exit_code_description 130 returns Interrupted (Ctrl+C)" {
  run exit_code_description 130
  assert_output "Interrupted (Ctrl+C)"
}

@test "exit_code_description unknown code returns Unknown error" {
  run exit_code_description 999
  assert_output "Unknown error (999)"
}

@test "exit_code_description with no argument defaults to 0" {
  run exit_code_description
  assert_output "Success"
}

# ---------- All sysexits.h codes ----------

@test "exit_code_description covers all sysexits.h codes 64-78" {
  for code in 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78; do
    run exit_code_description "$code"
    refute_output --partial "Unknown"
  done
}
