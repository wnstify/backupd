#!/usr/bin/env bash
# ============================================================================
# Backupd - Verify Module
# Backup integrity verification functions
# ============================================================================

# Last full verification tracking file
LAST_FULL_VERIFY_FILE="$INSTALL_DIR/.last_full_verify"
FULL_VERIFY_INTERVAL_DAYS=30

# ---------- Quick Verification (Checksum-only, no download) ----------
# Optimized: Uses only 1 API call per backup type (lists all files at once)

verify_quick() {
  log_func_enter
  debug_enter "verify_quick" "$1"
  local backup_type="$1"  # "db", "files", or "both"
  local secrets_dir rclone_remote rclone_db_path rclone_files_path
  secrets_dir="$(get_secrets_dir)"
  rclone_remote="$(get_config_value 'RCLONE_REMOTE')"
  rclone_db_path="$(get_config_value 'RCLONE_DB_PATH')"
  rclone_files_path="$(get_config_value 'RCLONE_FILES_PATH')"

  local db_result="SKIPPED" files_result="SKIPPED"
  local db_details="" files_details=""

  # Helper to format size
  format_size() {
    numfmt --to=iec-i --suffix=B "$1" 2>/dev/null || echo "${1}B"
  }

  # Check ALL database backups (single API call)
  if [[ "$backup_type" == "db" || "$backup_type" == "both" ]] && [[ -n "$rclone_db_path" ]]; then
    echo "Checking database backups (quick)..."

    local db_total=0 db_with_checksum=0 db_without_checksum=0 db_total_size=0
    declare -A checksum_files=()

    # Single API call: get all files with sizes
    local all_files
    all_files=$(rclone lsl "$rclone_remote:$rclone_db_path" 2>/dev/null)

    # Build set of checksum files and process backups
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local size filename
      size=$(echo "$line" | awk '{print $1}')
      filename=$(echo "$line" | awk '{print $NF}')

      if [[ "$filename" == *.sha256 ]]; then
        checksum_files["$filename"]=1
      elif [[ "$filename" == *-db_backups-*.tar.gz.gpg ]]; then
        ((db_total++)) || true
        db_total_size=$((db_total_size + size))

        if [[ -n "${checksum_files[${filename}.sha256]:-}" ]]; then
          ((db_with_checksum++)) || true
        else
          # Check if checksum exists (might come later in list)
          :
        fi
      fi
    done <<< "$all_files"

    # Second pass: check which backups have checksums
    db_with_checksum=0
    db_without_checksum=0
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local filename
      filename=$(echo "$line" | awk '{print $NF}')

      if [[ "$filename" == *-db_backups-*.tar.gz.gpg ]]; then
        if [[ -n "${checksum_files[${filename}.sha256]:-}" ]]; then
          ((db_with_checksum++)) || true
        else
          ((db_without_checksum++)) || true
          echo "  Missing checksum: $filename"
        fi
      fi
    done <<< "$all_files"

    if [[ $db_total -eq 0 ]]; then
      db_result="FAILED"
      db_details="No backups found"
    elif [[ $db_without_checksum -gt 0 ]]; then
      db_result="WARNING"
      db_details="$db_total backups ($(format_size "$db_total_size")), $db_without_checksum missing checksums"
    else
      db_result="PASSED"
      db_details="$db_total backups ($(format_size "$db_total_size")), all have checksums"
    fi

    if [[ "$db_result" == "PASSED" ]]; then
      print_success "Database: $db_details"
    elif [[ "$db_result" == "WARNING" ]]; then
      print_warning "Database: $db_details"
    else
      print_error "Database: $db_details"
    fi
  fi

  # Check ALL files backups (single API call)
  if [[ "$backup_type" == "files" || "$backup_type" == "both" ]] && [[ -n "$rclone_files_path" ]]; then
    echo "Checking files backups (quick)..."

    local files_total=0 files_with_checksum=0 files_without_checksum=0 files_total_size=0
    declare -A checksum_files=()

    # Single API call: get all files with sizes
    local all_files
    all_files=$(rclone lsl "$rclone_remote:$rclone_files_path" 2>/dev/null)

    # First pass: build checksum set and count backups
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local size filename
      size=$(echo "$line" | awk '{print $1}')
      filename=$(echo "$line" | awk '{print $NF}')

      if [[ "$filename" == *.sha256 ]]; then
        checksum_files["$filename"]=1
      elif [[ "$filename" == *.tar.gz ]] && [[ "$filename" != *.sha256 ]]; then
        ((files_total++)) || true
        files_total_size=$((files_total_size + size))
      fi
    done <<< "$all_files"

    # Second pass: check which backups have checksums
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local filename
      filename=$(echo "$line" | awk '{print $NF}')

      if [[ "$filename" == *.tar.gz ]] && [[ "$filename" != *.sha256 ]]; then
        if [[ -n "${checksum_files[${filename}.sha256]:-}" ]]; then
          ((files_with_checksum++)) || true
        else
          ((files_without_checksum++)) || true
          echo "  Missing checksum: $filename"
        fi
      fi
    done <<< "$all_files"

    if [[ $files_total -eq 0 ]]; then
      files_result="FAILED"
      files_details="No backups found"
    elif [[ $files_without_checksum -gt 0 ]]; then
      files_result="WARNING"
      files_details="$files_total backups ($(format_size "$files_total_size")), $files_without_checksum missing checksums"
    else
      files_result="PASSED"
      files_details="$files_total backups ($(format_size "$files_total_size")), all have checksums"
    fi

    if [[ "$files_result" == "PASSED" ]]; then
      print_success "Files: $files_details"
    elif [[ "$files_result" == "WARNING" ]]; then
      print_warning "Files: $files_details"
    else
      print_error "Files: $files_details"
    fi
  fi

  # Send notification (ntfy + webhook)
  local secrets_dir ntfy_url ntfy_token webhook_url webhook_token
  secrets_dir="$(get_secrets_dir)"
  ntfy_url="$(get_secret "$secrets_dir" ".c5" 2>/dev/null || echo "")"
  ntfy_token="$(get_secret "$secrets_dir" ".c4" 2>/dev/null || echo "")"
  webhook_url="$(get_secret "$secrets_dir" ".c6" 2>/dev/null || echo "")"
  webhook_token="$(get_secret "$secrets_dir" ".c7" 2>/dev/null || echo "")"

  local notification_title notification_body event_type
  local hostname
  hostname="$(hostname -f 2>/dev/null || hostname)"

  if [[ "$db_result" == "FAILED" || "$files_result" == "FAILED" ]]; then
    notification_title="Quick Check FAILED on $hostname"
    event_type="verify_failed"
  elif [[ "$db_result" == "WARNING" || "$files_result" == "WARNING" ]]; then
    notification_title="Quick Check WARNING on $hostname"
    event_type="verify_warning"
  else
    notification_title="Quick Check PASSED on $hostname"
    event_type="verify_passed"
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
    json_payload="{\"event\":\"$event_type\",\"title\":\"$notification_title\",\"hostname\":\"$hostname\",\"message\":\"$notification_body\",\"timestamp\":\"$timestamp\",\"details\":{\"db_result\":\"$db_result\",\"files_result\":\"$files_result\"}}"
    if [[ -n "$webhook_token" ]]; then
      curl -s -X POST "$webhook_url" -H "Content-Type: application/json" -H "Authorization: Bearer $webhook_token" -d "$json_payload" -o /dev/null --max-time 10 || true
    else
      curl -s -X POST "$webhook_url" -H "Content-Type: application/json" -d "$json_payload" -o /dev/null --max-time 10 || true
    fi
  fi

  # Return status
  if [[ "$db_result" == "FAILED" || "$files_result" == "FAILED" ]]; then
    return 1
  elif [[ "$db_result" == "WARNING" || "$files_result" == "WARNING" ]]; then
    return 2
  fi
  return 0
}

# ---------- Check if full verification is due ----------

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

# Mark full verification as completed
mark_full_verify_done() {
  date +%s > "$LAST_FULL_VERIFY_FILE"
  chmod 600 "$LAST_FULL_VERIFY_FILE" 2>/dev/null
}

# Show reminder if full test is due
show_full_verify_reminder() {
  local days_since
  days_since=$(check_full_verify_due)

  if [[ "$days_since" == "never" ]]; then
    echo
    print_warning "You have never performed a full backup test!"
    echo "  A full test downloads and verifies backup decryption/contents."
    echo "  This confirms your backups are actually restorable."
    echo
  elif [[ "$days_since" -ge "$FULL_VERIFY_INTERVAL_DAYS" ]]; then
    echo
    print_warning "Last full backup test was $days_since days ago."
    echo "  Recommended: Run a full verification test at least every 30 days."
    echo "  Quick checks only verify files exist, not that they're valid."
    echo
  fi
}

# ---------- Verify Backup Integrity (Menu) ----------

verify_backup_integrity() {
  log_func_enter
  debug_enter "verify_backup_integrity"
  while true; do
    print_header
    echo "Verify Backup Integrity"
    echo "======================="
    echo

    # Show reminder if full test is due
    show_full_verify_reminder

    echo "Verification Options:"
    echo
    echo -e "  ${CYAN}Quick Check${NC} (recommended for scheduled runs)"
    echo "  Verifies backups exist with checksums. No download required."
    echo
    echo -e "  ${CYAN}Full Test${NC} (recommended monthly)"
    echo "  Downloads and fully verifies backup decryption and contents."
    echo
    echo "1. Quick check - Database"
    echo "2. Quick check - Files"
    echo "3. Quick check - Both"
    echo "4. Full test - Database (downloads backup)"
    echo "5. Full test - Files (downloads backup)"
    echo "6. Full test - Both (downloads backups)"
    echo "7. Back"
    echo
    read -p "Select option [1-7]: " verify_choice

    case "$verify_choice" in
      1)
        echo
        verify_quick "db"
        press_enter_to_continue
        continue
        ;;
      2)
        echo
        verify_quick "files"
        press_enter_to_continue
        continue
        ;;
      3)
        echo
        verify_quick "both"
        press_enter_to_continue
        continue
        ;;
      4) verify_choice="1" ;;  # Map to original full test options
      5) verify_choice="2" ;;
      6) verify_choice="3" ;;
      7|"") return ;;
      *) continue ;;
    esac

  # Continue with full verification (original logic below)

  local secrets_dir rclone_remote rclone_db_path rclone_files_path
  secrets_dir="$(get_secrets_dir)"
  rclone_remote="$(get_config_value 'RCLONE_REMOTE')"
  rclone_db_path="$(get_config_value 'RCLONE_DB_PATH')"
  rclone_files_path="$(get_config_value 'RCLONE_FILES_PATH')"

  local db_result="SKIPPED" files_result="SKIPPED"
  local db_details="" files_details=""

  # Create temp directory
  local temp_dir
  temp_dir=$(mktemp -d)
  trap "rm -rf '$temp_dir'" RETURN

  # Verify database backup
  if [[ "$verify_choice" == "1" || "$verify_choice" == "3" ]]; then
    echo
    echo "═══════════════════════════════════════"
    echo "Verifying Database Backup"
    echo "═══════════════════════════════════════"
    echo

    # Get latest DB backup
    echo "Fetching latest database backup..."
    local latest_db
    latest_db=$(rclone lsf "$rclone_remote:$rclone_db_path" --include "*-db_backups-*.tar.gz.gpg" 2>/dev/null | sort -r | head -1)

    if [[ -z "$latest_db" ]]; then
      print_error "No database backups found"
      db_result="FAILED"
      db_details="No backups found"
    else
      echo "Latest backup: $latest_db"

      # Download backup
      echo "Downloading backup..."
      if ! rclone copy "$rclone_remote:$rclone_db_path/$latest_db" "$temp_dir/" --progress; then
        print_error "Download failed"
        db_result="FAILED"
        db_details="Download failed"
      else
        # Download checksum if exists
        local checksum_file="${latest_db}.sha256"
        rclone copy "$rclone_remote:$rclone_db_path/$checksum_file" "$temp_dir/" 2>/dev/null

        # Verify checksum
        if [[ -f "$temp_dir/$checksum_file" ]]; then
          echo "Verifying checksum..."
          local stored_checksum calculated_checksum
          stored_checksum=$(cat "$temp_dir/$checksum_file")
          calculated_checksum=$(sha256sum "$temp_dir/$latest_db" | awk '{print $1}')

          if [[ "$stored_checksum" == "$calculated_checksum" ]]; then
            print_success "Checksum verified"
          else
            print_error "Checksum mismatch!"
            echo "  Expected: $stored_checksum"
            echo "  Got:      $calculated_checksum"
            db_result="FAILED"
            db_details="Checksum mismatch"
          fi
        else
          print_warning "No checksum file found (backup may predate checksum feature)"
        fi

        # Test decryption if checksum passed or no checksum
        if [[ "$db_result" != "FAILED" ]]; then
          echo "Testing decryption..."
          echo
          read -s -p "Enter encryption password: " passphrase
          echo

          if gpg --batch --quiet --pinentry-mode=loopback --passphrase "$passphrase" -d "$temp_dir/$latest_db" 2>/dev/null | tar -tzf - >/dev/null 2>&1; then
            print_success "Decryption and archive verified"

            # List contents
            echo
            echo "Archive contents:"
            gpg --batch --quiet --pinentry-mode=loopback --passphrase "$passphrase" -d "$temp_dir/$latest_db" 2>/dev/null | tar -tzf - 2>/dev/null | head -20
            local file_count
            file_count=$(gpg --batch --quiet --pinentry-mode=loopback --passphrase "$passphrase" -d "$temp_dir/$latest_db" 2>/dev/null | tar -tzf - 2>/dev/null | wc -l)
            echo "... ($file_count files total)"

            db_result="PASSED"
            db_details="$latest_db - $file_count files"
          else
            print_error "Decryption or archive verification failed"
            db_result="FAILED"
            db_details="Decryption failed - wrong password?"
          fi
        fi
      fi
    fi
  fi

  # Verify files backup
  if [[ "$verify_choice" == "2" || "$verify_choice" == "3" ]]; then
    echo
    echo "═══════════════════════════════════════"
    echo "Verifying Files Backup"
    echo "═══════════════════════════════════════"
    echo

    # Get latest files backup
    echo "Fetching latest files backup..."
    local latest_files
    latest_files=$(rclone lsf "$rclone_remote:$rclone_files_path" --include "*.tar.gz" --exclude "*.sha256" 2>/dev/null | sort -r | head -1)

    if [[ -z "$latest_files" ]]; then
      print_error "No files backups found"
      files_result="FAILED"
      files_details="No backups found"
    else
      echo "Latest backup: $latest_files"

      # Download backup
      echo "Downloading backup..."
      if ! rclone copy "$rclone_remote:$rclone_files_path/$latest_files" "$temp_dir/" --progress; then
        print_error "Download failed"
        files_result="FAILED"
        files_details="Download failed"
      else
        # Download checksum if exists
        local checksum_file="${latest_files}.sha256"
        rclone copy "$rclone_remote:$rclone_files_path/$checksum_file" "$temp_dir/" 2>/dev/null

        # Verify checksum
        if [[ -f "$temp_dir/$checksum_file" ]]; then
          echo "Verifying checksum..."
          local stored_checksum calculated_checksum
          stored_checksum=$(cat "$temp_dir/$checksum_file")
          calculated_checksum=$(sha256sum "$temp_dir/$latest_files" | awk '{print $1}')

          if [[ "$stored_checksum" == "$calculated_checksum" ]]; then
            print_success "Checksum verified"
          else
            print_error "Checksum mismatch!"
            echo "  Expected: $stored_checksum"
            echo "  Got:      $calculated_checksum"
            files_result="FAILED"
            files_details="Checksum mismatch"
          fi
        else
          print_warning "No checksum file found (backup may predate checksum feature)"
        fi

        # Test archive integrity if checksum passed or no checksum
        if [[ "$files_result" != "FAILED" ]]; then
          echo "Testing archive integrity..."

          if tar -tzf "$temp_dir/$latest_files" >/dev/null 2>&1; then
            print_success "Archive verified"

            # List contents (|| true to prevent SIGPIPE exit with pipefail)
            echo
            echo "Archive contents:"
            tar -tzf "$temp_dir/$latest_files" 2>/dev/null | head -20 || true
            local file_count
            file_count=$(tar -tzf "$temp_dir/$latest_files" 2>/dev/null | wc -l) || file_count=0
            echo "... ($file_count files total)"

            files_result="PASSED"
            files_details="$latest_files - $file_count files"
          else
            print_error "Archive verification failed - file may be corrupted"
            files_result="FAILED"
            files_details="Archive corrupted"
          fi
        fi
      fi
    fi
  fi

  # Summary
  echo
  echo "═══════════════════════════════════════"
  echo "Verification Summary"
  echo "═══════════════════════════════════════"
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

  # Send notification (ntfy + webhook)
  local ntfy_url ntfy_token webhook_url webhook_token
  ntfy_url="$(get_secret "$secrets_dir" ".c5" 2>/dev/null || echo "")"
  ntfy_token="$(get_secret "$secrets_dir" ".c4" 2>/dev/null || echo "")"
  webhook_url="$(get_secret "$secrets_dir" ".c6" 2>/dev/null || echo "")"
  webhook_token="$(get_secret "$secrets_dir" ".c7" 2>/dev/null || echo "")"

  local notification_title notification_body event_type

  if [[ "$db_result" == "FAILED" || "$files_result" == "FAILED" ]]; then
    notification_title="Backup Verification FAILED on $HOSTNAME"
    notification_body="DB: $db_result, Files: $files_result"
    event_type="full_verify_failed"
  else
    notification_title="Backup Verification PASSED on $HOSTNAME"
    notification_body="DB: $db_result, Files: $files_result"
    event_type="full_verify_passed"
  fi

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
    json_payload="{\"event\":\"$event_type\",\"title\":\"$notification_title\",\"hostname\":\"$HOSTNAME\",\"message\":\"$notification_body\",\"timestamp\":\"$timestamp\",\"details\":{\"db_result\":\"$db_result\",\"files_result\":\"$files_result\"}}"
    if [[ -n "$webhook_token" ]]; then
      curl -s -X POST "$webhook_url" -H "Content-Type: application/json" -H "Authorization: Bearer $webhook_token" -d "$json_payload" -o /dev/null --max-time 10 || true
    else
      curl -s -X POST "$webhook_url" -H "Content-Type: application/json" -d "$json_payload" -o /dev/null --max-time 10 || true
    fi
  fi

  # Mark full verification as done if at least one type passed
  if [[ "$db_result" == "PASSED" || "$files_result" == "PASSED" ]]; then
    mark_full_verify_done
    echo
    print_info "Full verification timestamp recorded."
  fi

  press_enter_to_continue
  done  # End of while loop
}
