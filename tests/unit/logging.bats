#!/usr/bin/env bash
# tests/unit/logging.bats — Tests for lib/logging.sh redaction functions

setup() {
  load '../test_helper'
  export BACKUPD_TRAP_SET=1
  # logging.sh depends on debug.sh which depends on core.sh
  source_modules "exitcodes" "core" "debug" "logging"
}

# ---------- log_redact() ----------

@test "log_redact hides password= values" {
  run log_redact 'password="secret123"'
  refute_output --partial "secret123"
  assert_output --partial "[REDACTED]"
}

@test "log_redact hides token= values" {
  run log_redact 'token="abc123def456"'
  refute_output --partial "abc123def456"
}

@test "log_redact hides Bearer tokens" {
  run log_redact 'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9'
  refute_output --partial "eyJhbGciOiJIUzI1NiJ9"
}

@test "log_redact hides Basic auth" {
  run log_redact 'Authorization: Basic dXNlcjpwYXNz'
  refute_output --partial "dXNlcjpwYXNz"
}

@test "log_redact hides api_key values" {
  run log_redact 'api_key=sk_live_abc123'
  refute_output --partial "sk_live_abc123"
}

@test "log_redact preserves non-sensitive content" {
  run log_redact 'Starting backup for database main_db'
  assert_output "Starting backup for database main_db"
}

@test "log_redact handles empty input" {
  run log_redact ''
  assert_success
}

@test "log_redact hides secret= values" {
  run log_redact 'secret="mysecretvalue"'
  refute_output --partial "mysecretvalue"
}

# ---------- redact_cmdline_args() ----------

@test "redact_cmdline_args hides --passphrase value" {
  run redact_cmdline_args '--passphrase mypass123 --verbose'
  refute_output --partial "mypass123"
  assert_output --partial "--passphrase"
}

@test "redact_cmdline_args hides -p value" {
  run redact_cmdline_args '-p secretpass --backup'
  refute_output --partial "secretpass"
}

@test "redact_cmdline_args hides BACKUPD_PASSPHRASE env" {
  run redact_cmdline_args 'BACKUPD_PASSPHRASE=mysecret backupd backup'
  refute_output --partial "mysecret"
}

@test "redact_cmdline_args preserves non-sensitive args" {
  run redact_cmdline_args 'backupd backup db --verbose'
  assert_output "backupd backup db --verbose"
}
