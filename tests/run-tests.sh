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
  echo "Usage: $0 [--syntax|--unit|--integration|--all|--coverage]"
  echo ""
  echo "Test levels:"
  echo "  --syntax        Run bash -n syntax check on all source files"
  echo "  --unit          Run unit tests (no root required, fast)"
  echo "  --integration   Run integration tests (requires root, real system)"
  echo "  --all           Run all levels (syntax + unit + integration)"
  echo "  --coverage      Measure coverage with kcov (unit + best-effort"
  echo "                  integration), emit Cobertura XML. Needs the container"
  echo "                  harness (kcov); see tests/docker/Dockerfile."
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

run_coverage() {
  echo -e "${YELLOW}=== Coverage (kcov) ===${NC}"
  local KCOV; KCOV="$(command -v kcov || true)"
  if [[ -z "$KCOV" ]]; then
    echo -e "${RED}kcov not found.${NC} Run coverage inside the container harness:"
    echo "  docker build -t backupd-ci tests/docker"
    echo "  docker run --rm -v \"\$PWD\":/src -w /src backupd-ci ./tests/run-tests.sh --coverage"
    return 1
  fi
  if [[ ! -x "$BATS" ]]; then
    echo -e "${RED}Error: bats not found at $BATS${NC}"
    echo "Run: git submodule update --init --recursive"
    return 1
  fi

  local WORK="/tmp/backupd-cov"
  local COV="${COVERAGE_DIR:-$PROJECT_ROOT/coverage}"
  local INC="$PROJECT_ROOT/lib,$PROJECT_ROOT/backupd.sh"
  local EXC="$PROJECT_ROOT/tests"
  rm -rf "$WORK"; mkdir -p "$WORK/int" "$COV"

  local -a merge_dirs=()

  # --- Unit coverage: bats sources lib modules into its own process, so kcov
  #     wrapping bats captures them directly. ---
  echo "--- unit ---"
  if "$KCOV" --include-path="$INC" --exclude-pattern="$EXC" "$WORK/unit" "$BATS" "$SCRIPT_DIR/unit/"; then
    merge_dirs+=("$WORK/unit")
  fi

  # --- Integration coverage (best-effort): the suite shells out to the installed
  #     `backupd` (a separate process), so we install a kcov shim as the binary.
  #     Each invocation self-instruments; coverage accrues across the suite even
  #     though some tests can't fully run without MySQL/cloud. Requires root + sudo
  #     (i.e. the container), matching the run_backupd helper's `sudo backupd`. ---
  if [[ $EUID -eq 0 ]] && command -v sudo >/dev/null 2>&1; then
    echo "--- integration (best-effort) ---"
    cat > /usr/local/bin/backupd <<SHIM
#!/usr/bin/env bash
d="\$(mktemp -d "$WORK/int/XXXXXX")"
exec "$KCOV" --include-path="$INC" --exclude-pattern="$EXC" "\$d" "$PROJECT_ROOT/backupd.sh" "\$@"
SHIM
    chmod +x /usr/local/bin/backupd
    "$BATS" "$SCRIPT_DIR/integration/" || true
    local d
    for d in "$WORK"/int/*/; do [[ -d "$d" ]] && merge_dirs+=("$d"); done
  else
    echo "(skipping integration coverage: needs root + sudo; run in the container)"
  fi

  if [[ ${#merge_dirs[@]} -eq 0 ]]; then
    echo -e "${RED}No coverage data produced.${NC}"
    return 1
  fi

  echo "--- merge ---"
  "$KCOV" --merge "$WORK/merged" "${merge_dirs[@]}"

  local cob; cob="$(find "$WORK/merged" -name cobertura.xml 2>/dev/null | head -1)"
  if [[ -n "$cob" ]]; then
    cp "$cob" "$COV/cobertura.xml"
    echo -e "${GREEN}Cobertura:${NC} $COV/cobertura.xml"
  fi

  local mj; mj="$(find "$WORK/merged" -name coverage.json 2>/dev/null | head -1)"
  if [[ -n "$mj" ]] && command -v jq >/dev/null 2>&1; then
    echo "--- summary (merged unit + integration) ---"
    jq -r '"TOTAL \(.percent_covered)% (\(.covered_lines)/\(.total_lines) lines)"' "$mj"
    jq -r '.files[]? | "  \(.percent_covered)%\t\(.covered_lines)/\(.total_lines)\t\(.file | split("/") | last)"' "$mj" | sort -rn
  fi
}

# Parse arguments
[[ $# -eq 0 ]] && usage

case "${1:-}" in
  --syntax)      run_syntax ;;
  --unit)        run_unit ;;
  --integration) run_integration ;;
  --coverage)    run_coverage ;;
  --all)
    run_syntax
    echo ""
    run_unit
    echo ""
    run_integration
    ;;
  *) usage ;;
esac
