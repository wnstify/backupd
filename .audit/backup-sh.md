# Logging Audit: lib/backup.sh

## Summary
- Total issues found: 10
- HIGH priority: 3
- MEDIUM priority: 3
- LOW priority: 4

## Architecture Note

The codebase uses a dual-output system:
- `print_*` functions (from `lib/core.sh`): User-facing colored console output
- `log_*` functions (from `lib/logging.sh`): Structured file logging with stack traces

**Finding**: `lib/backup.sh` uses `print_error`, `print_warning`, `print_info`, `print_success` for user-facing output, but these do NOT call `log_*` functions. This means errors are displayed to users but NOT recorded in the log file.

---

## Issues

### Issue 1: print_error does not log to file
- **Line:** 18, 40, 52, 64, 72, 128, 153, 177
- **Priority:** HIGH
- **Description:** `print_error` only outputs to stderr with color formatting. Errors are not recorded in the log file for debugging.
- **Current:**
```bash
print_error "System not configured. Please run setup first."
```
- **Fix:**
```bash
log_error "System not configured. Please run setup first."
print_error "System not configured. Please run setup first."
```

---

### Issue 2: print_warning does not log to file
- **Line:** 100, 187
- **Priority:** MEDIUM
- **Description:** `print_warning` only outputs to console. Warnings are not recorded in the log file.
- **Current:**
```bash
print_warning "No retention policy configured (automatic cleanup disabled)"
```
- **Fix:**
```bash
log_warn "No retention policy configured (automatic cleanup disabled)"
print_warning "No retention policy configured (automatic cleanup disabled)"
```

---

### Issue 3: print_info does not log to file
- **Line:** 35, 47, 59, 68
- **Priority:** LOW
- **Description:** `print_info` only outputs to console. Info messages are not recorded in the log file.
- **Current:**
```bash
print_info "Starting database backup..."
```
- **Fix:**
```bash
log_info "Starting database backup..."
print_info "Starting database backup..."
```

---

### Issue 4: print_success does not log to file
- **Line:** 189
- **Priority:** LOW
- **Description:** `print_success` only outputs to console. Success messages are not recorded in the log file.
- **Current:**
```bash
print_success "Cleanup complete. Removed $cleanup_count old backup(s)."
```
- **Fix:**
```bash
log_info "Cleanup complete. Removed $cleanup_count old backup(s)."
print_success "Cleanup complete. Removed $cleanup_count old backup(s)."
```

---

### Issue 5: Plain echo for status messages
- **Lines:** 13-14, 23-27, 34, 57, 60, 62, 91-92, 101-102, 107-109, 114, 133-134, 139, 146, 163, 170, 185
- **Priority:** LOW
- **Description:** Many plain `echo` statements are used for UI display. While appropriate for interactive menus, critical status messages (like "Cancelled" on line 114) should be logged.
- **Current:**
```bash
echo "Cancelled."
```
- **Fix:**
```bash
log_debug "Cleanup cancelled by user"
echo "Cancelled."
```

---

### Issue 6: Cleanup deletion errors not fully logged
- **Line:** 153, 177
- **Priority:** HIGH
- **Description:** When `rclone delete` fails, the error is only shown via `print_error` and not logged. This makes debugging remote storage issues difficult.
- **Current:**
```bash
print_error "  Failed to delete $remote_file: $delete_output"
((cleanup_errors++)) || true
```
- **Fix:**
```bash
log_error "Failed to delete remote file: $remote_file - Output: $delete_output"
print_error "  Failed to delete $remote_file: $delete_output"
((cleanup_errors++)) || true
```

---

### Issue 7: Cutoff time calculation failure not logged
- **Line:** 127-131
- **Priority:** HIGH
- **Description:** If cutoff time calculation fails, the error is only shown to user via `print_error`, not logged for debugging.
- **Current:**
```bash
if [[ "$cutoff_time" -eq 0 ]]; then
  print_error "Could not calculate cutoff time"
  press_enter_to_continue
  return
fi
```
- **Fix:**
```bash
if [[ "$cutoff_time" -eq 0 ]]; then
  log_error "Could not calculate cutoff time for retention_minutes=$retention_minutes"
  print_error "Could not calculate cutoff time"
  press_enter_to_continue
  return
fi
```

---

### Issue 8: Missing log_func_exit calls
- **Lines:** 9 (run_backup), 87 (run_cleanup_now)
- **Priority:** MEDIUM
- **Description:** Functions call `log_func_enter` but do not call `log_func_exit` at return points. This breaks function timing and stack trace accuracy in TRACE mode.
- **Current:**
```bash
run_backup() {
  log_func_enter
  debug_enter "run_backup"
  # ... function body with multiple return statements
}
```
- **Fix:**
```bash
run_backup() {
  log_func_enter
  debug_enter "run_backup"
  # Use log_func_trap instead of log_func_enter for auto-exit logging
  # OR add log_func_exit before each return statement
}
```

---

### Issue 9: Backup script execution not logged
- **Lines:** 37, 49, 61, 70
- **Priority:** MEDIUM
- **Description:** When backup scripts are executed via `bash "$SCRIPTS_DIR/db_backup.sh"`, there is no log entry indicating which script was run or its outcome.
- **Current:**
```bash
bash "$SCRIPTS_DIR/db_backup.sh"
```
- **Fix:**
```bash
log_info "Executing database backup script: $SCRIPTS_DIR/db_backup.sh"
bash "$SCRIPTS_DIR/db_backup.sh"
local exit_code=$?
log_info "Database backup script completed with exit code: $exit_code"
```

---

### Issue 10: Cleanup operations not logged
- **Lines:** 146, 170
- **Priority:** LOW
- **Description:** Successful file deletions during cleanup are echoed to console but not logged.
- **Current:**
```bash
echo "  Deleting: $remote_file ($(date -d "@$file_epoch" +"%Y-%m-%d %H:%M" 2>/dev/null))"
```
- **Fix:**
```bash
log_debug "Deleting old backup: $remote_file (file_epoch=$file_epoch, cutoff=$cutoff_time)"
echo "  Deleting: $remote_file ($(date -d "@$file_epoch" +"%Y-%m-%d %H:%M" 2>/dev/null))"
```

---

## Recommendation

Consider creating wrapper functions that handle both console output and logging:

```bash
# Example helper function
print_and_log_error() {
  local msg="$1"
  log_error "$msg"
  print_error "$msg"
}

print_and_log_warn() {
  local msg="$1"
  log_warn "$msg"
  print_warning "$msg"
}

print_and_log_info() {
  local msg="$1"
  log_info "$msg"
  print_info "$msg"
}
```

This would reduce code duplication and ensure all user-visible messages are also logged for debugging purposes.

---

## Detailed Line Reference

| Line | Current Function | Issue | Priority |
|------|-----------------|-------|----------|
| 18 | print_error | Not logged | HIGH |
| 35 | print_info | Not logged | LOW |
| 40 | print_error | Not logged | HIGH |
| 47 | print_info | Not logged | LOW |
| 52 | print_error | Not logged | HIGH |
| 59 | print_info | Not logged | LOW |
| 64 | print_error | Not logged | HIGH |
| 68 | print_info | Not logged | LOW |
| 72 | print_error | Not logged | HIGH |
| 100 | print_warning | Not logged | MEDIUM |
| 128 | print_error | Not logged | HIGH |
| 153 | print_error | Not logged | HIGH |
| 177 | print_error | Not logged | HIGH |
| 187 | print_warning | Not logged | MEDIUM |
| 189 | print_success | Not logged | LOW |

---

*Audit completed: 2026-01-05*
