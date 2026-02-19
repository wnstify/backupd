#!/usr/bin/env bash
# tests/unit/crypto.bats — Tests for lib/crypto.sh pure functions

setup() {
  load '../test_helper'
  # Prevent core.sh from overwriting bats' EXIT trap
  export BACKUPD_TRAP_SET=1
  source_modules "exitcodes" "core" "crypto"
}

# ---------- get_crypto_name() ----------

@test "get_crypto_name version 1 returns PBKDF2 legacy" {
  run get_crypto_name 1
  assert_output --partial "PBKDF2"
  assert_output --partial "legacy"
}

@test "get_crypto_name version 2 returns PBKDF2" {
  run get_crypto_name 2
  assert_output --partial "PBKDF2"
}

@test "get_crypto_name version 3 returns Argon2id" {
  run get_crypto_name 3
  assert_output --partial "Argon2id"
}

@test "get_crypto_name unknown version returns Unknown" {
  run get_crypto_name 99
  assert_output --partial "Unknown"
}

# ---------- get_best_crypto_version() ----------

@test "get_best_crypto_version returns 2 or 3" {
  run get_best_crypto_version
  assert_success
  # Must be either 2 (no argon2) or 3 (argon2 available)
  [[ "$output" -eq 2 || "$output" -eq 3 ]]
}

# ---------- Crypto version constants ----------

@test "CRYPTO_VERSION_LEGACY is 1" {
  [[ "$CRYPTO_VERSION_LEGACY" -eq 1 ]]
}

@test "CRYPTO_VERSION_PBKDF2 is 2" {
  [[ "$CRYPTO_VERSION_PBKDF2" -eq 2 ]]
}

@test "CRYPTO_VERSION_ARGON2ID is 3" {
  [[ "$CRYPTO_VERSION_ARGON2ID" -eq 3 ]]
}

# ---------- get_crypto_version() with temp dir ----------

@test "get_crypto_version returns 1 when .algo file missing" {
  local tmpdir
  tmpdir=$(mktemp -d)
  run get_crypto_version "$tmpdir"
  assert_output "1"
  rm -rf "$tmpdir"
}

@test "get_crypto_version reads .algo file correctly" {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo "3" > "$tmpdir/.algo"
  run get_crypto_version "$tmpdir"
  assert_output "3"
  rm -rf "$tmpdir"
}

# ---------- store_secret() atomic write pattern ----------

@test "store_secret uses atomic write (temp + mv pattern)" {
  # Verify the source code uses mktemp + mv pattern, not direct write
  local crypto_src="${BATS_TEST_DIRNAME}/../../lib/crypto.sh"
  # Check that store_secret contains mktemp (atomic write)
  run grep -A 20 '^store_secret()' "$crypto_src"
  assert_output --partial "mktemp"
  assert_output --partial 'mv "'
}
