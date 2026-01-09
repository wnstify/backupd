# Logging Audit Report: lib/crypto.sh

**Audit Date:** 2026-01-05
**Auditor:** Claude Code
**File:** `/home/webnestify/backupd/lib/crypto.sh`
**Lines Analyzed:** 425

---

## Summary

| Priority | Count | Description |
|----------|-------|-------------|
| HIGH     | 2     | Error messages bypassing logging API |
| MEDIUM   | 1     | Warning message bypassing logging API |
| LOW      | 5     | Status/info messages using direct echo |

**Total Issues Found:** 8

---

## HIGH Priority Issues

### Issue 1: Direct stderr error message bypasses log_error

**Line:** 160
**Current Code:**
```bash
echo "ERROR: Argon2 required but not installed" >&2
```

**Problem:** Error message is written directly to stderr with `>&2` redirect, bypassing the `log_error` function. This means:
- No stack trace is captured
- No structured log format
- No log file persistence
- No timestamp/caller info

**Recommended Fix:**
```bash
log_error "Argon2 required but not installed"
```

---

### Issue 2: Direct stderr error message bypasses log_error

**Line:** 347
**Current Code:**
```bash
echo "ERROR: Argon2 is not installed. Install with: sudo apt install argon2" >&2
```

**Problem:** Same as Issue 1 - error message bypasses logging API with direct stderr redirect.

**Recommended Fix:**
```bash
log_error "Argon2 is not installed. Install with: sudo apt install argon2"
```

---

## MEDIUM Priority Issues

### Issue 3: Warning message bypasses log_warn

**Line:** 393
**Current Code:**
```bash
echo "WARNING: $failed secrets failed to migrate"
```

**Problem:** Warning message uses direct `echo` with `WARNING:` prefix instead of the proper `log_warn` function. This means:
- No structured log format
- Inconsistent with logging standards
- May not appear in log file

**Recommended Fix:**
```bash
log_warn "$failed secrets failed to migrate"
```

---

## LOW Priority Issues

### Issue 4: Status message during migration - direct echo

**Line:** 351
**Current Code:**
```bash
echo "Migrating from $(get_crypto_name "$from_version") to $(get_crypto_name "$to_version")..."
```

**Problem:** Informational status message uses direct `echo` instead of `log_info`.

**Recommended Fix:**
```bash
log_info "Migrating from $(get_crypto_name "$from_version") to $(get_crypto_name "$to_version")..."
```

---

### Issue 5: Status message during migration - direct echo

**Line:** 357
**Current Code:**
```bash
echo "  Reading secrets with current algorithm..."
```

**Problem:** Progress message uses direct `echo`.

**Recommended Fix:**
```bash
log_info "Reading secrets with current algorithm..."
```

---

### Issue 6: Success/failure indicators with echo

**Lines:** 364, 366-367
**Current Code:**
```bash
echo "    ✓ Read $secret_name"
# ...
echo "    ⚠ Could not read $secret_name (may be empty)"
```

**Problem:** Status indicators use direct `echo`. Note: The warning-like message at line 366-367 could be upgraded to `log_warn`.

**Recommended Fix:**
```bash
log_info "Read $secret_name"
# For the warning case:
log_warn "Could not read $secret_name (may be empty)"
```

---

### Issue 7: Status messages during re-encryption

**Lines:** 372, 376
**Current Code:**
```bash
echo "  Updating algorithm marker..."
# ...
echo "  Re-encrypting secrets with new algorithm..."
```

**Problem:** Progress messages use direct `echo`.

**Recommended Fix:**
```bash
log_info "Updating algorithm marker..."
# ...
log_info "Re-encrypting secrets with new algorithm..."
```

---

### Issue 8: Success/failure indicators during encryption

**Lines:** 383, 385
**Current Code:**
```bash
echo "    ✓ Encrypted $secret_name"
# ...
echo "    ✗ Failed to encrypt $secret_name"
```

**Problem:** Status indicators use direct `echo`. The failure case at line 385 should use `log_error`.

**Recommended Fix:**
```bash
log_info "Encrypted $secret_name"
# For the failure case:
log_error "Failed to encrypt $secret_name"
```

---

### Issue 9: Completion message

**Line:** 397
**Current Code:**
```bash
echo "Migration complete!"
```

**Problem:** Completion message uses direct `echo`.

**Recommended Fix:**
```bash
log_info "Migration complete!"
```

---

## Functions with Proper Logging (Positive Findings)

The following functions already use the logging API correctly:

1. **`store_secret()`** (lines 231-232): Uses `log_func_enter` and `debug_enter`
2. **`get_secret()`** (lines 254-255): Uses `log_func_enter` and `debug_enter`
3. **`get_secret()`** (line 261): Uses `log_debug` for missing secret file

---

## Patterns Not Found (Good)

The following problematic patterns were **not found** in this file:
- `error_exit` calls (not present)
- `printf` for error/warning messages (not present)
- `[WARN]` string literals (only `WARNING:` at line 393)

---

## Remediation Summary

### Quick Fix Commands

To fix the HIGH priority issues, update these lines:

```bash
# Line 160 - change from:
echo "ERROR: Argon2 required but not installed" >&2
# to:
log_error "Argon2 required but not installed"

# Line 347 - change from:
echo "ERROR: Argon2 is not installed. Install with: sudo apt install argon2" >&2
# to:
log_error "Argon2 is not installed. Install with: sudo apt install argon2"

# Line 393 - change from:
echo "WARNING: $failed secrets failed to migrate"
# to:
log_warn "$failed secrets failed to migrate"
```

### User-Facing Messages Consideration

For LOW priority issues (lines 351, 357, 364, 366-367, 372, 376, 383, 385, 397), consider whether these messages are:
1. **Interactive user feedback** - may intentionally bypass logging for cleaner output
2. **Debug/operational logs** - should use logging API

If these are meant to be user-facing progress indicators during interactive migration, they may be acceptable as direct `echo`. However, the failure indicators should still use proper logging.

---

## Verification Checklist

After remediation, verify:
- [ ] `grep -n "echo.*ERROR" lib/crypto.sh` returns no results
- [ ] `grep -n "echo.*WARNING" lib/crypto.sh` returns no results
- [ ] `grep -n ">&2" lib/crypto.sh` returns only acceptable redirects
- [ ] Test `migrate_secrets` function to ensure logging works correctly
- [ ] Verify log file captures error conditions properly

---

**End of Audit Report**
