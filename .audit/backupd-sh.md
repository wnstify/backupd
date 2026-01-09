# Logging Audit: backupd.sh

## Summary
- Total issues found: 10
- HIGH priority: 4
- MEDIUM priority: 3
- LOW priority: 3

## Context

The proper logging API (from `lib/logging.sh`) includes:
- `log_error "message"` - for errors (auto-logs stack trace)
- `log_warn "message"` - for warnings
- `log_info "message"` - for info
- `log_debug "message"` - for debug
- `log_trace "message"` - for trace
- `log_error_full "message" exit_code` - for critical errors with full context

The existing `print_error`, `print_warning`, `print_info` functions in `lib/core.sh` are **UI-only** functions that:
- Output colored text to terminal
- Do NOT call the logging API
- Are appropriate for interactive menu feedback, but errors should ALSO be logged

## Issues

### Issue 1: Direct echo for critical library error
- **Line:** 44
- **Priority:** HIGH
- **Description:** Critical startup error bypasses logging entirely. This happens before logging is initialized, but should still be handled properly.
- **Current:**
```bash
  echo "Error: Library directory not found: $LIB_DIR"
```
- **Fix:**
```bash
  echo "Error: Library directory not found: $LIB_DIR" >&2
  # Note: Cannot use log_error here as logging.sh hasn't been sourced yet
  # This is acceptable for pre-initialization errors
```
- **Notes:** This is a special case - logging module not yet loaded. The fix should at least redirect to stderr. Consider a minimal fallback logging function.

---

### Issue 2: Direct echo for argument parsing error
- **Line:** 479
- **Priority:** HIGH
- **Description:** Error message for missing --log-file argument not logged.
- **Current:**
```bash
          echo "Error: --log-file requires a path argument"
```
- **Fix:**
```bash
          log_error "--log-file requires a path argument"
          echo "Error: --log-file requires a path argument" >&2
```

---

### Issue 3: Direct echo for unknown option error
- **Line:** 570
- **Priority:** HIGH
- **Description:** Unknown option error not logged.
- **Current:**
```bash
      echo "Unknown option: $1"
```
- **Fix:**
```bash
      log_error "Unknown option: $1"
      echo "Unknown option: $1" >&2
```

---

### Issue 4: Direct echo for root check failure
- **Line:** 612
- **Priority:** HIGH
- **Description:** Critical permission error not logged. However, logging may not be initialized at this point.
- **Current:**
```bash
  echo "This tool must be run as root."
```
- **Fix:**
```bash
  echo "This tool must be run as root." >&2
  # Note: log_error may not be available here depending on initialization order
```
- **Notes:** This error occurs before `log_init` is called. At minimum, should output to stderr.

---

### Issue 5: print_error in menu without logging
- **Line:** 223
- **Priority:** MEDIUM
- **Description:** Invalid option errors use print_error (UI only) but are not logged.
- **Current:**
```bash
        *) print_error "Invalid option" ; sleep 1 ;;
```
- **Fix:**
```bash
        *) log_warn "Invalid menu option selected"; print_error "Invalid option" ; sleep 1 ;;
```

---

### Issue 6: print_error in menu without logging (unconfigured state)
- **Line:** 239
- **Priority:** MEDIUM
- **Description:** Invalid option errors use print_error (UI only) but are not logged.
- **Current:**
```bash
        *) print_error "Invalid option" ; sleep 1 ;;
```
- **Fix:**
```bash
        *) log_warn "Invalid menu option selected"; print_error "Invalid option" ; sleep 1 ;;
```

---

### Issue 7: print_error without logging in encryption functions
- **Line:** 360
- **Priority:** MEDIUM
- **Description:** Encryption status error uses print_error without logging.
- **Current:**
```bash
    print_error "No encryption configured (setup not completed)"
```
- **Fix:**
```bash
    log_error "No encryption configured (setup not completed)"
    print_error "No encryption configured (setup not completed)"
```

---

### Issue 8: print_error without logging for Argon2 check
- **Line:** 378
- **Priority:** LOW
- **Description:** Missing dependency error uses print_error without logging.
- **Current:**
```bash
    print_error "Argon2 not installed"
```
- **Fix:**
```bash
    log_error "Argon2 not installed - cannot migrate encryption"
    print_error "Argon2 not installed"
```

---

### Issue 9: print_error without logging for migration failure
- **Line:** 414
- **Priority:** LOW
- **Description:** Migration failure uses print_error without logging.
- **Current:**
```bash
    print_error "Migration failed"
```
- **Fix:**
```bash
    log_error "Encryption migration failed"
    print_error "Migration failed"
```

---

### Issue 10: Informational echo statements in uninstall function
- **Lines:** 104, 110, 116, 119, 122, 127, 137, 141, 150, 163, 172, 395
- **Priority:** LOW
- **Description:** Multiple informational echo statements in `uninstall_tool()` and `do_migrate_encryption()` that could benefit from logging for audit trail purposes.
- **Current:**
```bash
  echo "Stopping timers..."
  echo "Stopping services..."
  echo "Disabling units..."
  echo "Removing systemd units..."
  echo "Removing secrets..."
  echo "Removing installation..."
  echo "Cancelled."
```
- **Fix:**
```bash
  log_info "Stopping timers..."; echo "Stopping timers..."
  log_info "Stopping services..."; echo "Stopping services..."
  # etc.
```
- **Notes:** These are informational messages during uninstall. Logging would provide an audit trail but is optional.

---

## Architectural Recommendations

### 1. Create a unified error output function

Consider creating a helper that both logs and displays errors:

```bash
# In lib/core.sh or lib/logging.sh
error_msg() {
  local msg="$1"
  log_error "$msg"
  print_error "$msg"
}

warn_msg() {
  local msg="$1"
  log_warn "$msg"
  print_warning "$msg"
}
```

### 2. Handle pre-initialization errors

For errors before logging is initialized (lines 44, 612), consider:

```bash
# Minimal fallback for pre-init errors
_early_error() {
  echo "Error: $1" >&2
  # Optionally write to a fixed fallback log location
}
```

### 3. Ensure stderr for all errors

All error messages should go to stderr (`>&2`), not stdout. The current `print_error` already does this correctly.

## Files to Update

1. `/home/webnestify/backupd/backupd.sh` - Primary file with issues
2. `/home/webnestify/backupd/lib/core.sh` - Consider adding unified error/warn helpers

## Testing Checklist

After fixes:
- [ ] Run `backupd --help` - should not produce log entries
- [ ] Run `backupd --unknown` - should log error and show error message
- [ ] Run `backupd` as non-root - should output to stderr
- [ ] Test uninstall flow - verify audit trail in logs
- [ ] Test encryption migration errors - verify logging
- [ ] Test invalid menu options - verify logging
