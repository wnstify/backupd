# Logging Audit Report: lib/config.sh

**File:** `/home/webnestify/backupd/lib/config.sh`
**Audit Date:** 2026-01-05
**Auditor:** Claude Code

## Summary

| Severity | Count |
|----------|-------|
| HIGH     | 1     |
| MEDIUM   | 0     |
| LOW      | 0     |
| **Total**| **1** |

## Findings

### Issue 1: print_error used instead of log_error

| Field | Value |
|-------|-------|
| **Line** | 26 |
| **Priority** | HIGH |
| **Pattern** | `print_error` without logging |

**Current Code:**
```bash
print_error "Invalid config key: $key"
```

**Context:**
```bash
save_config() {
  local key="$1"
  local value="$2"

  # Validate key (alphanumeric and underscore only)
  if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    print_error "Invalid config key: $key"  # <-- Issue here
    return 1
  fi
```

**Problem:**
The `print_error` function (from lib/core.sh) only outputs to stderr with formatting. It does not:
- Log to the log file
- Include stack trace information
- Record caller function/file/line information

This is a validation error that should be logged for debugging purposes.

**Recommended Fix:**
```bash
log_error "Invalid config key: $key"
print_error "Invalid config key: $key"
```

Or if `print_error` should be replaced entirely with a logging + display function:
```bash
log_error "Invalid config key: $key"
[[ "${QUIET_MODE:-0}" -ne 1 ]] && echo -e "${RED}Invalid config key: $key${NC}" >&2
```

**Rationale:**
- Invalid config keys could indicate bugs in calling code or configuration corruption
- Having this logged helps diagnose issues when users report problems
- The stack trace in `log_error` would show which function attempted to save an invalid key

---

## Non-Issues (Reviewed and Cleared)

### Line 41: echo for config file writing
```bash
echo "${key}=\"${value}\"" >> "$CONFIG_FILE"
```
**Status:** CORRECT - This is data output to the config file, not a log/status message.

### Line 37: Suppressed stderr
```bash
grep -v "^${key}=" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" 2>/dev/null || true
```
**Status:** CORRECT - This suppresses grep errors when the key doesn't exist (expected behavior).

### Line 16: Suppressed stderr
```bash
grep "^${key}=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"'
```
**Status:** CORRECT - This suppresses grep errors when looking up potentially non-existent keys.

---

## Recommendations

1. **Add log_error before print_error on line 26** to ensure the validation failure is recorded in the log file with full context.

2. **Consider adding log_debug calls** for successful config operations to aid troubleshooting:
   - `log_debug "Config value saved: $key"` in `save_config()`
   - `log_debug "Config value retrieved: $key"` in `get_config_value()` (optional, may be too verbose)

3. **Consider adding log_trace** for function entry/exit if detailed debugging is needed:
   ```bash
   save_config() {
     log_trace "save_config called with key=$key"
     # ... existing code ...
   }
   ```

---

## File Statistics

- **Total Lines:** 44
- **Functions:** 3 (`is_configured`, `get_config_value`, `save_config`)
- **Logging Issues Found:** 1
- **Clean Patterns:** 3 (echo for data, suppressed stderr for expected conditions)
