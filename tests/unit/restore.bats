#!/usr/bin/env bash
# tests/unit/restore.bats — Tests for lib/restore.sh

setup() {
  load '../test_helper'
  export BACKUPD_TRAP_SET=1
  source_modules "exitcodes" "core" "debug" "logging" "crypto" "restic" "config" "restore"
}

# ---------- post-restore verification presence ----------

@test "inline_restore_database verifies table count after import" {
  local restore_src="${BATS_TEST_DIRNAME}/../../lib/restore.sh"
  local body
  body=$(sed -n '/^inline_restore_database()/,/^}/p' "$restore_src")
  # Must query information_schema after successful import
  echo "$body" | grep -q "information_schema" || {
    echo "No information_schema query found in inline_restore_database"
    return 1
  }
}

@test "inline_restore_files verifies files exist after restore" {
  local restore_src="${BATS_TEST_DIRNAME}/../../lib/restore.sh"
  local body
  body=$(sed -n '/^inline_restore_files()/,/^}/p' "$restore_src")
  # Must check file count or existence after successful restore
  echo "$body" | grep -q "file_count\|find.*wc\|ls.*wc" || {
    echo "No file count verification found in inline_restore_files"
    return 1
  }
}
