#!/usr/bin/env bash
# ============================================================================
# Backupd - Restore Module
# Restore execution functions
# ============================================================================

# ---------- Run Restore ----------

run_restore() {
  print_header
  echo "Restore from Backup"
  echo "==================="
  echo

  if ! is_configured; then
    print_error "System not configured. Please run setup first."
    press_enter_to_continue
    return
  fi

  echo "1. Restore database(s)"
  echo "2. Restore files/sites"
  echo "3. Back to main menu"
  echo
  read -p "Select option [1-3]: " restore_choice

  case "$restore_choice" in
    1)
      if [[ -f "$SCRIPTS_DIR/db_restore.sh" ]]; then
        echo
        bash "$SCRIPTS_DIR/db_restore.sh"
        press_enter_to_continue
      else
        print_error "Database restore script not found."
        press_enter_to_continue
      fi
      ;;
    2)
      if [[ -f "$SCRIPTS_DIR/files_restore.sh" ]]; then
        echo
        bash "$SCRIPTS_DIR/files_restore.sh"
        press_enter_to_continue
      else
        print_error "Files restore script not found."
        press_enter_to_continue
      fi
      ;;
    3|*)
      return
      ;;
  esac
}
