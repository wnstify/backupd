#!/usr/bin/env bash
# ============================================================================
# Backupd - Setup Module
# Setup wizard for initial configuration
# ============================================================================

# ---------- Setup Wizard ----------

run_setup() {
  print_header
  echo "Setup Wizard"
  echo "============"
  echo

  # Check if already configured
  if is_configured; then
    echo "Existing configuration detected."
    echo
    echo "1. Reconfigure everything (overwrites existing)"
    echo "2. Cancel and return to menu"
    echo
    read -p "Select option [1-2]: " reconfig_choice

    if [[ "$reconfig_choice" != "1" ]]; then
      return
    fi

    # Unlock secrets for modification
    local secrets_dir
    secrets_dir="$(get_secrets_dir)"
    if [[ -n "$secrets_dir" ]]; then
      unlock_secrets "$secrets_dir"
    fi
  fi

  # Create directories
  mkdir -p "$INSTALL_DIR" "$SCRIPTS_DIR" "$INSTALL_DIR/logs"
  chmod 700 "$INSTALL_DIR" "$SCRIPTS_DIR"

  # Initialize secure storage
  local SECRETS_DIR
  SECRETS_DIR="$(init_secure_storage)"
  print_success "Secure storage initialized: $SECRETS_DIR"
  echo

  # ---------- Step 1: Backup Type Selection ----------
  echo "Step 1: Backup Type Selection"
  echo "-----------------------------"
  echo "What would you like to back up?"
  echo "1. Database only"
  echo "2. Files only (WordPress sites)"
  echo "3. Both Database and Files"
  read -p "Select option [1-3]: " BACKUP_TYPE
  BACKUP_TYPE=${BACKUP_TYPE:-3}

  local DO_DATABASE=false
  local DO_FILES=false

  case "$BACKUP_TYPE" in
    1) DO_DATABASE=true ;;
    2) DO_FILES=true ;;
    3) DO_DATABASE=true; DO_FILES=true ;;
    *) DO_DATABASE=true; DO_FILES=true ;;
  esac

  save_config "DO_DATABASE" "$DO_DATABASE"
  save_config "DO_FILES" "$DO_FILES"

  echo
  [[ "$DO_DATABASE" == "true" ]] && print_success "Database backup: ENABLED"
  [[ "$DO_FILES" == "true" ]] && print_success "Files backup: ENABLED"
  echo

  # ---------- Step 1b: Web Application Paths (if files backup enabled) ----------
  local WEB_PATH_PATTERN=""
  local WEBROOT_SUBDIR=""
  local PANEL_KEY=""

  if [[ "$DO_FILES" == "true" ]]; then
    echo "Step 1b: Web Application Paths"
    echo "------------------------------"
    echo "Where are your web applications stored?"
    echo

    # Auto-detect panel
    local detected_panel
    detected_panel="$(detect_panel)"
    local detected_name
    detected_name="$(get_panel_info "$detected_panel" "name")"
    local detected_pattern
    detected_pattern="$(get_panel_info "$detected_panel" "pattern")"
    local site_count
    site_count="$(count_sites_for_pattern "$detected_pattern")"

    echo -e "${GREEN}Detected: $detected_name ($detected_pattern)${NC}"
    [[ "$site_count" -gt 0 ]] && echo -e "${GREEN}Found $site_count site(s) matching this pattern${NC}"
    echo

    echo "  1) Use detected: $detected_name"
    echo "     Pattern: $detected_pattern"
    echo
    echo "  -- Or select a different panel --"
    echo "  2) Enhance      /var/www/*/public_html"
    echo "  3) xCloud       /var/www/*/public_html"
    echo "  4) RunCloud     /home/*/webapps/*"
    echo "  5) Ploi         /home/*/*"
    echo "  6) cPanel       /home/*/public_html"
    echo "  7) Plesk        /var/www/vhosts/*/httpdocs"
    echo "  8) CloudPanel   /home/*/htdocs/*"
    echo "  9) CyberPanel   /home/*/public_html"
    echo " 10) aaPanel      /www/wwwroot/*"
    echo " 11) HestiaCP     /home/*/web/*/public_html"
    echo " 12) Virtualmin   /home/*/public_html"
    echo " 13) Custom path"
    echo
    read -p "Select option [1-13] (default: 1): " PANEL_CHOICE
    PANEL_CHOICE=${PANEL_CHOICE:-1}

    case "$PANEL_CHOICE" in
      1)
        PANEL_KEY="$detected_panel"
        ;;
      2) PANEL_KEY="enhance" ;;
      3) PANEL_KEY="xcloud" ;;
      4) PANEL_KEY="runcloud" ;;
      5) PANEL_KEY="ploi" ;;
      6) PANEL_KEY="cpanel" ;;
      7) PANEL_KEY="plesk" ;;
      8) PANEL_KEY="cloudpanel" ;;
      9) PANEL_KEY="cyberpanel" ;;
      10) PANEL_KEY="aapanel" ;;
      11) PANEL_KEY="hestia" ;;
      12) PANEL_KEY="virtualmin" ;;
      13)
        PANEL_KEY="custom"
        echo
        echo "Enter custom path pattern. Use * as wildcard for user/site directories."
        echo "Examples:"
        echo "  /var/www/*           - All directories in /var/www"
        echo "  /home/*/sites/*      - All sites under each user's sites folder"
        echo "  /opt/apps/*          - All apps in /opt/apps"
        echo
        read -p "Enter path pattern: " CUSTOM_PATTERN
        if [[ -z "$CUSTOM_PATTERN" ]]; then
          print_error "Path pattern cannot be empty"
          press_enter_to_continue
          return
        fi
        # Validate the pattern exists
        if ! pattern_exists "$CUSTOM_PATTERN"; then
          print_warning "Warning: No directories match '$CUSTOM_PATTERN'"
          read -p "Continue anyway? (y/N): " CONTINUE_ANYWAY
          if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
            return
          fi
        fi
        WEB_PATH_PATTERN="$CUSTOM_PATTERN"
        WEBROOT_SUBDIR="."

        echo
        echo "Does each site have a subdirectory for web files?"
        echo "  1) No - files are directly in the site folder"
        echo "  2) public_html"
        echo "  3) httpdocs"
        echo "  4) public"
        echo "  5) www"
        echo "  6) Other (specify)"
        read -p "Select [1-6] (default: 1): " SUBDIR_CHOICE
        SUBDIR_CHOICE=${SUBDIR_CHOICE:-1}

        case "$SUBDIR_CHOICE" in
          1) WEBROOT_SUBDIR="." ;;
          2) WEBROOT_SUBDIR="public_html" ;;
          3) WEBROOT_SUBDIR="httpdocs" ;;
          4) WEBROOT_SUBDIR="public" ;;
          5) WEBROOT_SUBDIR="www" ;;
          6)
            read -p "Enter subdirectory name: " WEBROOT_SUBDIR
            WEBROOT_SUBDIR="${WEBROOT_SUBDIR:-.}"
            ;;
        esac
        ;;
      *)
        PANEL_KEY="$detected_panel"
        ;;
    esac

    # Get pattern and subdir from panel definition if not custom
    if [[ "$PANEL_CHOICE" != "13" ]]; then
      WEB_PATH_PATTERN="$(get_panel_info "$PANEL_KEY" "pattern")"
      WEBROOT_SUBDIR="$(get_panel_info "$PANEL_KEY" "webroot_subdir")"
    fi

    # Save configuration
    save_config "PANEL_KEY" "$PANEL_KEY"
    save_config "WEB_PATH_PATTERN" "$WEB_PATH_PATTERN"
    save_config "WEBROOT_SUBDIR" "$WEBROOT_SUBDIR"

    local final_panel_name
    final_panel_name="$(get_panel_info "$PANEL_KEY" "name")"
    print_success "Panel: $final_panel_name"
    print_success "Path pattern: $WEB_PATH_PATTERN"
    [[ "$WEBROOT_SUBDIR" != "." ]] && print_success "Webroot subdir: $WEBROOT_SUBDIR"
    echo
  fi

  # ---------- Step 2: Encryption Password ----------
  echo "Step 2: Encryption Password"
  echo "---------------------------"
  if argon2_available; then
    echo "Your backups will be encrypted with AES-256 + Argon2id key derivation."
  else
    echo "Your backups will be encrypted with AES-256 + PBKDF2 key derivation."
    print_info "Install 'argon2' package for stronger Argon2id encryption."
  fi
  echo
  show_password_requirements
  read -sp "Enter encryption password: " ENCRYPTION_PASSWORD
  echo
  read -sp "Confirm encryption password: " ENCRYPTION_PASSWORD_CONFIRM
  echo

  if [[ "$ENCRYPTION_PASSWORD" != "$ENCRYPTION_PASSWORD_CONFIRM" ]]; then
    print_error "Passwords don't match. Please restart setup."
    press_enter_to_continue
    return
  fi

  if ! validate_password "$ENCRYPTION_PASSWORD"; then
    press_enter_to_continue
    return
  fi

  store_secret "$SECRETS_DIR" "$SECRET_PASSPHRASE" "$ENCRYPTION_PASSWORD"
  print_success "Encryption password stored securely."
  echo

  # ---------- Step 3: Database Authentication (if enabled) ----------
  local HAVE_DB_CREDS=false

  if [[ "$DO_DATABASE" == "true" ]]; then
    echo "Step 3: Database Authentication"
    echo "--------------------------------"

    # Detect DB client
    local DB_CLIENT=""
    if command -v mariadb >/dev/null 2>&1; then
      DB_CLIENT="mariadb"
    elif command -v mysql >/dev/null 2>&1; then
      DB_CLIENT="mysql"
    else
      print_error "Neither MariaDB nor MySQL client found."
      press_enter_to_continue
      return
    fi

    # Determine default database user based on panel
    local DEFAULT_DB_USER="root"
    if [[ "${PANEL_KEY:-}" == "ploi" ]]; then
      DEFAULT_DB_USER="ploi"
      echo "Ploi panel detected - default database user is 'ploi'"
      echo
    else
      echo "On many systems, root can access MySQL/MariaDB via socket authentication."
      echo
    fi

    read -p "Do you need to use a password for database access? (y/N): " USE_DB_PASSWORD
    USE_DB_PASSWORD=${USE_DB_PASSWORD:-N}

    if [[ "$USE_DB_PASSWORD" =~ ^[Yy]$ ]]; then
      # Ask for username (with panel-aware default)
      read -p "Enter database username (default: $DEFAULT_DB_USER): " DB_USER
      DB_USER="${DB_USER:-$DEFAULT_DB_USER}"

      read -sp "Enter database password for '$DB_USER': " DB_PASSWORD
      echo

      if "$DB_CLIENT" -u "$DB_USER" -p"$DB_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; then
        print_success "Database connection successful."
        store_secret "$SECRETS_DIR" "$SECRET_DB_USER" "$DB_USER"
        store_secret "$SECRETS_DIR" "$SECRET_DB_PASS" "$DB_PASSWORD"
        HAVE_DB_CREDS=true
        print_success "Database credentials stored securely."
      else
        print_error "Could not connect to database. Please check username/password."
        press_enter_to_continue
        return
      fi
    else
      if "$DB_CLIENT" -e "SELECT 1" >/dev/null 2>&1; then
        print_success "Socket authentication successful."
      else
        print_error "Socket authentication failed. Please restart setup with password."
        press_enter_to_continue
        return
      fi
    fi
    echo
  fi

  # ---------- Step 4: rclone Remote Storage ----------
  echo "Step 4: Remote Storage (rclone)"
  echo "--------------------------------"

  if ! command -v rclone &>/dev/null; then
    print_warning "rclone is not installed."
    read -p "Install rclone now? (Y/n): " INSTALL_RCLONE
    INSTALL_RCLONE=${INSTALL_RCLONE:-Y}

    if [[ "$INSTALL_RCLONE" =~ ^[Yy]$ ]]; then
      print_info "Installing rclone with verified download..."
      if ! install_rclone_verified; then
        print_error "Failed to install rclone."
        print_info "You can install manually: https://rclone.org/install/"
        press_enter_to_continue
        return
      fi
    else
      print_error "rclone is required. Please install it and restart setup."
      press_enter_to_continue
      return
    fi
  fi

  # Check for remotes
  local REMOTES
  REMOTES="$(rclone listremotes || true)"

  if [[ -z "$REMOTES" ]]; then
    print_warning "No rclone remotes configured."
    read -p "Configure rclone now? (Y/n): " CONFIG_RCLONE
    CONFIG_RCLONE=${CONFIG_RCLONE:-Y}

    if [[ "$CONFIG_RCLONE" =~ ^[Yy]$ ]]; then
      rclone config
      REMOTES="$(rclone listremotes || true)"
    fi

    if [[ -z "$REMOTES" ]]; then
      print_error "No remotes configured. Please configure rclone and restart setup."
      press_enter_to_continue
      return
    fi
  fi

  echo "Available rclone remotes:"
  echo "$REMOTES"
  echo
  read -p "Enter remote name (without colon): " RCLONE_REMOTE

  if ! rclone listremotes | grep -q "^$RCLONE_REMOTE:$"; then
    print_error "Remote '$RCLONE_REMOTE' not found."
    press_enter_to_continue
    return
  fi

  save_config "RCLONE_REMOTE" "$RCLONE_REMOTE"

  # Database path
  local RCLONE_DB_PATH=""
  local RCLONE_FILES_PATH=""

  if [[ "$DO_DATABASE" == "true" ]]; then
    read -p "Enter path for database backups (e.g., backups/db): " RCLONE_DB_PATH
    if ! validate_path "$RCLONE_DB_PATH" "Database backup path"; then
      press_enter_to_continue
      return
    fi
    save_config "RCLONE_DB_PATH" "$RCLONE_DB_PATH"
    print_success "Database backups: $RCLONE_REMOTE:$RCLONE_DB_PATH"
  fi

  # Files path
  if [[ "$DO_FILES" == "true" ]]; then
    read -p "Enter path for files backups (e.g., backups/files): " RCLONE_FILES_PATH
    if ! validate_path "$RCLONE_FILES_PATH" "Files backup path"; then
      press_enter_to_continue
      return
    fi
    save_config "RCLONE_FILES_PATH" "$RCLONE_FILES_PATH"
    print_success "Files backups: $RCLONE_REMOTE:$RCLONE_FILES_PATH"
  fi
  echo

  # ---------- Step 5: Notifications (ntfy) ----------
  echo "Step 5: Notifications (optional)"
  echo "---------------------------------"
  read -p "Set up ntfy notifications? (y/N): " SETUP_NTFY
  SETUP_NTFY=${SETUP_NTFY:-N}

  if [[ "$SETUP_NTFY" =~ ^[Yy]$ ]]; then
    read -p "Enter ntfy topic URL (e.g., https://ntfy.sh/mytopic): " NTFY_URL
    if ! validate_url "$NTFY_URL" "ntfy URL"; then
      print_warning "Skipping notifications due to invalid URL"
    else
      store_secret "$SECRETS_DIR" "$SECRET_NTFY_URL" "$NTFY_URL"

      read -p "Do you have an ntfy auth token? (y/N): " HAS_NTFY_TOKEN
      if [[ "$HAS_NTFY_TOKEN" =~ ^[Yy]$ ]]; then
        read -sp "Enter ntfy token: " NTFY_TOKEN
        echo
        store_secret "$SECRETS_DIR" "$SECRET_NTFY_TOKEN" "$NTFY_TOKEN"
      fi

      print_success "Notifications configured."
    fi
  fi
  echo

  # ---------- Step 6: Retention Policy ----------
  echo "Step 6: Retention Policy"
  echo "------------------------"
  echo "How long should backups be kept before automatic cleanup?"
  echo
  echo "  1) 1 minute (TESTING ONLY)"
  echo "  2) 1 hour (TESTING)"
  echo "  3) 7 days"
  echo "  4) 14 days"
  echo "  5) 30 days"
  echo "  6) 60 days"
  echo "  7) 90 days"
  echo "  8) 365 days (1 year)"
  echo "  9) No automatic cleanup"
  echo
  read -p "Select retention period [1-9] (default: 5): " RETENTION_CHOICE
  RETENTION_CHOICE=${RETENTION_CHOICE:-5}

  local RETENTION_MINUTES=0
  local RETENTION_DESC=""
  case "$RETENTION_CHOICE" in
    1) RETENTION_MINUTES=1; RETENTION_DESC="1 minute (TESTING)" ;;
    2) RETENTION_MINUTES=60; RETENTION_DESC="1 hour (TESTING)" ;;
    3) RETENTION_MINUTES=$((7 * 24 * 60)); RETENTION_DESC="7 days" ;;
    4) RETENTION_MINUTES=$((14 * 24 * 60)); RETENTION_DESC="14 days" ;;
    5) RETENTION_MINUTES=$((30 * 24 * 60)); RETENTION_DESC="30 days" ;;
    6) RETENTION_MINUTES=$((60 * 24 * 60)); RETENTION_DESC="60 days" ;;
    7) RETENTION_MINUTES=$((90 * 24 * 60)); RETENTION_DESC="90 days" ;;
    8) RETENTION_MINUTES=$((365 * 24 * 60)); RETENTION_DESC="365 days" ;;
    9) RETENTION_MINUTES=0; RETENTION_DESC="No automatic cleanup" ;;
    *) RETENTION_MINUTES=$((30 * 24 * 60)); RETENTION_DESC="30 days (default)" ;;
  esac

  save_config "RETENTION_MINUTES" "$RETENTION_MINUTES"
  save_config "RETENTION_DESC" "$RETENTION_DESC"
  print_success "Retention policy: $RETENTION_DESC"
  echo

  # ---------- Step 7: Generate Scripts ----------
  echo "Step 7: Generating Backup Scripts"
  echo "----------------------------------"

  generate_all_scripts "$SECRETS_DIR" "$DO_DATABASE" "$DO_FILES" "$RCLONE_REMOTE" \
    "${RCLONE_DB_PATH:-}" "${RCLONE_FILES_PATH:-}" "$RETENTION_MINUTES" \
    "${WEB_PATH_PATTERN:-/var/www/*}" "${WEBROOT_SUBDIR:-.}"

  echo

  # ---------- Step 8: Schedule Backups ----------
  echo "Step 8: Schedule Backups (systemd timers)"
  echo "------------------------------------------"

  if [[ "$DO_DATABASE" == "true" ]]; then
    read -p "Schedule automatic database backups? (Y/n): " SCHEDULE_DB
    SCHEDULE_DB=${SCHEDULE_DB:-Y}

    if [[ "$SCHEDULE_DB" =~ ^[Yy]$ ]]; then
      set_systemd_schedule "db" "Database"
    fi
  fi

  if [[ "$DO_FILES" == "true" ]]; then
    read -p "Schedule automatic files backups? (Y/n): " SCHEDULE_FILES
    SCHEDULE_FILES=${SCHEDULE_FILES:-Y}

    if [[ "$SCHEDULE_FILES" =~ ^[Yy]$ ]]; then
      set_systemd_schedule "files" "Files"
    fi
  fi

  # ---------- Step 9: Enable Verification Timers ----------
  echo
  echo "Step 9: Backup Verification (recommended)"
  echo "------------------------------------------"
  echo
  echo "Backupd can automatically verify your backups to ensure they're restorable."
  echo

  # Generate and enable quick verification (weekly by default)
  echo "Setting up weekly quick verification..."
  generate_verify_script

  cat > /etc/systemd/system/backupd-verify.service << EOF
[Unit]
Description=Backupd - Quick Integrity Verification
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPTS_DIR/verify_backup.sh
StandardOutput=journal
StandardError=journal
Nice=19
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/systemd/system/backupd-verify.timer << EOF
[Unit]
Description=Backupd - Weekly Quick Integrity Verification

[Timer]
OnCalendar=Sun *-*-* 02:00:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable backupd-verify.timer 2>/dev/null
  systemctl start backupd-verify.timer 2>/dev/null
  print_success "Weekly quick verification enabled (Sundays at 2 AM)"

  # Generate and enable full verification (monthly by default)
  echo "Setting up monthly full verification..."
  generate_full_verify_script

  cat > /etc/systemd/system/backupd-verify-full.service << EOF
[Unit]
Description=Backupd - Monthly Full Backup Verification
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPTS_DIR/verify_full_backup.sh
StandardOutput=journal
StandardError=journal
Nice=19
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/systemd/system/backupd-verify-full.timer << EOF
[Unit]
Description=Backupd - Monthly Full Backup Verification Timer

[Timer]
OnCalendar=*-*-01 03:00:00
Persistent=true
RandomizedDelaySec=3600

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable backupd-verify-full.timer 2>/dev/null
  systemctl start backupd-verify-full.timer 2>/dev/null
  print_success "Monthly full verification enabled (1st of month at 3 AM)"

  echo
  print_info "Quick check: Verifies backups exist (no download)"
  print_info "Full check: Downloads and tests decryption monthly"
  echo
  print_info "Manage via: sudo backupd → Manage schedules"

  # Lock secrets
  lock_secrets "$SECRETS_DIR"

  # ---------- Complete ----------
  echo
  echo "========================================================"
  echo "                 Setup Complete!"
  echo "========================================================"
  echo
  print_success "Backup management system is ready."
  echo
  echo "You can now use 'backupd' command from anywhere."
  echo
  echo "Systemd timers are managing your backup schedules."
  echo "View status anytime with: systemctl list-timers backupd-*"
  echo

  press_enter_to_continue
}
