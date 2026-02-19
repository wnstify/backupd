#!/usr/bin/env bash
# ============================================================================
# Backupd - Notifications Module
# Notification configuration and testing functions
# ============================================================================

# ---------- Manage Notifications ----------

manage_notifications() {
  log_func_enter
  debug_enter "manage_notifications"
  while true; do
    print_header
    echo "Notifications"
    echo "============="
    echo

    # Show current status
    show_notification_status_brief

    echo
    echo "Options:"
    echo "1. Configure ntfy"
    echo "2. Configure webhook"
    echo "3. Configure Pushover"
    echo "4. Test notifications"
    echo "5. View notification failures"
    echo "6. Disable all notifications"
    echo "0. Back to main menu"
    echo
    read -p "Select option [0-6]: " notif_choice

    case "$notif_choice" in
      1) configure_ntfy ;;
      2) configure_webhook ;;
      3) configure_pushover ;;
      4) test_notifications ;;
      5) view_notification_failures ;;
      6) disable_all_notifications ;;
      0) return ;;
      *) print_error "Invalid option" ; sleep 1 ;;
    esac
  done
}

# ---------- Show Notification Status ----------

show_notification_status_brief() {
  local secrets_dir ntfy_url webhook_url

  secrets_dir="$(get_secrets_dir)"

  if [[ -z "$secrets_dir" || ! -d "$secrets_dir" ]]; then
    print_warning "Notifications: NOT CONFIGURED (run setup first)"
    return
  fi

  echo "Current Configuration:"
  echo

  # Check ntfy
  ntfy_url="$(get_secret "$secrets_dir" "$SECRET_NTFY_URL" 2>/dev/null || echo "")"
  if [[ -n "$ntfy_url" ]]; then
    local ntfy_token
    ntfy_token="$(get_secret "$secrets_dir" "$SECRET_NTFY_TOKEN" 2>/dev/null || echo "")"
    if [[ -n "$ntfy_token" ]]; then
      print_success "ntfy: ${ntfy_url:0:40}... (with token)"
    else
      print_success "ntfy: ${ntfy_url:0:40}... (no token)"
    fi
  else
    echo -e "  ${YELLOW}ntfy: Not configured${NC}"
  fi

  # Check webhook
  webhook_url="$(get_secret "$secrets_dir" "$SECRET_WEBHOOK_URL" 2>/dev/null || echo "")"
  if [[ -n "$webhook_url" ]]; then
    local webhook_token
    webhook_token="$(get_secret "$secrets_dir" "$SECRET_WEBHOOK_TOKEN" 2>/dev/null || echo "")"
    if [[ -n "$webhook_token" ]]; then
      print_success "Webhook: ${webhook_url:0:40}... (with token)"
    else
      print_success "Webhook: ${webhook_url:0:40}... (no token)"
    fi
  else
    echo -e "  ${YELLOW}Webhook: Not configured${NC}"
  fi

  # Check Pushover
  local pushover_user pushover_token
  pushover_user="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_USER" 2>/dev/null || echo "")"
  if [[ -n "$pushover_user" ]]; then
    pushover_token="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_TOKEN" 2>/dev/null || echo "")"
    if [[ -n "$pushover_token" ]]; then
      print_success "Pushover: Configured (user key + API token)"
    else
      echo -e "  ${YELLOW}Pushover: User key set but missing API token${NC}"
    fi
  else
    echo -e "  ${YELLOW}Pushover: Not configured${NC}"
  fi

  # Check failure log
  local fail_log="$INSTALL_DIR/logs/notification_failures.log"
  if [[ -f "$fail_log" ]]; then
    local fail_count
    fail_count=$(wc -l < "$fail_log" 2>/dev/null || echo "0")
    if [[ "$fail_count" -gt 0 ]]; then
      print_warning "Failure log: $fail_count entries"
    fi
  fi
}

# ---------- Configure ntfy ----------

configure_ntfy() {
  log_func_enter 2>/dev/null || true
  debug_enter "configure_ntfy" 2>/dev/null || true
  print_header
  echo "Configure ntfy Notifications"
  echo "============================"
  echo

  local secrets_dir
  secrets_dir="$(get_secrets_dir)"

  if [[ -z "$secrets_dir" ]]; then
    print_error "Secure storage not initialized. Run setup first."
    press_enter_to_continue
    return
  fi

  # Show current config
  local current_url current_token
  current_url="$(get_secret "$secrets_dir" "$SECRET_NTFY_URL" 2>/dev/null || echo "")"
  current_token="$(get_secret "$secrets_dir" "$SECRET_NTFY_TOKEN" 2>/dev/null || echo "")"

  if [[ -n "$current_url" ]]; then
    echo "Current URL: $current_url"
    [[ -n "$current_token" ]] && echo "Token: configured" || echo "Token: not set"
    echo
  fi

  echo "Enter new ntfy topic URL (or press Enter to keep current):"
  echo "Example: https://ntfy.sh/your-topic"
  echo
  read -p "URL: " new_url

  if [[ -n "$new_url" ]]; then
    # Validate URL
    if ! validate_url "$new_url" "ntfy URL"; then
      print_error "Invalid URL. Must start with https://"
      press_enter_to_continue
      return
    fi
    store_secret "$secrets_dir" "$SECRET_NTFY_URL" "$new_url"
    print_success "ntfy URL saved"
  fi

  echo
  read -p "Configure/update access token? (y/N): " update_token
  if [[ "$update_token" =~ ^[Yy]$ ]]; then
    read -sp "Enter ntfy token (or press Enter to remove): " new_token
    echo
    if [[ -n "$new_token" ]]; then
      store_secret "$secrets_dir" "$SECRET_NTFY_TOKEN" "$new_token"
      print_success "ntfy token saved"
    else
      rm -f "$secrets_dir/$SECRET_NTFY_TOKEN" 2>/dev/null
      print_info "ntfy token removed"
    fi
  fi

  echo
  print_success "ntfy configuration updated"
  
  # Offer to regenerate scripts
  echo
  read -p "Regenerate backup scripts with new settings? (Y/n): " regen
  if [[ ! "$regen" =~ ^[Nn]$ ]]; then
    regenerate_scripts_silent
    print_success "Backup scripts regenerated"
  fi

  press_enter_to_continue
}

# ---------- Configure Webhook ----------

configure_webhook() {
  log_func_enter 2>/dev/null || true
  debug_enter "configure_webhook" 2>/dev/null || true
  print_header
  echo "Configure Webhook Notifications"
  echo "================================"
  echo

  local secrets_dir
  secrets_dir="$(get_secrets_dir)"

  if [[ -z "$secrets_dir" ]]; then
    print_error "Secure storage not initialized. Run setup first."
    press_enter_to_continue
    return
  fi

  # Show current config
  local current_url current_token
  current_url="$(get_secret "$secrets_dir" "$SECRET_WEBHOOK_URL" 2>/dev/null || echo "")"
  current_token="$(get_secret "$secrets_dir" "$SECRET_WEBHOOK_TOKEN" 2>/dev/null || echo "")"

  if [[ -n "$current_url" ]]; then
    echo "Current URL: $current_url"
    [[ -n "$current_token" ]] && echo "Token: configured" || echo "Token: not set"
    echo
  fi

  echo "Enter webhook URL (or press Enter to keep current):"
  echo "Receives JSON POST with: event, title, message, hostname, timestamp, details"
  echo "Example: https://n8n.example.com/webhook/backupd"
  echo
  read -p "URL: " new_url

  if [[ -n "$new_url" ]]; then
    # Validate URL
    if ! validate_url "$new_url" "webhook URL"; then
      print_error "Invalid URL. Must start with https://"
      press_enter_to_continue
      return
    fi
    store_secret "$secrets_dir" "$SECRET_WEBHOOK_URL" "$new_url"
    print_success "Webhook URL saved"
  fi

  echo
  read -p "Configure Bearer token? (most webhooks don't need this) (y/N): " update_token
  if [[ "$update_token" =~ ^[Yy]$ ]]; then
    read -sp "Enter Bearer token (or press Enter to remove): " new_token
    echo
    if [[ -n "$new_token" ]]; then
      store_secret "$secrets_dir" "$SECRET_WEBHOOK_TOKEN" "$new_token"
      print_success "Webhook token saved"
    else
      rm -f "$secrets_dir/$SECRET_WEBHOOK_TOKEN" 2>/dev/null
      print_info "Webhook token removed"
    fi
  fi

  echo
  print_success "Webhook configuration updated"

  # Offer to regenerate scripts
  echo
  read -p "Regenerate backup scripts with new settings? (Y/n): " regen
  if [[ ! "$regen" =~ ^[Nn]$ ]]; then
    regenerate_scripts_silent
    print_success "Backup scripts regenerated"
  fi

  press_enter_to_continue
}

# ---------- Configure Pushover ----------

configure_pushover() {
  log_func_enter 2>/dev/null || true
  debug_enter "configure_pushover" 2>/dev/null || true
  print_header
  echo "Configure Pushover Notifications"
  echo "================================="
  echo
  echo "Pushover sends notifications to iOS/Android devices."
  echo "Get your credentials at: https://pushover.net"
  echo

  local secrets_dir
  secrets_dir="$(get_secrets_dir)"

  if [[ -z "$secrets_dir" ]]; then
    print_error "Secure storage not initialized. Run setup first."
    press_enter_to_continue
    return
  fi

  # Show current config
  local current_user current_token
  current_user="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_USER" 2>/dev/null || echo "")"
  current_token="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_TOKEN" 2>/dev/null || echo "")"

  if [[ -n "$current_user" ]]; then
    echo "Current User Key: ${current_user:0:8}...${current_user: -4} (masked)"
    [[ -n "$current_token" ]] && echo "API Token: configured" || echo "API Token: not set"
    echo
  fi

  echo "Enter your Pushover User Key (or press Enter to keep current):"
  echo "Found at: https://pushover.net (after login, look for 'Your User Key')"
  echo
  read -p "User Key: " new_user

  if [[ -n "$new_user" ]]; then
    # Validate format (30 alphanumeric characters)
    if [[ ! "$new_user" =~ ^[A-Za-z0-9]{30}$ ]]; then
      print_error "Invalid user key format. Must be 30 alphanumeric characters."
      press_enter_to_continue
      return
    fi
    store_secret "$secrets_dir" "$SECRET_PUSHOVER_USER" "$new_user"
    print_success "Pushover user key saved"
  fi

  echo
  echo "Enter your Pushover API Token (or press Enter to keep current):"
  echo "Create an application at: https://pushover.net/apps/build"
  echo
  read -sp "API Token: " new_token
  echo

  if [[ -n "$new_token" ]]; then
    # Validate format (30 alphanumeric characters)
    if [[ ! "$new_token" =~ ^[A-Za-z0-9]{30}$ ]]; then
      print_error "Invalid API token format. Must be 30 alphanumeric characters."
      press_enter_to_continue
      return
    fi
    store_secret "$secrets_dir" "$SECRET_PUSHOVER_TOKEN" "$new_token"
    print_success "Pushover API token saved"
  fi

  # Check if both are now configured
  current_user="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_USER" 2>/dev/null || echo "")"
  current_token="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_TOKEN" 2>/dev/null || echo "")"

  echo
  if [[ -n "$current_user" && -n "$current_token" ]]; then
    print_success "Pushover configuration complete"

    # Offer to test
    echo
    read -p "Send a test notification now? (Y/n): " test_now
    if [[ ! "$test_now" =~ ^[Nn]$ ]]; then
      test_pushover_notification "$current_user" "$current_token"
    fi
  else
    print_warning "Pushover not fully configured. Both user key and API token are required."
  fi

  # Offer to regenerate scripts
  if [[ -n "$current_user" && -n "$current_token" ]]; then
    echo
    read -p "Regenerate backup scripts with new settings? (Y/n): " regen
    if [[ ! "$regen" =~ ^[Nn]$ ]]; then
      regenerate_scripts_silent
      print_success "Backup scripts regenerated"
    fi
  fi

  press_enter_to_continue
}

# ---------- Test Pushover Notification ----------

test_pushover_notification() {
  local user_key="$1"
  local api_token="$2"
  local hostname timestamp http_code response

  hostname="$(hostname -f 2>/dev/null || hostname)"
  timestamp="$(date -Iseconds)"

  echo -n "Sending test notification to Pushover... "

  response=$(timeout 15 curl -s -w "\n%{http_code}" \
    --form-string "token=$api_token" \
    --form-string "user=$user_key" \
    --form-string "title=Backupd Test on $hostname" \
    --form-string "message=Test notification sent at $timestamp" \
    --form-string "priority=0" \
    --form-string "sound=pushover" \
    https://api.pushover.net/1/messages.json 2>/dev/null) || response="000"

  http_code=$(echo "$response" | tail -1)
  local body=$(echo "$response" | sed '$d')

  if [[ "$http_code" == "200" ]]; then
    echo -e "${GREEN}OK (HTTP $http_code)${NC}"
    return 0
  else
    echo -e "${RED}FAILED (HTTP $http_code)${NC}"
    # Try to extract error message
    if command -v jq &>/dev/null && [[ -n "$body" ]]; then
      local errors=$(echo "$body" | jq -r '.errors[]?' 2>/dev/null)
      [[ -n "$errors" ]] && echo "  Error: $errors"
    fi
    return 1
  fi
}

# ---------- Test Notifications ----------

test_notifications() {
  log_func_enter
  debug_enter "test_notifications"
  log_info "Testing notifications"
  print_header
  echo "Test Notifications"
  echo "=================="
  echo

  local secrets_dir
  secrets_dir="$(get_secrets_dir)"

  if [[ -z "$secrets_dir" ]]; then
    print_error "Secure storage not initialized. Run setup first."
    press_enter_to_continue
    return
  fi

  local ntfy_url ntfy_token webhook_url webhook_token pushover_user pushover_token
  ntfy_url="$(get_secret "$secrets_dir" "$SECRET_NTFY_URL" 2>/dev/null || echo "")"
  ntfy_token="$(get_secret "$secrets_dir" "$SECRET_NTFY_TOKEN" 2>/dev/null || echo "")"
  webhook_url="$(get_secret "$secrets_dir" "$SECRET_WEBHOOK_URL" 2>/dev/null || echo "")"
  webhook_token="$(get_secret "$secrets_dir" "$SECRET_WEBHOOK_TOKEN" 2>/dev/null || echo "")"
  pushover_user="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_USER" 2>/dev/null || echo "")"
  pushover_token="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_TOKEN" 2>/dev/null || echo "")"

  if [[ -z "$ntfy_url" && -z "$webhook_url" && ( -z "$pushover_user" || -z "$pushover_token" ) ]]; then
    print_warning "No notification channels configured."
    echo
    echo "Configure ntfy, webhook, or Pushover first."
    press_enter_to_continue
    return
  fi

  local hostname timestamp
  hostname="$(hostname -f 2>/dev/null || hostname)"
  timestamp="$(date -Iseconds)"

  echo "Sending test notifications..."
  echo

  local ntfy_ok=0 webhook_ok=0

  # Test ntfy
  if [[ -n "$ntfy_url" ]]; then
    echo -n "Testing ntfy... "
    local http_code
    if [[ -n "$ntfy_token" ]]; then
      http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $ntfy_token" \
        -H "Title: Backupd Test on $hostname" \
        -H "Tags: test_tube" \
        -d "Test notification sent at $timestamp" \
        "$ntfy_url" 2>/dev/null) || http_code="000"
    else
      http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
        -H "Title: Backupd Test on $hostname" \
        -H "Tags: test_tube" \
        -d "Test notification sent at $timestamp" \
        "$ntfy_url" 2>/dev/null) || http_code="000"
    fi

    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
      echo -e "${GREEN}OK (HTTP $http_code)${NC}"
      ntfy_ok=1
    else
      echo -e "${RED}FAILED (HTTP $http_code)${NC}"
    fi
  else
    echo "ntfy: not configured (skipped)"
  fi

  # Test webhook
  if [[ -n "$webhook_url" ]]; then
    echo -n "Testing webhook... "
    local json_payload http_code
    json_payload="{\"event\":\"test\",\"title\":\"Backupd Test on $hostname\",\"hostname\":\"$hostname\",\"message\":\"Test notification sent at $timestamp\",\"timestamp\":\"$timestamp\",\"details\":{}}"

    if [[ -n "$webhook_token" ]]; then
      http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$webhook_url" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $webhook_token" \
        -d "$json_payload" 2>/dev/null) || http_code="000"
    else
      http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$webhook_url" \
        -H "Content-Type: application/json" \
        -d "$json_payload" 2>/dev/null) || http_code="000"
    fi

    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
      echo -e "${GREEN}OK (HTTP $http_code)${NC}"
      webhook_ok=1
    else
      echo -e "${RED}FAILED (HTTP $http_code)${NC}"
    fi
  else
    echo "Webhook: not configured (skipped)"
  fi

  # Test Pushover
  local pushover_ok=0
  if [[ -n "$pushover_user" && -n "$pushover_token" ]]; then
    echo -n "Testing Pushover... "
    local response http_code
    response=$(timeout 15 curl -s -w "\n%{http_code}" \
      --form-string "token=$pushover_token" \
      --form-string "user=$pushover_user" \
      --form-string "title=Backupd Test on $hostname" \
      --form-string "message=Test notification sent at $timestamp" \
      --form-string "priority=0" \
      --form-string "sound=pushover" \
      https://api.pushover.net/1/messages.json 2>/dev/null) || response="000"

    http_code=$(echo "$response" | tail -1)

    if [[ "$http_code" == "200" ]]; then
      echo -e "${GREEN}OK (HTTP $http_code)${NC}"
      pushover_ok=1
    else
      echo -e "${RED}FAILED (HTTP $http_code)${NC}"
    fi
  else
    echo "Pushover: not configured (skipped)"
  fi

  echo
  if [[ $ntfy_ok -eq 1 || $webhook_ok -eq 1 || $pushover_ok -eq 1 ]]; then
    print_success "Test complete! Check your notification channels."
  else
    print_error "All notification tests failed. Check your configuration."
  fi

  press_enter_to_continue
}

# ---------- View Notification Failures ----------

view_notification_failures() {
  print_header
  echo "Notification Failure Log"
  echo "========================"
  echo

  local fail_log="$INSTALL_DIR/logs/notification_failures.log"

  if [[ ! -f "$fail_log" ]]; then
    print_success "No notification failures recorded!"
    echo
    echo "This log is created when notifications fail to send."
    press_enter_to_continue
    return
  fi

  local line_count
  line_count=$(wc -l < "$fail_log" 2>/dev/null || echo "0")

  if [[ "$line_count" -eq 0 ]]; then
    print_success "Notification failure log is empty."
    press_enter_to_continue
    return
  fi

  echo "Found $line_count failure entries:"
  echo
  echo "1. View last 20 entries"
  echo "2. View all entries"
  echo "3. Clear failure log"
  echo "0. Back"
  echo
  read -p "Select option [0-3]: " log_choice

  case "$log_choice" in
    1)
      echo
      tail -20 "$fail_log"
      press_enter_to_continue
      ;;
    2)
      less "$fail_log"
      ;;
    3)
      read -p "Clear notification failure log? (y/N): " confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # shellcheck disable=SC2188  # Intentional: truncate file using redirection
        > "$fail_log"
        print_success "Notification failure log cleared"
      fi
      press_enter_to_continue
      ;;
    0|*)
      return
      ;;
  esac
}

# ---------- Disable All Notifications ----------

disable_all_notifications() {
  print_header
  echo "Disable All Notifications"
  echo "========================="
  echo

  local secrets_dir
  secrets_dir="$(get_secrets_dir)"

  if [[ -z "$secrets_dir" ]]; then
    print_error "Secure storage not initialized."
    press_enter_to_continue
    return
  fi

  echo -e "${YELLOW}WARNING: This will remove all notification configuration.${NC}"
  echo
  echo "You will NOT receive alerts for:"
  echo "  - Backup successes"
  echo "  - Backup failures"
  echo "  - Verification results"
  echo "  - Any other backup events"
  echo
  read -p "Are you sure? Type 'DISABLE' to confirm: " confirm

  if [[ "$confirm" == "DISABLE" ]]; then
    rm -f "$secrets_dir/$SECRET_NTFY_URL" 2>/dev/null
    rm -f "$secrets_dir/$SECRET_NTFY_TOKEN" 2>/dev/null
    rm -f "$secrets_dir/$SECRET_WEBHOOK_URL" 2>/dev/null
    rm -f "$secrets_dir/$SECRET_WEBHOOK_TOKEN" 2>/dev/null
    rm -f "$secrets_dir/$SECRET_PUSHOVER_USER" 2>/dev/null
    rm -f "$secrets_dir/$SECRET_PUSHOVER_TOKEN" 2>/dev/null

    # Regenerate scripts
    regenerate_scripts_silent

    echo
    print_warning "All notifications disabled"
    echo
    echo "To re-enable, configure ntfy or webhook from this menu."
  else
    echo
    print_info "Cancelled. Notifications remain enabled."
  fi

  press_enter_to_continue
}

# ---------- Helper: Regenerate Scripts Silently ----------

regenerate_scripts_silent() {
  local secrets_dir rclone_remote rclone_db_path rclone_files_path retention_days
  local web_path_pattern webroot_subdir do_database do_files

  secrets_dir="$(get_secrets_dir)"
  rclone_remote="$(get_config_value 'RCLONE_REMOTE')"
  rclone_db_path="$(get_config_value 'RCLONE_DB_PATH')"
  rclone_files_path="$(get_config_value 'RCLONE_FILES_PATH')"
  retention_days="$(get_config_value 'RETENTION_DAYS')"
  web_path_pattern="$(get_config_value 'WEB_PATH_PATTERN')"
  webroot_subdir="$(get_config_value 'WEBROOT_SUBDIR')"
  do_database="$(get_config_value 'DO_DATABASE')"
  do_files="$(get_config_value 'DO_FILES')"

  # Only regenerate if we have the minimum config
  if [[ -n "$secrets_dir" && -n "$rclone_remote" ]]; then
    generate_all_scripts "$secrets_dir" "$do_database" "$do_files" "$rclone_remote" \
      "$rclone_db_path" "$rclone_files_path" "${retention_days:-30}" \
      "${web_path_pattern:-/var/www/*}" "${webroot_subdir:-.}" 2>/dev/null

    # Also regenerate verify scripts if they exist
    if [[ -f "$SCRIPTS_DIR/verify_backup.sh" ]]; then
      generate_verify_script 2>/dev/null
    fi
    if [[ -f "$SCRIPTS_DIR/verify_full_backup.sh" ]]; then
      generate_full_verify_script 2>/dev/null
    fi
  fi
}
