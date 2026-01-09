# PRD: Phase C - Schedule Enhancements

**Feature:** Schedule validation, conflict detection, and interactive menu
**Version:** v3.2.0
**Codename:** Multi-Schedule (Phase C)
**Branch:** ralph/multi-schedule-per-job-timers
**Created:** 2026-01-09
**Status:** TODO

---

## 1. Introduction/Overview

Phase C completes the Multi-Schedule feature by adding schedule validation, conflict warnings, a cross-job schedule overview, and an interactive menu for non-CLI users. These enhancements build on the Phase A+B CLI foundation (BACKUPD-008 to BACKUPD-017) to provide a more robust and user-friendly scheduling experience.

**Prerequisites:** Phase A+B must be complete (verified in `.claude/v32.json`).

---

## 2. Goals

- Validate OnCalendar expressions before timer creation to prevent invalid schedules
- Warn users about potential schedule conflicts (same backup type at same time across jobs)
- Provide a global view of all job schedules via `backupd job schedule --all`
- Add interactive menu for users who prefer menu-driven configuration
- Maintain backward compatibility with existing Phase A+B functionality
- Zero breaking changes to existing commands

---

## 3. User Stories

### US-018: Validate Schedule Format Function
**ID:** BACKUPD-018
**Description:** As a developer, I want to add a `validate_schedule_format()` function so that invalid OnCalendar expressions are rejected before timer creation.

**Acceptance Criteria:**
- [ ] Function `validate_schedule_format(schedule)` added to `lib/jobs.sh`
- [ ] Uses `systemd-analyze calendar "$schedule" --iterations=1` for validation
- [ ] Returns 0 if valid, 1 if invalid
- [ ] Captures and can return the error message from systemd-analyze
- [ ] Shellcheck passes: `shellcheck -S error lib/jobs.sh`

**Implementation Notes:**
- Add after `get_timer_name()` function (~line 458)
- Suppress stdout, capture stderr for error message
- Example: `systemd-analyze calendar "*-*-* 02:00:00" --iterations=1 >/dev/null 2>&1`

---

### US-019: Integrate Validation in CLI
**ID:** BACKUPD-019
**Description:** As a user, I want the CLI to validate my schedule format before creating a timer so that I get a helpful error message for invalid expressions.

**Acceptance Criteria:**
- [ ] `cli_job_schedule()` calls `validate_schedule_format()` before `create_job_timer()`
- [ ] Invalid format returns exit code 6 (new code for validation failure)
- [ ] Error message includes: "Invalid schedule format: [expression]"
- [ ] Error message includes hint: "Test with: systemd-analyze calendar 'your-expression'"
- [ ] Valid formats proceed to timer creation unchanged
- [ ] JSON output includes `{"error": "Invalid schedule format", "schedule": "..."}` on failure
- [ ] Shellcheck passes: `shellcheck -S error lib/cli.sh`

**Implementation Notes:**
- Add validation check at ~line 2663 in `cli_job_schedule()`, before the `create_job_timer()` call
- Exit code 6 chosen to not conflict with existing codes (0-5)

---

### US-020: Integrate Validation in create_job_timer
**ID:** BACKUPD-020
**Description:** As a developer, I want `create_job_timer()` to validate schedules so that all code paths (CLI, menu, programmatic) are protected.

**Acceptance Criteria:**
- [ ] `create_job_timer()` calls `validate_schedule_format()` at the start
- [ ] Returns 1 immediately if validation fails
- [ ] Prints error message to stderr: "Error: Invalid schedule format"
- [ ] Existing callers handle the return code correctly
- [ ] Shellcheck passes: `shellcheck -S error lib/jobs.sh`

**Implementation Notes:**
- Add at ~line 465 in `create_job_timer()`, after local variable declarations
- This is defense-in-depth; CLI validates first for better UX

---

### US-021: Check Schedule Conflicts Function
**ID:** BACKUPD-021
**Description:** As a developer, I want to add a `check_schedule_conflicts()` function so that users are warned when the same backup type runs at the same time across different jobs.

**Acceptance Criteria:**
- [ ] Function `check_schedule_conflicts(job_name, backup_type, schedule)` added to `lib/jobs.sh`
- [ ] Loops through all jobs in `/etc/backupd/jobs/`
- [ ] Compares `SCHEDULE_{TYPE}` values (exact string match)
- [ ] Skips the current job being configured
- [ ] Prints warning if conflict found: "Warning: Job 'X' also has {type} backup scheduled at {schedule}"
- [ ] Returns 0 always (advisory only, does not block)
- [ ] Shellcheck passes: `shellcheck -S error lib/jobs.sh`

**Implementation Notes:**
- Add after `validate_schedule_format()` function
- Use `list_jobs()` to get all job names
- Only compare same backup type (db vs db, files vs files)

---

### US-022: Integrate Conflict Check in CLI
**ID:** BACKUPD-022
**Description:** As a user, I want to see a warning when I schedule a backup at the same time as another job so that I can avoid resource contention.

**Acceptance Criteria:**
- [ ] `cli_job_schedule()` calls `check_schedule_conflicts()` after successful timer creation
- [ ] Warning is printed to stderr (does not affect exit code)
- [ ] Warning only shown for same backup type across different jobs
- [ ] No warning for different backup types at same time
- [ ] JSON output includes `"warnings": ["..."]` array if conflicts detected
- [ ] Shellcheck passes: `shellcheck -S error lib/cli.sh`

**Implementation Notes:**
- Call after `create_job_timer()` succeeds at ~line 2680
- Use `print_warning()` for consistent styling

---

### US-023: List All Schedules Flag
**ID:** BACKUPD-023
**Description:** As a user, I want to run `backupd job schedule --all` to see all schedules across all jobs so that I can review my backup timing at a glance.

**Acceptance Criteria:**
- [ ] `cli_job_schedule()` handles `--all` or `-a` flag
- [ ] When `--all` flag provided, job_name is optional
- [ ] Output displays table: Job | Type | Schedule | Timer Status
- [ ] Loops through all jobs and all 4 backup types
- [ ] Shows "No schedule" for unconfigured types (or omits them)
- [ ] Supports `--json` flag for JSON array output
- [ ] Exit code 0 on success
- [ ] Shellcheck passes: `shellcheck -S error lib/cli.sh`

**Example Output:**
```
All Job Schedules:
JOB          TYPE         SCHEDULE              STATUS
default      db           *-*-* 02:00:00        active
default      files        *-*-* 03:00:00        active
production   db           *-*-* 04:00:00        inactive
staging      verify       *-*-* 06:00:00        active
```

**Implementation Notes:**
- Add `--all|-a` to argument parsing at ~line 2500
- Create helper function `list_all_job_schedules()` in lib/jobs.sh for reuse

---

### US-024: List All Schedules Helper Function
**ID:** BACKUPD-024
**Description:** As a developer, I want a `list_all_job_schedules()` function so that the schedule listing logic is reusable.

**Acceptance Criteria:**
- [ ] Function `list_all_job_schedules()` added to `lib/jobs.sh`
- [ ] Returns structured data: job_name, backup_type, schedule, timer_status
- [ ] Uses `list_jobs()` to enumerate all jobs
- [ ] Uses `get_job_config()` to read SCHEDULE_* values
- [ ] Uses `get_timer_name()` and `systemctl is-active` for status
- [ ] Shellcheck passes: `shellcheck -S error lib/jobs.sh`

**Implementation Notes:**
- Add after `check_schedule_conflicts()` function
- Output format suitable for both text table and JSON conversion

---

### US-025: Interactive Schedule Menu
**ID:** BACKUPD-025
**Description:** As a user who prefers menus, I want a "Manage Job Schedules" option in the main menu so that I can configure schedules without using CLI commands.

**Acceptance Criteria:**
- [ ] New menu option "Manage Job Schedules" added to main menu in `lib/schedule.sh`
- [ ] Menu shows list of existing jobs to select from
- [ ] After selecting job, shows submenu with backup types (db, files, verify, verify-full)
- [ ] After selecting type, prompts for OnCalendar expression
- [ ] Validates input using `validate_schedule_format()`
- [ ] Creates timer using `create_job_timer()`
- [ ] Shows success/error message
- [ ] Option to return to main menu or configure another schedule
- [ ] Shellcheck passes: `shellcheck -S error lib/schedule.sh`

**Implementation Notes:**
- Follow existing menu patterns in `lib/schedule.sh`
- Use `select` or numbered menu for job/type selection
- Provide common schedule examples as hints

---

### US-026: Update Help Text for --all Flag
**ID:** BACKUPD-026
**Description:** As a user, I want the help text to document the `--all` flag so that I can discover the feature.

**Acceptance Criteria:**
- [ ] `cli_job_help()` includes `--all` flag in options section
- [ ] Description: "Show all schedules across all jobs"
- [ ] Example added: `backupd job schedule --all`
- [ ] Shellcheck passes: `shellcheck -S error lib/cli.sh`

**Implementation Notes:**
- Update help text at ~line 2807-2872

---

## 4. Functional Requirements

**FR-1:** The system must validate OnCalendar expressions using `systemd-analyze calendar` before creating timers.

**FR-2:** The system must return exit code 6 for invalid schedule format in CLI, with a helpful error message.

**FR-3:** The system must warn (not block) when the same backup type is scheduled at the same time across different jobs.

**FR-4:** The system must provide `backupd job schedule --all` to list all schedules across all jobs.

**FR-5:** The system must provide an interactive menu option "Manage Job Schedules" for menu-driven configuration.

**FR-6:** All new code must pass `shellcheck -S error`.

**FR-7:** All commits must be signed (`git commit -S`) with no AI/Claude mentions.

**FR-8:** Exit codes: 0=success, 2=usage, 3=job not found, 4=invalid type, 5=timer fail, 6=invalid format.

---

## 5. Non-Goals (Out of Scope)

- **Time-based conflict detection:** Only exact string matching, not parsing OnCalendar to detect near-overlaps
- **Automatic conflict resolution:** System warns but does not suggest alternative times
- **Schedule templates:** No predefined schedule options (user enters OnCalendar directly)
- **Cross-server scheduling:** Only local job schedules, not distributed coordination
- **Calendar visualization:** Text output only, no graphical timeline

---

## 6. Technical Considerations

### Files to Modify

| File | Changes | Stories |
|------|---------|---------|
| lib/jobs.sh | Add validate_schedule_format(), check_schedule_conflicts(), list_all_job_schedules() | BACKUPD-018, 020, 021, 024 |
| lib/cli.sh | Integrate validation, conflict check, --all flag | BACKUPD-019, 022, 023, 026 |
| lib/schedule.sh | Add interactive schedule menu | BACKUPD-025 |

### Dependencies

- `systemd-analyze` must be available (standard on systemd systems)
- Existing functions: `get_job_config()`, `create_job_timer()`, `get_timer_name()`, `list_jobs()`

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 2 | Invalid usage (missing args) |
| 3 | Job not found |
| 4 | Invalid backup type |
| 5 | Timer creation failed |
| 6 | Invalid schedule format (NEW) |

---

## 7. Success Metrics

- All 9 user stories pass acceptance criteria
- Shellcheck passes on all modified files
- All commits signed with no AI mentions
- Backward compatibility maintained (existing commands unchanged)
- Phase A+B functionality unaffected

---

## 8. Open Questions

None - all clarified during PRD creation.

---

## 9. Implementation Order

Recommended sequence for Ralph iterations:

1. **BACKUPD-018:** validate_schedule_format() function
2. **BACKUPD-020:** Integrate validation in create_job_timer()
3. **BACKUPD-019:** Integrate validation in CLI
4. **BACKUPD-021:** check_schedule_conflicts() function
5. **BACKUPD-022:** Integrate conflict check in CLI
6. **BACKUPD-024:** list_all_job_schedules() function
7. **BACKUPD-023:** --all flag in CLI
8. **BACKUPD-026:** Update help text
9. **BACKUPD-025:** Interactive schedule menu

---

## 10. References

- **Phase A+B PRD:** `/home/webnestify/backupd/tasks/prd-multi-schedule-per-job-timers.md`
- **Master plan:** `/home/webnestify/backupd/.claude/v32.json`
- **Progress log:** `/home/webnestify/backupd/progress.txt`
- **Project rules:** `/home/webnestify/backupd/CLAUDE.md`
- **Jobs module:** `/home/webnestify/backupd/lib/jobs.sh`
- **CLI module:** `/home/webnestify/backupd/lib/cli.sh`
- **Schedule module:** `/home/webnestify/backupd/lib/schedule.sh`
