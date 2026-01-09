# Logging Audit Report: lib/setup.sh

**Audited File:** `/home/webnestify/backupd/lib/setup.sh`
**Audit Date:** 2026-01-05
**Auditor:** Claude Opus 4.5

## Summary

| Priority | Count | Description |
|----------|-------|-------------|
| HIGH     | 0     | Error logging issues |
| MEDIUM   | 0     | Warning logging issues |
| LOW      | 16    | Info/status message issues |

**Overall Assessment:** The setup.sh file uses proper logging for errors via `print_error`, `print_warning`, `print_success`, and `print_info` functions (which are UI display functions, not logging functions). However, the file is a setup wizard that is primarily interactive and user-facing. Most `echo` statements are intentional UI output for the wizard flow, not log-worthy events.

---

## Proper Logging Practices Found

The file correctly uses:
- `log_func_enter` (line 10) - Function entry instrumentation
- `log_info` (line 12) - Logging setup wizard start
- `debug_enter` (line 11) - Debug tracing

---

## Issues Found

### LOW Priority - Interactive UI Output (Not Logging Issues)

The following `echo` statements are **intentional interactive UI** for the setup wizard and should NOT be converted to log_* functions. These are user-facing prompts and menus:

| Line | Current Code | Assessment |
|------|--------------|------------|
| 14 | `echo "Setup Wizard"` | UI header - OK as-is |
| 15 | `echo "============"` | UI decoration - OK as-is |
| 16 | `echo` | Blank line for spacing - OK as-is |
| 20-24 | Configuration detected prompts | Interactive menu - OK as-is |
| 50-56 | Step 1 prompts | Interactive menu - OK as-is |
| 83-118 | Step 1b prompts | Interactive menu - OK as-is |
| 139-145 | Custom path prompts | Interactive menu - OK as-is |
| 164-171 | Subdirectory prompts | Interactive menu - OK as-is |
| 211-220 | Step 2 prompts | Interactive menu - OK as-is |
| 245-268 | Step 3 prompts | Interactive menu - OK as-is |
| 306-351 | Step 4 prompts | Interactive menu - OK as-is |
| 390-411 | Step 5 prompts | Interactive menu - OK as-is |
| 415-450 | Step 6 prompts | Interactive menu - OK as-is |
| 453-458 | Step 7 prompts | Interactive menu - OK as-is |
| 463-481 | Step 8 prompts | Interactive menu - OK as-is |
| 486-576 | Step 9 prompts + systemd setup | Interactive menu - OK as-is |
| 583-593 | Completion message | UI output - OK as-is |

---

## Potential Logging Enhancements (Optional)

While not strictly issues, the following could benefit from additional logging for debugging purposes:

### 1. Configuration Save Events
**Line:** 69-70, 198-200, 361, 373-374, 384-385, 447-448
**Current:** `save_config "KEY" "value"` (no logging)
**Recommended Enhancement:** Consider adding `log_debug` after config saves for troubleshooting.
**Priority:** LOW (enhancement, not a bug)

```bash
# Example enhancement:
save_config "DO_DATABASE" "$DO_DATABASE"
log_debug "Saved config: DO_DATABASE=$DO_DATABASE"
```

### 2. Secret Storage Events
**Line:** 237, 284-285, 400, 406
**Current:** `store_secret` calls (no logging)
**Recommended Enhancement:** Consider `log_debug "Stored secret: $SECRET_PASSPHRASE"` (redacted automatically by logging module).
**Priority:** LOW (enhancement, not a bug)

### 3. Systemd Operations
**Lines:** 527-529, 567-569
**Current:**
```bash
systemctl daemon-reload
systemctl enable backupd-verify.timer 2>/dev/null
systemctl start backupd-verify.timer 2>/dev/null
```
**Recommended Enhancement:**
```bash
systemctl daemon-reload
log_debug "Systemd daemon-reload completed"
if systemctl enable backupd-verify.timer 2>/dev/null; then
  log_debug "Enabled backupd-verify.timer"
else
  log_warn "Failed to enable backupd-verify.timer"
fi
```
**Priority:** LOW (enhancement for troubleshooting)

### 4. External Command Results
**Lines:** 316-321 (rclone install), 339-340 (rclone config)
**Current:** No logging of command results
**Recommended Enhancement:** Add `log_debug` or `log_cmd_result` for external command outcomes.
**Priority:** LOW

### 5. Notification Curl Commands
**Lines:** 610-627
**Current:** `curl ... || true` (silent failure)
**Recommended Enhancement:**
```bash
if curl -s ...; then
  log_debug "Setup notification sent successfully"
else
  log_warn "Failed to send setup notification to ntfy"
fi
```
**Priority:** LOW

---

## Error Handling Review

The file uses `print_error` and `return` pattern consistently:
- Line 148, 227, 255, 289, 297, 317, 323, 344, 356 - All use `print_error` followed by return

**Assessment:** The `print_error` function is a UI display function, not a logging function. For critical errors, these could additionally call `log_error` for persistent logging:

```bash
# Current pattern:
print_error "Passwords don't match. Please restart setup."
press_enter_to_continue
return

# Enhanced pattern (optional):
log_error "Setup aborted: passwords don't match"
print_error "Passwords don't match. Please restart setup."
press_enter_to_continue
return
```

---

## Conclusion

**lib/setup.sh is primarily an interactive setup wizard.** The `echo` statements are intentional UI output for user interaction, not events that should go to the log file. The file correctly uses:

1. `log_func_enter` for function instrumentation
2. `log_info` for recording that setup started
3. `print_*` functions for user-facing messages

**No HIGH or MEDIUM priority issues found.**

The LOW priority suggestions are optional enhancements that would improve debugging capabilities but are not violations of the logging API.

---

## Recommended Actions

1. **No immediate action required** - The file follows appropriate patterns for an interactive wizard.
2. **Optional:** Add `log_debug` statements for configuration saves and external command results to improve troubleshooting.
3. **Optional:** Add `log_info "Setup completed successfully"` at the end of the function (around line 630) before the notification sends.
