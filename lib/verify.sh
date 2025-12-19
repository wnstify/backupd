#!/usr/bin/env bash
# ============================================================================
# Backupd - Verify Module
# Backup integrity verification functions
# ============================================================================

# Last full verification tracking file
LAST_FULL_VERIFY_FILE="$INSTALL_DIR/.last_full_verify"
FULL_VERIFY_INTERVAL_DAYS=30

# ---------- Quick Verification (Checksum-only, no download) ----------

verify_quick() {
  local backup_type="$1"  # "db", "files", or "both"
  local secrets_dir rclone_remote rclone_db_path rclone_files_path
  secrets_dir="$(get_secrets_dir)"
  rclone_remote="$(get_config_value 'RCLONE_REMOTE')"
  rclone_db_path="$(get_config_value 'RCLONE_DB_PATH')"
  rclone_files_path="$(get_config_value 'RCLONE_FILES_PATH')"

  local db_result="SKIPPED" files_result="SKIPPED"
  local db_details="" files_details=""

  # Check database backups
  if [[ "$backup_type" == "db" || "$backup_type" == "both" ]] && [[ -n "$rclone_db_path" ]]; then
    echo "Checking database backups (quick)..."

    # Get latest backup
    local latest_db
    latest_db=$(rclone lsf "$rclone_remote:$rclone_db_path" --include "*-db_backups-*.tar.gz.gpg" 2>/dev/null | sort -r | head -1)

    if [[ -z "$latest_db" ]]; then
      db_result="FAILED"
      db_details="No backups found"
    else
      # Check if backup file exists with size
      local file_info
      file_info=$(rclone lsl "$rclone_remote:$rclone_db_path/$latest_db" 2>/dev/null)
      if [[ -n "$file_info" ]]; then
        local file_size
        file_size=$(echo "$file_info" | awk '{print $1}')

        # Check if checksum file exists
        local checksum_file="${latest_db}.sha256"
        if rclone lsf "$rclone_remote:$rclone_db_path/$checksum_file" &>/dev/null; then
          db_result="PASSED"
          db_details="$latest_db ($(numfmt --to=iec-i --suffix=B "$file_size" 2>/dev/null || echo "${file_size}B"))"
        else
          db_result="WARNING"
          db_details="$latest_db - no checksum file"
        fi
      else
        db_result="FAILED"
        db_details="Backup file not accessible"
      fi
    fi

    if [[ "$db_result" == "PASSED" ]]; then
      print_success "Database: OK - $db_details"
    elif [[ "$db_result" == "WARNING" ]]; then
      print_warning "Database: $db_details"
    else
      print_error "Database: $db_details"
    fi
  fi

  # Check files backups
  if [[ "$backup_type" == "files" || "$backup_type" == "both" ]] && [[ -n "$rclone_files_path" ]]; then
    echo "Checking files backups (quick)..."

    # Get latest backup
    local latest_files
    latest_files=$(rclone lsf "$rclone_remote:$rclone_files_path" --include "*.tar.gz" --exclude "*.sha256" 2>/dev/null | sort -r | head -1)

    if [[ -z "$latest_files" ]]; then
      files_result="FAILED"
      files_details="No backups found"
    else
      # Check if backup file exists with size
      local file_info
      file_info=$(rclone lsl "$rclone_remote:$rclone_files_path/$latest_files" 2>/dev/null)
      if [[ -n "$file_info" ]]; then
        local file_size
        file_size=$(echo "$file_info" | awk '{print $1}')

        # Check if checksum file exists
        local checksum_file="${latest_files}.sha256"
        if rclone lsf "$rclone_remote:$rclone_files_path/$checksum_file" &>/dev/null; then
          files_result="PASSED"
          files_details="$latest_files ($(numfmt --to=iec-i --suffix=B "$file_size" 2>/dev/null || echo "${file_size}B"))"
        else
          files_result="WARNING"
          files_details="$latest_files - no checksum file"
        fi
      else
        files_result="FAILED"
        files_details="Backup file not accessible"
      fi
    fi

    if [[ "$files_result" == "PASSED" ]]; then
      print_success "Files: OK - $files_details"
    elif [[ "$files_result" == "WARNING" ]]; then
      print_warning "Files: $files_details"
    else
      print_error "Files: $files_details"
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
  print_header
  echo "Verify Backup Integrity"
  echo "======================="
  echo

  # Show reminder if full test is due
  show_full_verify_reminder

  echo "Verification Options:"
  echo
  echo "  ${CYAN}Quick Check${NC} (recommended for scheduled runs)"
  echo "  Verifies backups exist with checksums. No download required."
  echo
  echo "  ${CYAN}Full Test${NC} (recommended monthly)"
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
      return
      ;;
    2)
      echo
      verify_quick "files"
      press_enter_to_continue
      return
      ;;
    3)
      echo
      verify_quick "both"
      press_enter_to_continue
      return
      ;;
    4) verify_choice="1" ;;  # Map to original full test options
    5) verify_choice="2" ;;
    6) verify_choice="3" ;;
    7|"") return ;;
    *) return ;;
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

  # Send notification
  local ntfy_url ntfy_token
  ntfy_url="$(get_secret "$secrets_dir" ".c5")"
  ntfy_token="$(get_secret "$secrets_dir" ".c4")"

  if [[ -n "$ntfy_url" ]]; then
    local notification_title notification_body

    if [[ "$db_result" == "FAILED" || "$files_result" == "FAILED" ]]; then
      notification_title="Backup Verification FAILED on $HOSTNAME"
      notification_body="DB: $db_result, Files: $files_result"
    else
      notification_title="Backup Verification PASSED on $HOSTNAME"
      notification_body="DB: $db_result, Files: $files_result"
    fi

    if [[ -n "$ntfy_token" ]]; then
      curl -s -H "Authorization: Bearer $ntfy_token" -H "Title: $notification_title" -d "$notification_body" "$ntfy_url" -o /dev/null --max-time 10 || true
    else
      curl -s -H "Title: $notification_title" -d "$notification_body" "$ntfy_url" -o /dev/null --max-time 10 || true
    fi
  fi

  # Mark full verification as done if at least one type passed
  if [[ "$db_result" == "PASSED" || "$files_result" == "PASSED" ]]; then
    mark_full_verify_done
    echo
    print_info "Full verification timestamp recorded."
  fi

  press_enter_to_continue
}
