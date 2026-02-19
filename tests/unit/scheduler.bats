#!/usr/bin/env bash
# tests/unit/scheduler.bats — Tests for lib/scheduler.sh parsing functions

setup() {
  load '../test_helper'
  export BACKUPD_TRAP_SET=1
  source_modules "exitcodes" "core" "debug" "logging" "scheduler"
  # Re-declare DOW_MAP — bats does not inherit top-level declare -A from sourced files
  declare -gA DOW_MAP=(
    [Mon]=1 [Tue]=2 [Wed]=3 [Thu]=4 [Fri]=5 [Sat]=6 [Sun]=0
    [Monday]=1 [Tuesday]=2 [Wednesday]=3 [Thursday]=4 [Friday]=5 [Saturday]=6 [Sunday]=0
  )
}

# ---------- oncalendar_to_cron() ----------

@test "oncalendar_to_cron converts hourly" {
  run oncalendar_to_cron "hourly"
  assert_success
  assert_output "0 * * * *"
}

@test "oncalendar_to_cron converts daily" {
  run oncalendar_to_cron "daily"
  assert_success
  assert_output "0 0 * * *"
}

@test "oncalendar_to_cron converts weekly" {
  run oncalendar_to_cron "weekly"
  assert_success
  assert_output "0 0 * * 0"
}

@test "oncalendar_to_cron converts monthly" {
  run oncalendar_to_cron "monthly"
  assert_success
  assert_output "0 0 1 * *"
}

@test "oncalendar_to_cron converts specific time *-*-* 02:30:00" {
  run oncalendar_to_cron "*-*-* 02:30:00"
  assert_success
  assert_output "30 2 * * *"
}

@test "oncalendar_to_cron converts interval 0/6 hours" {
  run oncalendar_to_cron "*-*-* 0/6:00:00"
  assert_success
  assert_output "0 */6 * * *"
}

@test "oncalendar_to_cron converts day-of-week Mon *-*-* 09:00" {
  run oncalendar_to_cron "Mon *-*-* 09:00:00"
  assert_success
  assert_output "0 9 * * 1"
}

@test "oncalendar_to_cron converts time without seconds" {
  run oncalendar_to_cron "*-*-* 14:30"
  assert_success
  assert_output "30 14 * * *"
}

@test "oncalendar_to_cron rejects empty input" {
  run oncalendar_to_cron ""
  assert_failure
}

# ---------- validate_cron_format() ----------

@test "validate_cron_format accepts standard 5-field cron" {
  run validate_cron_format "0 * * * *"
  assert_success
}

@test "validate_cron_format accepts all-stars" {
  run validate_cron_format "* * * * *"
  assert_success
}

@test "validate_cron_format accepts ranges and steps" {
  run validate_cron_format "*/15 0-6 * * 1-5"
  assert_success
}

@test "validate_cron_format rejects 4 fields" {
  run validate_cron_format "0 * * *"
  assert_failure
}

@test "validate_cron_format rejects 6 fields" {
  run validate_cron_format "0 * * * * *"
  assert_failure
}

@test "validate_cron_format rejects invalid characters" {
  run validate_cron_format "0 * * * abc"
  assert_failure
}

@test "validate_cron_format rejects empty input" {
  run validate_cron_format ""
  assert_failure
}
