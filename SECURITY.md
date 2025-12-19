# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 2.1.x   | :white_check_mark: |
| 2.0.x   | :white_check_mark: |
| 1.6.x   | :x:                |
| 1.5.x   | :x:                |
| 1.4.x   | :x:                |
| 1.3.x   | :x:                |
| 1.2.x   | :x:                |
| 1.1.x   | :x:                |
| 1.0.x   | :x:                |

We recommend always using the latest version for the best security.

---

## Reporting a Vulnerability

If you discover a security vulnerability in Backupd, please report it responsibly:

1. **Do NOT** open a public GitHub issue for security vulnerabilities
2. **Email us directly** at: security@webnestify.cloud
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Any suggested fixes (optional)

**Response Timeline:**
- We will acknowledge receipt within 48 hours
- We aim to provide an initial assessment within 7 days
- Critical vulnerabilities will be prioritized for immediate patching

---

## Security Model

### How Credentials Are Protected

**Modern (v3 - Argon2id, default for new installations):**
```
┌─────────────────┐     ┌──────────────┐     ┌─────────────────┐
│   machine-id    │────▶│   + salt     │────▶│    Argon2id     │
│  (unique/server)│     │  (random)    │     │  (derived key)  │
└─────────────────┘     └──────────────┘     └────────┬────────┘
                                                      │
                                                      ▼
┌─────────────────┐     ┌──────────────┐     ┌─────────────────┐
│  Your secrets   │────▶│   AES-256    │────▶│  .enc files     │
│  (credentials)  │     │  + PBKDF2    │     │  (encrypted)    │
└─────────────────┘     └──────────────┘     └─────────────────┘
```

**Fallback (v2 - PBKDF2, when argon2 not installed):**
```
┌─────────────────┐     ┌──────────────┐     ┌─────────────────┐
│   machine-id    │────▶│   + salt     │────▶│  SHA256 hash    │
│  (unique/server)│     │  (random)    │     │  (derived key)  │
└─────────────────┘     └──────────────┘     └────────┬────────┘
                                                      │
                                                      ▼
┌─────────────────┐     ┌──────────────┐     ┌─────────────────┐
│  Your secrets   │────▶│   AES-256    │────▶│  .enc files     │
│  (credentials)  │     │  + PBKDF2    │     │  (encrypted)    │
└─────────────────┘     └──────────────┘     └─────────────────┘
```

### Encryption Versions

| Version | Key Derivation | PBKDF2 Iterations | Status |
|---------|----------------|-------------------|--------|
| v3 | Argon2id (64MB, 3 iter) | 100,000 | **Default** (modern) |
| v2 | SHA256 | 800,000 | Fallback (if argon2 not installed) |
| v1 | SHA256 | 100,000 | Legacy (existing installs) |

### Encryption Details

| Component | v3 (Argon2id) | v2/v1 (PBKDF2) |
|-----------|---------------|----------------|
| **Encryption Algorithm** | AES-256-CBC | AES-256-CBC |
| **Key Derivation** | Argon2id(machine-id + salt) | SHA256(machine-id + salt) |
| **Argon2id Memory** | 64MB (2^16) | N/A |
| **Argon2id Iterations** | 3 | N/A |
| **Argon2id Parallelism** | 4 threads | N/A |
| **PBKDF2 Iterations** | 100,000 | 800,000 (v2) / 100,000 (v1) |
| **Salt** | Random 64-byte value, unique per installation | Same |
| **Machine Binding** | `/etc/machine-id` (Linux standard) | Same |

### Why Argon2id?

Argon2id is recommended by OWASP (2023) for password hashing and key derivation:

- **Memory-hard**: Requires 64MB RAM, making GPU attacks expensive
- **Time-hard**: Multiple iterations prevent brute-force attacks
- **Parallelism**: Utilizes multiple CPU cores efficiently
- **Side-channel resistant**: The "id" variant is resistant to timing attacks

### Encryption Migration

Existing installations can upgrade to modern encryption:

```bash
# Check current encryption status
sudo backupd --encryption-status

# Upgrade to best available encryption
sudo backupd --migrate-encryption
```

Migration safely:
1. Decrypts all secrets with current algorithm
2. Re-encrypts with best available algorithm
3. Regenerates backup scripts with new encryption

### Protected Credentials

The following secrets are encrypted and stored securely:

| Secret | Purpose |
|--------|---------|
| `.s` | Salt for key derivation (not encrypted, but protected) |
| `.algo` | Encryption version marker (1, 2, or 3) |
| `.c1` | Backup encryption passphrase |
| `.c2` | Database username |
| `.c3` | Database password |
| `.c4` | ntfy notification token (optional) |
| `.c5` | ntfy notification URL (optional) |

### Storage Security

- **Hidden directory**: Secrets stored in `/etc/.{random}/` with random name
- **Immutable flags**: Files protected with `chattr +i` (cannot be modified/deleted without unlocking)
- **Restrictive permissions**: All files created with `umask 077` (owner-only access)
- **No plain-text storage**: Credentials are never written to disk unencrypted

---

## Threat Model

### What This Protects Against

| Threat | Protected? | Notes |
|--------|------------|-------|
| Casual file browsing | :white_check_mark: Yes | Encrypted, hidden directory |
| Automated malware scanners | :white_check_mark: Yes | No recognizable patterns |
| Credential harvesting scripts | :white_check_mark: Yes | No plain-text credentials |
| Log file exposure | :white_check_mark: Yes | Passwords never logged |
| Server migration/cloning | :white_check_mark: Yes | Credentials tied to machine-id |
| Backup file theft | :white_check_mark: Yes | Backups encrypted with GPG |
| Man-in-the-middle | :white_check_mark: Yes | rclone uses TLS for transfers |
| Attacker with root access | :warning: Partial | See limitations below |

### Honest Limitations

**If an attacker gains root access** to your running server, they could potentially:

1. Extract the `/etc/machine-id`
2. Find and read the salt file
3. Derive the encryption key
4. Decrypt the stored credentials

**This is a fundamental limitation** — no solution can fully protect secrets on a compromised server where the secrets must be usable by running processes. Our approach:

- Raises the bar significantly above plain-text storage
- Stops opportunistic and automated attacks
- Prevents credential reuse if server is cloned
- Is NOT impenetrable against a determined attacker with persistent root access

### What We DON'T Protect Against

- Physical access to the server
- Kernel-level rootkits
- Memory forensics on a running system
- Compromised cloud storage provider
- Weak encryption passwords chosen by user

---

## Security Best Practices

### Server Hardening

1. **SSH Security**
   ```bash
   # Disable password authentication
   sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
   systemctl restart sshd
   ```

2. **Firewall Configuration**
   ```bash
   # UFW example
   ufw default deny incoming
   ufw default allow outgoing
   ufw allow ssh
   ufw allow http
   ufw allow https
   ufw enable
   ```

3. **Fail2ban Installation**
   ```bash
   apt install fail2ban
   systemctl enable fail2ban
   systemctl start fail2ban
   ```

4. **Automatic Security Updates**
   ```bash
   apt install unattended-upgrades
   dpkg-reconfigure -plow unattended-upgrades
   ```

### Backup Security

1. **Strong Encryption Password** (enforced during setup)
   - **Minimum 12 characters** (enforced)
   - **At least 2 special characters** (enforced)
   - Recommended: 16+ characters with mix of uppercase, lowercase, numbers
   - Don't reuse passwords from other services

2. **Cloud Storage Security**
   - Enable 2FA on your cloud storage account
   - Use application-specific API keys (not main account password)
   - Regularly rotate API credentials

3. **Retention Policy**
   - Set appropriate retention (we recommend 14-30 days)
   - Shorter retention = less exposure if credentials compromised
   - Longer retention = more recovery options

4. **Regular Verification**
   - Weekly quick checks run automatically (no download, low bandwidth)
   - Monthly reminders prompt you to test actual restorability
   - Periodically test restore process manually
   - Monitor backup notifications (if configured)

5. **Optional Notifications**
   - ntfy notifications are optional - all operations work without them
   - If not configured, backups/restores/verifications run normally
   - Consider enabling for critical production systems

### Credential Rotation

We recommend rotating credentials periodically:

| Credential | Recommended Rotation |
|------------|---------------------|
| Database password | Every 90 days |
| Cloud storage API keys | Every 180 days |
| Encryption passphrase | Annually (requires re-backup) |

To rotate credentials, run:
```bash
sudo backupd
# Select: Reconfigure
```

---

## Database Backup Security

### What's Backed Up

- All database **content** (tables, data, views, procedures)
- Database **structure** (schemas, indexes)

### What's NOT Backed Up

- MySQL/MariaDB **users** (stored in `mysql.user` table)
- **Grants/permissions** (would require `--flush-privileges`)
- **Binary logs** (for point-in-time recovery)

This is intentional — backing up MySQL system tables can cause issues when restoring to a different server or MySQL version.

### Secure Database Dump

The backup script uses secure practices:

```bash
# Passwords passed via --defaults-extra-file (not command line)
# Temp auth file deleted immediately after use
# ps aux won't show database password
```

---

## File Backup Security

### Backup Encryption

| Component | Method |
|-----------|--------|
| Compression | pigz (parallel gzip) |
| Encryption | GPG symmetric (AES-256) |
| Integrity | SHA256 checksum |

### What's Included

- All files in web root
- Hidden files (`.htaccess`, `.env`, etc.)
- Symlinks (as links, not targets)

### What's Excluded

- Nothing — full backup for disaster recovery
- Previous versions excluded `node_modules`, `vendor`, etc.
- Now we backup everything for complete restore capability

---

## Incident Response

### If You Suspect Compromise

1. **Isolate the server** (if possible)
2. **Check backup integrity**
   ```bash
   sudo backupd
   # Select: Run backup now → Verify backup integrity
   ```
3. **Rotate all credentials**
   - Database passwords
   - Cloud storage API keys
   - Encryption passphrase
4. **Review logs**
   ```bash
   sudo backupd
   # Select: View logs
   ```
5. **Restore from known-good backup** if needed

### If Backups Are Compromised

1. **Change encryption passphrase immediately**
2. **Create new backups** with new passphrase
3. **Delete compromised backups** from cloud storage
4. **Rotate cloud storage credentials**

---

## Update Security

### Current Protections

Updates from GitHub releases include these security measures:

| Protection | Description |
|------------|-------------|
| **HTTPS Only** | Downloads enforce `--proto '=https'` - no HTTP downgrade |
| **SHA256 Verification** | Checksum verification is **required** - updates fail if checksum missing or mismatched |
| **Fail on HTTP Errors** | curl `-f` flag ensures 404/500 errors are caught |
| **Empty File Detection** | Downloads verified to be non-empty |
| **Automatic Rollback** | Failed updates restore previous version |
| **Verified Dependencies** | rclone installed from GitHub releases with SHA256 verification in both installer and setup wizard (no `curl \| bash`) |

### Future Enhancements

**GPG Signing** (planned for future release):
- Release archives will be GPG signed
- Verification will check both SHA256 checksum AND GPG signature
- Provides cryptographic proof of authenticity from maintainers

Until GPG signing is implemented, users should:
- Verify they're downloading from the official GitHub repository
- Check release notes on GitHub before updating
- Use `--check-update` to review before `--update`

---

## Compliance Notes

This tool is designed with security in mind but is provided "as is". Users are responsible for:

- Ensuring compliance with their organization's security policies
- Meeting regulatory requirements (GDPR, HIPAA, PCI-DSS, etc.)
- Proper key management and credential rotation
- Secure disposal of old backups containing sensitive data

---

## Security Changelog

| Version | Security Changes |
|---------|-----------------|
| 2.1.0 | Argon2id encryption, required checksums, HTTPS-only, verified rclone install, strong password requirements (12+ chars, 2+ special), graceful ntfy handling, optimized quick verification |
| 1.5.0 | Secure update system with SHA256 checksum verification of releases |
| 1.4.2 | Configurable database username (reduced privilege support) |
| 1.4.1 | Database restore verification prompt (prevents accidental data loss) |
| 1.2.0 | SHA256 checksums, integrity verification |
| 1.1.0 | MySQL password protection, input validation, disk space checks, timeouts |
| 1.0.0 | Initial release with AES-256 encryption |

---

## Contact

- **Security Issues**: security@webnestify.cloud
- **General Support**: support@webnestify.cloud
- **Website**: [backupd.io](https://backupd.io)

---

<p align="center">
  <strong>Built with security in mind by <a href="https://backupd.io">Backupd</a></strong>
</p>
