#!/usr/bin/env bash
# tests/unit/debug.bats — Tests for lib/debug.sh sanitization functions

setup() {
  load '../test_helper'
  export BACKUPD_TRAP_SET=1
  source_modules "exitcodes" "core" "debug"
}

# ---------- debug_sanitize() ----------

@test "debug_sanitize hides password values" {
  run debug_sanitize 'password="secret123"'
  refute_output --partial "secret123"
}

@test "debug_sanitize hides token values" {
  run debug_sanitize 'token="abc123"'
  refute_output --partial "abc123"
}

@test "debug_sanitize hides long hex strings (hashes)" {
  run debug_sanitize 'hash=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2'
  refute_output --partial "a1b2c3d4e5f6"
}

@test "debug_sanitize preserves normal log messages" {
  run debug_sanitize 'Backup completed successfully for job default'
  assert_output 'Backup completed successfully for job default'
}

@test "debug_sanitize handles empty input" {
  run debug_sanitize ''
  assert_success
}

# ---------- debug_sanitize_path() ----------

@test "debug_sanitize_path hides secret directory names" {
  run debug_sanitize_path '/etc/.abc123def456/'
  refute_output --partial "abc123def456"
}

@test "debug_sanitize_path preserves normal paths" {
  run debug_sanitize_path '/etc/backupd/lib/core.sh'
  assert_output '/etc/backupd/lib/core.sh'
}
