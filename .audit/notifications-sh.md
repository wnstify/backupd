# Logging Audit Report: lib/notifications.sh

**File:** `/home/webnestify/backupd/lib/notifications.sh`
**Audit Date:** 2026-01-05
**Auditor:** Claude Code

---

## Summary

| Severity | Count |
|----------|-------|
| HIGH     | 2     |
| MEDIUM   | 4     |
| LOW      | 8     |
| **Total**| **14**|

---

## Issues Found

### HIGH Priority (Errors bypassing logging)

#### Issue #1: Line 309 - Direct ANSI echo for FAILED status
**Current Code:**
```bash
echo -e "${RED}FAILED (HTTP $http_code)${NC}"
```

**Problem:** Notification test failure is outputted directly without logging. This is an error condition that should be logged for troubleshooting.

**Recommended Fix:**
```bash
log_warn "ntfy notification test failed (HTTP $http_code)"
echo -e "${RED}FAILED (HTTP $http_code)${NC}"
```

---

#### Issue #2: Line 338 - Direct ANSI echo for webhook FAILED status
**Current Code:**
```bash
echo -e "${RED}FAILED (HTTP $http_code)${NC}"
```

**Problem:** Webhook test failure is outputted directly without logging. This is an error condition that should be logged.

**Recommended Fix:**
```bash
log_warn "Webhook notification test failed (HTTP $http_code)"
echo -e "${RED}FAILED (HTTP $http_code)${NC}"
```

---

### MEDIUM Priority (Warnings/important states not logged)

#### Issue #3: Line 39 - print_error without logging
**Current Code:**
```bash
*) print_error "Invalid option" ; sleep 1 ;;
```

**Problem:** User input error uses `print_error` but does not log. While this is a user error, it could be useful for debugging user interaction issues.

**Recommended Fix:**
```bash
*) log_debug "Invalid notification menu option: $notif_choice"; print_error "Invalid option" ; sleep 1 ;;
```

---

#### Issue #4: Lines 110, 134, 182, 207, 348, 425 - print_error without log_error
**Current Code:**
```bash
# Line 110
print_error "Secure storage not initialized. Run setup first."

# Line 134
print_error "Invalid URL. Must start with https://"

# Line 182
print_error "Secure storage not initialized. Run setup first."

# Line 207
print_error "Invalid URL. Must start with https://"

# Line 348
print_error "All notification tests failed. Check your configuration."

# Line 425
print_error "Secure storage not initialized."
```

**Problem:** These error conditions use `print_error` for user display but do not call `log_error` for persistent logging. Errors should be logged for troubleshooting.

**Recommended Fix:** Add corresponding `log_error` calls before each `print_error`:
```bash
# Line 110
log_error "Secure storage not initialized during ntfy configuration"
print_error "Secure storage not initialized. Run setup first."

# Line 134
log_error "Invalid ntfy URL provided: URL must start with https://"
print_error "Invalid URL. Must start with https://"

# Line 182
log_error "Secure storage not initialized during webhook configuration"
print_error "Secure storage not initialized. Run setup first."

# Line 207
log_error "Invalid webhook URL provided: URL must start with https://"
print_error "Invalid URL. Must start with https://"

# Line 348
log_error "All notification channel tests failed"
print_error "All notification tests failed. Check your configuration."

# Line 425
log_error "Secure storage not initialized during disable operation"
print_error "Secure storage not initialized."
```

---

#### Issue #5: Line 258 - print_error without log_error
**Current Code:**
```bash
print_error "Secure storage not initialized. Run setup first."
```

**Problem:** Error in `test_notifications` function not logged.

**Recommended Fix:**
```bash
log_error "Secure storage not initialized during notification test"
print_error "Secure storage not initialized. Run setup first."
```

---

#### Issue #6: Line 450 - print_warning for important state change
**Current Code:**
```bash
print_warning "All notifications disabled"
```

**Problem:** Disabling all notifications is a significant configuration change that should be logged for audit purposes.

**Recommended Fix:**
```bash
log_warn "All notifications have been disabled by user"
print_warning "All notifications disabled"
```

---

### LOW Priority (Info/status messages)

#### Issue #7: Lines 14, 56 - Echo for menu headers
**Current Code:**
```bash
echo "Notifications"
echo "============="
# ...
echo "Current Configuration:"
```

**Problem:** Menu UI output - not a logging issue, but could use `log_trace` for debugging menu navigation.

**Recommended Fix:** Optional - add `log_trace "Displaying notifications menu"` at start of `manage_notifications`.

---

#### Issue #8: Line 52 - print_warning without log_warn
**Current Code:**
```bash
print_warning "Notifications: NOT CONFIGURED (run setup first)"
```

**Problem:** Warning state not logged.

**Recommended Fix:**
```bash
log_warn "Notifications not configured - secrets directory missing"
print_warning "Notifications: NOT CONFIGURED (run setup first)"
```

---

#### Issue #9: Lines 70, 84 - Direct echo with YELLOW ANSI
**Current Code:**
```bash
echo -e "  ${YELLOW}ntfy: Not configured${NC}"
# ...
echo -e "  ${YELLOW}Webhook: Not configured${NC}"
```

**Problem:** Status information using direct echo with color codes. These are informational displays, not log-worthy events.

**Recommended Fix:** No action needed - these are UI status displays, not log events.

---

#### Issue #10: Line 93 - print_warning without log_warn
**Current Code:**
```bash
print_warning "Failure log: $fail_count entries"
```

**Problem:** Notification failure count warning not logged.

**Recommended Fix:**
```bash
log_warn "Notification failure log has $fail_count entries"
print_warning "Failure log: $fail_count entries"
```

---

#### Issue #11: Line 270 - print_warning without log_warn
**Current Code:**
```bash
print_warning "No notification channels configured."
```

**Problem:** Warning state in test function not logged.

**Recommended Fix:**
```bash
log_warn "No notification channels configured for testing"
print_warning "No notification channels configured."
```

---

#### Issue #12: Lines 306, 335 - OK status not logged
**Current Code:**
```bash
echo -e "${GREEN}OK (HTTP $http_code)${NC}"
```

**Problem:** Successful notification tests not logged. Could be useful for audit trail.

**Recommended Fix:**
```bash
log_info "ntfy notification test succeeded (HTTP $http_code)"
echo -e "${GREEN}OK (HTTP $http_code)${NC}"

# And for webhook (line 335):
log_info "Webhook notification test succeeded (HTTP $http_code)"
echo -e "${GREEN}OK (HTTP $http_code)${NC}"
```

---

#### Issue #13: Line 430 - Direct echo with YELLOW for WARNING
**Current Code:**
```bash
echo -e "${YELLOW}WARNING: This will remove all notification configuration.${NC}"
```

**Problem:** User warning using direct ANSI echo. This is a user prompt, not a log event.

**Recommended Fix:** No action needed - this is a UI confirmation prompt, not a loggable event.

---

#### Issue #14: Lines 481-482 - Suppressed stderr with 2>/dev/null
**Current Code:**
```bash
generate_all_scripts "$secrets_dir" ... 2>/dev/null
```

**Problem:** Errors from script regeneration are silently suppressed. Any failures should be logged.

**Recommended Fix:**
```bash
if ! generate_all_scripts "$secrets_dir" "$do_database" "$do_files" "$rclone_remote" \
    "$rclone_db_path" "$rclone_files_path" "${retention_minutes:-43200}" \
    "${web_path_pattern:-/var/www/*}" "${webroot_subdir:-.}" 2>&1; then
  log_warn "Silent script regeneration may have encountered issues"
fi
```

---

## Good Practices Found

The file correctly uses the logging API in several places:

1. **Line 10:** `log_func_enter` - Proper function entry instrumentation
2. **Line 246:** `log_func_enter` - Proper function entry instrumentation
3. **Line 248:** `log_info "Testing notifications"` - Proper info logging

---

## Recommendations Summary

1. **Immediate (HIGH):** Add `log_warn` calls for notification test failures (lines 309, 338)

2. **Important (MEDIUM):** Add `log_error` before all `print_error` calls (6 locations)

3. **Nice-to-have (LOW):** Add `log_info` or `log_debug` for successful operations and `log_warn` for warning states

4. **Pattern to follow:** Before `print_error`, always call `log_error`; before `print_warning`, always call `log_warn`

---

## Missing Function Instrumentation

The following functions lack `log_func_enter` calls:

- `show_notification_status_brief()` - Line 46
- `configure_ntfy()` - Line 100
- `configure_webhook()` - Line 172
- `view_notification_failures()` - Line 356
- `disable_all_notifications()` - Line 415
- `regenerate_scripts_silent()` - Line 463

**Recommended:** Add `log_func_enter` at the start of each function for trace-level debugging.
