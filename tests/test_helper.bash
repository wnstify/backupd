#!/usr/bin/env bash
# tests/test_helper.bash — Shared setup for all bats tests

# Locate project root (one level up from tests/)
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

# Load bats libraries
load "${TEST_DIR}/libs/bats-support/load"
load "${TEST_DIR}/libs/bats-assert/load"

# ---------- Unit Test Helpers ----------

# Source a single lib module with minimal globals set up.
# Usage: source_module "core" (loads lib/core.sh)
source_module() {
  local module="$1"

  # Set globals that modules expect (mimic backupd.sh lines 14-45)
  export VERSION="${VERSION:-3.2.2}"
  export INSTALL_DIR="${INSTALL_DIR:-/etc/backupd}"
  export SCRIPTS_DIR="${SCRIPTS_DIR:-$INSTALL_DIR/scripts}"
  export CONFIG_FILE="${CONFIG_FILE:-$INSTALL_DIR/.config}"
  export LIB_DIR="$PROJECT_ROOT/lib"

  # Suppress side effects during sourcing
  export QUIET_MODE="${QUIET_MODE:-1}"
  export JSON_OUTPUT="${JSON_OUTPUT:-0}"
  export DRY_RUN="${DRY_RUN:-0}"
  export DEBUG_ENABLED="${DEBUG_ENABLED:-0}"

  source "$PROJECT_ROOT/lib/${module}.sh"
}

# Source multiple modules in dependency order.
# Usage: source_modules "core" "exitcodes" "logging"
source_modules() {
  for mod in "$@"; do
    source_module "$mod"
  done
}

# ---------- Integration Test Helpers ----------

# Run backupd CLI command (requires root for most commands).
# Usage: run_backupd "status" "--json"
run_backupd() {
  run sudo /usr/local/bin/backupd "$@"
}

# Validate output is valid JSON via jq
assert_valid_json() {
  echo "$output" | jq . >/dev/null 2>&1 || {
    echo "Invalid JSON output: $output"
    return 1
  }
}

# Extract a JSON field from $output
# Usage: json_field ".configured"
json_field() {
  echo "$output" | jq -r "$1"
}

# ---------- Job Test Helpers ----------

TEST_JOB_PREFIX="test-"

# Create a test job, returns job name
create_test_job() {
  local name="${1:-${TEST_JOB_PREFIX}job-$$}"
  sudo backupd job create "$name" 2>/dev/null
  echo "$name"
}

# Clean up all test-* jobs
cleanup_test_jobs() {
  local jobs
  jobs=$(sudo backupd job list --json 2>/dev/null | jq -r '.jobs[]?.name // empty' 2>/dev/null) || true
  for job in $jobs; do
    if [[ "$job" == ${TEST_JOB_PREFIX}* ]]; then
      sudo backupd job delete "$job" --force 2>/dev/null || true
    fi
  done
}
