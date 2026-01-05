#!/usr/bin/env bash
# Smoke tests for backupd CLIG compliance
# Run: ./tests/smoke_test.sh

set -euo pipefail

# Colors (respect NO_COLOR)
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    NC=''
fi

# Counters
PASSED=0
FAILED=0

# Test helpers
pass() {
    PASSED=$((PASSED + 1))
    echo -e "${GREEN}PASS${NC}: $1"
}

fail() {
    FAILED=$((FAILED + 1))
    echo -e "${RED}FAIL${NC}: $1"
    if [[ -n "${2:-}" ]]; then
        echo "      Expected: $2"
    fi
    if [[ -n "${3:-}" ]]; then
        echo "      Got: $3"
    fi
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUPD="$PROJECT_DIR/backupd.sh"

echo "================================"
echo "Backupd Smoke Tests"
echo "================================"
echo ""

# Test 1: Script exists and is executable
echo "--- Basic Checks ---"
if [[ -x "$BACKUPD" ]]; then
    pass "backupd.sh is executable"
else
    fail "backupd.sh is executable" "executable" "not executable or missing"
fi

# Test 2: --help flag works (doesn't require root)
output=$("$BACKUPD" --help 2>&1) || true
if echo "$output" | grep -qi "usage\|help\|backup"; then
    pass "--help shows usage information"
else
    fail "--help shows usage information" "usage text" "$output"
fi

# Test 3: --version flag works (doesn't require root)
output=$("$BACKUPD" --version 2>&1) || true
if echo "$output" | grep -qE "v?[0-9]+\.[0-9]+"; then
    pass "--version shows version number"
else
    fail "--version shows version number" "version number" "$output"
fi

# Test 4: -h shorthand works
output=$("$BACKUPD" -h 2>&1) || true
if echo "$output" | grep -qi "usage\|help\|backup"; then
    pass "-h shows usage information"
else
    fail "-h shows usage information" "usage text" "$output"
fi

# Test 5: -v shorthand works
output=$("$BACKUPD" -v 2>&1) || true
if echo "$output" | grep -qE "v?[0-9]+\.[0-9]+"; then
    pass "-v shows version number"
else
    fail "-v shows version number" "version number" "$output"
fi

# Test 6: Invalid argument returns non-zero
echo ""
echo "--- Error Handling ---"
if ! "$BACKUPD" --invalid-flag-xyz 2>/dev/null; then
    pass "Invalid flag returns non-zero exit code"
else
    fail "Invalid flag returns non-zero exit code" "non-zero" "zero"
fi

# Test 7: Help output contains expected sections
echo ""
echo "--- Help Content ---"
help_output=$("$BACKUPD" --help 2>&1) || true

if echo "$help_output" | grep -qi "backup"; then
    pass "Help mentions 'backup'"
else
    fail "Help mentions 'backup'" "contains 'backup'" "missing"
fi

if echo "$help_output" | grep -qi "menu\|interactive"; then
    pass "Help mentions interactive menu"
else
    fail "Help mentions interactive menu" "contains 'menu'" "missing"
fi

# Test 8: Version format is semantic
echo ""
echo "--- Version Format ---"
version_output=$("$BACKUPD" --version 2>&1) || true
if echo "$version_output" | grep -qE "[0-9]+\.[0-9]+\.[0-9]+"; then
    pass "Version follows semver format (x.y.z)"
else
    fail "Version follows semver format" "x.y.z" "$version_output"
fi

# ============================================================================
# Phase 2: Subcommand Tests
# These test the CLI subcommand dispatcher
# ============================================================================

echo ""
echo "--- Phase 2: Subcommand Help ---"

# Test 9: backup subcommand --help
output=$("$BACKUPD" backup --help 2>&1) || true
if echo "$output" | grep -qi "usage.*backup\|backup.*db\|database"; then
    pass "backup --help shows usage"
else
    fail "backup --help shows usage" "usage text" "$output"
fi

# Test 10: restore subcommand --help
output=$("$BACKUPD" restore --help 2>&1) || true
if echo "$output" | grep -qi "usage.*restore\|restore.*db\|database"; then
    pass "restore --help shows usage"
else
    fail "restore --help shows usage" "usage text" "$output"
fi

# Test 11: status subcommand --help
output=$("$BACKUPD" status --help 2>&1) || true
if echo "$output" | grep -qi "usage.*status\|status"; then
    pass "status --help shows usage"
else
    fail "status --help shows usage" "usage text" "$output"
fi

# Test 12: verify subcommand --help
output=$("$BACKUPD" verify --help 2>&1) || true
if echo "$output" | grep -qi "usage.*verify\|verify\|integrity"; then
    pass "verify --help shows usage"
else
    fail "verify --help shows usage" "usage text" "$output"
fi

# Test 13: schedule subcommand --help
output=$("$BACKUPD" schedule --help 2>&1) || true
if echo "$output" | grep -qi "usage.*schedule\|schedule\|list\|enable\|disable"; then
    pass "schedule --help shows usage"
else
    fail "schedule --help shows usage" "usage text" "$output"
fi

# Test 14: logs subcommand --help
output=$("$BACKUPD" logs --help 2>&1) || true
if echo "$output" | grep -qi "usage.*logs\|logs\|lines"; then
    pass "logs --help shows usage"
else
    fail "logs --help shows usage" "usage text" "$output"
fi

echo ""
echo "--- Phase 2: Subcommand Errors ---"

# Test 15: Unknown subcommand returns error
if ! "$BACKUPD" unknownsubcmd 2>/dev/null; then
    pass "Unknown subcommand returns non-zero"
else
    fail "Unknown subcommand returns non-zero" "non-zero" "zero"
fi

# Test 16: backup with invalid type returns error
output=$("$BACKUPD" backup invalidtype 2>&1) || exit_code=$?
if [[ "${exit_code:-1}" -ne 0 ]] || echo "$output" | grep -qi "unknown\|invalid\|error"; then
    pass "backup invalidtype returns error"
else
    fail "backup invalidtype returns error" "error message" "$output"
fi

echo ""
echo "--- Phase 2: JSON Output ---"

# Test 17 & 18: JSON tests require root - skip if not root
if [[ $EUID -eq 0 ]]; then
    # Test 17: status --json produces valid JSON structure
    output=$("$BACKUPD" status --json 2>&1) || true
    if echo "$output" | grep -qE '^\s*\{' && echo "$output" | grep -qE '"configured"\s*:'; then
        pass "status --json produces JSON with 'configured' field"
    else
        fail "status --json produces JSON" "JSON object" "$output"
    fi

    # Test 18: schedule --json produces valid JSON structure
    output=$("$BACKUPD" schedule --json 2>&1) || true
    if echo "$output" | grep -qE '^\s*\{' && echo "$output" | grep -qE '"schedules"\s*:'; then
        pass "schedule --json produces JSON with 'schedules' field"
    else
        fail "schedule --json produces JSON" "JSON object" "$output"
    fi
else
    echo "SKIP: status --json (requires root)"
    echo "SKIP: schedule --json (requires root)"
    echo "      Run with sudo to test JSON output"
fi

# ============================================================================
# Phase 3: Polish Tests
# These test --dry-run flag and enhanced JSON output
# ============================================================================

echo ""
echo "--- Phase 3: Dry-Run Flag ---"

# Test 19: Main help mentions --dry-run
help_output=$("$BACKUPD" --help 2>&1) || true
if echo "$help_output" | grep -qi "dry-run"; then
    pass "Main help mentions --dry-run"
else
    fail "Main help mentions --dry-run" "contains '--dry-run'" "missing"
fi

# Test 20: backup --help mentions --dry-run
output=$("$BACKUPD" backup --help 2>&1) || true
if echo "$output" | grep -qi "dry-run"; then
    pass "backup --help mentions --dry-run"
else
    fail "backup --help mentions --dry-run" "contains '--dry-run'" "missing"
fi

# Test 21: restore --help mentions --dry-run
output=$("$BACKUPD" restore --help 2>&1) || true
if echo "$output" | grep -qi "dry-run"; then
    pass "restore --help mentions --dry-run"
else
    fail "restore --help mentions --dry-run" "contains '--dry-run'" "missing"
fi

echo ""
echo "--- Phase 3: Verify JSON ---"

# Test 22: verify --help mentions --json
output=$("$BACKUPD" verify --help 2>&1) || true
if echo "$output" | grep -qi "json"; then
    pass "verify --help mentions --json"
else
    fail "verify --help mentions --json" "contains '--json'" "missing"
fi

# Tests 23-24: JSON output tests require root
if [[ $EUID -eq 0 ]]; then
    # Test 23: verify --json produces valid JSON structure
    output=$("$BACKUPD" verify --json 2>&1) || true
    if echo "$output" | grep -qE '^\s*\{' && echo "$output" | grep -qE '"results"\s*:'; then
        pass "verify --json produces JSON with 'results' field"
    else
        fail "verify --json produces JSON" "JSON object with results" "$output"
    fi

    # Test 24: verify --json contains expected fields
    if echo "$output" | grep -qE '"status"\s*:.*"(PASSED|FAILED|WARNING|SKIPPED)"'; then
        pass "verify --json contains status field"
    else
        fail "verify --json contains status field" "status field" "$output"
    fi
else
    echo "SKIP: verify --json (requires root)"
    echo "SKIP: verify --json status field (requires root)"
fi

echo ""
echo "--- Phase 3: Help Quality ---"

# Test 25: Main help has DESCRIPTION or description section
help_output=$("$BACKUPD" --help 2>&1) || true
if echo "$help_output" | grep -qi "comprehensive\|solution\|backup.*restore\|wordpress\|mysql"; then
    pass "Main help describes the tool"
else
    fail "Main help describes the tool" "descriptive text" "missing description"
fi

# Summary
echo ""
echo "================================"
echo "Results: $PASSED passed, $FAILED failed"
echo "================================"

# Exit with failure if any tests failed
if [[ $FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
