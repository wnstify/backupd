# Disclaimer

## Backupd

**Last Updated:** January 2025

---

## Terms of Use

By downloading, installing, or using Backupd ("the Software"), you acknowledge that you have read, understood, and agree to be bound by the terms of this disclaimer.

---

## No Warranty

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT.

IN NO EVENT SHALL THE AUTHORS, COPYRIGHT HOLDERS, OR BACKUPD BE LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT, OR OTHERWISE, ARISING FROM, OUT OF, OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

## Limitation of Liability

### The Author (Backupd) is NOT responsible for:

1. **Data Loss**
   - Loss of databases, files, or any other data
   - Corruption of existing backups
   - Failed backup or restore operations
   - Incomplete or partial backups

2. **System Damage**
   - Server crashes or instability
   - Operating system corruption
   - Service interruptions or downtime
   - Hardware failures triggered by software operations

3. **Security Incidents**
   - Unauthorized access to backups
   - Credential exposure or theft
   - Security vulnerabilities in the software
   - Breaches resulting from misconfiguration

4. **Financial Losses**
   - Business interruption costs
   - Lost revenue due to downtime
   - Recovery expenses
   - Third-party liability claims

5. **Misuse**
   - Improper configuration by the user
   - Use in unsupported environments
   - Modifications to the software
   - Ignoring documented warnings and recommendations

---

## User Responsibilities

### Before Using This Software, You MUST:

1. **Create a Server Snapshot**
   - Always create a full server snapshot before running any backup or restore operations
   - Verify the snapshot was created successfully
   - Keep snapshots until you've verified the operation completed correctly

2. **Test in a Safe Environment**
   - Test the software in a non-production environment first
   - Verify backup integrity before relying on them
   - Practice restore procedures before you need them

3. **Maintain Your Own Backups**
   - Do not rely solely on this tool for your backup strategy
   - Maintain independent backup copies
   - Store backups in multiple locations

4. **Secure Your Credentials**
   - Use strong, unique encryption passwords
   - Store passwords securely (not on the server)
   - Protect access to your cloud storage credentials

5. **Monitor Backup Operations**
   - Regularly check backup logs for errors
   - Verify backups are being created as scheduled
   - Test restore procedures periodically

---

## Software Limitations

### This Software:

- Is designed for **Linux servers** with **MySQL/MariaDB** database environments
- Supports web applications (WordPress, Laravel, Node.js, PHP, static sites, etc.)
- Requires **root access** and proper system configuration
- Depends on **third-party tools** (rclone, gpg, mysql/mariadb, etc.)
- May not be compatible with all server configurations
- Is provided for **general use cases** and may not suit specific needs

### This Software Does NOT:

- Guarantee 100% backup success
- Protect against hardware failures during operations
- Replace professional backup solutions for critical systems
- Provide any form of data recovery services
- Offer technical support or SLA guarantees

---

## Security Considerations

### The Software Implements:

- AES-256 encryption for credentials and backups
- Machine-bound encryption keys
- Secure storage with file permission restrictions

### However:

- No security measure is 100% foolproof
- A compromised root account can access all data
- Physical access to the server can bypass protections
- The software cannot protect against sophisticated attacks
- You are responsible for overall server security

---

## Third-Party Dependencies

This software relies on third-party tools and services:

| Dependency | Responsibility |
|------------|---------------|
| rclone | The rclone project |
| GPG | GNU Privacy Guard project |
| MySQL/MariaDB | Oracle/MariaDB Foundation |
| OpenSSL | OpenSSL project |
| ntfy.sh | ntfy project |
| Cloud Storage | Your chosen provider |

**Backupd is not responsible for:**
- Bugs or vulnerabilities in third-party software
- Changes to third-party APIs or services
- Service outages of cloud storage providers
- Data handling by third-party services

---

## Recommended Precautions

### Always:

✅ Create server snapshots before major operations  
✅ Test backups by performing regular test restores  
✅ Store encryption passwords in a secure password manager  
✅ Monitor backup notifications and logs  
✅ Keep multiple backup copies in different locations  
✅ Document your backup and recovery procedures  
✅ Keep the software updated to the latest version  

### Never:

❌ Use in production without thorough testing  
❌ Store encryption passwords on the same server  
❌ Ignore backup failure notifications  
❌ Assume backups are working without verification  
❌ Rely on a single backup location  
❌ Run restore operations without a snapshot  

---

## Acceptance

By using this software, you acknowledge and accept:

1. You have read and understood this disclaimer
2. You accept all risks associated with using this software
3. You will not hold Backupd liable for any damages
4. You are solely responsible for your data and backups
5. You will take appropriate precautions as described above

---

## Contact

For questions about this disclaimer:

- **Website:** [backupd.io](https://backupd.io)
- **GitHub:** [github.com/wnstify/backupd](https://github.com/wnstify/backupd)

---

## License

This software is released under the MIT License. See the [LICENSE](LICENSE) file for the complete license text.

---

<p align="center">
  <strong>Backupd</strong><br>
  Copyright © 2025 Backupd<br>
  <a href="https://backupd.io">backupd.io</a>
</p>