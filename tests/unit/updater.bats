#!/usr/bin/env bash
# tests/unit/updater.bats — Tests for lib/updater.sh version functions

setup() {
  load '../test_helper'
  export BACKUPD_TRAP_SET=1
  source_modules "exitcodes" "core" "debug" "logging" "crypto" "config" "updater"
}

# ---------- version_compare() ----------

@test "version_compare equal versions returns 0" {
  run version_compare "3.2.2" "3.2.2"
  assert_success
}

@test "version_compare v1 > v2 returns 1" {
  version_compare "3.3.0" "3.2.2" || true
  version_compare "3.3.0" "3.2.2" && false || [[ $? -eq 1 ]]
}

@test "version_compare v1 < v2 returns 2" {
  local rc=0
  version_compare "3.2.1" "3.2.2" || rc=$?
  [[ $rc -eq 2 ]]
}

@test "version_compare strips v prefix" {
  run version_compare "v3.2.2" "3.2.2"
  assert_success  # equal (0)
}

@test "version_compare strips pre-release suffix" {
  run version_compare "3.2.2-rc1" "3.2.2"
  assert_success  # equal after stripping
}

@test "version_compare handles major version difference" {
  local rc=0
  version_compare "4.0.0" "3.9.9" || rc=$?
  [[ $rc -eq 1 ]]
}

@test "version_compare handles minor version difference" {
  local rc=0
  version_compare "3.3.0" "3.2.9" || rc=$?
  [[ $rc -eq 1 ]]
}

@test "version_compare handles patch version difference" {
  local rc=0
  version_compare "3.2.3" "3.2.2" || rc=$?
  [[ $rc -eq 1 ]]
}

@test "version_compare handles empty v1" {
  local rc=0
  version_compare "" "3.2.2" || rc=$?
  [[ $rc -eq 3 ]]
}

@test "version_compare handles empty v2" {
  local rc=0
  version_compare "3.2.2" "" || rc=$?
  [[ $rc -eq 3 ]]
}

@test "version_compare handles both v prefixes" {
  run version_compare "v3.2.2" "v3.2.2"
  assert_success
}
