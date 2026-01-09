# PRD: Multi-Schedule (Per-Job Timers)

**Feature:** Per-job backup schedule configuration via CLI
**Version:** v3.2.0
**Codename:** Multi-Schedule
**GitHub Issue:** #4
**Created:** 2026-01-09
**Status:** PHASE A+B COMPLETE - Ready for v3.2.0 Release

---

## Implementation Status

| Phase | Name | Status | Completed |
|-------|------|--------|-----------|
| A | CLI Exposure (MVP) | COMPLETE | 2026-01-09 |
| B | Bug Fix & Enhancement | COMPLETE | 2026-01-09 |
| C | Optional Enhancements | TODO | Target: v3.2.1 |

### Completed Commits (Phase A + B)
| Commit | Story | Description |
|--------|-------|-------------|
| 5656a75 | BACKUPD-008 | Add case statement for schedule command |
| 2442bf9 | BACKUPD-009 | Add cli_job_schedule function argument parsing |
| ebe45fd | BACKUPD-010 | Add cli_job_schedule validation |
| 946ed16 | BACKUPD-011 | Add cli_job_schedule show schedule |
| 91f64a3 | BACKUPD-012 | Add cli_job_schedule disable timer |
| 88fdd03 | BACKUPD-013 | Add cli_job_schedule create timer handler |
| ab1ffa2 | BACKUPD-014 | Update cli_job_help with schedule command |
| 50521e7 | BACKUPD-015 | Update cli_job_show with schedules section |
| 766cbf4 | BACKUPD-016 | Fix enable_job to recreate timers |
| N/A | BACKUPD-017 | Verify backward compatibility (verification only) |

### Verification Results
- Shellcheck: PASS
- Backward Compatibility: VERIFIED
- All Commits Signed: YES (9/9)
- AI Mentions: NONE
- Recommendation: GO FOR v3.2.0 RELEASE

---

## 1. Introduction/Overview

Backupd v3.1.0 introduced multi-job support with systemd timer infrastructure. However, scheduling is currently only configurable through the interactive menu for the default job. This feature exposes per-job timer scheduling via the CLI, allowing administrators to set independent backup schedules for each job without using the interactive menu.

The implementation leverages existing `create_job_timer()` infrastructure from v3.1.0, requiring minimal new code (~70 lines total). This also fixes a bug where `enable_job()` doesn't recreate timers from stored configuration.

---

## 2. Goals

- [x] Enable per-job schedule configuration via CLI command
- [x] Support all 4 backup types: `db`, `files`, `verify`, `verify-full`
- [x] Maintain backward compatibility with default job legacy timer names (`backupd-db.timer`)
- [x] Fix `enable_job()` bug that doesn't recreate timers from stored config
- [x] Provide `--show`, `--disable`, and `--json` flags for complete schedule control
- [x] Display schedules in `backupd job show` output
- [x] Zero changes to existing workflows or timer behavior

---

## 3. User Stories

### US-001: Set Backup Schedule via CLI - COMPLETE
**Description:** As a system administrator, I want to set a backup schedule for a specific job and backup type via CLI so that I can automate backup timing without using the interactive menu.

**Acceptance Criteria:**
- [x] Command `backupd job schedule <job_name> <type> <schedule>` creates systemd timer
- [x] Timer uses OnCalendar format (e.g., `*-*-* 02:00:00`)
- [x] Schedule is persisted to `/etc/backupd/jobs/{jobname}/job.conf` as `SCHEDULE_{TYPE}`
- [x] Timer is enabled and started immediately after creation
- [x] Success message displays timer name and schedule
- [x] Exit code 0 on success

**Implementation:** `lib/cli.sh:2663-2690` (BACKUPD-013)

---

### US-002: View Current Schedule - COMPLETE
**Description:** As a system administrator, I want to view the current schedule for a job so that I can verify timing before making changes.

**Acceptance Criteria:**
- [x] Command `backupd job schedule <job_name> <type> --show` displays current schedule
- [x] Command `backupd job schedule <job_name> --show` displays all schedules for the job
- [x] Output shows OnCalendar value from config
- [x] Output indicates if timer is active or disabled
- [x] Shows "No schedule configured" if SCHEDULE_{TYPE} is empty
- [x] Exit code 0 on success

**Implementation:** `lib/cli.sh:2568-2635` (BACKUPD-011)

---

### US-003: Disable Schedule - COMPLETE
**Description:** As a system administrator, I want to disable a backup schedule without deleting the configuration so that I can temporarily pause backups and re-enable them later.

**Acceptance Criteria:**
- [x] Command `backupd job schedule <job_name> <type> --disable` stops the timer
- [x] Timer unit is stopped and disabled (not deleted)
- [x] `SCHEDULE_{TYPE}` config value is preserved in job.conf
- [x] Success message confirms timer disabled
- [x] Exit code 0 on success

**Implementation:** `lib/cli.sh:2638-2660` (BACKUPD-012)

---

### US-004: JSON Output - COMPLETE
**Description:** As an automation engineer, I want JSON output from schedule commands so that I can parse results programmatically.

**Acceptance Criteria:**
- [x] Flag `--json` outputs valid JSON for all schedule operations
- [x] JSON includes: job_name, backup_type, schedule, timer_name, status
- [x] `backupd job schedule <job_name> --json` returns all schedules as JSON array
- [x] Exit code 0 on success with valid JSON

**Implementation:** Throughout cli_job_schedule() (BACKUPD-011, BACKUPD-012, BACKUPD-013)

---

### US-005: Enable Job Recreates Timers - COMPLETE
**Description:** As a system administrator, I want `backupd job enable` to recreate timers from stored configuration so that re-enabling a disabled job restores its schedules automatically.

**Acceptance Criteria:**
- [x] `enable_job()` reads SCHEDULE_DB, SCHEDULE_FILES, SCHEDULE_VERIFY, SCHEDULE_VERIFY_FULL from config
- [x] For each non-empty SCHEDULE_* value, `create_job_timer()` is called
- [x] Timers are started and enabled after job enable
- [x] No action taken for empty SCHEDULE_* values

**Implementation:** `lib/jobs.sh:606-619` (BACKUPD-016)

---

### US-006: Display Schedules in Job Show - COMPLETE
**Description:** As a system administrator, I want to see current schedules when viewing job details so that I have complete job information in one place.

**Acceptance Criteria:**
- [x] `backupd job show <name>` includes "Schedules:" section
- [x] Each configured schedule type is displayed with its OnCalendar value
- [x] Timer status (active/inactive) is shown
- [x] Section omitted if no schedules configured

**Implementation:** `lib/cli.sh:2165-2194` (BACKUPD-015)

---

### US-007: Input Validation - COMPLETE
**Description:** As a system administrator, I want clear error messages when I provide invalid input so that I can correct my command quickly.

**Acceptance Criteria:**
- [x] Invalid job name returns "Error: Job 'X' not found" with exit code 3
- [x] Invalid backup type returns "Error: Invalid backup type 'X'. Valid types: db, files, verify, verify-full" with exit code 4
- [x] Missing required arguments returns usage help with exit code 2
- [x] Invalid OnCalendar format returns systemd's error message with exit code 5

**Implementation:** `lib/cli.sh:2550-2564` (BACKUPD-010)

---

### US-008: Backward Compatibility - VERIFIED
**Description:** As an existing backupd user, I want my default job to continue using legacy timer names so that existing integrations and monitoring don't break.

**Acceptance Criteria:**
- [x] Default job uses `backupd-db.timer`, `backupd-files.timer` (no job name prefix)
- [x] Non-default jobs use `backupd-{jobname}-{type}.timer`
- [x] Existing timers are not modified unless explicitly changed
- [x] `get_timer_name()` function handles naming convention

**Implementation:** `lib/jobs.sh:447-457` (BACKUPD-017 - verification)

---

## 4. Phase C: TODO for v3.2.1

The following enhancements are deferred to v3.2.1:

| Task | Description | File | Lines | Purpose |
|------|-------------|------|-------|---------|
| C1 | `validate_schedule_format()` | lib/jobs.sh | ~15 | Validate OnCalendar expression before timer creation |
| C2 | `check_schedule_conflicts()` | lib/jobs.sh | ~25 | Warn about overlapping schedules across jobs |
| C3 | `list_all_job_schedules()` | lib/jobs.sh | ~20 | Cross-job schedule overview (`backupd schedule list-all`) |
| C4 | Interactive schedule menu | lib/schedule.sh | ~40 | Menu-driven schedule selection for non-CLI users |

**Total Phase C:** ~100 lines

---

## 5. Functional Requirements (All Implemented)

**FR-1:** [x] The system must provide command `backupd job schedule <job_name> <backup_type> [schedule] [options]`.

**FR-2:** [x] The system must call existing `create_job_timer(job_name, backup_type, schedule)` from `lib/jobs.sh:460-537` for timer creation.

**FR-3:** [x] Timer naming convention must be:
- Default job: `backupd-{type}.timer` (e.g., `backupd-db.timer`)
- Other jobs: `backupd-{jobname}-{type}.timer` (e.g., `backupd-prod-db.timer`)

**FR-4:** [x] Schedule must be persisted to `/etc/backupd/jobs/{jobname}/job.conf` as `SCHEDULE_{TYPE}` key.

**FR-5:** [x] The `--disable` flag must stop and disable the timer but preserve the `SCHEDULE_*` config value.

**FR-6:** [x] The `enable_job()` function must recreate timers from stored `SCHEDULE_*` config values.

**FR-7:** [x] The system must validate job exists and backup type is valid.

**FR-8:** [x] Exit codes: 0=success, 2=usage, 3=job not found, 4=invalid type, 5=timer fail

**FR-9:** [x] The `--show` flag behavior handles both single type and all types.

**FR-10:** [x] The `cli_job_show()` function displays configured schedules.

---

## 6. Technical Implementation Summary

### Files Modified

| File | Location | Changes | Story |
|------|----------|---------|-------|
| lib/cli.sh | Lines 2081-2083 | Case statement routing | BACKUPD-008 |
| lib/cli.sh | Lines 2516-2691 | cli_job_schedule() function | BACKUPD-009 to BACKUPD-013 |
| lib/cli.sh | Lines 2165-2194 | cli_job_show() schedules section | BACKUPD-015 |
| lib/cli.sh | Lines 2807-2872 | cli_job_help() documentation | BACKUPD-014 |
| lib/jobs.sh | Lines 606-619 | enable_job() timer recreation | BACKUPD-016 |

### Existing Infrastructure Used (No Changes)

| Function | File | Lines |
|----------|------|-------|
| `create_job_timer()` | lib/jobs.sh | 460-537 |
| `get_timer_name()` | lib/jobs.sh | 447-457 |
| `disable_job_timers()` | lib/jobs.sh | 541-569 |
| `list_job_timers()` | lib/jobs.sh | 573-587 |
| `save_job_config()` | lib/jobs.sh | 208-240 |
| `get_job_config()` | lib/jobs.sh | 196-206 |
| `job_exists()` | lib/jobs.sh | 33-42 |

---

## 7. Next Steps

### For v3.2.0 Release
1. Merge `ralph/multi-schedule-per-job-timers` to `develop`
2. Update version in `backupd.sh:18` to `3.2.0`
3. Update `CHANGELOG.md` with multi-schedule feature
4. Update `USAGE.md:3` header version
5. Follow release workflow in `CLAUDE.md`
6. Create signed tag `v3.2.0`

### For v3.2.1 (Phase C)
1. Create PRD for Phase C tasks
2. Implement C1-C4 in new Ralph iteration cycle

---

## 8. References

- **Analysis spec:** `/home/webnestify/backupd/.claude/v32.json`
- **Ralph PRD:** `/home/webnestify/backupd/tasks/prd.json`
- **Progress log:** `/home/webnestify/backupd/progress.txt`
- **Jobs module:** `/home/webnestify/backupd/lib/jobs.sh`
- **CLI module:** `/home/webnestify/backupd/lib/cli.sh`
- **GitHub Issue:** #4
