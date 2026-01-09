# Logging Audit Report: lib/restore.sh

**File:** `/home/webnestify/backupd/lib/restore.sh`
**Audit Date:** 2026-01-05
**Auditor:** Claude Code

---

## Summary

The `lib/restore.sh` file is a small module (55 lines) with **4 logging issues** identified. The issues are primarily related to:
1. Use of `print_error` which bypasses the structured logging API
2. Direct `echo` statements for user-facing messages that should optionally be logged

---

## Issues Found

### Issue 1: print_error bypasses logging API

**Line:** 18
**Priority:** HIGH
**Current Code:**
```bash
print_error "System not configured. Please run setup first."
```

**Problem:** `print_error()` (defined in `lib/core.sh:61-63`) writes directly to stderr with `echo -e "${RED}... ${NC}" >&2` without calling `log_error()`. This means:
- Errors are not captured in the log file
- No stack trace is generated
- No structured logging format

**Recommended Fix:**
```bash
log_error "System not configured. Please run setup first."
print_error "System not configured. Please run setup first."
```

Or create a unified function that does both:
```bash
error_msg "System not configured. Please run setup first."
```

---

### Issue 2: print_error for missing database restore script

**Line:** 36
**Priority:** HIGH
**Current Code:**
```bash
print_error "Database restore script not found."
```

**Problem:** Same as Issue 1 - error is displayed to user but not logged for debugging.

**Recommended Fix:**
```bash
log_error "Database restore script not found: $SCRIPTS_DIR/db_restore.sh"
print_error "Database restore script not found."
```

---

### Issue 3: print_error for missing files restore script

**Line:** 46
**Priority:** HIGH
**Current Code:**
```bash
print_error "Files restore script not found."
```

**Problem:** Same as Issues 1-2 - error is displayed to user but not logged for debugging.

**Recommended Fix:**
```bash
log_error "Files restore script not found: $SCRIPTS_DIR/files_restore.sh"
print_error "Files restore script not found."
```

---

### Issue 4: Status echo statements not logged

**Lines:** 13-15, 23-26, 32, 42
**Priority:** LOW
**Current Code:**
```bash
echo "Restore from Backup"
echo "==================="
echo

echo "1. Restore database(s)"
echo "2. Restore files/sites"
echo "3. Back to main menu"
echo
```

**Problem:** Menu and header output is not logged. While this is user interface text and may not need logging, it could be useful for debugging to know which menu the user was in.

**Recommended Fix (optional):**
```bash
log_debug "Displaying restore menu"
echo "Restore from Backup"
echo "==================="
echo
```

---

## Structural Recommendations

### 1. Unified Error Display and Logging

Create a helper function that both logs and displays errors:

```bash
# In lib/core.sh or lib/logging.sh
error_msg() {
    local message="$1"
    log_error "$message"
    print_error "$message"
}

warn_msg() {
    local message="$1"
    log_warn "$message"
    print_warning "$message"
}
```

### 2. Function Exit Logging

The function currently calls `log_func_enter` but lacks corresponding `log_func_exit` or proper instrumentation:

```bash
run_restore() {
  log_func_enter
  debug_enter "run_restore"
  # ... function body ...
  # Missing: log_func_exit
}
```

**Recommended:** Add `log_func_exit` before all return statements or use the trap-based approach.

---

## Issues by Priority

| Priority | Count | Description |
|----------|-------|-------------|
| HIGH     | 3     | `print_error` calls that bypass logging |
| LOW      | 1     | Status `echo` statements not logged |

---

## Files Requiring Coordinated Updates

1. **lib/core.sh** - Update `print_error()`, `print_warning()`, `print_info()` to also call logging functions, or create wrapper functions
2. **lib/restore.sh** - Apply fixes as documented above

---

## Testing After Fix

After applying fixes, verify:
1. Run `backupd restore` with `--verbose` and `--log-file /tmp/test.log`
2. Trigger each error condition
3. Check that `/tmp/test.log` contains structured error entries with stack traces
4. Verify terminal output still displays colored error messages

---

## Conclusion

The `lib/restore.sh` file has **3 HIGH priority issues** where errors displayed to users are not being logged to the structured log file. This makes debugging difficult as there is no record of errors that occurred during restore operations.

The recommended approach is to either:
1. Add explicit `log_error()` calls before each `print_error()` call, OR
2. Create unified wrapper functions that handle both logging and display

The module is otherwise well-structured with proper function entry instrumentation via `log_func_enter`.
