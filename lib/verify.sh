#!/usr/bin/env bash
# ============================================================================
# Backupd - Verify Module
# Backup integrity verification functions
# ============================================================================

# ---------- Verify Backup Integrity ----------

verify_backup_integrity() {
  print_header
  echo "Verify Backup Integrity"
  echo "======================="
  echo
  echo "This will download and verify backups without restoring them."
  echo "It checks: checksum, decryption, and archive contents."
  echo
  echo "1. Verify database backup"
  echo "2. Verify files backup"
  echo "3. Verify both"
  echo "4. Back"
  echo
  read -p "Select option [1-4]: " verify_choice

  [[ "$verify_choice" == "4" || -z "$verify_choice" ]] && return

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

  press_enter_to_continue
}
