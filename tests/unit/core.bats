#!/usr/bin/env bash
# tests/unit/core.bats — Tests for lib/core.sh pure functions

setup() {
  load '../test_helper'
  # Prevent core.sh from overwriting bats' EXIT trap
  export BACKUPD_TRAP_SET=1
  source_modules "exitcodes" "core"
}

# ---------- validate_path() ----------

@test "validate_path accepts normal path" {
  run validate_path "/home/user/backups"
  assert_success
}

@test "validate_path accepts relative path" {
  run validate_path "backups/today"
  assert_success
}

@test "validate_path rejects empty string" {
  run validate_path ""
  assert_failure
}

@test "validate_path rejects path traversal (..)" {
  run validate_path "/home/../etc/passwd"
  assert_failure
}

@test "validate_path rejects semicolon injection" {
  run validate_path "/tmp; rm -rf /"
  assert_failure
}

@test "validate_path rejects pipe injection" {
  run validate_path "/tmp | cat /etc/passwd"
  assert_failure
}

@test "validate_path rejects backtick injection" {
  run validate_path '/tmp/`whoami`'
  assert_failure
}

@test "validate_path rejects dollar expansion" {
  run validate_path '/tmp/$(whoami)'
  assert_failure
}

@test "validate_path rejects ampersand" {
  run validate_path "/tmp & whoami"
  assert_failure
}

@test "validate_path rejects single quotes" {
  run validate_path "/tmp/'test'"
  assert_failure
}

@test "validate_path rejects double quotes" {
  run validate_path '/tmp/"test"'
  assert_failure
}

@test "validate_path allows brackets in path" {
  run validate_path "/tmp/file[1]"
  assert_success
}

@test "validate_path uses custom name in error message" {
  run validate_path "" "backup directory"
  assert_failure
  assert_output --partial "backup directory"
}

# ---------- validate_url() ----------

@test "validate_url accepts https URL" {
  run validate_url "https://example.com"
  assert_success
}

@test "validate_url accepts http URL" {
  run validate_url "http://example.com"
  assert_success
}

@test "validate_url rejects empty string" {
  run validate_url ""
  assert_failure
}

@test "validate_url rejects URL without scheme" {
  run validate_url "example.com"
  assert_failure
}

@test "validate_url rejects ftp URL" {
  run validate_url "ftp://example.com"
  assert_failure
}

# ---------- validate_password() ----------

@test "validate_password accepts strong password" {
  run validate_password 'MyP@ssw0rd!#x' 12 2
  assert_success
}

@test "validate_password rejects short password" {
  run validate_password 'Sh0rt!' 12 2
  assert_failure
}

@test "validate_password rejects password with insufficient special chars" {
  run validate_password 'abcdefghijkl1' 12 2
  assert_failure
}

@test "validate_password uses custom min_length" {
  run validate_password 'Ab!@1234' 8 2
  assert_success
}

@test "validate_password uses custom min_special" {
  run validate_password 'Abcdefghijkl!' 12 1
  assert_success
}

@test "validate_password rejects empty password" {
  run validate_password '' 12 2
  assert_failure
}

# ---------- verify_file_integrity (removed in v3.2.4) ----------

@test "verify_file_integrity is removed (dead code referenced gpg)" {
  run type -t verify_file_integrity 2>/dev/null
  assert_failure
}
