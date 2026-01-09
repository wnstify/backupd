# Logging Audit Report: lib/updater.sh

**Audited:** 2026-01-05
**Auditor:** Claude Opus 4.5
**File:** `/home/webnestify/backupd/lib/updater.sh`
**Lines:** 653

## Summary

The `updater.sh` module handles auto-update functionality with GitHub releases. The file uses `print_*` functions (UI/display) extensively but lacks corresponding `log_*` calls for proper structured logging. This means errors and warnings are displayed to users but NOT recorded to log files for debugging.

**Critical Finding:** This file does NOT use any `log_*` functions from `lib/logging.sh`. All error conditions use only `print_error` which writes to stderr but does not create log entries with stack traces.

## Issues Found

### HIGH Priority (Errors not logged)

| Line | Current Code | Issue | Recommended Fix |
|------|--------------|-------|-----------------|
| 182-183 | `print_error "Failed to download update"` | Error displayed but not logged | Add `log_error "Failed to download update from $release_url"` before print_error |
| 188-189 | `print_error "Downloaded file is empty"` | Error displayed but not logged | Add `log_error "Downloaded update file is empty: ${temp_dir}/update.tar.gz"` |
| 197-199 | `print_error "Failed to download checksum file"` | Error not logged with context | Add `log_error "Failed to download checksum from $checksum_url"` |
| 204-205 | `print_error "Checksum file is empty or invalid"` | Error not logged | Add `log_error "Checksum file empty or invalid: $checksum_file"` |
| 215-217 | `print_error "Checksum for backupd-v${version}.tar.gz not found in SHA256SUMS"` | Security-critical error not logged | Add `log_error "Checksum not found for backupd-v${version}.tar.gz - possible tampered release"` |
| 224-228 | `print_error "Checksum verification failed!"` (multiple lines) | Security-critical verification failure not logged | Add `log_error_full "Checksum verification failed: expected=$expected_checksum actual=$actual_checksum" 1` |
| 253-254 | `print_error "No backup found to restore"` | Rollback failure not logged | Add `log_error "Rollback failed: no backup found at $backup_dir"` |
| 279 | `print_error "Failed to extract update"` | Extraction failure not logged | Add `log_error "Failed to extract update archive: ${temp_dir}/update.tar.gz"` |
| 291-292 | `print_error "Invalid update archive structure"` | Archive structure error not logged | Add `log_error "Invalid archive structure: backupd.sh not found in extracted update"` |
| 315-317 | `print_error "Version mismatch after update"` | Version mismatch not logged | Add `log_error "Version mismatch: expected=$expected_version got=$new_version"` |
| 322-323 | `print_error "Syntax error in updated script"` | Syntax error not logged | Add `log_error "Syntax error in updated backupd.sh - rolling back"` |
| 381-382 | `print_error "Failed to check for updates..."` | Network failure not logged | Add `log_warn "Failed to check for updates: no response from GitHub API"` |
| 431 | `print_error "Update failed, rolling back..."` | Update failure not logged | Add `log_error "Update to $latest_version failed, initiating rollback"` |
| 440 | `print_error "Update verification failed, rolling back..."` | Verification failure not logged | Add `log_error "Update verification failed for $latest_version, initiating rollback"` |
| 480 | `print_error "Failed to check for updates."` | Verbose check failure not logged | Add `log_warn "Failed to check for updates in verbose mode"` |
| 584-585 | `print_error "Failed to download ${main_script}"` | Dev update download failure not logged | Add `log_error "Failed to download $main_script from branch $branch"` |
| 595-596 | `print_error "Failed to download ${lib_file}"` | Lib file download failure not logged | Add `log_error "Failed to download $lib_file from branch $branch"` |
| 623-624 | `print_error "Syntax error in updated script, rolling back..."` | Dev update syntax error not logged | Add `log_error "Syntax error in dev-updated backupd.sh from branch $branch"` |

### MEDIUM Priority (Warnings not logged)

| Line | Current Code | Issue | Recommended Fix |
|------|--------------|-------|-----------------|
| 355 | `print_warning "This installation is from the '${installed_branch}' branch."` | Branch mismatch warning not logged | Add `log_warn "Update attempted on non-main branch installation: $installed_branch"` |
| 535-536 | `print_warning "This updates from the '${branch}' branch directly."` | Dev update warning not logged | Add `log_warn "Dev update initiated from branch: $branch"` |

### LOW Priority (Info/Debug not logged)

| Line | Current Code | Issue | Recommended Fix |
|------|--------------|-------|-----------------|
| 176 | `print_info "Downloading version ${version}..."` | Download start not logged | Add `log_info "Downloading update version $version from $release_url"` |
| 194 | `print_info "Downloading checksum..."` | Checksum download not logged | Add `log_debug "Downloading checksum from $checksum_url"` |
| 208 | `print_info "Verifying checksum..."` | Verification start not logged | Add `log_debug "Verifying checksum for update archive"` |
| 245 | `print_success "Current version backed up..."` | Backup success not logged | Add `log_info "Backed up current version to $backup_dir"` |
| 257 | `print_info "Rolling back to previous version..."` | Rollback start not logged | Add `log_info "Initiating rollback from $backup_dir"` |
| 265 | `print_success "Rollback complete"` | Rollback success not logged | Add `log_info "Rollback completed successfully"` |
| 272 | `print_info "Applying update..."` | Update application not logged | Add `log_info "Applying update from $temp_dir"` |
| 372 | `print_info "Current version: ${VERSION}"` | Version info not logged | Add `log_debug "Current version: $VERSION"` |
| 375 | `print_info "Checking for updates..."` | Update check not logged | Add `log_debug "Checking GitHub for latest version"` |
| 386 | `print_info "Latest version: ${latest_version}"` | Latest version not logged | Add `log_debug "Latest version from GitHub: $latest_version"` |
| 454 | `print_success "Update complete! Version: ${latest_version}"` | Update success not logged | Add `log_info "Update completed successfully to version $latest_version"` |
| 456 | `print_info "Please restart the tool..."` | Restart reminder not logged | Add `log_info "Restart required for new version"` |
| 582 | `print_info "Downloading ${main_script}..."` | Download start not logged | Add `log_debug "Downloading $main_script from branch $branch"` |
| 593 | `print_info "Downloading ${lib_file}..."` | Lib file download not logged | Add `log_debug "Downloading $lib_file from branch $branch"` |
| 602 | `print_success "All files downloaded"` | Download success not logged | Add `log_info "All dev update files downloaded from branch $branch"` |
| 609 | `print_info "Applying update..."` | Dev update application not logged | Add `log_info "Applying dev update from branch $branch"` |
| 641-643 | `print_success "Development update complete!"` | Dev update success not logged | Add `log_info "Dev update completed: branch=$branch version=$new_version"` |

## Patterns NOT Found (Good)

- No `echo "[ERROR]"` patterns
- No `echo "Error:"` patterns
- No `error_exit` calls
- No `printf` for error messages
- No direct `>&2` bypasses that should use logging
- No `[WARN]` or `[WARNING]` strings

## Structural Issues

### 1. No logging initialization
The file does not call `log_init` or source `logging.sh`. It relies on the main `backupd.sh` to have already sourced it.

**Recommendation:** Ensure `logging.sh` is sourced before `updater.sh` in the main script.

### 2. Silent failures suppressed
Multiple locations use `2>/dev/null` to suppress errors silently:

| Line | Code | Issue |
|------|------|-------|
| 69 | `curl ... 2>/dev/null` | API fetch errors silently discarded |
| 98 | `find ... 2>/dev/null` | Find errors silently discarded |
| 112 | `cat "$UPDATE_CHECK_FILE" 2>/dev/null` | Read errors silently discarded |
| 133 | `echo "$latest" > "$UPDATE_CHECK_FILE" 2>/dev/null` | Write errors silently discarded |
| 196 | `curl ... 2>/dev/null` | Checksum download errors silently discarded |
| 212 | `grep ... 2>/dev/null` | Grep errors silently discarded |
| 312 | `grep ... 2>/dev/null` | Version extraction errors silently discarded |
| 321 | `bash -n ... 2>/dev/null` | Syntax check errors silently discarded |
| 335 | `cat "$branch_file" 2>/dev/null` | Branch file read errors silently discarded |
| 514 | `curl ... 2>/dev/null` | Branch download errors silently discarded |
| 622 | `bash -n ... 2>/dev/null` | Syntax check errors silently discarded |
| 638 | `grep ... 2>/dev/null` | Version extraction errors silently discarded |

**Recommendation:** For critical operations (downloads, checksums), capture stderr and log it:
```bash
local stderr_output
stderr_output=$(curl ... 2>&1) || {
    log_error "Curl failed: $stderr_output"
    return 1
}
```

### 3. Security-critical operations not logged
The checksum verification (lines 210-232) is security-critical but failures are only displayed, not logged. This makes security incident investigation difficult.

**Recommendation:** Add `log_error_full` for all checksum/verification failures with full context.

## Recommended Implementation Pattern

For each `print_error` call, add a corresponding `log_error` call BEFORE it:

```bash
# Current (line 182-183):
if ! curl -sfL ...; then
    print_error "Failed to download update"
    return 1
fi

# Recommended:
if ! curl -sfL ...; then
    log_error "Failed to download update from $release_url"
    print_error "Failed to download update"
    return 1
fi
```

For security-critical failures, use `log_error_full`:

```bash
# Current (line 224-228):
if [[ "$expected_checksum" != "$actual_checksum" ]]; then
    print_error "Checksum verification failed!"
    ...
fi

# Recommended:
if [[ "$expected_checksum" != "$actual_checksum" ]]; then
    log_error_full "Checksum verification FAILED for update v${version}: expected=$expected_checksum actual=$actual_checksum" 1
    print_error "Checksum verification failed!"
    ...
fi
```

## Statistics

| Category | Count |
|----------|-------|
| HIGH Priority Issues | 18 |
| MEDIUM Priority Issues | 2 |
| LOW Priority Issues | 17 |
| Total Issues | 37 |
| Silent Error Suppressions | 12 |

## Conclusion

The `updater.sh` file has **37 logging issues**, with **18 HIGH priority** issues where errors are displayed but not logged. The most critical gaps are:

1. **Security failures not logged** - Checksum verification failures need `log_error_full`
2. **Download failures not logged** - All download errors should be logged for debugging
3. **No structured logging at all** - File uses 0 `log_*` functions currently

This module handles security-sensitive operations (downloading and verifying updates) and should have comprehensive logging for audit trails and incident investigation.
