# Logging Audit Report: lib/verify.sh

**Audit Date:** 2026-01-05
**File:** `/home/webnestify/backupd/lib/verify.sh`
**Lines Reviewed:** 573

## Summary

| Severity | Count |
|----------|-------|
| HIGH     | 0     |
| MEDIUM   | 4     |
| LOW      | 13    |
| **Total**| **17**|

## Proper Logging API (from lib/logging.sh)

- `log_error "message"` - for errors (auto-logs stack trace)
- `log_warn "message"` - for warnings
- `log_info "message"` - for info
- `log_debug "message"` - for debug
- `log_trace "message"` - for trace
- `log_error_full "message" exit_code` - for critical errors with full context

## Current State Analysis

The file uses `print_error`, `print_warning`, `print_success`, and `print_info` functions from `lib/core.sh`. These functions:
- Are designed for **user-facing terminal output** (with colors/symbols)
- Do NOT write to the log file
- `print_error` writes to stderr but does NOT call `log_error`

The file also has `log_func_enter` and `debug_enter` calls at function entry points, which is good practice.

---

## Issues Found

### MEDIUM Priority Issues

#### Issue 1: Line 34
**Current Code:**
```bash
echo "Checking database backups (quick)..."
```
**Problem:** Status message bypasses logging system
**Recommended Fix:**
```bash
log_info "Checking database backups (quick)..."
echo "Checking database backups (quick)..."
```
**Note:** Keep echo for user output, add log_info for file logging

---

#### Issue 2: Line 78
**Current Code:**
```bash
echo "  Missing checksum: $filename"
```
**Problem:** Warning-level message (missing checksum) not logged
**Recommended Fix:**
```bash
log_warn "Missing checksum for backup: $filename"
echo "  Missing checksum: $filename"
```

---

#### Issue 3: Line 105
**Current Code:**
```bash
echo "Checking files backups (quick)..."
```
**Problem:** Status message bypasses logging system
**Recommended Fix:**
```bash
log_info "Checking files backups (quick)..."
echo "Checking files backups (quick)..."
```

---

#### Issue 4: Line 140
**Current Code:**
```bash
echo "  Missing checksum: $filename"
```
**Problem:** Warning-level message (missing checksum) not logged
**Recommended Fix:**
```bash
log_warn "Missing checksum for files backup: $filename"
echo "  Missing checksum: $filename"
```

---

### LOW Priority Issues

#### Issue 5: Line 99 (print_error without log_error)
**Current Code:**
```bash
print_error "Database: $db_details"
```
**Problem:** `print_error` only outputs to terminal, does not log to file
**Recommended Fix:**
```bash
log_error "Database verification failed: $db_details"
print_error "Database: $db_details"
```

---

#### Issue 6: Line 161 (print_error without log_error)
**Current Code:**
```bash
print_error "Files: $files_details"
```
**Problem:** `print_error` only outputs to terminal, does not log to file
**Recommended Fix:**
```bash
log_error "Files verification failed: $files_details"
print_error "Files: $files_details"
```

---

#### Issue 7: Line 350
**Current Code:**
```bash
echo "Fetching latest database backup..."
```
**Problem:** Informational message not logged
**Recommended Fix:**
```bash
log_info "Fetching latest database backup"
echo "Fetching latest database backup..."
```

---

#### Issue 8: Line 355-357
**Current Code:**
```bash
print_error "No database backups found"
```
**Problem:** Error not logged to file
**Recommended Fix:**
```bash
log_error "No database backups found in $rclone_remote:$rclone_db_path"
print_error "No database backups found"
```

---

#### Issue 9: Line 362-366
**Current Code:**
```bash
echo "Downloading backup..."
# ...
print_error "Download failed"
```
**Problem:** Download start/failure messages not logged
**Recommended Fix:**
```bash
log_info "Downloading backup: $latest_db"
echo "Downloading backup..."
# ...
log_error "Failed to download backup: $latest_db"
print_error "Download failed"
```

---

#### Issue 10: Line 382
**Current Code:**
```bash
print_error "Checksum mismatch!"
```
**Problem:** Critical verification failure not logged
**Recommended Fix:**
```bash
log_error "Checksum mismatch for $latest_db: expected=$stored_checksum, got=$calculated_checksum"
print_error "Checksum mismatch!"
```

---

#### Issue 11: Line 413
**Current Code:**
```bash
print_error "Decryption or archive verification failed"
```
**Problem:** Decryption failure not logged
**Recommended Fix:**
```bash
log_error "Decryption or archive verification failed for $latest_db"
print_error "Decryption or archive verification failed"
```

---

#### Issue 12: Line 431
**Current Code:**
```bash
echo "Fetching latest files backup..."
```
**Problem:** Informational message not logged
**Recommended Fix:**
```bash
log_info "Fetching latest files backup"
echo "Fetching latest files backup..."
```

---

#### Issue 13: Line 436-438
**Current Code:**
```bash
print_error "No files backups found"
```
**Problem:** Error not logged
**Recommended Fix:**
```bash
log_error "No files backups found in $rclone_remote:$rclone_files_path"
print_error "No files backups found"
```

---

#### Issue 14: Line 444-446
**Current Code:**
```bash
print_error "Download failed"
```
**Problem:** Download failure not logged
**Recommended Fix:**
```bash
log_error "Failed to download files backup: $latest_files"
print_error "Download failed"
```

---

#### Issue 15: Line 463-467
**Current Code:**
```bash
print_error "Checksum mismatch!"
```
**Problem:** Checksum mismatch not logged
**Recommended Fix:**
```bash
log_error "Checksum mismatch for $latest_files: expected=$stored_checksum, got=$calculated_checksum"
print_error "Checksum mismatch!"
```

---

#### Issue 16: Line 491
**Current Code:**
```bash
print_error "Archive verification failed - file may be corrupted"
```
**Problem:** Archive corruption not logged
**Recommended Fix:**
```bash
log_error "Archive verification failed for $latest_files - file may be corrupted"
print_error "Archive verification failed - file may be corrupted"
```

---

#### Issue 17: Lines 511, 519
**Current Code:**
```bash
print_error "Database: FAILED - $db_details"
print_error "Files: FAILED - $files_details"
```
**Problem:** Summary failures not logged
**Recommended Fix:**
```bash
log_error "Verification summary - Database: FAILED - $db_details"
print_error "Database: FAILED - $db_details"
# ...
log_error "Verification summary - Files: FAILED - $files_details"
print_error "Files: FAILED - $files_details"
```

---

## Patterns That Are Correct

The following patterns are correctly implemented:

1. **Line 15-16:** `log_func_enter` and `debug_enter` for function entry tracking
2. **Line 270-271:** `log_func_enter` and `debug_enter` in `verify_backup_integrity()`
3. **Lines 96-97, 156-158:** `print_success` and `print_warning` for user feedback (these are fine for terminal output, though adding corresponding log_* calls would be beneficial)

---

## Recommendations

### High-Level Recommendations

1. **Add log_error before every print_error call** - Ensures errors are captured in log files for debugging
2. **Add log_warn before every print_warning call** - Ensures warnings are logged
3. **Add log_info for status messages** - Key operations like "Downloading", "Verifying" should be logged
4. **Consider creating wrapper functions** - A `report_error()` that calls both `log_error` and `print_error`

### Example Wrapper Pattern

```bash
# Add to lib/core.sh or lib/logging.sh
report_error() {
  log_error "$1"
  print_error "$1"
}

report_warn() {
  log_warn "$1"
  print_warning "$1"
}

report_success() {
  log_info "$1"
  print_success "$1"
}
```

This would allow single-call replacements throughout the codebase.

---

## No Issues Found (Positive Findings)

- No direct `echo "[ERROR]"` or `echo "Error:"` patterns found
- No direct `error_exit` calls that bypass logging
- No `>&2` redirects that bypass the logging system for error messages
- Proper function entry instrumentation with `log_func_enter`

---

## Conclusion

The file has **17 logging gaps** where terminal output is not accompanied by structured logging. The majority are LOW priority since `print_*` functions do provide user feedback, but errors and warnings are not being captured in the log file for post-mortem analysis.

**Priority for fixes:**
1. First: Add `log_error` before all `print_error` calls (affects debugging capability)
2. Second: Add `log_warn` for warning conditions (missing checksums)
3. Third: Add `log_info` for status messages (nice to have for tracing)
