#!/usr/bin/env bash
# tests/unit/jobs.bats — Tests for lib/jobs.sh validation functions

setup() {
  load '../test_helper'
  export BACKUPD_TRAP_SET=1
  source_modules "exitcodes" "core" "debug" "logging" "jobs"
  # Override JOBS_DIR after sourcing (jobs.sh sets it from INSTALL_DIR at source time)
  export JOBS_DIR="/tmp/backupd-test-jobs-$$"
  mkdir -p "$JOBS_DIR"
}

teardown() {
  rm -rf "$JOBS_DIR"
}

# ---------- validate_job_name() ----------

@test "validate_job_name accepts alphanumeric name" {
  run validate_job_name "mybackup"
  assert_success
}

@test "validate_job_name accepts name with hyphens" {
  run validate_job_name "my-backup-job"
  assert_success
}

@test "validate_job_name accepts name with underscores" {
  run validate_job_name "my_backup_job"
  assert_success
}

@test "validate_job_name accepts name with numbers" {
  run validate_job_name "backup123"
  assert_success
}

@test "validate_job_name accepts 2-char name (minimum)" {
  run validate_job_name "ab"
  assert_success
}

@test "validate_job_name accepts 32-char name (maximum)" {
  run validate_job_name "abcdefghijklmnopqrstuvwxyz123456"
  assert_success
}

@test "validate_job_name rejects empty string" {
  run validate_job_name ""
  assert_failure
}

@test "validate_job_name rejects single char" {
  run validate_job_name "a"
  assert_failure
}

@test "validate_job_name rejects 33+ chars" {
  run validate_job_name "abcdefghijklmnopqrstuvwxyz1234567"
  assert_failure
}

@test "validate_job_name rejects special characters" {
  run validate_job_name "my job!"
  assert_failure
}

@test "validate_job_name rejects name starting with hyphen" {
  run validate_job_name "-mybackup"
  assert_failure
}

@test "validate_job_name rejects name starting with underscore" {
  run validate_job_name "_mybackup"
  assert_failure
}

@test "validate_job_name rejects reserved name 'all'" {
  run validate_job_name "all"
  assert_failure
}

@test "validate_job_name rejects reserved name 'list'" {
  run validate_job_name "list"
  assert_failure
}

@test "validate_job_name rejects reserved name 'help'" {
  run validate_job_name "help"
  assert_failure
}

@test "validate_job_name rejects reserved name 'none'" {
  run validate_job_name "none"
  assert_failure
}

@test "validate_job_name rejects reserved name case-insensitive 'ALL'" {
  run validate_job_name "ALL"
  assert_failure
}

@test "validate_job_name quiet mode suppresses error output" {
  run validate_job_name "" "true"
  assert_failure
  assert_output ""
}
