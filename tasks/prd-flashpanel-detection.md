# PRD: FlashPanel Detection Support

**Version:** 1.0
**Target Release:** v3.2.0
**Created:** 2026-01-09
**Status:** Draft

---

## 1. Introduction/Overview

Add FlashPanel server management panel detection to Backupd. FlashPanel is a modern server management panel that supports two site isolation modes:

- **Non-isolated mode:** All sites under `/home/flashpanel/{site}/`
- **Isolated mode:** Each site under its own user `/home/{user}/{site}/`

This feature enables Backupd to automatically detect FlashPanel installations and configure appropriate backup paths, following the existing panel detection architecture in `lib/core.sh`.

---

## 2. Goals

- Automatically detect FlashPanel installations via service detection
- Support both non-isolated and isolated site configurations
- Auto-detect which isolation mode is in use
- Allow manual override during setup for edge cases
- Follow existing panel detection patterns for consistency
- Enable FlashPanel users to back up their sites without manual path configuration

---

## 3. User Stories

### US-001: Add FlashPanel Panel Definitions

**Description:** As a developer, I want FlashPanel entries in PANEL_DEFINITIONS so that the panel detection system recognizes FlashPanel configurations.

**Acceptance Criteria:**
- [ ] Add `flashpanel` entry to PANEL_DEFINITIONS array (~line 591)
  - Format: `["flashpanel"]="FlashPanel|/home/flashpanel/*|.|service"`
- [ ] Add `flashpanel-isolated` entry to PANEL_DEFINITIONS array
  - Format: `["flashpanel-isolated"]="FlashPanel (Isolated)|/home/*/*|.|service"`
- [ ] Both entries use `service` as detection_method
- [ ] Webroot subdirectory is `.` (direct) for both
- [ ] Shellcheck passes: `shellcheck -S error lib/core.sh`

---

### US-002: Add FlashPanel Service Detection

**Description:** As a user with FlashPanel installed, I want Backupd to automatically detect my panel so that I don't have to manually configure paths.

**Acceptance Criteria:**
- [ ] Add FlashPanel detection in `detect_panel_by_service()` function (~line 643)
- [ ] Check for `flashpanel.service` using `is_service_running`
- [ ] Also check for binary at `/root/.flashpanel/agent/flashpanel` as fallback
- [ ] When detected, determine isolation mode:
  - If `/home/flashpanel/` exists AND has subdirectories → return `flashpanel`
  - Else → return `flashpanel-isolated`
- [ ] Detection runs before user-based detection (maintain priority order)
- [ ] Shellcheck passes: `shellcheck -S error lib/core.sh`

---

### US-003: Add Isolation Mode Detection Helper

**Description:** As a developer, I want a helper function to detect FlashPanel isolation mode so that detection logic is clean and reusable.

**Acceptance Criteria:**
- [ ] Add `detect_flashpanel_isolation_mode()` function in lib/core.sh
- [ ] Function checks if `/home/flashpanel/` directory exists
- [ ] Function checks if directory has site subdirectories (not empty)
- [ ] Returns `flashpanel` for non-isolated mode
- [ ] Returns `flashpanel-isolated` for isolated mode
- [ ] Function is called by `detect_panel_by_service()` when FlashPanel is detected
- [ ] Shellcheck passes: `shellcheck -S error lib/core.sh`

---

### US-004: Update Setup Flow for FlashPanel

**Description:** As a user running setup, I want to be able to confirm or override the detected FlashPanel isolation mode so that I can handle edge cases.

**Acceptance Criteria:**
- [ ] When FlashPanel is detected, display which mode was auto-detected
- [ ] Show message: "FlashPanel detected (non-isolated mode)" or "FlashPanel detected (isolated mode)"
- [ ] Allow user to accept detected mode or switch to the other mode
- [ ] If user switches mode, update the panel key accordingly
- [ ] Existing setup flow handles the pattern from PANEL_DEFINITIONS
- [ ] Shellcheck passes: `shellcheck -S error lib/setup.sh`

---

### US-005: Add FlashPanel to Panel Selection Menu

**Description:** As a user manually selecting a panel, I want FlashPanel options in the panel selection menu so that I can choose my panel type.

**Acceptance Criteria:**
- [ ] Add FlashPanel options to interactive panel selection in setup
- [ ] Display as two options:
  - "FlashPanel (standard)" for non-isolated
  - "FlashPanel (isolated)" for isolated mode
- [ ] Selection sets appropriate panel key (`flashpanel` or `flashpanel-isolated`)
- [ ] Works correctly when auto-detection fails or is overridden
- [ ] Shellcheck passes: `shellcheck -S error lib/setup.sh`

---

### US-006: Update Documentation

**Description:** As a user, I want documentation about FlashPanel support so that I understand how to configure backups for my FlashPanel server.

**Acceptance Criteria:**
- [ ] Add FlashPanel to supported panels list in USAGE.md
- [ ] Document both isolation modes
- [ ] Include example paths for each mode
- [ ] Note that deeper directory paths can be customized during setup

---

## 4. Functional Requirements

**FR-1:** The system must detect FlashPanel by checking if `flashpanel.service` is running via systemctl.

**FR-2:** The system must fall back to checking for the binary at `/root/.flashpanel/agent/flashpanel` if the service check fails.

**FR-3:** When FlashPanel is detected, the system must auto-detect isolation mode by checking:
- If `/home/flashpanel/` exists AND contains subdirectories → non-isolated mode
- Otherwise → isolated mode

**FR-4:** The PANEL_DEFINITIONS array must contain two entries:
- `flashpanel`: Pattern `/home/flashpanel/*`, webroot `.`, detection `service`
- `flashpanel-isolated`: Pattern `/home/*/*`, webroot `.`, detection `service`

**FR-5:** The system must allow users to override the auto-detected isolation mode during setup.

**FR-6:** The panel selection menu must include both FlashPanel options for manual selection.

**FR-7:** Detection priority must be: service-based (FlashPanel before others in the function), then user-based, then file-based.

---

## 5. Non-Goals (Out of Scope)

- **FlashPanel API integration:** No direct API calls to FlashPanel for site discovery
- **Database detection:** FlashPanel database backup configuration is handled separately
- **Automatic site discovery:** Using FlashPanel's internal site list (we use filesystem patterns)
- **FlashPanel-specific features:** Custom backup types or panel-specific options
- **Remote FlashPanel servers:** Only local panel detection

---

## 6. Technical Considerations

### Detection Order
FlashPanel detection should be added to `detect_panel_by_service()` with appropriate priority. Suggested position: after HestiaCP, before the function's return statement.

### Pattern Conflicts
The isolated mode pattern `/home/*/*` is identical to Ploi's pattern. This is acceptable because:
1. Service-based detection runs first and takes priority
2. FlashPanel service detection will return before Ploi user detection runs
3. If FlashPanel service is not detected, the pattern won't be used

### Existing Code Locations
- Panel definitions: `lib/core.sh` lines 579-592
- Service detection: `lib/core.sh` lines 607-646
- Panel info getter: `lib/core.sh` lines 732-760
- Setup panel selection: `lib/setup.sh`

### Directory Structure Examples

**Non-isolated mode:**
```
/home/flashpanel/
├── site1.com/
│   ├── index.php
│   └── wp-content/
├── site2.com/
│   └── public/        # User might use subdirectory
│       └── index.php
└── site3.com/
    └── app/
        └── public/    # Deeper nesting possible
```

**Isolated mode:**
```
/home/
├── user1/
│   └── site1.com/
│       └── index.php
├── user2/
│   └── site2.com/
│       └── index.php
└── user3/
    └── site3.com/
        └── public/
            └── index.php
```

---

## 7. Success Metrics

| Metric | Target |
|--------|--------|
| Auto-detection accuracy | FlashPanel detected when service is running |
| Isolation mode accuracy | Correct mode detected based on directory structure |
| Setup completion | Users can complete setup without manual path entry |
| Backward compatibility | Existing panel detection unaffected |
| Code quality | Shellcheck passes on all modified files |

---

## 8. Open Questions

1. **Q:** Are there any other FlashPanel-specific paths or configurations we should consider?
   **A:** TBD - May need user feedback after initial release

2. **Q:** Should we add FlashPanel logo/branding to status output?
   **A:** Out of scope for v3.2.0, consider for future release

3. **Q:** How common is the isolated mode vs non-isolated mode in production?
   **A:** TBD - Auto-detection with override should handle both cases

---

## Appendix: Implementation Reference

### PANEL_DEFINITIONS Entry Format
```bash
["key"]="DisplayName|pattern|webroot_subdir|detection_method"
```

### Detection Function Pattern
```bash
# In detect_panel_by_service()
if is_service_running "flashpanel" || [[ -f "/root/.flashpanel/agent/flashpanel" ]]; then
  detect_flashpanel_isolation_mode
  return 0
fi
```

### Isolation Mode Detection Pattern
```bash
detect_flashpanel_isolation_mode() {
  if [[ -d "/home/flashpanel" ]] && compgen -G "/home/flashpanel/*/" >/dev/null 2>&1; then
    echo "flashpanel"
  else
    echo "flashpanel-isolated"
  fi
}
```
