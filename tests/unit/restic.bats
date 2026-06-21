#!/usr/bin/env bash
# tests/unit/restic.bats — Tests for lib/restic.sh

setup() {
  load '../test_helper'
  export BACKUPD_TRAP_SET=1
  source_modules "exitcodes" "core" "debug" "logging" "crypto" "restic"
}

# ---------- --retry-lock presence ----------

@test "restic.sh uses --retry-lock in lock-acquiring functions" {
  local restic_src="${BATS_TEST_DIRNAME}/../../lib/restic.sh"

  # These functions must have --retry-lock
  local functions=(
    apply_retention_days
  )

  local missing=()
  for func in "${functions[@]}"; do
    # Extract function body and check for --retry-lock
    local body
    body=$(sed -n "/^${func}()/,/^}/p" "$restic_src")
    if [[ -n "$body" ]] && ! echo "$body" | grep -q "retry-lock"; then
      missing+=("$func")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Functions missing --retry-lock: ${missing[*]}"
    return 1
  fi
}

@test "restic.sh does NOT use --retry-lock in lockless functions" {
  local restic_src="${BATS_TEST_DIRNAME}/../../lib/restic.sh"

  # These functions must NOT have --retry-lock
  local functions=(
    init_restic_repo
    repo_exists
  )

  local wrongly_has=()
  for func in "${functions[@]}"; do
    local body
    body=$(sed -n "/^${func}()/,/^}/p" "$restic_src")
    if [[ -n "$body" ]] && echo "$body" | grep -q "retry-lock"; then
      wrongly_has+=("$func")
    fi
  done

  if [[ ${#wrongly_has[@]} -gt 0 ]]; then
    echo "Lockless functions should not have --retry-lock: ${wrongly_has[*]}"
    return 1
  fi
}
