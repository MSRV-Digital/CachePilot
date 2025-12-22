# CachePilot

A production-ready system for managing isolated Redis instances with TLS encryption, resource limits, monitoring, and optional RedisInsight.

CachePilot is a suite of Bash scripts for administering multi-tenant Redis environments. It uses Docker for tenant isolation, automates certificate management with a local CA, and provides a command-line interface for management tasks.

This project is designed for hosting providers, agencies, and developers who need to manage Redis services for multiple clients or projects on a single server.

---

**Author:** Patrick Schlesinger, MSRV Digital  
**Version:** 2.1.2-Beta  
**Status:** Beta - Active Development  
**Redis Version:** 7 (stable)  
**License:** MIT  
**FHS Compliant:** Production-ready with Linux Filesystem Hierarchy Standard

---

**BETA SOFTWARE NOTICE**

CachePilot is currently in BETA (v2.1.2-Beta) and under active development.

- Core functionality is stable and tested
- Some features may have bugs or limitations
- Breaking changes may occur in future releases
- Documentation is comprehensive but may have gaps
- User feedback is highly encouraged and appreciated

**For Production Use:**
- Test thoroughly in staging environment first
- Maintain regular backups of all data
- Monitor the project repository for updates
- Report issues via GitHub Issues or email
- Review the Known Issues section below

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to report issues and provide feedback.

---

**SYSTEM MODIFICATION WARNING**

CachePilot makes significant system modifications including:
- Installing and configuring Nginx as a reverse proxy
- Creating system directories and modifying file permissions
- Installing and managing Docker containers for Redis instances
- Generating and managing SSL/TLS certificates
- Modifying system networking configuration

**CRITICAL:** Create a full system backup before installation. Only Ubuntu 22.04+ and Debian 12+ are supported.

See [docs/SECURITY.md](docs/SECURITY.md) for complete security guidelines.

---

**🔒 INSTALLATION SECURITY WARNING**

**NEVER share installation logs, screenshots, or terminal output publicly!**

During installation, sensitive information is generated that could compromise your system if exposed:
- API keys are saved to `/root/.cachepilot-api-key` (temporary file)
- System and network configuration details are displayed

**After installation, you MUST:**
1. Copy your API key to a secure password manager
2. Delete the temporary key file: `rm /root/.cachepilot-api-key`
3. Never commit or share the key file
4. Consider rotating the key after initial setup

**If you accidentally exposed your API key:** See [docs/SECURITY.md](docs/SECURITY.md) for key rotation instructions.

---

## System Requirements

### Supported Operating Systems

**Officially Supported:**
- Ubuntu 22.04 LTS (Jammy Jellyfish) or later
- Debian 12 (Bookworm) or later

### Minimum Hardware Requirements

- **CPU**: 2 cores (4+ recommended for production)
- **RAM**: 4 GB minimum (8+ GB recommended)
- **Disk**: 20 GB free space (+ space for Redis data)
- **Network**: Static IP address recommended for production

### Required Software

The installation script will check for and install missing dependencies, but you should verify:

- Root or sudo access
- Docker 20.10+
- OpenSSL (for certificate generation)
- Standard utilities: curl, jq, zip

## Features

### Core Functionality
- **Multi-Tenant Isolation:** Dedicated Docker containers for data and resource separation
- **TLS Encryption:** Automatic certificate generation from local CA
- **Resource Management:** Per-tenant memory limits for Redis and Docker
- **CLI:** Single command for tenant lifecycle management
- **Optional RedisInsight:** Web interface with auto-configuration

### Monitoring & Observability
- **Health Checks:** Real-time monitoring of system, tenants, certificates, and disk space
- **Alert System:** Multi-severity alerts (info/warning/critical) with email and webhook support
- **Metrics Collection:** Time-series performance data with automatic retention
- **Structured Logging:** JSON-formatted logs with automatic sanitization and rotation
- **Audit Trail:** Log of all operations with user attribution
- **CLI:** JSON output support for monitoring commands

### Backup & Recovery
- **Daily Backups by Default:** All new tenants automatically have daily backups enabled
- **Automated Backups:** Scheduled backups with configurable retention (30 days, 50 max)
- **Manual Backups:** On-demand backup creation with verification
- **Point-in-Time Recovery:** Restore from any backup with rollback protection
- **Backup Status Overview:** Visual overview showing which tenants have backups enabled
- **Bulk Operations:** Enable backups for all existing tenants at once
- **Backup Health Monitoring:** Automated checks and alerts for backup status
- **Retention Policies:** Configurable age-based and count-based cleanup

### REST API
- **RESTful API:** Programmatic access to management operations
- **API Key Authentication:** API key-based authentication with rate limiting
- **Interactive Documentation:** Swagger UI and ReDoc documentation
- **JSON Responses:** Structured JSON responses
- **Service Integration:** Built on FastAPI
- **Coverage:** Manage tenants, monitoring, backups, and system operations via API

### Operations
- **Automated Maintenance:** Cron jobs with health checks, metric collection, and backups
- **Customer Handover:** Auto-generated credential packages

## Getting Started

### Pre-Installation Checklist

**Before installing CachePilot, ensure:**

- Your system is Ubuntu 22.04+ or Debian 12+
- You have created a full system backup
- You have reviewed the installation script
- You have read the Security Policy
- No conflicting services are running (Nginx, port 80/443)
- You have a rollback plan in case of issues
- You understand the system modifications (see warning above)

### Installation

CachePilot v2.1.2+ uses **Git-based deployment** for easier updates and version management.

1. **Download installation files:**
   ```bash
   # Temporary clone for running the installer
   git clone https://github.com/MSRV-Digital/CachePilot.git /tmp/cachepilot-install
   cd /tmp/cachepilot-install
   ```

2. **Create system backup (critical)**

3. **Run installer:**
   ```bash
   sudo ./install/install.sh
   ```
   
   The installer will:
   - Clone the repository to `/opt/cachepilot` (permanent Git-based installation)
   - Select branch: **main** (stable) or **develop** (beta)
   - Check dependencies and install missing packages
   - Set up FHS-compliant directory structure
   - Configure network settings (prompts for IPs)
   - Optionally install REST API (prompts)
   - Configure server domain and SSL (prompts)
   - Optionally build frontend with nginx (prompts)

4. **Verify installation:**
   ```bash
   cachepilot --version
   cachepilot system info   # Shows Git branch and commit
   cachepilot health
   ```

5. **Clean up (optional):**
   ```bash
   cd ~
   rm -rf /tmp/cachepilot-install
   ```

**New in v2.1.2:** Git-based installation enables:
- One-command updates: `sudo cachepilot system update`
- Easy rollback: `sudo cachepilot system rollback`
- Branch switching: stable ↔ beta
- Version tracking with Git history

**Note:** The initial clone in `/tmp` is temporary and only used to run the installer. The installer creates the permanent Git-based installation in `/opt/cachepilot`.

See [docs/GIT-WORKFLOW.md](docs/GIT-WORKFLOW.md) for complete Git workflow documentation.

### Quick Start

- **Create your first tenant:**
  ```bash
  cachepilot new my-first-client
  ```

- **View the list of all tenants:**
  ```bash
  cachepilot list
  ```

- **Get detailed status for a tenant:**
  ```bash
  cachepilot status my-first-client
  ```

- **Enable RedisInsight:**
  ```bash
  cachepilot insight-enable my-first-client
  ```

- **Show global statistics:**
  ```bash
  cachepilot stats
  ```

- **Check system health:**
  ```bash
  cachepilot health
  ```

## Command-Line Interface (CLI)

The `cachepilot` command provides system management. It is symlinked to `/usr/local/bin/cachepilot` for global access.

```
Usage: cachepilot <command> [arguments]

Tenant Management:
  new <tenant> [mem] [docker] [mode]  Create new Redis instance
  rm <tenant>                     Remove instance and all data
  start <tenant>                  Start instance
  stop <tenant>                   Stop instance
  restart <tenant>                Restart instance

Monitoring & Statistics:
  status <tenant>                 Show instance status and statistics
  list                            List all instances with statistics
  stats                           Show global statistics and top consumers
  logs <tenant> [lines]           Show container logs
  health                          Check system health status
  alerts                          List active alerts

Configuration:
  set-mem <tenant> <max> <hard>   Set memory limits (MB)
  set-access <tenant> <mode>      Change security mode (tls-only, dual-mode, plain-only)
  rotate <tenant>                 Rotate password and regenerate handover

Maintenance:
  update all                      Rolling update of all instances
  renew-certs all                 Renew expiring certificates
  check-certs                     Check certificate expiration dates

Backup & Restore:
  backup <tenant>                 Create manual backup
  restore <tenant> <file>         Restore from backup file
  list-backups <tenant>           List available backups
  verify-backup <file>            Verify backup integrity
  backup-enable <tenant>          Enable auto backup (daily)
  backup-disable <tenant>         Disable auto backup
  backup-status                   Show backup status overview
  backup-enable-all               Enable backups for all tenants

RedisInsight:
  insight-enable <tenant>         Enable RedisInsight web interface
  insight-disable <tenant>        Disable RedisInsight
  insight-status <tenant>         Show RedisInsight status and credentials

Handover:
  handover <tenant>               Regenerate handover package for customer

API Management:
  api start                       Start REST API service
  api stop                        Stop REST API service
  api restart                     Restart REST API service
  api status                      Show API service status and URL
  api logs [lines]                Show API service logs
  api key generate <name>         Generate new API key
  api key list                    List all API keys
  api key revoke <name>           Revoke an API key
```

## REST API

CachePilot includes an optional REST API for programmatic access to management operations.

### Quick Start

The API is installed by default during system installation. If you skipped it:

1. Install the API:
   ```bash
   cd /opt/cachepilot
   sudo ./install/scripts/setup-api.sh
   ```

2. The API service starts automatically. To manage it:
   ```bash
   systemctl status cachepilot-api   # Check status
   systemctl restart cachepilot-api  # Restart
   systemctl stop cachepilot-api     # Stop
   ```

3. Generate additional API keys:
   ```bash
   cachepilot api key generate username
   ```

4. Access the interactive documentation:
   - Swagger UI: http://localhost:8000/docs
   - ReDoc: http://localhost:8000/redoc

### Example API Usage

```bash
# List all tenants
curl -H "X-API-Key: your-key" http://localhost:8000/api/v1/tenants

# Create a new tenant
curl -X POST -H "X-API-Key: your-key" \
  -H "Content-Type: application/json" \
  -d '{"tenant_name": "newclient", "maxmemory_mb": 256, "docker_limit_mb": 512}' \
  http://localhost:8000/api/v1/tenants

# Get health status
curl -H "X-API-Key: your-key" http://localhost:8000/api/v1/monitoring/health
```

For complete API documentation, see [docs/API.md](docs/API.md).

## Web Frontend

CachePilot includes an optional React-based web frontend for visual management and monitoring.

### Quick Start

The frontend is installed by default during system installation. If you skipped it:

**Prerequisites:**
- Node.js 18+ and npm must be installed
- nginx web server (installed automatically)

**Installation Steps:**

1. Build the frontend:
   ```bash
   cd /opt/cachepilot
   sudo ./install/scripts/setup-frontend.sh
   ```

2. Configure nginx reverse proxy:
   ```bash
   cd /opt/cachepilot
   sudo ./install/scripts/setup-nginx.sh your-domain.com
   ```
   
   Replace `your-domain.com` with your server's domain or IP address.

3. Access the frontend:
   - Local: http://localhost/
   - Production: http://your-domain.com/

The frontend provides:
- Visual dashboard for tenant management
- Real-time monitoring and statistics
- Health status overview
- Backup management interface
- Integration with the REST API

**Note:** The frontend requires the REST API to be installed and running. See the REST API section above for installation instructions.

For detailed frontend documentation, see [docs/FRONTEND.md](docs/FRONTEND.md).

## Architecture

The system is designed to be modular and easy to maintain. All logic is organized into separate library files located in `/opt/cachepilot/lib`.

- **`cachepilot`**: The main CLI entrypoint
- **`lib/common.sh`**: Shared utility functions
- **`lib/tenant.sh`**: Core logic for tenant lifecycle management
- **`lib/docker.sh`**: Docker and Docker Compose interactions
- **`lib/certs.sh`**: TLS certificate generation and management
- **`lib/monitoring.sh`**: Statistics, metrics, and JSON output
- **`lib/health.sh`**: Health checks for system and tenants
- **`lib/alerts.sh`**: Alert management with notifications
- **`lib/logger.sh`**: Structured logging with JSON format
- **`lib/validator.sh`**: Input validation library
- **`lib/redisinsight.sh`**: RedisInsight management
- **`lib/nginx.sh`**: Nginx reverse proxy for RedisInsight
- **`lib/handover.sh`**: Customer handover package generation
- **`lib/backup.sh`**: Backup and restore operations

## Configuration

System configuration files:
- `/etc/cachepilot/*`

Per-tenant configuration: `/var/cachepilot/tenants/<tenant_name>/config.env`

Data directories (FHS-compliant):
- `/var/cachepilot/tenants/` - Tenant data and configurations
- `/var/cachepilot/backups/` - Tenant backups (30-day retention, 50 max)
- `/var/cachepilot/ca/` - SSL/TLS certificates and CA
- `/var/log/cachepilot/` - All log files (main, audit, metrics, alerts)

Application directories:
- `/opt/cachepilot/` - Application code and scripts
- `/etc/cachepilot/` - System configuration files

## Security

CachePilot implements security measures to protect Redis instances and data.

### Security Features

- **TLS Encryption:** All Redis connections require TLS/SSL encryption
- **Password Authentication:** Strong, randomly generated passwords per tenant
- **Container Isolation:** Docker-based tenant separation with resource limits
- **Input Validation:** Input validation prevents injection attacks
- **API Authentication:** API key-based authentication with rate limiting
- **Audit Logging:** Operation accountability with user tracking
- **Sensitive Data Protection:** Automatic sanitization of passwords/tokens in logs
- **RedisInsight Security:** Protected by unique credentials over HTTPS
- **Secure Defaults:** Security-first default configuration (restrictive CORS, rate limiting enabled)

### Security Best Practices

**Before going to production:**

1. **Read the Security Guide**: Security documentation at [docs/SECURITY.md](docs/SECURITY.md)

2. **Secure API Keys:**
   ```bash
   sudo chmod 600 /etc/cachepilot/api-keys.json
   ```

3. **Configure Firewall:**
   ```bash
   sudo ufw allow 22/tcp    # SSH
   sudo ufw allow 80/tcp    # HTTP (redirects to HTTPS)
   sudo ufw allow 443/tcp   # HTTPS
   sudo ufw enable
   ```

4. **Configure CORS** (if using API):
   Edit `/etc/cachepilot/api.yaml`:
   ```yaml
   cors:
     origins:
       - "https://your-frontend.example.com"
     # NEVER use "*" in production
   ```

5. **Enable Rate Limiting** (enabled by default):
   Verify in `/etc/cachepilot/api.yaml`

6. **Monitor Logs:**
   ```bash
   tail -f /opt/cachepilot/data/logs/api.log
   tail -f /var/log/nginx/cachepilot-access.log
   ```

7. **Rotate API Keys Regularly:**
   ```bash
   cachepilot api key generate new-user
   # Update applications with new key
   cachepilot api key revoke old-user
   ```

8. **Monitor Certificate Expiry:**
   ```bash
   cachepilot certs check
   ```

### Security Checklist

- System backup created before installation
- API keys secured with 600 permissions
- CORS configured with specific origins (no wildcards)
- Firewall configured and enabled
- TLS certificates verified
- Nginx security headers enabled
- Rate limiting enabled and tested
- Logs reviewed for suspicious activity
- Security guide reviewed: [docs/SECURITY.md](docs/SECURITY.md)

### Reporting Security Issues

**DO NOT** create public GitHub issues for security vulnerabilities.

Instead, please email: **cachepilot@msrv-digital.de**

See [docs/SECURITY.md](docs/SECURITY.md) for the security policy and responsible disclosure process.

## Known Issues

As this is a BETA release, the following known issues are being tracked:

### Current Limitations

1. **API Documentation**
   - Some advanced API features may not be fully documented yet
   - OpenAPI schema generation is functional but may need refinement

2. **Frontend (Optional Component)**
   - Frontend is fully functional but in active development
   - Some UI/UX improvements planned for stable release
   - Additional dashboard features under development

3. **Performance Optimization**
   - Large-scale deployments (100+ tenants) need additional testing
   - Performance benchmarks being collected for various scenarios

4. **Platform Support**
   - Only Ubuntu 22.04+ and Debian 12+ are officially supported
   - Other Linux distributions may work but are untested

### Reporting Issues

Found a bug or issue? Please help us improve CachePilot:

1. **Search existing issues** on GitHub to avoid duplicates
2. **Provide detailed information**:
   - CachePilot version (`cachepilot --version`)
   - Operating system and version
   - Steps to reproduce
   - Expected vs actual behavior
   - Relevant log files
3. **Submit via GitHub Issues**: https://github.com/MSRV-Digital/CachePilot/issues
4. **For security issues**: Email cachepilot@msrv-digital.de (do NOT create public issues)

## Roadmap to Stable Release

Our path from BETA (v2.1.2-Beta) to v2 stable release (December 2025 - December 2026):

### Phase 1: Beta Refinement & Testing (December 2025 - Q1 2026)
**Focus: Stability & Production Readiness**
- Comprehensive testing of all v2.1.2-Beta features
- Critical bug fixes and stability improvements
- Security audit and penetration testing
- Performance optimization for large-scale deployments (100+ tenants)
- Extended platform testing (Ubuntu 22.04+, Debian 12+ variants)
- Real-world production deployment case studies
- Community feedback integration and issue resolution
- Documentation review and improvements
- Frontend UI/UX refinements
- API documentation completion

### Phase 2: Release Candidate Preparation (Q2 2026)
**Focus: Feature Freeze & Hardening**
- Feature freeze - no new features, only bug fixes
- Complete performance optimization for production workloads
- Comprehensive load testing and benchmarking
- API stability guarantees and versioning finalization
- Security hardening and final penetration testing
- Beta-to-stable migration tools development
- Professional support options documentation
- Enterprise deployment guides
- Long-term support (LTS) planning
- Release candidate builds and testing

### Phase 3: Release Candidate Testing (Q3 2026)
**Focus: Final Validation**
- Release Candidate 1 (RC1) deployment and testing
- Community and enterprise user testing programs
- Performance benchmarking under production loads
- Final bug fixes and stability patches
- Documentation finalization and review
- Migration path validation from beta to stable
- Backup and disaster recovery testing
- Multi-platform validation
- API backward compatibility verification
- Security compliance verification

### Phase 4: Stable Release v2.1 (Q4 2026)
**Target: December 2026**
- Official v2.x stable release announcement
- API versioning with backward compatibility commitment
- Long-term support (LTS) schedule publication
- Professional support options and SLA offerings
- Complete production deployment guides
- Automated migration tools for beta users
- Full security hardening documentation
- Performance benchmarks and best practices
- Enterprise features documentation (clustering readiness, advanced monitoring)
- Community celebration and release promotion

### Post-Stable: Maintenance & Future Development (2027+)
**Continuous Improvement:**
- Regular patch releases for critical issues (v2.x.x)
- Performance tuning based on production feedback
- Documentation improvements and video tutorials
- Security updates and vulnerability patches
- Community support enhancement

**Future Features (v2.2+ Planning):**
- Multi-server clustering and high availability
- Advanced monitoring with AI-powered alerting
- Native integration with monitoring platforms (Zabbix)
- Enhanced RedisInsight features and custom dashboards + SSL
- Automated scaling policies based on workload patterns
- Cloud provider integrations (AWS, Azure, GCP)
- Kubernetes operator for container orchestration
- Multi-region replication and disaster recovery
- Advanced backup strategies (incremental, point-in-time)
- Enhanced multi-tenancy features and resource quotas

**Timeline Note**: The stable v2.x release is planned for December 2026. This timeline allows for thorough testing, security validation, and production-readiness verification. All dates are estimates and may be adjusted based on quality requirements, community feedback, and testing results. Our commitment is to deliver a robust, enterprise-grade stable release that meets the highest standards of reliability and security.

## Contributing

Contributions are welcome. Please feel free to submit a pull request or open an issue.

**Beta Testing Help Needed:**
- Testing on different platforms
- Performance testing with various workloads
- Documentation improvements
- Bug reports and feature requests
- Security audits and recommendations

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Disclaimer

This software is provided "as is", without warranty of any kind, express or implied. The authors and copyright holders are not liable for any claim, damages, or other liability arising from the use of this software. Use at your own risk.

### Redis Trademark Notice

**CachePilot is an independent, open-source project and is NOT affiliated with, endorsed by, or sponsored by Redis Ltd. or the Redis project.**

Redis is a registered trademark of Redis Ltd. Any use of the Redis name in this project is for descriptive and compatibility purposes only, to indicate that this software is designed to manage Redis database instances. This usage falls under nominative fair use, as it is necessary to describe the purpose and functionality of the software.

CachePilot:
- Is not an official Redis product or service
- Has no commercial or organizational relationship with Redis Ltd.
- Does not imply any endorsement by Redis Ltd. or the Redis project
- Is independently developed and maintained by MSRV Digital

All trademarks, service marks, trade names, product names, and logos are the property of their respective owners. The use of any trademark on this site does not imply any affiliation with or endorsement by the trademark owner.

For information about Redis and official Redis products, please visit: https://redis.io

---

## Keywords & Tags

`redis` `redis-manager` `multi-tenant` `docker` `tls-encryption` `ssl-certificates` `redis-cluster` `database-management` `devops` `infrastructure` `container-orchestration` `tenant-isolation` `redis-monitoring` `backup-restore` `rest-api` `redis-insight` `production-ready` `fhs-compliant` `linux` `automation` `security` `monitoring` `alerting` `metrics` `audit-logging` `resource-management` `hosting-provider` `managed-redis` `redis-as-a-service` `database-administration` `bash-scripts` `fastapi` `systemd` `nginx` `reverse-proxy` `certificate-management` `health-checks` `disaster-recovery` `high-availability` `scalable` `enterprise-ready`
