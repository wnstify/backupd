#!/usr/bin/env bash
# tests/run-tests.sh — Single entry point for all test levels
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BATS="$SCRIPT_DIR/libs/bats-core/bin/bats"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  echo "Usage: $0 [--syntax|--unit|--integration|--all]"
  echo ""
  echo "Test levels:"
  echo "  --syntax        Run bash -n syntax check on all source files"
  echo "  --unit          Run unit tests (no root required, fast)"
  echo "  --integration   Run integration tests (requires root, real system)"
  echo "  --all           Run all levels (syntax + unit + integration)"
  echo ""
  echo "Examples:"
  echo "  $0 --syntax                    # Quick syntax check"
  echo "  $0 --unit                      # Unit tests only"
  echo "  sudo $0 --integration          # Integration tests"
  echo "  sudo $0 --all                  # Everything"
  exit 1
}

run_syntax() {
  echo -e "${YELLOW}=== Syntax Check ===${NC}"
  local failed=0
  local checked=0

  # Check main entry point
  if bash -n "$PROJECT_ROOT/backupd.sh" 2>&1; then
    echo -e "  ${GREEN}PASS${NC}  backupd.sh"
  else
    echo -e "  ${RED}FAIL${NC}  backupd.sh"
    failed=$((failed + 1))
  fi
  checked=$((checked + 1))

  # Check all lib modules
  for f in "$PROJECT_ROOT"/lib/*.sh; do
    local name
    name=$(basename "$f")
    if bash -n "$f" 2>&1; then
      echo -e "  ${GREEN}PASS${NC}  lib/$name"
    else
      echo -e "  ${RED}FAIL${NC}  lib/$name"
      failed=$((failed + 1))
    fi
    checked=$((checked + 1))
  done

  echo ""
  if [[ $failed -eq 0 ]]; then
    echo -e "${GREEN}Syntax check passed: $checked files${NC}"
  else
    echo -e "${RED}Syntax check failed: $failed/$checked files${NC}"
    return 1
  fi
}

run_unit() {
  echo -e "${YELLOW}=== Unit Tests ===${NC}"
  if [[ ! -x "$BATS" ]]; then
    echo -e "${RED}Error: bats not found at $BATS${NC}"
    echo "Run: git submodule update --init --recursive"
    return 1
  fi
  "$BATS" "$SCRIPT_DIR/unit/"
}

run_integration() {
  echo -e "${YELLOW}=== Integration Tests ===${NC}"
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: Integration tests require root. Run with sudo.${NC}"
    return 1
  fi
  if [[ ! -x "$BATS" ]]; then
    echo -e "${RED}Error: bats not found at $BATS${NC}"
    echo "Run: git submodule update --init --recursive"
    return 1
  fi
  "$BATS" "$SCRIPT_DIR/integration/"
}

# Parse arguments
[[ $# -eq 0 ]] && usage

case "${1:-}" in
  --syntax)      run_syntax ;;
  --unit)        run_unit ;;
  --integration) run_integration ;;
  --all)
    run_syntax
    echo ""
    run_unit
    echo ""
    run_integration
    ;;
  *) usage ;;
esac
