# Logging Audit Report: lib/generators.sh

**File:** `/home/webnestify/backupd/lib/generators.sh`
**Date:** 2026-01-05
**Auditor:** Claude Code
**Lines Reviewed:** 1-2239

## Summary

This file generates standalone backup/restore/verify scripts that are written to disk and executed independently. Since these generated scripts run as standalone executables (not within the main backupd context), they **cannot** use the centralized logging library from `lib/logging.sh`. The generated scripts define their own inline logging mechanisms.

**Context Note:** The logging patterns found here are within heredoc blocks (embedded script templates). These patterns are intentional for standalone script operation, but could be standardized for consistency across all generated scripts.

---

## Issues Found

### EMBEDDED SCRIPTS (Generated Content)

The following issues are in generated script content (heredocs). These scripts run standalone and define their own logging.

---

### Issue 1: Inconsistent `[ERROR]` format in embedded crypto functions
**Line:** 66 (within `generate_embedded_crypto` heredoc)
**Priority:** MEDIUM
**Current Code:**
```bash
echo "[ERROR] Argon2 required but not installed. Run: sudo apt install argon2" >&2
```
**Context:** This is within the embedded crypto functions that get injected into all generated scripts.
**Recommendation:** This pattern is acceptable for standalone scripts, but should be consistent across all generated scripts. Consider prefixing with timestamp for debugging: `echo "[$(date '+%F %T')] [ERROR] ..."`.

---

### Issue 2: `[INFO]` message on lock contention (db_backup.sh)
**Line:** 166-167 (within `generate_db_backup_script` heredoc)
**Priority:** LOW
**Current Code:**
```bash
echo "[INFO] Another database backup is running. Exiting."
exit 0
```
**Recommendation:** Consistent with other scripts, acceptable as-is for standalone operation.

---

### Issue 3: `[ERROR]` messages in db_backup.sh
**Lines:** 201, 207, 310, 334, 358, 372, 388, 428
**Priority:** MEDIUM
**Current Code Examples:**
```bash
# Line 201
echo "[ERROR] Insufficient disk space in /tmp (${AVAIL_MB}MB available, 1000MB required)"

# Line 207
[[ -z "$PASSPHRASE" ]] && { echo "[ERROR] No passphrase found"; exit 2; }

# Line 310
echo "[ERROR] No database client found"; exit 5

# Line 334
echo "[ERROR] No databases found or cannot connect to database"

# Line 358
echo "[ERROR] All database dumps failed"

# Line 372
echo "[ERROR] Archive verification failed"

# Line 388
echo "[ERROR] Upload failed"

# Line 428
echo "  [ERROR] Failed to delete $remote_file: $delete_output"
```
**Recommendation:** These are acceptable for standalone scripts. Consider adding timestamps for easier log correlation.

---

### Issue 4: `[WARNING]` messages in db_backup.sh
**Lines:** 395, 400, 436, 445
**Priority:** LOW
**Current Code:**
```bash
# Line 395
echo "[WARNING] Checksum upload failed, but backup succeeded"

# Line 400
echo "[WARNING] Upload verification could not complete, but upload may have succeeded"

# Line 436
echo "[WARNING] Retention cleanup completed with $cleanup_errors error(s)..."

# Line 445
echo "  [WARNING] Could not calculate cutoff time, skipping cleanup"
```
**Recommendation:** Acceptable for standalone scripts.

---

### Issue 5: `[CRITICAL]` message in notification failure
**Lines:** 290-291, 928-929, 1797-1798, 2162-2163
**Priority:** MEDIUM
**Current Code:**
```bash
echo "[CRITICAL] ALL NOTIFICATION CHANNELS FAILED for: $title" >&2
```
**Recommendation:** This uses stderr redirect (`>&2`), which is appropriate for critical errors. Consider adding timestamp.

---

### Issue 6: LOG_PREFIX pattern in db_restore.sh
**Line:** 500-526 (within `generate_db_restore_script` heredoc)
**Priority:** LOW
**Current Code:**
```bash
LOG_PREFIX="[DB-RESTORE]"
echo "$LOG_PREFIX ERROR: Could not acquire lock..."
echo "$LOG_PREFIX [ERROR] Checksum mismatch! Backup may be corrupted."
```
**Recommendation:** Inconsistent format - some use `$LOG_PREFIX ERROR:` and others use `$LOG_PREFIX [ERROR]`. Standardize to one format.

---

### Issue 7: LOG_PREFIX pattern in files_backup.sh
**Lines:** 782, 843, 935-936, 999, 1062-1063, 1081, 1088, 1117, 1125, 1134
**Priority:** MEDIUM
**Current Code Examples:**
```bash
LOG_PREFIX="[FILES-BACKUP]"

# Line 843
echo "$LOG_PREFIX [ERROR] Insufficient disk space in /tmp..."

# Lines 935-936
echo "$LOG_PREFIX pigz not found"; exit 1
echo "$LOG_PREFIX tar not found"; exit 1

# Line 999
echo "$LOG_PREFIX [ERROR] No directories found matching pattern..."

# Line 1088
echo "$LOG_PREFIX [WARNING] No sites found in $WWW_DIR"

# Line 1117
echo "$LOG_PREFIX   [ERROR] Failed to delete $remote_file: $delete_output"
```
**Recommendation:** Inconsistent - some messages have `[ERROR]` tag, others don't. Standardize: all error conditions should include `[ERROR]` tag.

---

### Issue 8: LOG_PREFIX pattern in files_restore.sh
**Lines:** 1187, 1195-1196, 1349, 1365-1367, 1377, 1388-1402, 1407, 1417, 1431, 1479, 1529-1532, 1579-1581
**Priority:** MEDIUM
**Current Code Examples:**
```bash
LOG_PREFIX="[FILES-RESTORE]"

# Lines 1195-1196
echo "$LOG_PREFIX ERROR: Could not acquire lock. A backup may be running."
echo "$LOG_PREFIX Please wait for the backup to complete and try again."

# Line 1349
echo "$LOG_PREFIX   [ERROR] Download failed"

# Line 1365
echo "$LOG_PREFIX   [ERROR] Checksum mismatch!"

# Line 1377
echo "$LOG_PREFIX   [INFO] No checksum file found"

# Line 1388
echo "$LOG_PREFIX   [DEBUG] No metadata restore path..."

# Line 1401
echo "$LOG_PREFIX   [WARNING] No restore-path metadata found..."

# Line 1407
echo "$LOG_PREFIX   [ERROR] No restore path provided."
```
**Recommendation:**
- Line 1195: Uses `ERROR:` format instead of `[ERROR]` - inconsistent
- Mix of `[ERROR]`, `[WARNING]`, `[INFO]`, `[DEBUG]` tags is good but format should be consistent

---

### Issue 9: verify_backup.sh log function
**Lines:** 1712-1714
**Priority:** LOW
**Current Code:**
```bash
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}
```
**Recommendation:** This is a good pattern - includes timestamp. Other generated scripts should adopt this approach.

---

### Issue 10: `[WARNING]` without log function in verify_backup.sh
**Lines:** 1895, 1901-1902, 1953
**Priority:** LOW
**Current Code:**
```bash
log "  [WARNING] Missing checksum: $filename"
log "[WARNING] No database backups found"
log "  [WARNING] Missing checksum: $filename"
```
**Recommendation:** Uses the `log` function correctly. Acceptable.

---

### Issue 11: `[REMINDER]` tag in verify_backup.sh
**Lines:** 1977-1978, 1980-1981
**Priority:** LOW
**Current Code:**
```bash
full_verify_reminder="REMINDER: No full backup test ever performed!..."
log "[REMINDER] $full_verify_reminder"
```
**Recommendation:** Non-standard tag `[REMINDER]` - consider using `[INFO]` or `[WARN]`.

---

### Issue 12: verify_full_backup.sh log function
**Lines:** 2076-2078
**Priority:** LOW
**Current Code:**
```bash
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}
```
**Recommendation:** Good pattern, consistent with verify_backup.sh.

---

### Issue 13: `[WARNING]` in verify_full_backup.sh
**Lines:** 2196, 2203
**Priority:** LOW
**Current Code:**
```bash
log "[WARNING] No full backup test has EVER been performed!"
log "[WARNING] Last full backup test was $days_since days ago..."
```
**Recommendation:** Uses log function correctly. Acceptable.

---

## MAIN SCRIPT CONTEXT (Non-heredoc)

### Issue 14: `print_success` usage in generate_all_scripts
**Lines:** 103-104, 111-112
**Priority:** LOW
**Current Code:**
```bash
print_success "Database backup script generated"
print_success "Database restore script generated"
print_success "Files backup script generated"
print_success "Files restore script generated"
```
**Context:** These use `print_success` which is likely a UI helper, not a logging function.
**Recommendation:** If these should be logged (not just displayed), consider adding `log_info` calls alongside.

---

## Recommendations Summary

### High Priority
None - the generated scripts operate correctly for their standalone context.

### Medium Priority
1. **Standardize error format in embedded scripts**: Choose one format (`[ERROR]` or `ERROR:`) and use consistently
2. **Add timestamps to critical messages**: Especially in embedded crypto functions (line 66)
3. **Standardize LOG_PREFIX usage**: All error messages should include the severity tag

### Low Priority
1. **Adopt the `log()` function pattern**: The verify scripts have a good timestamp-included log function; consider using similar pattern in backup/restore scripts
2. **Standardize `[REMINDER]` tag**: Use `[INFO]` or `[WARN]` instead
3. **Document logging conventions**: Add a comment block at the top of generators.sh explaining the logging approach for generated scripts

---

## Format Inconsistencies Table

| Script | Error Format | Warning Format | Info Format |
|--------|-------------|----------------|-------------|
| db_backup.sh | `[ERROR]` | `[WARNING]` | `[INFO]` |
| db_restore.sh | `$LOG_PREFIX ERROR:` or `$LOG_PREFIX [ERROR]` | N/A | N/A |
| files_backup.sh | `$LOG_PREFIX [ERROR]` or just `$LOG_PREFIX` | `$LOG_PREFIX [WARNING]` | N/A |
| files_restore.sh | `$LOG_PREFIX ERROR:` or `$LOG_PREFIX [ERROR]` | `$LOG_PREFIX [WARNING]` | `$LOG_PREFIX [INFO]` |
| verify_backup.sh | `[WARNING]` via log() | `[WARNING]` via log() | Via log() |
| verify_full_backup.sh | `[WARNING]` via log() | `[WARNING]` via log() | Via log() |

---

## Conclusion

The generators.sh file creates standalone scripts that run independently of the main backupd logging infrastructure. The current approach is **functionally correct** but has **format inconsistencies** across different generated scripts.

**Key Finding:** The verify scripts (verify_backup.sh and verify_full_backup.sh) have the best logging pattern with a proper `log()` function that includes timestamps. The backup and restore scripts should adopt a similar pattern for consistency.

**No blocking issues found.** The inconsistencies are cosmetic and do not affect functionality.
