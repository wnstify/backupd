# Security Documentation

Comprehensive security guide for Backupd - understanding the security model, best practices, and recommendations.

---

## Table of Contents

- [Security Overview](#security-overview)
- [Encryption Architecture](#encryption-architecture)
- [Credential Security](#credential-security)
- [Backup Security](#backup-security)
- [System Hardening](#system-hardening)
- [Best Practices](#best-practices)
- [Security Checklist](#security-checklist)
- [Vulnerability Reporting](#vulnerability-reporting)

---

## Security Overview

Backupd implements defense-in-depth security with multiple protective layers:

| Layer | Protection | Implementation |
|-------|------------|----------------|
| **Credentials** | AES-256-CBC encryption | Machine-bound keys, PBKDF2 |
| **Backups** | GPG symmetric encryption | AES-256, secure passphrase |
| **Storage** | Immutable files | `chattr +i` protection |
| **Processes** | Hidden secrets | File descriptor passphrase passing |
| **Transport** | TLS encryption | rclone encrypted transfers |
| **System** | Isolation | systemd PrivateTmp |

### Security Standards Compliance

| Standard | Status | Details |
|----------|--------|---------|
| OWASP Cryptographic Storage | ✅ Compliant | 600,000 PBKDF2 iterations |
| CIS Linux Benchmark | ✅ Partial | Root-only access, file permissions |
| PCI DSS | ⚠️ Review | Encryption meets standards; audit logging recommended |

---

## Encryption Architecture

### Machine-Bound Key Derivation

Backupd derives encryption keys from the server's unique machine ID, making credentials useless if stolen:

```
/etc/machine-id (32 hex chars)
       ↓
   + Salt (64 bytes, random)
       ↓
   SHA-256 Hash
       ↓
   Derived Key (256-bit)
```

**Key Properties:**
- Keys are never stored on disk
- Derived dynamically at runtime
- Invalid on different machines
- Salt stored in secrets directory

### PBKDF2 Parameters (OWASP 2023)

| Parameter | Value | Standard |
|-----------|-------|----------|
| Algorithm | PBKDF2-SHA256 | NIST SP 800-132 |
| Iterations | 600,000 | OWASP 2023 |
| Key Length | 256 bits | AES-256 requirement |
| Salt Length | 64 bytes | Above minimum (16 bytes) |

### Encryption Algorithms

| Use Case | Algorithm | Key Size | Mode |
|----------|-----------|----------|------|
| Credential Storage | AES-256-CBC | 256-bit | CBC with PKCS7 padding |
| Database Backups | GPG AES-256 | 256-bit | Symmetric encryption |
| Files Backups | None (optional) | - | Compressed only by default |

### Credential Encryption Flow

```
1. User enters password during setup
2. Salt generated (64 random bytes)
3. Machine ID read from /etc/machine-id
4. Key derived: SHA256(machine_id + salt)
5. Password encrypted: AES-256-CBC(password, derived_key)
6. Encrypted value stored in secrets directory
7. File made immutable: chattr +i
```

### Decryption Flow

```
1. Backup script starts
2. Read salt from secrets directory
3. Read machine ID
4. Derive key: SHA256(machine_id + salt)
5. Read encrypted credential
6. Decrypt: AES-256-CBC-decrypt(encrypted, derived_key)
7. Use credential (never written to disk)
8. Clear from memory on exit
```

---

## Credential Security

### Secrets Storage Location

Credentials are stored in a hidden directory with randomized name:

```
/etc/.{12-char-random-id}/
├── .s     # Salt (64 bytes, base64 encoded)
├── .c1    # Encryption passphrase (encrypted)
├── .c2    # Database username (encrypted)
├── .c3    # Database password (encrypted)
├── .c4    # ntfy token (encrypted, optional)
└── .c5    # ntfy URL (encrypted, optional)
```

### File Permissions

| File | Permissions | Attributes |
|------|-------------|------------|
| Secrets directory | 700 | Hidden (dot prefix) |
| Salt file (.s) | 600 | Immutable (chattr +i) |
| Credential files | 600 | Immutable (chattr +i) |
| Config file | 600 | Regular |
| Backup scripts | 700 | Executable by root |
| Log files | 600 | Root readable |

### Immutable Protection

Secrets are protected from modification using Linux extended attributes:

```bash
# Files are locked after setup
chattr +i /etc/.randomid/.s
chattr +i /etc/.randomid/.c1
chattr +i /etc/.randomid/.c2
# etc.

# Only root can remove immutable flag
chattr -i /etc/.randomid/.s  # Requires root + CAP_LINUX_IMMUTABLE
```

### Process Security

Credentials are never exposed in process listings:

**Before (vulnerable):**
```bash
# Visible in `ps aux`
gpg --passphrase "mysecretpassword" --decrypt backup.gpg
mysql -p"databasepassword" ...
```

**After (secure):**
```bash
# Hidden from process list
gpg --passphrase-fd 3 3< <(printf '%s' "$PASSPHRASE") --decrypt backup.gpg
mysql --defaults-extra-file=/tmp/secure-auth.cnf ...
```

---

## Backup Security

### Database Backup Encryption

Database backups are encrypted using GPG symmetric encryption:

```bash
# Encryption command (simplified)
gpg --batch --yes \
    --pinentry-mode=loopback \
    --passphrase-fd 3 3< <(printf '%s' "$PASSPHRASE") \
    --symmetric \
    --cipher-algo AES256 \
    --output backup.tar.gz.gpg \
    backup.tar.gz
```

**GPG Parameters:**
- Cipher: AES-256
- Mode: CFB (GPG default for symmetric)
- Key derivation: String-to-key (S2K)
- Compression: Disabled (already compressed)

### Files Backup Security

By default, files backups are compressed but **not encrypted**:

| Aspect | Default | Reason |
|--------|---------|--------|
| Encryption | Off | Large files, performance |
| Compression | pigz/gzip | Space efficiency |
| Integrity | SHA256 checksum | Corruption detection |

**To enable files encryption:** Modify generated script or use encrypted rclone remote.

### Checksum Verification

Every backup includes SHA256 checksum:

```bash
# Generated automatically
sha256sum backup.tar.gz.gpg > backup.tar.gz.gpg.sha256

# Verified on restore
sha256sum -c backup.tar.gz.gpg.sha256
```

### Transport Security

All uploads use TLS encryption via rclone:

```bash
# rclone encrypts in transit
rclone copy backup.tar.gz.gpg remote:path/

# For additional security, use rclone crypt
rclone config create encrypted-remote crypt \
    remote=actual-remote:path \
    password=xxx
```

---

## System Hardening

### systemd Service Hardening

Backup services run with isolation:

```ini
[Service]
Type=oneshot
PrivateTmp=yes          # Isolated /tmp
NoNewPrivileges=yes     # Prevent privilege escalation (future)
ProtectSystem=strict    # Read-only filesystem (future)
```

### Root-Only Execution

All backupd operations require root:

```bash
# Enforced at entry point
if [[ $EUID -ne 0 ]]; then
    echo "This tool must be run as root."
    exit 1
fi
```

### Lock File Protection

Concurrent operations are prevented:

```bash
# Prevents parallel backups
LOCK_FILE="/var/lock/backupd-db.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "Another backup is running"
    exit 0
fi
```

### Secure Temporary Files

All temporary files are created securely:

```bash
# umask prevents world-readable files
umask 077

# Secure temp directory
TEMP_DIR=$(mktemp -d)

# Cleanup on exit (including errors)
trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM
```

---

## Best Practices

### Password Management

| Do | Don't |
|----|-------|
| Use 16+ character passwords | Use dictionary words |
| Use password manager | Store password on server |
| Use unique password per server | Reuse passwords |
| Store password offline | Share passwords via email |

### Backup Management

| Do | Don't |
|----|-------|
| Test restores regularly | Assume backups work |
| Monitor backup notifications | Ignore failures |
| Keep multiple backup copies | Rely on single location |
| Verify checksums | Skip integrity checks |

### Access Control

| Do | Don't |
|----|-------|
| Use sudo for backupd | Run as unprivileged user |
| Limit SSH access | Allow password SSH login |
| Use key-based authentication | Share root credentials |
| Enable MFA where possible | Disable security features |

### Cloud Storage Security

| Do | Don't |
|----|-------|
| Use dedicated IAM credentials | Use root account keys |
| Enable bucket versioning | Allow public access |
| Use server-side encryption | Store unencrypted |
| Enable access logging | Ignore access patterns |

---

## Security Checklist

### Initial Setup

- [ ] Strong encryption password (16+ chars)
- [ ] Password stored in password manager
- [ ] Unique password for this server
- [ ] Database credentials tested
- [ ] rclone remote properly configured
- [ ] Notifications enabled

### Regular Maintenance

- [ ] Weekly: Check backup notifications
- [ ] Monthly: Verify backup integrity
- [ ] Monthly: Test restore procedure
- [ ] Quarterly: Review access logs
- [ ] Quarterly: Update backupd
- [ ] Annually: Rotate encryption password

### System Security

- [ ] Server snapshot before changes
- [ ] SSH key authentication enabled
- [ ] Firewall configured
- [ ] Fail2ban or similar enabled
- [ ] Regular OS updates
- [ ] Monitoring configured

### Disaster Recovery

- [ ] Encryption password backed up offline
- [ ] Recovery procedure documented
- [ ] Multiple backup locations configured
- [ ] Restore tested from each location
- [ ] Recovery time objective defined

---

## Threat Model

### Protected Against

| Threat | Protection |
|--------|------------|
| Stolen backup files | GPG AES-256 encryption |
| Credential theft | Machine-bound encryption |
| Process snooping | File descriptor passphrase |
| Unauthorized access | Root-only, immutable files |
| Backup tampering | SHA256 checksums |
| Concurrent corruption | flock file locking |

### Not Protected Against

| Threat | Mitigation |
|--------|------------|
| Root compromise | Use separate backup server |
| Physical access | Full disk encryption |
| Machine ID change | Re-run setup on new machine |
| Lost password | Store password securely offline |
| Advanced persistent threats | Security monitoring, EDR |

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Backup corruption | Low | High | Checksums, verification |
| Password loss | Medium | Critical | Password manager |
| Server compromise | Low | Critical | Access controls, monitoring |
| Cloud breach | Low | High | Client-side encryption |

---

## Dependency Security

### Version Requirements

| Dependency | Minimum Safe Version | CVE Concerns |
|------------|---------------------|--------------|
| OpenSSL | 3.0.13+ / 3.1.5+ | CVE-2023-5363 |
| curl | 8.4.0+ | CVE-2023-38545 |
| bash | 5.2-p15+ | CVE-2022-3715 |
| tar | 1.34+ | CVE-2022-48303 |
| GPG | 2.4.0+ | General updates |

### Update Commands

```bash
# Debian/Ubuntu
sudo apt update && sudo apt upgrade openssl curl bash tar gnupg

# RHEL/CentOS
sudo dnf update openssl curl bash tar gnupg2

# Verify versions
openssl version
curl --version | head -1
bash --version | head -1
tar --version | head -1
gpg --version | head -1
```

---

## Audit Logging

### Current Logging

Backupd logs all operations:

```bash
# Log locations
/etc/backupd/logs/db_logfile.log
/etc/backupd/logs/files_logfile.log
/etc/backupd/logs/verify_logfile.log

# Log format
==== 2024-12-16 10:00:00 START db backup ====
[INFO] Operation details...
[ERROR] Error details...
==== 2024-12-16 10:30:00 END (success) ====
```

### Enhanced Audit (Recommended)

For compliance requirements, enable system audit:

```bash
# Install auditd
sudo apt install auditd

# Add audit rules for backupd
sudo auditctl -w /etc/backupd/ -p wa -k backupd
sudo auditctl -w /etc/backupd/scripts/ -p x -k backupd-exec

# View audit logs
sudo ausearch -k backupd
```

---

## Incident Response

### Suspected Compromise

1. **Isolate**: Disconnect server from network
2. **Snapshot**: Create forensic image
3. **Investigate**: Check logs, processes, files
4. **Rotate**: Change all credentials
5. **Restore**: Use verified clean backup
6. **Report**: Document and report incident

### Password Compromise

1. **Rotate**: Change encryption password immediately
2. **Re-encrypt**: Re-run setup to regenerate scripts
3. **Audit**: Review access logs
4. **Notify**: Inform stakeholders if required

### Backup Corruption

1. **Verify**: Run integrity check on recent backups
2. **Identify**: Find last known good backup
3. **Restore**: Test restore from good backup
4. **Investigate**: Check for root cause
5. **Prevent**: Implement additional verification

---

## Vulnerability Reporting

### Reporting Process

If you discover a security vulnerability:

1. **Do NOT** open a public GitHub issue
2. **Email**: security@backupd.io (if available)
3. **Include**: Description, reproduction steps, impact
4. **Encrypt**: Use GPG if sensitive

### Response Timeline

| Severity | Response | Fix |
|----------|----------|-----|
| Critical | 24 hours | 7 days |
| High | 48 hours | 14 days |
| Medium | 7 days | 30 days |
| Low | 14 days | 60 days |

### Recognition

Security researchers who responsibly disclose vulnerabilities will be credited in release notes (with permission).

---

## Security Updates

### Staying Updated

```bash
# Check for updates
backupd --check-update

# Apply updates
sudo backupd --update
```

### Security Announcements

- GitHub Releases: [github.com/wnstify/backupd/releases](https://github.com/wnstify/backupd/releases)
- Website: [backupd.io](https://backupd.io)

---

## Additional Resources

- [OWASP Cryptographic Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html)
- [NIST SP 800-132: Password-Based Key Derivation](https://csrc.nist.gov/publications/detail/sp/800-132/final)
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks)
- [GPG Best Practices](https://riseup.net/en/security/message-security/openpgp/best-practices)

---

<p align="center">
  <strong>Security is a journey, not a destination.</strong><br>
  Keep your systems updated and monitor your backups.
</p>
