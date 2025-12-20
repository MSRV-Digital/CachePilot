# CachePilot - Security Policy & Guide

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>  
Company: MSRV Digital  
Version: 2.1.0-beta  
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital

---

**BETA SOFTWARE NOTICE**

This is beta software under active development. Read this entire document before production deployment. While core functionality is stable and tested, some features may have limitations. Maintain regular backups and test thoroughly in staging environments first.

---

## Reporting Security Vulnerabilities

**DO NOT** create public GitHub issues for security vulnerabilities.

**Email:** cachepilot@msrv-digital.de

Include:
- Clear description of the vulnerability
- Steps to reproduce
- Potential impact
- CachePilot version and OS
- Suggested fix (optional)

**Response time:** Within 48 hours

## Security Overview

CachePilot implements defense-in-depth security:

- **Authentication:** API key-based authentication required
- **Encryption:** TLS/SSL for all Redis connections (mandatory)
- **Input Validation:** Strict validation and sanitization
- **Rate Limiting:** Protection against abuse and DoS
- **Audit Logging:** Comprehensive security event logging
- **Secure Defaults:** Security-first default configuration

## Critical Installation Notes

CachePilot makes significant system modifications:
- Installs and configures Nginx
- Manages Docker containers
- Configures SSL/TLS certificates
- Modifies system networking

**Before Installation:**
1. Create full system backup
2. Review installation script
3. Use Ubuntu 22.04+ or Debian 12+ only
4. Plan rollback procedure

### ⚠️ CRITICAL: Installation Security

**NEVER share installation logs, screenshots, or terminal output publicly!**

During installation, sensitive information is displayed that could compromise your system:
- API keys are generated and saved to `/root/.cachepilot-api-key`
- System configuration details are shown
- Network information may be exposed

**After Installation:**
1. **Immediately copy** your API key to a secure password manager
2. **Delete the temporary key file:** `rm /root/.cachepilot-api-key`
3. **Clear your shell history** if you viewed the key: `history -c`
4. **Never commit** the key file to version control
5. **Consider rotating** the key after initial setup for additional security

**If you accidentally exposed your API key:**
1. Generate a new key: `cachepilot api key generate production`
2. Update your applications with the new key
3. Revoke the old key: `cachepilot api key revoke admin`
4. Restart the API: `systemctl restart cachepilot-api`

## Essential Security Configuration

### 1. API Security

**API Keys Location:** `/etc/cachepilot/api-keys.json`

```bash
# Secure API keys file (must be 600)
sudo chmod 600 /etc/cachepilot/api-keys.json

# Rotate default key immediately after installation
cachepilot api key generate production
cachepilot api key revoke admin
cachepilot api restart
```

**CORS Configuration** (`/etc/cachepilot/api.yaml`):
```yaml
cors:
  origins:
    - "https://your-domain.com"  # NEVER use "*"
```

**Rate Limiting** (enabled by default):
- 100 requests/minute per endpoint
- 1000 requests/hour globally

### 2. Firewall Configuration

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP (redirects to HTTPS)
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
```

**Never expose:**
- API port 8000 to public internet
- Redis tenant ports directly

### 3. File Permissions

Critical files must have correct permissions:

```bash
# Verify and fix if needed
sudo chmod 600 /etc/cachepilot/api-keys.json
sudo chmod 700 /var/cachepilot/ca
sudo find /var/cachepilot -name "*.key" -exec chmod 600 {} \;
```

### 4. TLS/SSL

**For nginx (Let's Encrypt):**
```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com
```

**Certificate Monitoring:**
```bash
cachepilot check-certs  # Check expiry
# Auto-renewal via cron is configured automatically
```

## Security Checklist

### Pre-Production
- System backup created
- Firewall configured and enabled
- HTTPS with valid certificate
- Default API key rotated
- CORS configured (no wildcards)
- File permissions verified
- Audit logging enabled

### Ongoing Maintenance
- **Daily:** Review critical alerts
- **Weekly:** Check audit logs, verify backups
- **Monthly:** Review firewall rules, test backup restoration
- **Quarterly:** Rotate API keys (recommended every 90 days)
- **Annually:** Security audit, disaster recovery drill

## Common Security Tasks

### Rotate API Key
```bash
cachepilot api key generate new-production-key
# Update applications with new key
cachepilot api key revoke old-key
cachepilot api restart
```

### Check for Suspicious Activity
```bash
# Failed authentication attempts
grep "Authentication failed" /var/log/cachepilot/audit.log

# Unusual tenant operations
grep "Tenant.*deleted" /var/log/cachepilot/audit.log
```

### Block Malicious IP
```bash
sudo ufw deny from <malicious-ip>
```

## Incident Response

If a security incident occurs:

1. **Isolate:** Stop affected services
   ```bash
   sudo systemctl stop cachepilot-api
   ```

2. **Assess:** Review logs for extent of breach
   ```bash
   tail -n 1000 /var/log/cachepilot/audit.log
   ```

3. **Contain:** Block IPs, revoke compromised keys
4. **Recover:** Restore from backup if needed
5. **Document:** Record incident and response actions

## Input Validation

All inputs are validated:
- **Tenant names:** `^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$`
- **Memory limits:** 64 MB - 16384 MB
- **Ports:** 1024-65535
- **Paths:** Canonicalized, within allowed directories

## Audit Logging

Security events logged:
- Authentication attempts (success/failure)
- API key usage and violations
- Tenant operations (create/delete/modify)
- Certificate operations
- Configuration changes

**Log location:** `/var/log/cachepilot/audit.log`

**Retention:** 90 days (configurable in `/etc/cachepilot/logging-config.yaml`)

## Additional Security Measures

### For Sensitive Data
- Use full disk encryption
- Implement additional network isolation
- Consider external HSM for key storage
- Enable SELinux/AppArmor policies
- Implement intrusion detection (IDS/IPS)

### Compliance
If subject to compliance requirements (GDPR, HIPAA, PCI-DSS):
- Consult with compliance officer
- Implement additional controls as required
- Document security measures
- Regular security audits

## Support

For security questions:
- **Email:** cachepilot@msrv-digital.de
- **Response time:** Within 48 hours
- **GPG Key:** Available on request

For detailed deployment guidance, see [DEPLOYMENT.md](DEPLOYMENT.md).

---

Last Updated: 2025-11-04 | Version: 2.1.0-beta
