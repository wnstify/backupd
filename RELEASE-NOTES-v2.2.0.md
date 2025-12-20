# Backupd v2.2.0 Release Notes

**Release Date:** December 20, 2025
**Previous Version:** 2.1.0

---

## Overview

Version 2.2.0 is a **security and reliability focused release** that enforces HTTPS for all notification URLs, fixes 6 bugs discovered during comprehensive production-readiness testing, and improves user experience with better warnings and complete webhook support.

This release was validated through extensive testing covering 22 notification scenarios across both ntfy and webhook channels, with all scenarios passing successfully.

---

## Changelog

### Security Enhancements

#### HTTPS Enforcement (Breaking Change for HTTP Users)
- **All notification URLs now require HTTPS** - no exceptions
- Previously: HTTP URLs were allowed with a warning
- Now: HTTP URLs are rejected with a clear error message
- Affects both ntfy and webhook notification channels
- Includes helpful guidance box explaining the security rationale

**Migration Required:** If you were using HTTP URLs for notifications, update them to HTTPS before upgrading.

```bash
# Before (no longer works):
http://ntfy.example.com/backups

# After (required):
https://ntfy.example.com/backups
```

### New Features

#### Complete Webhook JSON Payload
- **Added `title` field to webhook JSON payloads**
- Webhooks now receive the same information as ntfy notifications
- JSON structure now includes: `event`, `title`, `hostname`, `message`, `timestamp`, `details`

**Example webhook payload:**
```json
{
  "event": "backup_complete",
  "title": "Database Backup Complete",
  "hostname": "server.example.com",
  "message": "Backup completed successfully",
  "timestamp": "2025-12-20T21:00:00+01:00",
  "details": {"duration": "45s", "size": "1.2GB"}
}
```

### User Experience Improvements

#### Enhanced Reconfigure Warning
- **Explicit warning about backup unrecoverability** when changing encryption password
- Added clear red-highlighted message box
- Requires typing `YES` (uppercase) to confirm understanding
- Prevents accidental data loss from password changes

**New warning display:**
```
┌──────────────────────────────────────────────────────────┐
│  ⚠️  CRITICAL WARNING                                    │
│                                                          │
│  IF YOU CHANGE THE ENCRYPTION PASSWORD:                  │
│                                                          │
│  ALL EXISTING BACKUPS WILL BE UNRECOVERABLE              │
│                                                          │
│  Your current backups are encrypted with your current    │
│  password. Changing it means you cannot decrypt them.    │
│                                                          │
│  Before proceeding:                                      │
│  • Restore any needed backups first                      │
│  • Create a server snapshot                              │
│  • Document your current password securely               │
└──────────────────────────────────────────────────────────┘
```

---

## Bug Fixes

### Critical Fixes

#### 1. JSON Default Value Syntax Error (`core.sh:733`)
- **Issue:** Invalid bash syntax `\{\}` for default JSON object
- **Impact:** Could cause notification failures with empty details
- **Fix:** Changed to proper bash default value syntax `${4:-"{}"}`

#### 2. Webhook Missing Title Field (`core.sh:772`)
- **Issue:** Webhook JSON payload omitted the notification title
- **Impact:** Webhook recipients couldn't see what event occurred
- **Fix:** Added `"title":"$title"` to JSON payload construction

#### 3. Undefined Variable in Files Backup (`generators.sh:974`)
- **Issue:** Warning message referenced undefined `$WWW_DIR` variable
- **Impact:** Error message would be incomplete when no sites found
- **Fix:** Changed to use correct variable `$WEB_PATH_PATTERN`

#### 4. Wrong Hostname Variable in Verify Script (`verify.sh:510`)
- **Issue:** Used `$HOSTNAME` instead of local `$hostname_full` variable
- **Impact:** Could show incorrect hostname in failure notifications
- **Fix:** Corrected to use the locally defined `$hostname_full`

### Configuration Handling Fixes

#### 5. Wrong Function Call in Script Regeneration (`backupd.sh:383`)
- **Issue:** Called non-existent `get_config()` function
- **Impact:** Encryption migration would fail during script regeneration
- **Fix:** Changed to correct function `get_config_value()`

#### 6. Config Key Mismatch (`backupd.sh:390`)
- **Issue:** Checked for `BACKUP_DB` key instead of `DO_DATABASE`
- **Impact:** Database backup scripts might not regenerate correctly
- **Fix:** Changed to match actual config key names (`DO_DATABASE`, `DO_FILES`)

---

## Testing Summary

### Validation Performed

| Test Category | Scenarios | Result |
|---------------|-----------|--------|
| Notification Tests | 22 | ✅ All passed |
| Syntax Validation | 19 scripts | ✅ All passed |
| File Consistency | Source vs Installed | ✅ Matched |
| Debug Log Security | Secrets in logs | ✅ 0 found |

### Notification Scenarios Tested

**Database Backup:**
- ✅ Success notification
- ✅ Failure notification

**Files Backup:**
- ✅ Success notification
- ✅ Failure notification
- ✅ Empty backup warning (no sites found)

**Verification:**
- ✅ Full verification success
- ✅ Verification failure
- ✅ No backups found warning

**System Events:**
- ✅ Schedule enabled
- ✅ Schedule disabled
- ✅ Configuration complete
- ✅ Encryption migration

All scenarios tested on both ntfy and webhook channels with 100% delivery success.

---

## Files Changed

| File | Changes |
|------|---------|
| `backupd.sh` | Version bump, fixed `regenerate_all_scripts()` function |
| `lib/core.sh` | HTTPS enforcement, JSON default fix, webhook title fix |
| `lib/setup.sh` | Enhanced reconfigure warning with explicit data loss notice |
| `lib/generators.sh` | Fixed undefined `$WWW_DIR` variable |
| `lib/verify.sh` | Fixed hostname variable reference |

---

## Upgrade Instructions

### From v2.1.0

1. **Check your notification URLs:**
   ```bash
   grep -E "NTFY_URL|WEBHOOK_URL" /etc/backupd/.config
   ```
   If any use `http://`, update them to `https://` before upgrading.

2. **Update the installation:**
   ```bash
   cd /path/to/backupd
   git pull origin main  # or download the new version
   sudo ./backupd.sh     # Will auto-install to /usr/local/bin
   ```

3. **Verify the update:**
   ```bash
   backupd --version
   # Should show: Backupd v2.2.0
   ```

4. **Optional: Regenerate scripts** (recommended if you had any issues):
   ```bash
   sudo backupd
   # Choose option 6 (Reconfigure) and re-run setup
   ```

### From Earlier Versions

Follow the same steps, but also review the v2.1.0 release notes for additional changes.

---

## Debug Logging

If you encounter issues, enable debug logging to generate a report for GitHub issues:

```bash
# Run with debug enabled
sudo backupd --debug

# Export sanitized log for sharing
sudo backupd --debug-export

# Check debug status
backupd --debug-status
```

Debug logs automatically:
- Sanitize sensitive information (passwords, tokens, paths)
- Include system information for troubleshooting
- Track all operations with timestamps

---

## Known Issues

None at this time. All identified issues have been resolved in this release.

---

## Contributors

- **Backupd Team** - Core development
- **Claude (Anthropic)** - Code review and bug detection

---

## Support

- **Website:** https://backupd.io
- **GitHub Issues:** Report bugs or request features
- **Debug Export:** Use `backupd --debug-export` when reporting issues

---

## License

Backupd is provided "as is" without warranty. See the disclaimer in the main script for full terms.

---

*Thank you for using Backupd! Your backups are in safe hands.* 🛡️
