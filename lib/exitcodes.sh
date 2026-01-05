#!/usr/bin/env bash
# ============================================================================
# Backupd - Exit Codes Module
# Standardized exit codes following sysexits.h (BSD) conventions
# See: https://www.freebsd.org/cgi/man.cgi?query=sysexits
# CLIG reference: https://clig.dev/#the-basics
# ============================================================================

# ---------- Standard Exit Codes ----------

# Success
readonly EXIT_OK=0

# Generic errors (1-2)
readonly EXIT_ERROR=1          # General/unspecified error
readonly EXIT_USAGE=2          # Command line usage error

# ---------- Sysexits.h Range (64-78) ----------

# EX_USAGE (64) - Command was used incorrectly
readonly EXIT_CMDLINE=64

# EX_DATAERR (65) - Input data was incorrect
readonly EXIT_DATAERR=65

# EX_NOINPUT (66) - Input file/data missing or unreadable
readonly EXIT_NOINPUT=66

# EX_NOUSER (67) - User doesn't exist
readonly EXIT_NOUSER=67

# EX_NOHOST (68) - Host name lookup failure
readonly EXIT_NOHOST=68

# EX_UNAVAILABLE (69) - Service unavailable
readonly EXIT_UNAVAILABLE=69

# EX_SOFTWARE (70) - Internal software error
readonly EXIT_SOFTWARE=70

# EX_OSERR (71) - System error (fork failed, etc.)
readonly EXIT_OSERR=71

# EX_OSFILE (72) - Critical OS file missing
readonly EXIT_OSFILE=72

# EX_CANTCREAT (73) - Can't create output file
readonly EXIT_CANTCREAT=73

# EX_IOERR (74) - I/O error
readonly EXIT_IOERR=74

# EX_TEMPFAIL (75) - Temporary failure, retry may succeed
readonly EXIT_TEMPFAIL=75

# EX_PROTOCOL (76) - Remote error in protocol
readonly EXIT_PROTOCOL=76

# EX_NOPERM (77) - Permission denied
readonly EXIT_NOPERM=77

# EX_CONFIG (78) - Configuration error
readonly EXIT_CONFIG=78

# ---------- Backupd-Specific Mappings ----------
# These map current backupd exit codes to sysexits.h equivalents

# Backup operation failures
readonly EXIT_BACKUP_FAILED=$EXIT_IOERR         # 74 - Backup I/O failed
readonly EXIT_RESTORE_FAILED=$EXIT_IOERR        # 74 - Restore I/O failed
readonly EXIT_VERIFY_FAILED=$EXIT_DATAERR       # 65 - Verification failed

# Encryption/credential issues
readonly EXIT_NO_PASSPHRASE=$EXIT_NOINPUT       # 66 - No passphrase provided
readonly EXIT_DECRYPT_FAILED=$EXIT_DATAERR      # 65 - Decryption failed

# Storage issues
readonly EXIT_DISK_FULL=$EXIT_CANTCREAT         # 73 - Insufficient disk space
readonly EXIT_UPLOAD_FAILED=$EXIT_IOERR         # 74 - Upload to remote failed

# Database issues
readonly EXIT_NO_DB_CLIENT=$EXIT_UNAVAILABLE    # 69 - MySQL/MariaDB not found
readonly EXIT_DB_CONNECT_FAILED=$EXIT_NOHOST    # 68 - Can't connect to database
readonly EXIT_DB_DUMP_FAILED=$EXIT_IOERR        # 74 - Database dump failed

# Configuration issues
readonly EXIT_NOT_CONFIGURED=$EXIT_CONFIG       # 78 - Tool not configured
readonly EXIT_INVALID_CONFIG=$EXIT_CONFIG       # 78 - Invalid configuration

# System issues
readonly EXIT_NOT_ROOT=$EXIT_NOPERM             # 77 - Must be run as root
readonly EXIT_MISSING_DEP=$EXIT_UNAVAILABLE     # 69 - Missing dependency

# ---------- Helper Function ----------

# Get human-readable description for exit code
exit_code_description() {
  local code="${1:-0}"
  case "$code" in
    0)  echo "Success" ;;
    1)  echo "General error" ;;
    2)  echo "Command line usage error" ;;
    64) echo "Command line usage error" ;;
    65) echo "Data format error" ;;
    66) echo "Cannot open input" ;;
    67) echo "User does not exist" ;;
    68) echo "Host not found" ;;
    69) echo "Service unavailable" ;;
    70) echo "Internal software error" ;;
    71) echo "System error" ;;
    72) echo "Critical OS file missing" ;;
    73) echo "Cannot create output file" ;;
    74) echo "Input/output error" ;;
    75) echo "Temporary failure, retry may succeed" ;;
    76) echo "Remote protocol error" ;;
    77) echo "Permission denied" ;;
    78) echo "Configuration error" ;;
    130) echo "Interrupted (Ctrl+C)" ;;
    *)  echo "Unknown error ($code)" ;;
  esac
}
