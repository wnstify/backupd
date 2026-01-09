# Pushover Implementation Plan for Backupd

**Version:** 1.0.0
**Date:** 2026-01-06
**Author:** Chief Architect (Agentic Substrate)
**Status:** Ready for Implementation

---

## Executive Summary

This document provides a comprehensive implementation plan for adding Pushover as the third notification channel in backupd, alongside ntfy and webhooks. The implementation follows existing patterns established in the codebase to ensure consistency and maintainability.

---

## 1. ResearchPack: Pushover API

### 1.1 API Endpoint

```
URL: https://api.pushover.net/1/messages.json
Method: POST (required)
Protocol: HTTPS (required)
Response Format: JSON (use .xml for XML)
```

### 1.2 Authentication Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `token` | Yes | Application API token, 30 chars, alphanumeric [A-Za-z0-9] |
| `user` | Yes | User/group key, 30 chars, alphanumeric |

### 1.3 Message Parameters

| Parameter | Required | Max Length | Description |
|-----------|----------|------------|-------------|
| `message` | Yes | 1024 chars | Message body (UTF-8) |
| `title` | No | 250 chars | Message title (defaults to app name) |
| `device` | No | - | Target specific device(s), comma-separated |
| `url` | No | 512 chars | Supplementary URL |
| `url_title` | No | 100 chars | Title for supplementary URL |
| `priority` | No | - | -2 to 2 (see below) |
| `sound` | No | - | Notification sound name |
| `timestamp` | No | - | Unix timestamp for message time |
| `html` | No | - | Set to 1 to enable HTML tags |
| `monospace` | No | - | Set to 1 for monospace font |
| `ttl` | No | - | Seconds until message auto-deletes |

### 1.4 Priority Levels

| Priority | Value | Behavior | Use Case |
|----------|-------|----------|----------|
| Lowest | -2 | Silent, badge only (iOS) | Routine info |
| Low | -1 | No sound/vibration | Background events |
| Normal | 0 | Sound per user settings | Standard alerts |
| High | 1 | Bypasses quiet hours | Important failures |
| Emergency | 2 | Repeats until acknowledged | Critical failures |

**Emergency Priority (2) Requirements:**
- `retry`: Minimum 30 seconds between retries
- `expire`: Maximum 10,800 seconds (3 hours)
- `callback` (optional): URL for acknowledgment webhook

### 1.5 Sound Options

Standard sounds available:
```
pushover (default), bike, bugle, cashregister, classical, cosmic,
falling, gamelan, incoming, intermission, magic, mechanical,
pianobar, siren, spacealarm, tugboat, alien, climb, persistent,
echo, updown, vibrate, none
```

### 1.6 Rate Limits

- **Free tier:** 10,000 messages/month
- **Team apps:** 25,000 messages/month
- **Reset:** 00:00:00 Central Time on 1st of month
- **Overage:** HTTP 429

**Check limits:** `GET https://api.pushover.net/1/apps/limits.json?token=YOUR_TOKEN`

### 1.7 Response Format

**Success (HTTP 200):**
```json
{"status":1,"request":"647d2300-702c-4b38-8b2f-d56326ae460b"}
```

**Error (HTTP 4xx):**
```json
{
  "status":0,
  "user":"invalid",
  "errors":["user identifier is invalid"],
  "request":"5042853c-402d-4a18-abcb-168734a801de"
}
```

**Response Headers (on success):**
```
X-Limit-App-Limit: 10000
X-Limit-App-Remaining: 7496
X-Limit-App-Reset: 1393653600
```

### 1.8 HTTP Status Codes

| Code | Meaning | Action |
|------|---------|--------|
| 200 | Success | Continue |
| 4xx | Invalid input | Fix parameters (don't retry) |
| 429 | Quota exceeded | Wait until reset |
| 5xx | Server error | Retry after 5+ seconds |

### 1.9 Curl Example

```bash
curl -s -o /dev/null -w "%{http_code}" \
  --form-string "token=YOUR_API_TOKEN" \
  --form-string "user=YOUR_USER_KEY" \
  --form-string "title=Backup Complete" \
  --form-string "message=All databases backed up successfully" \
  --form-string "priority=0" \
  --form-string "sound=magic" \
  https://api.pushover.net/1/messages.json
```

---

## 2. Implementation Design

### 2.1 New Secret Constants

Add to `/home/webnestify/backupd/lib/crypto.sh`:

```bash
# Add after line 19 (SECRET_WEBHOOK_TOKEN=".c7")
SECRET_PUSHOVER_USER=".c8"
SECRET_PUSHOVER_TOKEN=".c9"
```

### 2.2 Update lock_secrets() and unlock_secrets()

In `/home/webnestify/backupd/lib/crypto.sh`, update the secret_files array:

```bash
# In lock_secrets() and unlock_secrets() functions
# Change:
local secret_files=(".s" ".c1" ".c2" ".c3" ".c4" ".c5" ".c6" ".c7" ".algo")
# To:
local secret_files=(".s" ".c1" ".c2" ".c3" ".c4" ".c5" ".c6" ".c7" ".c8" ".c9" ".algo")
```

### 2.3 Event to Priority/Sound Mapping

| Event | Priority | Sound | Rationale |
|-------|----------|-------|-----------|
| backup_started | -1 | none | Silent - too frequent |
| backup_complete | 0 | magic | Normal success |
| backup_warning | 0 | bike | Attention needed |
| backup_failed | 1 | siren | Important - bypasses quiet hours |
| verify_passed | 0 | magic | Normal success |
| verify_failed | 1 | falling | Important failure |
| verify_warning | 0 | bike | Attention needed |
| retention_cleanup | -1 | none | Background task |
| retention_warning | 0 | bike | Some issues |
| retention_failed | 1 | falling | Action needed |

---

## 3. File Changes

### 3.1 crypto.sh Changes

**File:** `/home/webnestify/backupd/lib/crypto.sh`

**Change 1:** Add secret constants (after line 19)

```bash
SECRET_WEBHOOK_TOKEN=".c7"
SECRET_PUSHOVER_USER=".c8"
SECRET_PUSHOVER_TOKEN=".c9"
```

**Change 2:** Update lock_secrets() (around line 318)

```bash
lock_secrets() {
  local secrets_dir="$1"
  local secret_files=(".s" ".c1" ".c2" ".c3" ".c4" ".c5" ".c6" ".c7" ".c8" ".c9" ".algo")
  for f in "${secret_files[@]}"; do
    [[ -f "$secrets_dir/$f" ]] && chattr +i "$secrets_dir/$f" 2>/dev/null || true
  done
  chattr +i "$secrets_dir" 2>/dev/null || true
}
```

**Change 3:** Update unlock_secrets() (around line 325)

```bash
unlock_secrets() {
  local secrets_dir="$1"
  chattr -i "$secrets_dir" 2>/dev/null || true
  local secret_files=(".s" ".c1" ".c2" ".c3" ".c4" ".c5" ".c6" ".c7" ".c8" ".c9" ".algo")
  for f in "${secret_files[@]}"; do
    [[ -f "$secrets_dir/$f" ]] && chattr -i "$secrets_dir/$f" 2>/dev/null || true
  done
}
```

**Change 4:** Update migrate_secrets() (around line 341)

```bash
# In migrate_secrets() function, update the secret_files array:
local secret_files=(".c1" ".c2" ".c3" ".c4" ".c5" ".c6" ".c7" ".c8" ".c9")
```

---

### 3.2 notifications.sh Changes

**File:** `/home/webnestify/backupd/lib/notifications.sh`

**Change 1:** Update manage_notifications() menu (around line 23-30)

```bash
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
```

**Change 2:** Update show_notification_status_brief() - add after webhook check (around line 85)

```bash
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
```

**Change 3:** Add configure_pushover() function (add after configure_webhook function, around line 241)

```bash
# ---------- Configure Pushover ----------

configure_pushover() {
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
```

**Change 4:** Update test_notifications() - add Pushover test (around line 263)

After the webhook test block, add:

```bash
  # Test Pushover
  local pushover_user pushover_token
  pushover_user="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_USER" 2>/dev/null || echo "")"
  pushover_token="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_TOKEN" 2>/dev/null || echo "")"

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
```

And update the success check:

```bash
  echo
  if [[ $ntfy_ok -eq 1 || $webhook_ok -eq 1 || $pushover_ok -eq 1 ]]; then
    print_success "Test complete! Check your notification channels."
  else
    print_error "All notification tests failed. Check your configuration."
  fi
```

**Change 5:** Update disable_all_notifications() - add Pushover cleanup (around line 441)

```bash
    rm -f "$secrets_dir/$SECRET_NTFY_URL" 2>/dev/null
    rm -f "$secrets_dir/$SECRET_NTFY_TOKEN" 2>/dev/null
    rm -f "$secrets_dir/$SECRET_WEBHOOK_URL" 2>/dev/null
    rm -f "$secrets_dir/$SECRET_WEBHOOK_TOKEN" 2>/dev/null
    rm -f "$secrets_dir/$SECRET_PUSHOVER_USER" 2>/dev/null
    rm -f "$secrets_dir/$SECRET_PUSHOVER_TOKEN" 2>/dev/null
```

---

### 3.3 generators.sh Changes

**File:** `/home/webnestify/backupd/lib/generators.sh`

The generators.sh file contains heredocs that generate standalone scripts. We need to add Pushover support to ALL generated scripts. There are 4 script generators:

1. `generate_db_backup_script()` - Database backup
2. `generate_files_backup_script()` - Files backup
3. `generate_verify_script()` - Quick verification
4. `generate_verify_full_script()` - Full verification

For each generator, we need to:
1. Add SECRET_PUSHOVER_USER and SECRET_PUSHOVER_TOKEN constants
2. Add PUSHOVER_USER and PUSHOVER_TOKEN variable retrieval
3. Add send_pushover() function
4. Update send_notification() to call send_pushover()

**Template for send_pushover() function:**

```bash
# Robust Pushover sender with retry (3 attempts, exponential backoff)
send_pushover() {
  local title="$1" message="$2" priority="${3:-0}" sound="${4:-pushover}"
  [[ -z "$PUSHOVER_USER" || -z "$PUSHOVER_TOKEN" ]] && return 0

  local attempt=1 max_attempts=3 delay=2 http_code

  # Truncate message to 1024 chars (Pushover limit)
  message="${message:0:1024}"
  # Truncate title to 250 chars
  title="${title:0:250}"

  while [[ \$attempt -le \$max_attempts ]]; do
    http_code=\$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \\
      --form-string "token=\$PUSHOVER_TOKEN" \\
      --form-string "user=\$PUSHOVER_USER" \\
      --form-string "title=\$title" \\
      --form-string "message=\$message" \\
      --form-string "priority=\$priority" \\
      --form-string "sound=\$sound" \\
      https://api.pushover.net/1/messages.json 2>/dev/null) || http_code="000"

    [[ "\$http_code" == "200" ]] && return 0

    # Don't retry on 4xx (validation errors)
    [[ "\$http_code" =~ ^4[0-9][0-9]$ ]] && break

    if [[ \$attempt -lt \$max_attempts ]]; then
      sleep \$delay
      delay=\$((delay * 2))
    fi
    ((attempt++))
  done

  echo "[\$(date -Iseconds)] PUSHOVER FAILED: title='\$title' http=\$http_code attempts=\$max_attempts" >> "\$NOTIFICATION_FAIL_LOG"
  return 1
}
```

**Updated send_notification() template:**

```bash
# Send to all channels, track failures
send_notification() {
  local title="$1" message="$2" event="${3:-backup}" details="${4:-"{}"}"
  local priority="${5:-0}" sound="${6:-pushover}"
  local ntfy_ok=0 webhook_ok=0 pushover_ok=0

  send_ntfy "\$title" "\$message" && ntfy_ok=1
  send_webhook "\$title" "\$message" "\$event" "\$details" && webhook_ok=1
  send_pushover "\$title" "\$message" "\$priority" "\$sound" && pushover_ok=1

  # CRITICAL: All channels failed - log prominently
  if [[ \$ntfy_ok -eq 0 && \$webhook_ok -eq 0 && \$pushover_ok -eq 0 && \\
        ( -n "\$NTFY_URL" || -n "\$WEBHOOK_URL" || -n "\$PUSHOVER_USER" ) ]]; then
    echo "[CRITICAL] ALL NOTIFICATION CHANNELS FAILED for: \$title" >&2
    echo "[\$(date -Iseconds)] CRITICAL: ALL CHANNELS FAILED - title='\$title' event='\$event'" >> "\$NOTIFICATION_FAIL_LOG"
  fi
}
```

**Secret constants to add in generators:**

```bash
SECRET_PUSHOVER_USER=".c8"
SECRET_PUSHOVER_TOKEN=".c9"
```

**Variable retrieval to add:**

```bash
PUSHOVER_USER="\$(get_secret "\$SECRETS_DIR" "\$SECRET_PUSHOVER_USER" 2>/dev/null || echo "")"
PUSHOVER_TOKEN="\$(get_secret "\$SECRETS_DIR" "\$SECRET_PUSHOVER_TOKEN" 2>/dev/null || echo "")"
```

**Notification calls to update:**

Each call to `send_notification` should include priority and sound based on the event type. For example:

```bash
# Backup started - quiet notification
send_notification "DB Backup Started on \$HOSTNAME" "Starting at \$(date)" "backup_started" "{}" "-1" "none"

# Backup complete - normal success
send_notification "DB Backup Successful on \$HOSTNAME" "All \$db_count databases backed up" "backup_complete" "{}" "0" "magic"

# Backup failed - high priority
send_notification "DB Backup Failed on \$HOSTNAME" "No databases found" "backup_failed" "{}" "1" "siren"

# Backup warning - normal with attention sound
send_notification "DB Backup Completed with Errors on \$HOSTNAME" "Backed up: \$db_count, Failed: \${failures[*]}" "backup_warning" "{}" "0" "bike"
```

---

### 3.4 cli.sh Changes (Optional Enhancement)

**File:** `/home/webnestify/backupd/lib/cli.sh`

Add a new `notifications` subcommand for non-interactive API usage. This is an optional enhancement for REST API and automation scenarios.

**Add to cli_dispatch() case statement:**

```bash
    notifications)
      cli_notifications "$@"
      ;;
```

**Add new functions:**

```bash
# ---------- Notifications Subcommand ----------

cli_notifications() {
  local action="${1:-status}"
  shift || true

  case "$action" in
    status)
      cli_notifications_status "$@"
      ;;
    set-pushover)
      cli_notifications_set_pushover "$@"
      ;;
    test-pushover)
      cli_notifications_test_pushover "$@"
      ;;
    disable-pushover)
      cli_notifications_disable_pushover "$@"
      ;;
    --help|-h)
      cli_notifications_help
      return 0
      ;;
    *)
      print_error "Unknown action: $action"
      cli_notifications_help
      return $EXIT_USAGE
      ;;
  esac
}

cli_notifications_status() {
  local secrets_dir
  secrets_dir="$(get_secrets_dir)"

  if [[ -z "$secrets_dir" || ! -d "$secrets_dir" ]]; then
    if is_json_output; then
      echo '{"configured": false, "error": "Secure storage not initialized"}'
    else
      print_error "Secure storage not initialized. Run setup first."
    fi
    return $EXIT_NOT_CONFIGURED
  fi

  local ntfy_url ntfy_token webhook_url webhook_token pushover_user pushover_token

  ntfy_url="$(get_secret "$secrets_dir" "$SECRET_NTFY_URL" 2>/dev/null || echo "")"
  ntfy_token="$(get_secret "$secrets_dir" "$SECRET_NTFY_TOKEN" 2>/dev/null || echo "")"
  webhook_url="$(get_secret "$secrets_dir" "$SECRET_WEBHOOK_URL" 2>/dev/null || echo "")"
  webhook_token="$(get_secret "$secrets_dir" "$SECRET_WEBHOOK_TOKEN" 2>/dev/null || echo "")"
  pushover_user="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_USER" 2>/dev/null || echo "")"
  pushover_token="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_TOKEN" 2>/dev/null || echo "")"

  if is_json_output; then
    cat <<EOF
{
  "configured": true,
  "channels": {
    "ntfy": {
      "enabled": $([[ -n "$ntfy_url" ]] && echo "true" || echo "false"),
      "has_token": $([[ -n "$ntfy_token" ]] && echo "true" || echo "false")
    },
    "webhook": {
      "enabled": $([[ -n "$webhook_url" ]] && echo "true" || echo "false"),
      "has_token": $([[ -n "$webhook_token" ]] && echo "true" || echo "false")
    },
    "pushover": {
      "enabled": $([[ -n "$pushover_user" && -n "$pushover_token" ]] && echo "true" || echo "false"),
      "has_user_key": $([[ -n "$pushover_user" ]] && echo "true" || echo "false"),
      "has_api_token": $([[ -n "$pushover_token" ]] && echo "true" || echo "false")
    }
  }
}
EOF
  else
    echo "Notification Channels"
    echo "====================="
    echo
    if [[ -n "$ntfy_url" ]]; then
      print_success "ntfy: Configured"
    else
      print_warning "ntfy: Not configured"
    fi
    if [[ -n "$webhook_url" ]]; then
      print_success "Webhook: Configured"
    else
      print_warning "Webhook: Not configured"
    fi
    if [[ -n "$pushover_user" && -n "$pushover_token" ]]; then
      print_success "Pushover: Configured"
    else
      print_warning "Pushover: Not configured"
    fi
  fi
}

cli_notifications_set_pushover() {
  local user_key="" api_token=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user-key)
        user_key="$2"
        shift
        ;;
      --user-key=*)
        user_key="${1#--user-key=}"
        ;;
      --api-token)
        api_token="$2"
        shift
        ;;
      --api-token=*)
        api_token="${1#--api-token=}"
        ;;
      --help|-h)
        echo "Usage: backupd notifications set-pushover --user-key KEY --api-token TOKEN"
        return 0
        ;;
      *)
        print_error "Unknown option: $1"
        return $EXIT_USAGE
        ;;
    esac
    shift
  done

  # Require root
  if [[ $EUID -ne 0 ]]; then
    print_error "This operation requires root privileges."
    return $EXIT_NOPERM
  fi

  # Validate inputs
  if [[ -z "$user_key" || -z "$api_token" ]]; then
    print_error "Both --user-key and --api-token are required."
    return $EXIT_USAGE
  fi

  if [[ ! "$user_key" =~ ^[A-Za-z0-9]{30}$ ]]; then
    print_error "Invalid user key format. Must be 30 alphanumeric characters."
    return $EXIT_DATAERR
  fi

  if [[ ! "$api_token" =~ ^[A-Za-z0-9]{30}$ ]]; then
    print_error "Invalid API token format. Must be 30 alphanumeric characters."
    return $EXIT_DATAERR
  fi

  local secrets_dir
  secrets_dir="$(get_secrets_dir)"

  if [[ -z "$secrets_dir" ]]; then
    print_error "Secure storage not initialized. Run setup first."
    return $EXIT_NOT_CONFIGURED
  fi

  store_secret "$secrets_dir" "$SECRET_PUSHOVER_USER" "$user_key"
  store_secret "$secrets_dir" "$SECRET_PUSHOVER_TOKEN" "$api_token"

  if is_json_output; then
    echo '{"success": true, "message": "Pushover configured successfully"}'
  else
    print_success "Pushover configured successfully"
    echo "Run 'backupd notifications test-pushover' to verify."
  fi

  # Regenerate scripts
  regenerate_scripts_silent 2>/dev/null || true
}

cli_notifications_test_pushover() {
  local secrets_dir user_key api_token

  secrets_dir="$(get_secrets_dir)"
  if [[ -z "$secrets_dir" ]]; then
    print_error "Secure storage not initialized."
    return $EXIT_NOT_CONFIGURED
  fi

  user_key="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_USER" 2>/dev/null || echo "")"
  api_token="$(get_secret "$secrets_dir" "$SECRET_PUSHOVER_TOKEN" 2>/dev/null || echo "")"

  if [[ -z "$user_key" || -z "$api_token" ]]; then
    if is_json_output; then
      echo '{"success": false, "error": "Pushover not configured"}'
    else
      print_error "Pushover not configured. Run 'backupd notifications set-pushover' first."
    fi
    return $EXIT_NOT_CONFIGURED
  fi

  local hostname timestamp response http_code
  hostname="$(hostname -f 2>/dev/null || hostname)"
  timestamp="$(date -Iseconds)"

  response=$(timeout 15 curl -s -w "\n%{http_code}" \
    --form-string "token=$api_token" \
    --form-string "user=$user_key" \
    --form-string "title=Backupd Test on $hostname" \
    --form-string "message=Test notification sent at $timestamp" \
    --form-string "priority=0" \
    --form-string "sound=pushover" \
    https://api.pushover.net/1/messages.json 2>/dev/null) || response="000"

  http_code=$(echo "$response" | tail -1)

  if [[ "$http_code" == "200" ]]; then
    if is_json_output; then
      echo '{"success": true, "http_code": 200}'
    else
      print_success "Pushover test successful (HTTP 200)"
    fi
    return 0
  else
    if is_json_output; then
      echo "{\"success\": false, \"http_code\": $http_code}"
    else
      print_error "Pushover test failed (HTTP $http_code)"
    fi
    return 1
  fi
}

cli_notifications_disable_pushover() {
  # Require root
  if [[ $EUID -ne 0 ]]; then
    print_error "This operation requires root privileges."
    return $EXIT_NOPERM
  fi

  local secrets_dir
  secrets_dir="$(get_secrets_dir)"

  if [[ -z "$secrets_dir" ]]; then
    print_error "Secure storage not initialized."
    return $EXIT_NOT_CONFIGURED
  fi

  rm -f "$secrets_dir/$SECRET_PUSHOVER_USER" 2>/dev/null
  rm -f "$secrets_dir/$SECRET_PUSHOVER_TOKEN" 2>/dev/null

  if is_json_output; then
    echo '{"success": true, "message": "Pushover disabled"}'
  else
    print_success "Pushover disabled"
  fi

  # Regenerate scripts
  regenerate_scripts_silent 2>/dev/null || true
}

cli_notifications_help() {
  cat <<EOF
Usage: backupd notifications [COMMAND] [OPTIONS]

Manage notification channels (ntfy, webhook, Pushover).

Commands:
  status              Show notification channel status (default)
  set-pushover        Configure Pushover notifications
  test-pushover       Send test notification via Pushover
  disable-pushover    Remove Pushover configuration

Options for set-pushover:
  --user-key KEY      Pushover user key (30 alphanumeric chars)
  --api-token TOKEN   Pushover API token (30 alphanumeric chars)

Global Options:
  --json              Output in JSON format
  --help, -h          Show this help message

Requires: Root privileges for set/disable operations.

Examples:
  backupd notifications status
  backupd notifications status --json
  backupd notifications set-pushover --user-key USER --api-token TOKEN
  backupd notifications test-pushover
  backupd notifications disable-pushover

Note: For interactive configuration, run 'backupd' without arguments
and select 'Notifications' from the menu.
EOF
}
```

---

## 4. Message Templates

### 4.1 Database Backup Events

| Event | Title Template | Message Template | Priority | Sound |
|-------|----------------|------------------|----------|-------|
| Started | "DB Backup Started on {hostname}" | "Starting at {timestamp}" | -1 | none |
| Complete | "DB Backup Successful on {hostname}" | "All {count} databases backed up" | 0 | magic |
| Warning | "DB Backup Completed with Errors on {hostname}" | "Backed up: {count}, Failed: {failures}" | 0 | bike |
| Failed | "DB Backup Failed on {hostname}" | "{error_reason}" | 1 | siren |

### 4.2 Files Backup Events

| Event | Title Template | Message Template | Priority | Sound |
|-------|----------------|------------------|----------|-------|
| Started | "Files Backup Started on {hostname}" | "Starting at {timestamp}" | -1 | none |
| Complete | "Files Backup Success on {hostname}" | "{count} sites backed up" | 0 | magic |
| Warning | "Files Backup Errors on {hostname}" | "Success: {count}, Failed: {failures}" | 0 | bike |
| Failed | "Files Backup Failed on {hostname}" | "{error_reason}" | 1 | siren |

### 4.3 Verification Events

| Event | Title Template | Message Template | Priority | Sound |
|-------|----------------|------------------|----------|-------|
| Passed | "Quick Check PASSED on {hostname}" | "DB: {db_result}, Files: {files_result}" | 0 | magic |
| Warning | "Quick Check WARNING on {hostname}" | "DB: {db_result}, Files: {files_result}" | 0 | bike |
| Failed | "Quick Check FAILED on {hostname}" | "DB: {db_result}, Files: {files_result}" | 1 | falling |

### 4.4 Retention Events

| Event | Title Template | Message Template | Priority | Sound |
|-------|----------------|------------------|----------|-------|
| Cleanup | "Retention Cleanup on {hostname}" | "Removed {count} old backup(s)" | -1 | none |
| Warning | "Retention Cleanup Warning on {hostname}" | "Removed: {count}, Errors: {errors}" | 0 | bike |
| Failed | "Retention Cleanup Failed on {hostname}" | "{error_reason}" | 1 | falling |

---

## 5. Error Handling

### 5.1 API Error Responses

| HTTP Code | Meaning | Action |
|-----------|---------|--------|
| 200 | Success | Continue |
| 400 | Bad request | Log error, don't retry |
| 401 | Invalid credentials | Log error, don't retry |
| 429 | Rate limited | Log warning, wait until reset |
| 5xx | Server error | Retry with exponential backoff |

### 5.2 Retry Logic

```bash
# Retry pattern (matches existing ntfy/webhook implementation)
local attempt=1 max_attempts=3 delay=2

while [[ $attempt -le $max_attempts ]]; do
  # Make API call
  http_code=$(curl ...)

  # Success
  [[ "$http_code" == "200" ]] && return 0

  # Don't retry on 4xx (client errors)
  [[ "$http_code" =~ ^4[0-9][0-9]$ ]] && break

  # Exponential backoff for 5xx
  if [[ $attempt -lt $max_attempts ]]; then
    sleep $delay
    delay=$((delay * 2))
  fi
  ((attempt++))
done

# Log failure
echo "[$(date -Iseconds)] PUSHOVER FAILED: ..." >> "$NOTIFICATION_FAIL_LOG"
return 1
```

### 5.3 Failure Logging

All failures are logged to `/etc/backupd/logs/notification_failures.log`:

```
[2026-01-06T10:30:00+00:00] PUSHOVER FAILED: title='DB Backup Failed' http=401 attempts=3
```

---

## 6. Security Considerations

### 6.1 Credential Storage

- User key and API token stored encrypted using machine-bound encryption
- Same security as existing ntfy/webhook credentials
- Files protected with chattr +i (immutable flag)
- Never logged in plaintext

### 6.2 Input Validation

```bash
# Validate user key format (30 alphanumeric)
if [[ ! "$user_key" =~ ^[A-Za-z0-9]{30}$ ]]; then
  print_error "Invalid user key format"
  return 1
fi

# Validate API token format (30 alphanumeric)
if [[ ! "$api_token" =~ ^[A-Za-z0-9]{30}$ ]]; then
  print_error "Invalid API token format"
  return 1
fi
```

### 6.3 Message Sanitization

- Truncate messages to API limits (1024 chars for message, 250 for title)
- No user-controlled URLs passed without validation
- Priority clamped to valid range (-2 to 2)

---

## 7. Testing Plan

### 7.1 Unit Tests

1. **Credential validation**
   - Valid 30-char alphanumeric user key
   - Valid 30-char alphanumeric API token
   - Invalid formats rejected

2. **Message formatting**
   - Long messages truncated to 1024 chars
   - Long titles truncated to 250 chars
   - Special characters handled

3. **Priority mapping**
   - Each event maps to correct priority
   - Priority values in valid range

### 7.2 Integration Tests

1. **Configuration flow**
   - Configure Pushover via interactive menu
   - Configure Pushover via CLI
   - Verify credentials stored encrypted

2. **Notification delivery**
   - Test notification sends successfully
   - Error responses handled correctly
   - Retry logic works on 5xx

3. **Script generation**
   - Generated scripts include Pushover code
   - Scripts work without Pushover configured
   - Scripts handle missing credentials gracefully

### 7.3 Manual Test Cases

```bash
# Test 1: Configure Pushover via CLI
sudo backupd notifications set-pushover \
  --user-key "your30charalphanumericuserkey1" \
  --api-token "your30charalphanumericapitoken"

# Test 2: Verify configuration
backupd notifications status --json

# Test 3: Send test notification
sudo backupd notifications test-pushover

# Test 4: Trigger backup and verify notification
sudo backupd backup db

# Test 5: Disable Pushover
sudo backupd notifications disable-pushover
```

---

## 8. Rollback Procedure

If issues arise after implementation:

### 8.1 Quick Disable

```bash
# Remove Pushover credentials (disables without code changes)
sudo backupd notifications disable-pushover

# Regenerate scripts without Pushover
sudo backupd  # Interactive: Settings -> Regenerate scripts
```

### 8.2 Full Rollback

1. Revert crypto.sh changes (remove SECRET_PUSHOVER_* constants)
2. Revert notifications.sh changes (remove configure_pushover, etc.)
3. Revert generators.sh changes (remove send_pushover code)
4. Revert cli.sh changes (if implemented)
5. Regenerate all backup scripts

```bash
# Git rollback (if committed)
git checkout HEAD~1 -- lib/crypto.sh lib/notifications.sh lib/generators.sh lib/cli.sh

# Regenerate scripts
sudo backupd  # Interactive: Settings -> Regenerate scripts
```

---

## 9. Implementation Checklist

### Phase 1: Core Implementation

- [ ] Update `lib/crypto.sh`
  - [ ] Add SECRET_PUSHOVER_USER and SECRET_PUSHOVER_TOKEN constants
  - [ ] Update lock_secrets() array
  - [ ] Update unlock_secrets() array
  - [ ] Update migrate_secrets() array

- [ ] Update `lib/notifications.sh`
  - [ ] Update manage_notifications() menu
  - [ ] Update show_notification_status_brief()
  - [ ] Add configure_pushover()
  - [ ] Add test_pushover_notification()
  - [ ] Update test_notifications()
  - [ ] Update disable_all_notifications()

### Phase 2: Script Generation

- [ ] Update `lib/generators.sh`
  - [ ] Add send_pushover() to generate_db_backup_script()
  - [ ] Add send_pushover() to generate_files_backup_script()
  - [ ] Add send_pushover() to generate_verify_script()
  - [ ] Add send_pushover() to generate_verify_full_script()
  - [ ] Update send_notification() in all generators
  - [ ] Update notification calls with priority/sound parameters

### Phase 3: CLI Enhancement (Optional)

- [ ] Update `lib/cli.sh`
  - [ ] Add notifications subcommand
  - [ ] Add cli_notifications_status()
  - [ ] Add cli_notifications_set_pushover()
  - [ ] Add cli_notifications_test_pushover()
  - [ ] Add cli_notifications_disable_pushover()
  - [ ] Add cli_notifications_help()

### Phase 4: Testing

- [ ] Test interactive configuration
- [ ] Test CLI configuration
- [ ] Test notification delivery
- [ ] Test error handling
- [ ] Test script generation
- [ ] Test disable/rollback

### Phase 5: Documentation

- [ ] Update USAGE.md with Pushover section
- [ ] Update CHANGELOG.md with new feature

---

## 10. Version Information

- **Backupd Version:** 2.2.11 -> 2.3.0 (minor version bump for new feature)
- **Pushover API Version:** v1 (stable, no breaking changes expected)
- **Implementation Date:** 2026-01-06

---

## Appendix A: Complete send_pushover() Implementation

```bash
# Robust Pushover sender with retry (3 attempts, exponential backoff)
# Follows Pushover API best practices:
# - HTTPS required
# - POST method only
# - Respect rate limits
# - Don't retry on 4xx (client errors)
send_pushover() {
  local title="$1" message="$2" priority="${3:-0}" sound="${4:-pushover}"

  # Skip if not configured
  [[ -z "$PUSHOVER_USER" || -z "$PUSHOVER_TOKEN" ]] && return 0

  # Validate/clamp priority
  [[ "$priority" -lt -2 ]] && priority=-2
  [[ "$priority" -gt 2 ]] && priority=2

  # Truncate to API limits
  message="${message:0:1024}"
  title="${title:0:250}"

  local attempt=1 max_attempts=3 delay=2 http_code

  while [[ $attempt -le $max_attempts ]]; do
    http_code=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" \
      --form-string "token=$PUSHOVER_TOKEN" \
      --form-string "user=$PUSHOVER_USER" \
      --form-string "title=$title" \
      --form-string "message=$message" \
      --form-string "priority=$priority" \
      --form-string "sound=$sound" \
      https://api.pushover.net/1/messages.json 2>/dev/null) || http_code="000"

    # Success
    [[ "$http_code" == "200" ]] && return 0

    # Don't retry on 4xx (validation errors, invalid credentials, etc.)
    [[ "$http_code" =~ ^4[0-9][0-9]$ ]] && break

    # Exponential backoff for 5xx and network errors
    if [[ $attempt -lt $max_attempts ]]; then
      sleep $delay
      delay=$((delay * 2))
    fi
    ((attempt++))
  done

  # Log failure
  echo "[$(date -Iseconds)] PUSHOVER FAILED: title='$title' priority=$priority http=$http_code attempts=$max_attempts" >> "$NOTIFICATION_FAIL_LOG"
  return 1
}
```

---

## Appendix B: Pushover Sounds Reference

| Sound | Description | Recommended Use |
|-------|-------------|-----------------|
| `pushover` | Default | General notifications |
| `none` | Silent | Background events |
| `vibrate` | Vibration only | Quiet hours |
| `magic` | Pleasant chime | Success events |
| `bike` | Bicycle bell | Warnings |
| `siren` | Alert siren | Failures |
| `falling` | Descending tone | Verification failures |
| `cosmic` | Space sound | Special events |
| `bugle` | Trumpet call | Important alerts |

---

**End of Implementation Plan**
