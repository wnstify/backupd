#!/bin/bash
#
# Backupd - One-Line Installer
# by Backupd (https://backupd.io)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wnstify/backupd/main/install.sh | sudo bash
#
# Uninstall:
#   curl -fsSL https://raw.githubusercontent.com/wnstify/backupd/main/install.sh | sudo bash -s -- --uninstall
#

set -e

# GitHub raw URL base
GITHUB_RAW="https://raw.githubusercontent.com/wnstify/backupd/main"

# Installation paths
INSTALL_DIR="/etc/backupd"
SCRIPT_NAME="backupd.sh"
BIN_LINK="/usr/local/bin/backupd"

# Library modules to download
LIB_MODULES=(
    "core.sh"
    "crypto.sh"
    "config.sh"
    "generators.sh"
    "status.sh"
    "backup.sh"
    "verify.sh"
    "restore.sh"
    "schedule.sh"
    "setup.sh"
    "updater.sh"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║              Backupd - Installer                          ║"
    echo "║                  by Backupd                               ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_disclaimer() {
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}                        DISCLAIMER${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "This tool is provided AS-IS without warranty. By installing,"
    echo "you acknowledge that:"
    echo ""
    echo "  - You are responsible for your own backups and data"
    echo "  - You should test restores before relying on backups"
    echo "  - The authors are not liable for any data loss"
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This installer must be run as root${NC}"
        echo "Please run: curl -fsSL ... | sudo bash"
        exit 1
    fi
}

check_system() {
    echo -e "${BLUE}[1/5] Checking system requirements...${NC}"

    # Check OS
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo -e "  OS: ${GREEN}$PRETTY_NAME${NC}"
    fi

    # Check required commands
    local required_cmds=("bash" "openssl" "gpg" "tar" "systemctl")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}Error: Required command '$cmd' not found${NC}"
            exit 1
        fi
    done
    echo -e "  Required tools: ${GREEN}OK${NC}"

    # Check for curl or wget
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        echo -e "${RED}Error: Either curl or wget is required${NC}"
        exit 1
    fi
    echo -e "  Download tool: ${GREEN}OK${NC}"

    # Check systemd
    if ! pidof systemd &> /dev/null; then
        echo -e "${YELLOW}Warning: systemd not detected. Timers may not work.${NC}"
    else
        echo -e "  systemd: ${GREEN}OK${NC}"
    fi
}

install_dependencies() {
    echo -e "${BLUE}[2/5] Installing dependencies...${NC}"

    # Update package list (suppress output)
    apt-get update -qq 2>/dev/null || true

    # Install pigz if not present
    if ! command -v pigz &> /dev/null; then
        echo -e "  Installing pigz..."
        apt-get install -y -qq pigz 2>/dev/null || echo -e "  ${YELLOW}pigz install failed - will use gzip${NC}"
    fi
    if command -v pigz &> /dev/null; then
        echo -e "  pigz: ${GREEN}OK${NC}"
    fi

    # Install rclone if not present
    if ! command -v rclone &> /dev/null; then
        echo -e "  Installing rclone..."
        if command -v curl &> /dev/null; then
            curl -fsSL https://rclone.org/install.sh | bash -s beta 2>/dev/null || true
        fi
    fi
    if command -v rclone &> /dev/null; then
        echo -e "  rclone: ${GREEN}OK${NC}"
    else
        echo -e "  rclone: ${YELLOW}Not installed - install manually or via setup${NC}"
    fi
}

download_file() {
    local url="$1"
    local target="$2"

    if command -v curl &> /dev/null; then
        if ! curl -fsSL "$url" -o "$target"; then
            return 1
        fi
    elif command -v wget &> /dev/null; then
        if ! wget -q "$url" -O "$target"; then
            return 1
        fi
    fi

    # Verify download
    if [[ ! -s "$target" ]]; then
        return 1
    fi

    return 0
}

download_scripts() {
    echo -e "${BLUE}[3/5] Downloading backupd...${NC}"

    # Create installation directories
    mkdir -p "$INSTALL_DIR"
    mkdir -p "${INSTALL_DIR}/scripts"
    mkdir -p "${INSTALL_DIR}/logs"
    mkdir -p "${INSTALL_DIR}/lib"

    # Download main script
    local script_url="${GITHUB_RAW}/${SCRIPT_NAME}"
    local target_path="${INSTALL_DIR}/${SCRIPT_NAME}"

    echo -e "  Downloading main script..."
    if ! download_file "$script_url" "$target_path"; then
        echo -e "${RED}Error: Failed to download main script${NC}"
        exit 1
    fi

    # Check if it looks like a bash script
    if ! head -1 "$target_path" | grep -q "^#!"; then
        echo -e "${RED}Error: Downloaded file does not appear to be a valid script${NC}"
        echo -e "${RED}First line: $(head -1 "$target_path")${NC}"
        exit 1
    fi

    chmod +x "$target_path"
    echo -e "  Main script: ${GREEN}OK${NC}"

    # Download library modules
    echo -e "  Downloading library modules..."
    local failed_modules=()

    for module in "${LIB_MODULES[@]}"; do
        local module_url="${GITHUB_RAW}/lib/${module}"
        local module_path="${INSTALL_DIR}/lib/${module}"

        if ! download_file "$module_url" "$module_path"; then
            failed_modules+=("$module")
            echo -e "    ${RED}Failed: ${module}${NC}"
        else
            chmod +x "$module_path"
            echo -e "    ${GREEN}OK: ${module}${NC}"
        fi
    done

    if [[ ${#failed_modules[@]} -gt 0 ]]; then
        echo -e "${RED}Error: Failed to download ${#failed_modules[@]} module(s): ${failed_modules[*]}${NC}"
        exit 1
    fi

    # Create symlink
    ln -sf "$target_path" "$BIN_LINK"

    echo -e "  Script: ${GREEN}${target_path}${NC}"
    echo -e "  Command: ${GREEN}backupd${NC}"
}

create_systemd_units() {
    echo -e "${BLUE}[4/5] Creating systemd service units...${NC}"

    # Database backup service
    cat > /etc/systemd/system/backupd-db.service << 'EOF'
[Unit]
Description=Backupd - Database Backup
After=network-online.target mysql.service mariadb.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/backupd/scripts/db_backup.sh
StandardOutput=append:/etc/backupd/logs/db_logfile.log
StandardError=append:/etc/backupd/logs/db_logfile.log
Nice=10
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
EOF

    # Database backup timer
    cat > /etc/systemd/system/backupd-db.timer << 'EOF'
[Unit]
Description=Backupd - Database Backup Timer
Requires=backupd-db.service

[Timer]
OnCalendar=*-*-* 0/2:00:00
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Files backup service
    cat > /etc/systemd/system/backupd-files.service << 'EOF'
[Unit]
Description=Backupd - Files Backup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/backupd/scripts/files_backup.sh
StandardOutput=append:/etc/backupd/logs/files_logfile.log
StandardError=append:/etc/backupd/logs/files_logfile.log
Nice=10
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
EOF

    # Files backup timer
    cat > /etc/systemd/system/backupd-files.timer << 'EOF'
[Unit]
Description=Backupd - Files Backup Timer
Requires=backupd-files.service

[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Reload systemd
    systemctl daemon-reload

    echo -e "  Services: ${GREEN}Created${NC}"
    echo -e "  Timers: ${GREEN}Created (not enabled yet)${NC}"
}

print_success() {
    echo -e "${BLUE}[5/5] Installation complete!${NC}"
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}            Installation Successful!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${CYAN}To get started, run:${NC}"
    echo ""
    echo -e "    ${YELLOW}sudo backupd${NC}"
    echo ""
    echo -e "  ${CYAN}This will guide you through:${NC}"
    echo "    1. Database credentials setup"
    echo "    2. Cloud storage configuration (rclone)"
    echo "    3. Backup scheduling"
    echo "    4. Notification settings (optional)"
    echo ""
    echo -e "  ${CYAN}Documentation:${NC}"
    echo -e "    https://github.com/wnstify/backupd"
    echo ""
}

uninstall() {
    echo -e "${YELLOW}Uninstalling Backupd...${NC}"

    # Stop and disable timers
    systemctl stop backupd-db.timer 2>/dev/null || true
    systemctl stop backupd-files.timer 2>/dev/null || true
    systemctl stop backupd-verify.timer 2>/dev/null || true
    systemctl disable backupd-db.timer 2>/dev/null || true
    systemctl disable backupd-files.timer 2>/dev/null || true
    systemctl disable backupd-verify.timer 2>/dev/null || true

    # Remove systemd units
    rm -f /etc/systemd/system/backupd-db.service
    rm -f /etc/systemd/system/backupd-db.timer
    rm -f /etc/systemd/system/backupd-files.service
    rm -f /etc/systemd/system/backupd-files.timer
    rm -f /etc/systemd/system/backupd-verify.service
    rm -f /etc/systemd/system/backupd-verify.timer
    systemctl daemon-reload

    # Remove symlink
    rm -f "$BIN_LINK"

    # Ask about config/secrets
    echo ""
    echo "Remove configuration and encrypted secrets? (y/N): "
    read -r remove_config < /dev/tty 2>/dev/null || remove_config="N"

    if [[ "$remove_config" =~ ^[Yy]$ ]]; then
        # Try to find and remove secrets directory
        if [[ -f "${INSTALL_DIR}/.secrets_location" ]]; then
            local secrets_dir
            secrets_dir=$(cat "${INSTALL_DIR}/.secrets_location" 2>/dev/null)
            if [[ -n "$secrets_dir" ]] && [[ -d "$secrets_dir" ]]; then
                # Unlock files first (including .s salt file)
                chattr -i "$secrets_dir" 2>/dev/null || true
                for f in ".s" ".c1" ".c2" ".c3" ".c4" ".c5"; do
                    [[ -f "$secrets_dir/$f" ]] && chattr -i "$secrets_dir/$f" 2>/dev/null || true
                done
                rm -rf "$secrets_dir"
                echo -e "  ${GREEN}Removed secrets directory${NC}"
            fi
        fi
        # Fallback: search for secrets directories
        for dir in /etc/.*; do
            if [[ -d "$dir" ]] && [[ -f "$dir/.c1" ]]; then
                chattr -i "$dir" 2>/dev/null || true
                for f in ".s" ".c1" ".c2" ".c3" ".c4" ".c5"; do
                    [[ -f "$dir/$f" ]] && chattr -i "$dir/$f" 2>/dev/null || true
                done
                rm -rf "$dir"
                echo -e "  ${GREEN}Removed secrets directory: $dir${NC}"
            fi
        done
        rm -rf "$INSTALL_DIR"
        echo -e "${GREEN}Configuration and secrets removed.${NC}"
    else
        rm -f "${INSTALL_DIR}/${SCRIPT_NAME}"
        rm -rf "${INSTALL_DIR}/lib"
        echo -e "${GREEN}Scripts removed. Configuration preserved at ${INSTALL_DIR}${NC}"
    fi

    echo -e "${GREEN}Uninstallation complete.${NC}"
    exit 0
}

# Main
main() {
    # Check for uninstall flag
    if [[ "${1:-}" == "--uninstall" ]] || [[ "${1:-}" == "-u" ]]; then
        check_root
        uninstall
    fi

    print_banner
    print_disclaimer
    check_root
    check_system
    install_dependencies
    download_scripts
    create_systemd_units
    print_success
}

main "$@"
