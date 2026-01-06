#!/usr/bin/env bash
# ============================================================================
# Backupd v3.0 - Verify Module (Restic-Based)
# Backup integrity verification using restic check commands
#
# v3.0 Changes:
#   - Replaced checksum-based verification with `restic check`
#   - Replaced GPG decrypt verification with `restic check --read-data`
#   - Simplified from ~570 lines to ~200 lines
# ============================================================================

# Last full verification tracking file
LAST_FULL_VERIFY_FILE="$INSTALL_DIR/.last_full_verify"
FULL_VERIFY_INTERVAL_DAYS=30

# ---------- Quick Verification (Metadata-only, no download) ----------
# Uses: restic check (fast, verifies repository structure and index)

verify_quick() {
  log_func_enter 2>/dev/null || true
  debug_enter "verify_quick" "$1" 2>/dev/null || true
  local backup_type="$1"  # "db", "files", or "both"
  local secrets_dir rclone_remote rclone_db_path rclone_files_path
  secrets_dir="$(get_secrets_dir)"
  rclone_remote="$(get_config_value 'RCLONE_REMOTE')"
  rclone_db_path="$(get_config_value 'RCLONE_DB_PATH')"
  rclone_files_path="$(get_config_value 'RCLONE_FILES_PATH')"

  # Get restic repository password
  local restic_password
  restic_password="$(get_secret "$secrets_dir" ".c1")"
  if [[ -z "$restic_password" ]]; then
    print_error "No repository password found in secrets"
    return 1
  fi

  local db_result="SKIPPED" files_result="SKIPPED"
  local db_details="" files_details=""
  local hostname
  hostname="$(hostname -f 2>/dev/null || hostname)"

  # Check database repository (quick - metadata only)
  if [[ "$backup_type" == "db" || "$backup_type" == "both" ]] && [[ -n "$rclone_db_path" ]]; then
    local repo="rclone:${rclone_remote}:${rclone_db_path}"
    echo "Checking database repository (quick)..."
    echo "  Repository: $repo"
    echo

    local check_output
    if check_output=$(RESTIC_PASSWORD="$restic_password" restic -r "$repo" check 2>&1); then
      db_result="PASSED"
      # Get snapshot count for details (use || true to prevent pipefail exit)
      local snapshot_count
      snapshot_count=$(RESTIC_PASSWORD="$restic_password" restic -r "$repo" snapshots --tag database --json 2>/dev/null | grep -c '"short_id"' || true)
      [[ -z "$snapshot_count" ]] && snapshot_count="0"
      db_details="Repository OK, $snapshot_count snapshot(s)"
      print_success "Database repository: $db_details"
    else
      db_result="FAILED"
      # Extract error from output (use || true to prevent pipefail exit)
      local error_msg
      error_msg=$(echo "$check_output" | grep -i "error\|fatal" | head -1 || true)
      db_details="${error_msg:-Repository check failed}"
      print_error "Database repository: $db_details"
      echo "$check_output" | head -10
    fi
    echo
  fi

  # Check files repository (quick - metadata only)
  if [[ "$backup_type" == "files" || "$backup_type" == "both" ]] && [[ -n "$rclone_files_path" ]]; then
    local repo="rclone:${rclone_remote}:${rclone_files_path}"
    echo "Checking files repository (quick)..."
    echo "  Repository: $repo"
    echo

    local check_output
    if check_output=$(RESTIC_PASSWORD="$restic_password" restic -r "$repo" check 2>&1); then
      files_result="PASSED"
      # Get snapshot count for details (use || true to prevent pipefail exit)
      local snapshot_count
      snapshot_count=$(RESTIC_PASSWORD="$restic_password" restic -r "$repo" snapshots --tag files --json 2>/dev/null | grep -c '"short_id"' || true)
      [[ -z "$snapshot_count" ]] && snapshot_count="0"
      files_details="Repository OK, $snapshot_count snapshot(s)"
      print_success "Files repository: $files_details"
    else
      files_result="FAILED"
      # Extract error from output (use || true to prevent pipefail exit)
      local error_msg
      error_msg=$(echo "$check_output" | grep -i "error\|fatal" | head -1 || true)
      files_details="${error_msg:-Repository check failed}"
      print_error "Files repository: $files_details"
      echo "$check_output" | head -10
    fi
    echo
  fi

  # Send notifications (ntfy + webhook)
  send_verify_notification "quick" "$db_result" "$files_result" "$db_details" "$files_details"

  # Return status
  if [[ "$db_result" == "FAILED" || "$files_result" == "FAILED" ]]; then
    return 1
  fi
  return 0
}

# ---------- Full Verification (Downloads and verifies all data) ----------
# Uses: restic check --read-data (thorough, downloads all pack files)

verify_full() {
  log_func_enter 2>/dev/null || true
  debug_enter "verify_full" "$1" 2>/dev/null || true
  local backup_type="$1"  # "db", "files", or "both"
  local secrets_dir rclone_remote rclone_db_path rclone_files_path
  secrets_dir="$(get_secrets_dir)"
  rclone_remote="$(get_config_value 'RCLONE_REMOTE')"
  rclone_db_path="$(get_config_value 'RCLONE_DB_PATH')"
  rclone_files_path="$(get_config_value 'RCLONE_FILES_PATH')"

  # Get restic repository password
  local restic_password
  restic_password="$(get_secret "$secrets_dir" ".c1")"
  if [[ -z "$restic_password" ]]; then
    print_error "No repository password found in secrets"
    return 1
  fi

  local db_result="SKIPPED" files_result="SKIPPED"
  local db_details="" files_details=""
  local hostname
  hostname="$(hostname -f 2>/dev/null || hostname)"

  # Full check database repository (downloads and verifies all data)
  if [[ "$backup_type" == "db" || "$backup_type" == "both" ]] && [[ -n "$rclone_db_path" ]]; then
    local repo="rclone:${rclone_remote}:${rclone_db_path}"
    echo
    echo "============================================="
    echo "Full Verification: Database Repository"
    echo "============================================="
    echo
    echo "  Repository: $repo"
    echo "  This will download and verify ALL backup data."
    echo "  This may take a long time for large repositories."
    echo
    print_info "Starting full verification (restic check --read-data)..."
    echo

    local start_time check_output
    start_time=$(date +%s)

    if check_output=$(RESTIC_PASSWORD="$restic_password" restic -r "$repo" check --read-data --retry-lock 2m 2>&1); then
      local end_time duration
      end_time=$(date +%s)
      duration=$((end_time - start_time))

      db_result="PASSED"

      # Get repository stats (use || true to prevent pipefail exit)
      local repo_stats snapshot_count total_size
      repo_stats=$(RESTIC_PASSWORD="$restic_password" restic -r "$repo" stats --json 2>/dev/null || echo "{}")
      snapshot_count=$(RESTIC_PASSWORD="$restic_password" restic -r "$repo" snapshots --tag database --json 2>/dev/null | grep -c '"short_id"' || true)
      [[ -z "$snapshot_count" ]] && snapshot_count="0"
      total_size=$(echo "$repo_stats" | grep -o '"total_size":[0-9]*' | cut -d':' -f2 || true)
      total_size_human=$(numfmt --to=iec-i --suffix=B "$total_size" 2>/dev/null || echo "${total_size:-0}B")

      db_details="All data verified OK ($snapshot_count snapshots, $total_size_human, ${duration}s)"
      print_success "Database repository: $db_details"
    else
      db_result="FAILED"
      # Extract error from output (use || true to prevent pipefail exit)
      local error_msg
      error_msg=$(echo "$check_output" | grep -i "error\|fatal" | head -1 || true)
      db_details="${error_msg:-Full verification failed}"
      print_error "Database repository: $db_details"
      echo "$check_output" | head -20
    fi
  fi

  # Full check files repository (downloads and verifies all data)
  if [[ "$backup_type" == "files" || "$backup_type" == "both" ]] && [[ -n "$rclone_files_path" ]]; then
    local repo="rclone:${rclone_remote}:${rclone_files_path}"
    echo
    echo "============================================="
    echo "Full Verification: Files Repository"
    echo "============================================="
    echo
    echo "  Repository: $repo"
    echo "  This will download and verify ALL backup data."
    echo "  This may take a long time for large repositories."
    echo
    print_info "Starting full verification (restic check --read-data)..."
    echo

    local start_time check_output
    start_time=$(date +%s)

    if check_output=$(RESTIC_PASSWORD="$restic_password" restic -r "$repo" check --read-data --retry-lock 2m 2>&1); then
      local end_time duration
      end_time=$(date +%s)
      duration=$((end_time - start_time))

      files_result="PASSED"

      # Get repository stats (use || true to prevent pipefail exit)
      local repo_stats snapshot_count total_size
      repo_stats=$(RESTIC_PASSWORD="$restic_password" restic -r "$repo" stats --json 2>/dev/null || echo "{}")
      snapshot_count=$(RESTIC_PASSWORD="$restic_password" restic -r "$repo" snapshots --tag files --json 2>/dev/null | grep -c '"short_id"' || true)
      [[ -z "$snapshot_count" ]] && snapshot_count="0"
      total_size=$(echo "$repo_stats" | grep -o '"total_size":[0-9]*' | cut -d':' -f2 || true)
      total_size_human=$(numfmt --to=iec-i --suffix=B "$total_size" 2>/dev/null || echo "${total_size:-0}B")

      files_details="All data verified OK ($snapshot_count snapshots, $total_size_human, ${duration}s)"
      print_success "Files repository: $files_details"
    else
      files_result="FAILED"
      # Extract error from output (use || true to prevent pipefail exit)
      local error_msg
      error_msg=$(echo "$check_output" | grep -i "error\|fatal" | head -1 || true)
      files_details="${error_msg:-Full verification failed}"
      print_error "Files repository: $files_details"
      echo "$check_output" | head -20
    fi
  fi

  # Summary
  echo
  echo "============================================="
  echo "Verification Summary"
  echo "============================================="
  echo

  if [[ "$db_result" != "SKIPPED" ]]; then
    if [[ "$db_result" == "PASSED" ]]; then
      print_success "Database: PASSED - $db_details"
    else
      print_error "Database: FAILED - $db_details"
    fi
  fi

  if [[ "$files_result" != "SKIPPED" ]]; then
    if [[ "$files_result" == "PASSED" ]]; then
      print_success "Files: PASSED - $files_details"
    else
      print_error "Files: FAILED - $files_details"
    fi
  fi

  # Send notifications
  send_verify_notification "full" "$db_result" "$files_result" "$db_details" "$files_details"

  # Mark full verification as done if at least one type passed
  if [[ "$db_result" == "PASSED" || "$files_result" == "PASSED" ]]; then
    mark_full_verify_done
    echo
    print_info "Full verification timestamp recorded."
  fi

  # Return status
  if [[ "$db_result" == "FAILED" || "$files_result" == "FAILED" ]]; then
    return 1
  fi
  return 0
}

# ---------- Send Verification Notification ----------

send_verify_notification() {
  local verify_type="$1"  # "quick" or "full"
  local db_result="$2"
  local files_result="$3"
  local db_details="$4"
  local files_details="$5"

  local secrets_dir ntfy_url ntfy_token webhook_url webhook_token
  secrets_dir="$(get_secrets_dir)"
  ntfy_url="$(get_secret "$secrets_dir" ".c5" 2>/dev/null || echo "")"
  ntfy_token="$(get_secret "$secrets_dir" ".c4" 2>/dev/null || echo "")"
  webhook_url="$(get_secret "$secrets_dir" ".c6" 2>/dev/null || echo "")"
  webhook_token="$(get_secret "$secrets_dir" ".c7" 2>/dev/null || echo "")"

  local notification_title notification_body event_type
  local hostname
  hostname="$(hostname -f 2>/dev/null || hostname)"

  local check_type_label
  [[ "$verify_type" == "quick" ]] && check_type_label="Quick Check" || check_type_label="Full Verification"

  if [[ "$db_result" == "FAILED" || "$files_result" == "FAILED" ]]; then
    notification_title="$check_type_label FAILED on $hostname"
    event_type="${verify_type}_verify_failed"
  else
    notification_title="$check_type_label PASSED on $hostname"
    event_type="${verify_type}_verify_passed"
  fi

  notification_body="DB: $db_result${db_details:+ ($db_details)}, Files: $files_result${files_details:+ ($files_details)}"

  # Send ntfy notification
  if [[ -n "$ntfy_url" ]]; then
    if [[ -n "$ntfy_token" ]]; then
      curl -s -H "Authorization: Bearer $ntfy_token" -H "Title: $notification_title" -d "$notification_body" "$ntfy_url" -o /dev/null --max-time 10 || true
    else
      curl -s -H "Title: $notification_title" -d "$notification_body" "$ntfy_url" -o /dev/null --max-time 10 || true
    fi
  fi

  # Send webhook notification
  if [[ -n "$webhook_url" ]]; then
    local timestamp json_payload
    timestamp="$(date -Iseconds)"
    json_payload="{\"event\":\"$event_type\",\"title\":\"$notification_title\",\"hostname\":\"$hostname\",\"message\":\"$notification_body\",\"timestamp\":\"$timestamp\",\"details\":{\"db_result\":\"$db_result\",\"files_result\":\"$files_result\",\"verify_type\":\"$verify_type\"}}"
    if [[ -n "$webhook_token" ]]; then
      curl -s -X POST "$webhook_url" -H "Content-Type: application/json" -H "Authorization: Bearer $webhook_token" -d "$json_payload" -o /dev/null --max-time 10 || true
    else
      curl -s -X POST "$webhook_url" -H "Content-Type: application/json" -d "$json_payload" -o /dev/null --max-time 10 || true
    fi
  fi
}

# ---------- Full Verification Tracking ----------

check_full_verify_due() {
  if [[ ! -f "$LAST_FULL_VERIFY_FILE" ]]; then
    echo "never"
    return 0
  fi

  local last_verify_epoch current_epoch days_since
  last_verify_epoch=$(cat "$LAST_FULL_VERIFY_FILE" 2>/dev/null)
  current_epoch=$(date +%s)

  if [[ -z "$last_verify_epoch" ]] || ! [[ "$last_verify_epoch" =~ ^[0-9]+$ ]]; then
    echo "never"
    return 0
  fi

  days_since=$(( (current_epoch - last_verify_epoch) / 86400 ))
  echo "$days_since"
}

mark_full_verify_done() {
  date +%s > "$LAST_FULL_VERIFY_FILE"
  chmod 600 "$LAST_FULL_VERIFY_FILE" 2>/dev/null
}

show_full_verify_reminder() {
  local days_since
  days_since=$(check_full_verify_due)

  if [[ "$days_since" == "never" ]]; then
    echo
    print_warning "You have never performed a full backup verification!"
    echo "  A full verification downloads and verifies all backup data."
    echo "  This confirms your backups are actually restorable."
    echo
  elif [[ "$days_since" -ge "$FULL_VERIFY_INTERVAL_DAYS" ]]; then
    echo
    print_warning "Last full backup verification was $days_since days ago."
    echo "  Recommended: Run a full verification at least every 30 days."
    echo "  Quick checks only verify metadata, not actual data integrity."
    echo
  fi
}

# ---------- Verify Backup Integrity (Menu) ----------

verify_backup_integrity() {
  log_func_enter 2>/dev/null || true
  debug_enter "verify_backup_integrity" 2>/dev/null || true

  while true; do
    print_header
    echo "Verify Backup Integrity (Restic)"
    echo "================================="
    echo

    # Show reminder if full test is due
    show_full_verify_reminder

    echo "Verification Options:"
    echo
    echo -e "  ${CYAN}Quick Check${NC} (recommended for scheduled runs)"
    echo "  Verifies repository structure and index. No data download."
    echo "  Uses: restic check"
    echo
    echo -e "  ${CYAN}Full Verification${NC} (recommended monthly)"
    echo "  Downloads and verifies ALL backup data integrity."
    echo "  Uses: restic check --read-data"
    echo
    echo "1. Quick check - Database"
    echo "2. Quick check - Files"
    echo "3. Quick check - Both"
    echo "4. Full verification - Database (downloads all data)"
    echo "5. Full verification - Files (downloads all data)"
    echo "6. Full verification - Both (downloads all data)"
    echo "7. Back"
    echo
    read -p "Select option [1-7]: " verify_choice

    case "$verify_choice" in
      1)
        echo
        verify_quick "db"
        press_enter_to_continue
        ;;
      2)
        echo
        verify_quick "files"
        press_enter_to_continue
        ;;
      3)
        echo
        verify_quick "both"
        press_enter_to_continue
        ;;
      4)
        echo
        echo -e "${YELLOW}WARNING: Full verification will download ALL database backup data.${NC}"
        echo -e "${YELLOW}This may take a long time and use significant bandwidth.${NC}"
        echo
        read -p "Continue? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy] ]]; then
          verify_full "db"
        fi
        press_enter_to_continue
        ;;
      5)
        echo
        echo -e "${YELLOW}WARNING: Full verification will download ALL files backup data.${NC}"
        echo -e "${YELLOW}This may take a long time and use significant bandwidth.${NC}"
        echo
        read -p "Continue? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy] ]]; then
          verify_full "files"
        fi
        press_enter_to_continue
        ;;
      6)
        echo
        echo -e "${YELLOW}WARNING: Full verification will download ALL backup data (DB + Files).${NC}"
        echo -e "${YELLOW}This may take a very long time and use significant bandwidth.${NC}"
        echo
        read -p "Continue? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy] ]]; then
          verify_full "both"
        fi
        press_enter_to_continue
        ;;
      7|"")
        return
        ;;
      *)
        continue
        ;;
    esac
  done
}
