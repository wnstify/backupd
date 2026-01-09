# Logging Audit Report: lib/core.sh

**Audited:** 2026-01-05
**File:** `/home/webnestify/backupd/lib/core.sh`
**Lines:** 741

## Summary

This file contains **core utility functions** including print helpers, validation, panel detection, and rclone installation. The file has **minimal critical logging issues** because it is primarily designed for user-facing output via the `print_*` helper functions. However, there are several places where errors are reported via `print_error` or direct `echo >&2` that could benefit from also calling `log_error` for persistent logging.

**Issues Found:** 9
- HIGH Priority: 2
- MEDIUM Priority: 3
- LOW Priority: 4

---

## Critical Finding: No `error_exit` Function

The `error_exit` function **does not exist** in this file. A search across the entire `lib/` directory shows that `error_exit` is only mentioned in the `.audit/schedule-sh.md` documentation as "not found".

**This is actually GOOD** - the codebase does not rely on a potentially problematic `error_exit` function. Error handling should use `log_error` followed by `return 1` or `exit 1` as needed.

---

## Issues Found

### Issue 1: print_error bypasses logging system (HIGH)

| Field | Value |
|-------|-------|
| **Line** | 61-63 |
| **Priority** | HIGH |
| **Current Code** | `print_error() { echo -e "${RED}X $1${NC}" >&2 }` |
| **Problem** | The `print_error` function writes to stderr but never calls `log_error`. This means errors displayed to users are NOT logged to the log file for debugging. This is the **root cause** of missing error logging throughout the codebase. |
| **Recommended Fix** | Add `log_error` call inside `print_error`: |

```bash
print_error() {
  echo -e "${RED}X $1${NC}" >&2
  log_error "$1"  # Add this line
}
```

**Impact:** Fixing this single function will automatically enable logging for ALL errors throughout the codebase that use `print_error`.

---

### Issue 2: Direct echo to stderr bypasses logging (HIGH)

| Field | Value |
|-------|-------|
| **Line** | 323 |
| **Priority** | HIGH |
| **Current Code** | `echo "Failed to create secure temp directory" >&2` |
| **Problem** | Critical security-related error message is written directly to stderr, bypassing both `print_error` and `log_error`. This error indicates a potential security issue (symlink attack) and MUST be logged. |
| **Recommended Fix** | |

```bash
# Replace:
echo "Failed to create secure temp directory" >&2
# With:
log_error "Failed to create secure temp directory"
print_error "Failed to create secure temp directory"
```

---

### Issue 3: Validation errors not logged (MEDIUM)

| Field | Value |
|-------|-------|
| **Lines** | 128, 134, 140 |
| **Priority** | MEDIUM |
| **Current Code** | Multiple `print_error` calls in `validate_path()` |
| **Problem** | Path validation failures (empty path, invalid characters, path traversal attempts) are displayed but not logged. These could indicate security probing attempts. |
| **Recommended Fix** | If Issue 1 is fixed, these will automatically be logged. Otherwise add explicit `log_warn` calls: |

```bash
# Line 128 - add before print_error:
log_warn "validate_path: $name cannot be empty"

# Line 134 - add before print_error:
log_warn "validate_path: $name contains invalid characters (possible injection attempt)"

# Line 140 - add before print_error:
log_warn "validate_path: $name contains '..' (path traversal attempt)"
```

---

### Issue 4: URL validation errors not logged (MEDIUM)

| Field | Value |
|-------|-------|
| **Lines** | 153, 159, 165 |
| **Priority** | MEDIUM |
| **Current Code** | Multiple `print_error` calls in `validate_url()` |
| **Problem** | URL validation failures are displayed but not logged. Invalid URL attempts could indicate configuration issues that need debugging. |
| **Recommended Fix** | If Issue 1 is fixed, these will automatically be logged. Otherwise add explicit `log_warn` calls. |

---

### Issue 5: Password validation errors not logged (MEDIUM)

| Field | Value |
|-------|-------|
| **Lines** | 198, 205, 214 |
| **Priority** | MEDIUM |
| **Current Code** | Multiple `print_error` calls in `validate_password()` |
| **Problem** | Password validation failures should be logged for debugging (though NOT the actual passwords). The current messages reveal validation criteria which is fine. |
| **Recommended Fix** | If Issue 1 is fixed, these will automatically be logged. |

---

### Issue 6: Disk space error not logged (LOW)

| Field | Value |
|-------|-------|
| **Line** | 238 |
| **Priority** | LOW |
| **Current Code** | `print_error "Insufficient disk space. Available: ${available_mb}MB, Required: ${required_mb}MB"` |
| **Problem** | Disk space errors could indicate systemic issues and should be logged for diagnostics. |
| **Recommended Fix** | If Issue 1 is fixed, this will automatically be logged. |

---

### Issue 7: Network connectivity error not logged (LOW)

| Field | Value |
|-------|-------|
| **Line** | 252 |
| **Priority** | LOW |
| **Current Code** | `print_error "No network connectivity"` |
| **Problem** | Network errors are critical for diagnosing backup failures and should be logged. |
| **Recommended Fix** | If Issue 1 is fixed, this will automatically be logged. |

---

### Issue 8: Rclone installation errors not logged (LOW)

| Field | Value |
|-------|-------|
| **Lines** | 654-656, 673-674, 680-681, 688-691, 697-700, 707-711, 724-725, 737-738 |
| **Priority** | LOW |
| **Current Code** | Multiple `print_error` and `print_warning` calls in `install_rclone_verified()` |
| **Problem** | Rclone installation failures have many potential causes and should be logged for troubleshooting. Particularly checksum verification failures (line 707-711) could indicate security issues. |
| **Recommended Fix** | If Issue 1 is fixed, `print_error` calls will automatically be logged. For security-critical messages like checksum failures, consider adding explicit `log_error` with more detail. |

---

### Issue 9: print_warning could also log (LOW)

| Field | Value |
|-------|-------|
| **Lines** | 65-68 |
| **Priority** | LOW |
| **Current Code** | `print_warning() { ... echo -e "${YELLOW}! $1${NC}" }` |
| **Problem** | Similar to `print_error`, warnings are displayed to users but not logged. While less critical than errors, warnings often indicate issues worth preserving in logs. |
| **Recommended Fix** | Consider adding `log_warn "$1"` to `print_warning()`: |

```bash
print_warning() {
  [[ "${QUIET_MODE:-0}" -eq 1 ]] && return
  echo -e "${YELLOW}! $1${NC}"
  log_warn "$1"  # Add this line
}
```

---

## Patterns Analyzed (No Issues Found)

### 1. Color code handling

Lines 7-23 correctly implement NO_COLOR environment variable support per CLIG standards. No logging issues.

### 2. JSON output functions

Lines 84-104 (`json_output`, `json_kv`, `is_json_output`) are output format helpers. No logging issues.

### 3. Dry-run functions

Lines 108-117 correctly handle dry-run messaging. No logging issues.

### 4. MySQL helper functions

Lines 262-278 (`create_mysql_auth_file`) properly handle credential files. No logging issues - passwords are handled securely via temp files.

### 5. Log rotation functions

Lines 282-309 (`rotate_log`) are part of the logging infrastructure itself. No issues.

### 6. Panel detection functions

Lines 371-556 are pure detection functions that return values rather than report errors. No logging issues - they use return codes appropriately.

### 7. Site naming functions

Lines 570-622 (`get_site_name`, `sanitize_for_filename`) are utility functions without error conditions. No issues.

---

## Recommendations

### Priority 1: Fix print_error (Issue 1)

**This is the most impactful fix.** By adding `log_error "$1"` to the `print_error` function, ALL errors throughout the codebase that use `print_error` will automatically be logged. This is a one-line change with massive impact.

```bash
# Current (line 61-63):
print_error() {
  echo -e "${RED}X $1${NC}" >&2
}

# Recommended:
print_error() {
  echo -e "${RED}X $1${NC}" >&2
  log_error "$1"
}
```

### Priority 2: Fix create_secure_temp (Issue 2)

Direct `echo >&2` should never be used. Replace with `log_error` + `print_error`.

### Priority 3: Consider print_warning (Issue 9)

A similar change to `print_warning` would capture warnings in logs.

### Priority 4: Security-sensitive logging (Issues 3-4)

Consider adding explicit `log_warn` for validation failures that could indicate attack attempts.

---

## Conclusion

The `lib/core.sh` file is **structurally sound** but has a **systemic issue**: the `print_error` helper function does not integrate with the logging system. This means user-visible errors are lost when reviewing logs for troubleshooting.

**Root Cause:** `print_error()` function at line 61-63 writes to stderr but does not call `log_error()`.

**Solution:** Add `log_error "$1"` to `print_error()`. This single change will fix the majority of logging gaps across the entire codebase.

**File Status:** NEEDS FIX (Priority 1 issue identified)

---

## Files to Update

1. `/home/webnestify/backupd/lib/core.sh` - Add logging to `print_error` and `print_warning`
2. Verify `lib/logging.sh` is sourced before `lib/core.sh` in the main script

---

## Verification

After fixing, verify with:
```bash
# Generate an error and check log
backupd verify nonexistent --verbose --log-file /tmp/test.log
cat /tmp/test.log | grep ERROR
```
