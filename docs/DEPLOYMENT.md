# CachePilot - Deployment Guide

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>  
Company: MSRV Digital  
Version: 2.1.0-beta  
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital

---

**BETA SOFTWARE NOTICE**

This deployment guide is for CachePilot v2.1.0-beta. The installation process is tested and stable. Use appropriate caution in production environments. Test in staging first, maintain comprehensive backups, and review the Known Issues section in README.md before deploying.

---

## System Requirements

**Supported Operating Systems:**
- Ubuntu 22.04 LTS or later
- Debian 12 or later

**Minimum Hardware:**
- CPU: 2 cores (4+ recommended for production)
- RAM: 4 GB (8+ GB recommended)
- Disk: 20 GB free space

**Required Software:**
- Root or sudo access
- Docker 20.10+
- OpenSSL
- Standard utilities: curl, jq, zip

## Pre-Deployment Planning

**Before installation:**

1. Review all configuration files in `config/`
2. Plan capacity (disk space, memory limits, expected tenant count)
3. Document network topology and firewall requirements
4. Prepare rollback procedure and test restoration
5. Review compliance requirements (if applicable)
6. Schedule deployment window with stakeholders
7. Prepare incident response procedures

## Installation

### 1. Clone Repository

```bash
git clone https://github.com/MSRV-Digital/CachePilot.git
cd CachePilot
```

### 2. Create System Backup

**This is critical.** Create a full system backup before proceeding.

### 3. Run Installation

```bash
sudo ./install/install.sh
```

The installer will:
- Clone repository to `/opt/cachepilot` (Git-based installation)
- Prompt for branch selection: **main** (stable) or **develop** (beta)
- Detect your system configuration
- Install dependencies
- Set up FHS-compliant directory structure
- Configure systemd services
- Optionally install the REST API

**New in v2.1.0:** Git-based installation enables easy updates and rollback. See [GIT-WORKFLOW.md](GIT-WORKFLOW.md) for details.

### 4. Verify Installation

```bash
cachepilot --version
cachepilot system info   # Shows Git branch and commit
cachepilot list
cachepilot health
```

## API Setup

If you didn't install the API during initial setup, run the installer again and choose 'Y' when prompted.

### Generate API Keys

```bash
cachepilot api key generate admin
cachepilot api key generate monitoring
cachepilot api key generate backup-service
```

### Manage API Service

```bash
cachepilot api status    # Check status
cachepilot api logs      # View logs
cachepilot api restart   # Restart service
```

## Security Configuration

For complete security documentation, see [SECURITY.md](SECURITY.md).

### Firewall Rules

```bash
# Reset firewall to defaults (if needed)
sudo ufw --force reset

# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH
sudo ufw allow 22/tcp

# Allow HTTP and HTTPS for nginx
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# API port - ONLY from localhost
sudo ufw allow from 127.0.0.1 to any port 8000

# Enable firewall
sudo ufw enable

# Verify rules
sudo ufw status numbered
```

**Important:**
- Never expose API port 8000 to public internet
- Never expose Redis ports directly - use VPN or stunnel for external access
- Always use the nginx reverse proxy for API access

### SSL/TLS Configuration

All Redis instances use TLS by default with auto-generated certificates.

**For production with Let's Encrypt:**

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d your-domain.com

# Test auto-renewal
sudo certbot renew --dry-run

# Check renewal timer
sudo systemctl status certbot.timer
```

**Certificate Monitoring:**

```bash
# Check certificate expiry
cachepilot check-certs

# Certificates are monitored automatically
# Alerts will be generated 30 days before expiry
```

### API Security

**Generate production API keys:**

```bash
# Generate API keys with descriptive names
cachepilot api key generate production-app
cachepilot api key generate monitoring-service
cachepilot api key generate backup-automation

# List all keys (shows metadata, not actual keys)
cachepilot api key list

# Revoke compromised keys immediately
cachepilot api key revoke <key-name>
cachepilot api restart
```

**API Key Storage:**

Never commit keys to version control. Use environment variables:

```bash
export REDIS_MGR_API_KEY="your-api-key-here"
```

**Verify API Keys File Permissions:**

```bash
# Must be 600
ls -l /etc/cachepilot/api-keys.json

# Fix if needed
sudo chmod 600 /etc/cachepilot/api-keys.json
```

**CORS Configuration:**

Edit `/etc/cachepilot/api.yaml`:
```yaml
cors:
  origins:
    - "https://your-domain.com"
    # NEVER use "*" in production
```

### Password Security

```bash
# Rotate password for a tenant
cachepilot rotate-password <tenant>

# Passwords are automatically generated with 24 characters
# Mixed case, numbers, and symbols
```

## Production Deployment Checklist

### Pre-Deployment

- System backup created
- Firewall configured and enabled
- HTTPS with valid certificate
- Default API key rotated
- CORS configured (no wildcards)
- File permissions verified
- Audit logging enabled
- Monitoring alerts configured and tested
- Automatic backups enabled and tested

### Post-Deployment

- All services running correctly
- Health checks passing
- Monitoring alerts generating appropriately
- Audit logs writing correctly
- TLS certificates valid and auto-renewal working
- Backups completing successfully
- API rate limiting working as expected
- No errors in system logs
- Firewall rules verified
- API accessible via HTTPS through nginx
- Direct API access blocked from external networks

### Ongoing Maintenance

**Daily:**
- Review critical alerts
- Check for failed authentication attempts
- Verify all services are running

**Weekly:**
- Review audit logs for suspicious activity
- Check disk space and resource usage
- Review backup success/failure

**Monthly:**
- Review and update firewall rules
- Audit user access and API keys
- Review monitoring alert thresholds
- Test backup restoration
- Check for security updates

**Quarterly:**
- Rotate API keys (recommended every 90 days)
- Review and update security policies
- Conduct security assessment
- Review incident response procedures

**Annually:**
- Comprehensive security audit
- Disaster recovery drill
- Review compliance requirements

## Monitoring Setup

### Enable Email Alerts

Edit `/etc/cachepilot/monitoring-config.yaml`:

```yaml
notifications:
  email_enabled: true
  email_from: "cachepilot@yourdomain.com"
  email_to: "admin@yourdomain.com"
```

### Enable Webhook Notifications

```yaml
notifications:
  webhook_enabled: true
  webhook_url: "https://your-webhook-endpoint.com/alerts"
```

### Configure Alert Thresholds

```yaml
thresholds:
  disk_space_warning: 80
  disk_space_critical: 90
  memory_warning: 85
  memory_critical: 95
  cert_expiry_warning_days: 30
  cert_expiry_critical_days: 7
```

## Backup Configuration

### Enable Automatic Backups

```bash
# Enable for all tenants
cachepilot backup-enable-all

# Or per tenant
cachepilot backup-enable <tenant>
```

### Configure Retention

Edit `lib/backup.sh`:

```bash
BACKUP_RETENTION_DAYS=30
BACKUP_MAX_COUNT=50
```

### Verify Backups

```bash
cachepilot list-backups <tenant>
cachepilot verify-backup /var/cachepilot/backups/<tenant>/<file>
```

## Maintenance

### Automated Tasks

The installation automatically sets up cron jobs for:
- Nightly maintenance (02:00)
- Health checks
- Metric collection
- Backup cleanup
- Log rotation

### Manual Maintenance

```bash
# Update all instances
cachepilot update all

# Renew certificates
cachepilot renew-certs all

# Check system health
cachepilot health
```

## Troubleshooting

### Check Logs

```bash
# Main log
tail -f /var/log/cachepilot/cachepilot.log

# Audit log
tail -f /var/log/cachepilot/audit.log

# Metrics
tail -f /var/log/cachepilot/metrics.jsonl

# Alerts
cat /var/log/cachepilot/alerts/history.json | jq
```

### API Issues

```bash
# Check API status
systemctl status cachepilot-api

# View API logs
journalctl -u cachepilot-api -f

# Restart API
systemctl restart cachepilot-api
```

### Container Issues

```bash
# List containers
docker ps -a | grep redis-

# Check container logs
cachepilot logs <tenant>

# Restart container
cachepilot restart <tenant>
```

## Rollback Procedure

If issues occur after deployment:

1. **Stop API Service** (if running)
   ```bash
   systemctl stop cachepilot-api
   ```

2. **Restore from Backup**
   ```bash
   cachepilot restore <tenant> /var/cachepilot/backups/<tenant>/<backup-file>
   ```

3. **Check System Health**
   ```bash
   cachepilot health
   cachepilot alerts
   ```

## Performance Tuning

### Memory Limits

```bash
# Adjust per-tenant limits
cachepilot set-mem <tenant> <redis_mb> <docker_mb>
```

### Container Resources

Edit tenant's docker-compose.yml to adjust:
- CPU limits
- Memory limits
- Restart policies

### Monitoring Intervals

Adjust in `/etc/cachepilot/monitoring-config.yaml`:

```yaml
intervals:
  health_check: 300      # 5 minutes
  metric_collection: 60  # 1 minute
  alert_check: 180       # 3 minutes
```

## Scaling Considerations

- Each tenant runs in isolated Docker container
- Port range: 7300-7399 (100 tenants max by default)
- Memory: Plan 512MB-1GB per tenant (including Docker overhead)
- Disk: ~100MB per tenant + backups
- CPU: Redis is single-threaded, distribute across cores via containers

## Git-Based Updates & Maintenance

CachePilot v2.1.0+ uses Git for easy updates and version management.

### Check for Updates

```bash
# Check if updates are available
cachepilot system check-updates

# View current Git status
cachepilot system info
```

### Install Updates

```bash
# Update to latest version
sudo cachepilot system update

# Or manually
sudo bash /opt/cachepilot/install/upgrade.sh
```

### Rollback to Previous Version

```bash
# Interactive rollback to previous commit
sudo cachepilot system rollback

# View Git history
cd /opt/cachepilot
git log --oneline -10
```

### Switch Branches

```bash
# Switch between stable and beta
cd /opt/cachepilot
sudo git checkout develop  # Beta version
sudo git checkout main     # Stable version
sudo cachepilot system update
```

For complete Git workflow documentation, see [GIT-WORKFLOW.md](GIT-WORKFLOW.md).

## Support

For issues or questions:
- GitHub Issues: https://github.com/MSRV-Digital/CachePilot/issues
- Documentation: https://github.com/MSRV-Digital/CachePilot/tree/main/docs
- Git Workflow Guide: [GIT-WORKFLOW.md](GIT-WORKFLOW.md)
- Email: cachepilot@msrv-digital.de
