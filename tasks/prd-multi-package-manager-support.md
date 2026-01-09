# PRD: Multi-Package Manager Support

**Feature:** Cross-distribution package manager detection and installation
**GitHub Issue:** #7
**Created:** 2026-01-09
**Status:** Draft

---

## 1. Introduction/Overview

Backupd currently hardcodes `apt-get` for all package installations (bzip2, argon2, unzip), limiting installation to Debian/Ubuntu-based systems. This feature adds automatic package manager detection to support all major Linux distributions including RHEL, AlmaLinux, Rocky Linux, Fedora, Arch Linux, Alpine, openSUSE, and others.

The solution detects the OS first, then uses the appropriate package manager. This enables backupd to install on any major Linux distribution without manual intervention.

---

## 2. Goals

- Support all major Linux distributions with native package managers
- Detect OS/distro reliably before attempting package installation
- Apply package manager abstraction to ALL package installations (bzip2, argon2, unzip)
- Gracefully handle unsupported distributions with clear user guidance
- Maintain backward compatibility with existing Debian/Ubuntu installations
- Zero changes to end-user workflow on supported systems

---

## 3. User Stories

### US-001: Package Manager Auto-Detection
**Description:** As a system administrator on RHEL/AlmaLinux/Rocky Linux, I want backupd to automatically detect and use dnf/yum so that I can install backupd without manual dependency installation.

**Acceptance Criteria:**
- [ ] Script detects `/etc/os-release` or equivalent to identify distribution
- [ ] Correct package manager is selected based on detected OS
- [ ] Installation succeeds without user intervention on supported distros
- [ ] No hardcoded `apt-get` calls remain in the codebase

---

### US-002: bzip2 Installation on RHEL-family
**Description:** As a user on Rocky Linux 9, I want bzip2 to install automatically when needed for restic extraction so that the installation completes successfully.

**Acceptance Criteria:**
- [ ] bzip2 installs via `dnf install -y bzip2` on RHEL 8+/Fedora
- [ ] bzip2 installs via `yum install -y bzip2` on RHEL 7/CentOS 7
- [ ] Installation succeeds on AlmaLinux 8, AlmaLinux 9
- [ ] Installation succeeds on Rocky Linux 8, Rocky Linux 9

---

### US-003: argon2 Installation Across Distros
**Description:** As a security-conscious user on Arch Linux, I want argon2 to install automatically so that I get Argon2id encryption without manual setup.

**Acceptance Criteria:**
- [ ] argon2 installs via `pacman -S --noconfirm argon2` on Arch
- [ ] argon2 installs via `apk add argon2` on Alpine
- [ ] argon2 installs via `zypper install -y argon2` on openSUSE
- [ ] Fallback message updated to show distro-appropriate install command

---

### US-004: unzip Installation Across Distros
**Description:** As a user on Fedora, I want unzip to install automatically during rclone installation so that remote sync setup works seamlessly.

**Acceptance Criteria:**
- [ ] unzip installs via appropriate package manager on all supported distros
- [ ] Both `install.sh` and `lib/core.sh` use the abstraction

---

### US-005: Unsupported Distribution Handling
**Description:** As a user on an unsupported/niche distribution, I want clear instructions on what to install manually so that I can still use backupd.

**Acceptance Criteria:**
- [ ] Unsupported distro is detected (not silently assumed)
- [ ] Warning message lists required packages: `bzip2`, `argon2` (optional), `unzip`
- [ ] Script continues without attempting package installation
- [ ] No installation failure on unsupported distros (graceful skip)

---

### US-006: Error Message Updates
**Description:** As a user who sees an error about missing argon2, I want the error message to show the correct install command for my distro.

**Acceptance Criteria:**
- [ ] `backupd.sh` error messages detect distro and show correct command
- [ ] `lib/crypto.sh` error messages detect distro and show correct command
- [ ] Messages cover: apt, dnf, yum, pacman, apk, zypper

---

## 4. Functional Requirements

**FR-1:** The system must detect the Linux distribution by reading `/etc/os-release` (primary) or `/etc/redhat-release`, `/etc/debian_version` (fallback).

**FR-2:** The system must map detected distributions to package managers:
| Distribution Family | Package Manager | Update Command | Install Command |
|---------------------|-----------------|----------------|-----------------|
| Debian, Ubuntu, Mint | apt-get | `apt-get update -qq` | `apt-get install -y -qq PKG` |
| RHEL 8+, Fedora, AlmaLinux, Rocky | dnf | (none required) | `dnf install -y PKG` |
| RHEL 7, CentOS 7 | yum | (none required) | `yum install -y PKG` |
| Arch, Manjaro | pacman | `pacman -Sy` | `pacman -S --noconfirm PKG` |
| Alpine | apk | `apk update` | `apk add PKG` |
| openSUSE, SLES | zypper | `zypper refresh` | `zypper install -y PKG` |

**FR-3:** The system must provide a reusable function `pkg_install()` that:
- Accepts a package name as argument
- Uses the detected package manager
- Returns success/failure status
- Suppresses verbose output (quiet mode)

**FR-4:** The system must provide a function `pkg_update()` that:
- Runs the package manager's update/refresh command
- Only runs once per installation session (cached flag)
- Silently skips for package managers that don't require updates (dnf, yum)

**FR-5:** The system must replace ALL existing `apt-get install` calls:
- `install.sh:134` - `apt-get update`
- `install.sh:153` - argon2 installation
- `install.sh:270` - unzip installation (if present)
- `install.sh:385` - bzip2 installation
- `lib/core.sh:730` - unzip installation

**FR-6:** The system must update ALL user-facing error messages that reference `apt install`:
- `backupd.sh:362` - argon2 suggestion
- `backupd.sh:395` - argon2 suggestion
- `lib/crypto.sh:377` - argon2 error

**FR-7:** The system must assume root privileges (no sudo wrapper needed).

**FR-8:** On unsupported distributions, the system must:
- Print a warning with required packages list
- Skip package installation (not fail)
- Continue with the rest of the installation

**FR-9:** Package name mapping for cross-distro differences:
| Generic | Debian/Ubuntu | RHEL/Fedora | Arch | Alpine | openSUSE |
|---------|---------------|-------------|------|--------|----------|
| bzip2 | bzip2 | bzip2 | bzip2 | bzip2 | bzip2 |
| argon2 | argon2 | argon2 | argon2 | argon2 | argon2 |
| unzip | unzip | unzip | unzip | unzip | unzip |

(All packages have the same name across distros for this feature.)

---

## 5. Non-Goals (Out of Scope)

- **macOS/BSD support** - This feature targets Linux only
- **Windows/WSL support** - Out of scope
- **Interactive package manager prompts** - All installs must be non-interactive
- **Package version pinning** - Install latest available version
- **Custom repository configuration** - Use default system repos only
- **Containerized environments** - Assume standard OS, not minimal containers
- **Non-root installation** - Script assumes root privileges per user requirement

---

## 6. Technical Considerations

### File Changes Required

1. **`install.sh`** - Main changes:
   - Add `detect_package_manager()` function near top
   - Add `pkg_install()` wrapper function
   - Add `pkg_update()` wrapper function (with run-once flag)
   - Replace all `apt-get` calls

2. **`lib/core.sh`** - Minor changes:
   - Replace `apt-get install unzip` with `pkg_install unzip`
   - May need to source package manager functions or duplicate detection

3. **`backupd.sh`** and **`lib/crypto.sh`** - Error message updates:
   - Add `get_install_hint()` function to return distro-appropriate command
   - Update hardcoded `apt install argon2` strings

### Detection Logic

```bash
detect_package_manager() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
            debian|ubuntu|linuxmint|pop) echo "apt" ;;
            rhel|centos|fedora|almalinux|rocky|ol)
                command -v dnf &>/dev/null && echo "dnf" || echo "yum" ;;
            arch|manjaro) echo "pacman" ;;
            alpine) echo "apk" ;;
            opensuse*|sles) echo "zypper" ;;
            *) echo "unknown" ;;
        esac
    elif [[ -f /etc/redhat-release ]]; then
        command -v dnf &>/dev/null && echo "dnf" || echo "yum"
    elif [[ -f /etc/debian_version ]]; then
        echo "apt"
    else
        echo "unknown"
    fi
}
```

### Dependencies

- No new external dependencies
- Uses only standard shell features and `/etc/os-release`

### Testing Considerations

- Test on: Ubuntu 22.04, Debian 12, RHEL 9, AlmaLinux 9, Rocky 9, Fedora 39, Arch, Alpine 3.19
- Can use Docker containers for multi-distro testing
- Verify both fresh installs and upgrades

---

## 7. Success Metrics

- **Installation success rate:** 100% on all listed distributions (vs current 100% Debian-only)
- **Zero regression:** Existing Debian/Ubuntu installations work identically
- **User reports:** GitHub issue #7 closed, no new distro-related issues
- **Code quality:** Single source of truth for package installation (no duplicated apt-get calls)

---

## 8. Open Questions

1. **Q:** Should we cache the detected package manager in a variable or detect each time?
   **A:** Cache in global variable at script start for consistency and performance.

2. **Q:** Should `lib/core.sh` duplicate the detection logic or source from a shared location?
   **A:** TBD during implementation - may need to add to `lib/core.sh` since it's sourced by main script.

3. **Q:** Are there any package name differences we missed?
   **A:** Research needed - argon2 may be `argon2-cli` on some distros.

---

## 9. Implementation Order

1. Add detection functions to `install.sh`
2. Replace `install.sh` apt-get calls with new abstraction
3. Update `lib/core.sh` unzip installation
4. Update error messages in `backupd.sh` and `lib/crypto.sh`
5. Test on multiple distributions
6. Update documentation if needed

---

## Appendix: Current apt-get Locations

```
install.sh:134:    apt-get update -qq
install.sh:153:    apt-get install -y -qq argon2
install.sh:270:    apt-get install -y -qq unzip
install.sh:385:    apt-get install -y -qq bzip2
lib/core.sh:730:   apt-get install -y -qq unzip
backupd.sh:362:    "sudo apt install argon2" (error message)
backupd.sh:395:    "sudo apt install argon2" (error message)
lib/crypto.sh:377: "sudo apt install argon2" (error message)
```
