# Changelog

All notable changes to CachePilot will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **Cronjob CLI Compatibility**: Fixed incompatible CLI commands in automated tasks
  - Corrected `health check-system --quiet` → `health --json` (subcommand didn't exist)
  - Corrected `certs check-expiry --quiet` → `check-certs` (wrong command format)
  - Removed `backup cleanup --days 30` (not implemented, handled by maintenance script)
  - Removed `logs rotate` (not implemented, handled by logrotate)
  - All cronjobs now use correct CLI syntax and execute successfully
  - Added `validate-cron.sh` script to test cronjob commands before deployment

- **RedisInsight Integration**: Fixed duplicate connections and configuration issues
  - Removed dual configuration approach (environment variables + database manipulation)
  - Fixed TLS configuration for plain-only tenants
  - Fixed port configuration: TLS uses port 6380, plain-only uses port 6379
  - Migration: Disable/re-enable RedisInsight to apply fix

### Added
- **RedisInsight API Integration**: Complete REST API and frontend support for RedisInsight management
- **Memory-Only Persistence Mode**: In-memory operation for ultra-low latency (1-5ms vs 100-200ms)
- **Redis Latency Testing Tool**: Performance validation script (`scripts/test-redis-latency.py`)
- **Cronjob Validation Script**: `install/scripts/validate-cron.sh` for testing automated task commands

## [2.1.2-Beta] - 2025-12-22

### Added
- **Security Mode Switcher**: TLS/Plain-Text/Dual-Mode Unterstützung mit automatischem Tenant-Neustart

### Fixed
- **Docker Compose v1 compatibility**: Changed `docker compose` to `docker-compose` syntax (cli/lib/docker.sh, cli/lib/redisinsight.sh)
- **Default IP configuration**: Updated config template to use safe localhost defaults (127.0.0.1)
- **Missing zip dependency**: Added zip package to install-deps.sh
- **Handover script bug**: Fixed unbound variable error when RedisInsight not enabled (cli/lib/handover.sh)
- **Docker stats parsing**: Added error handling to prevent jq parse errors in status command (cli/lib/monitoring.sh)
- **Health command display**: Fixed color codes showing as literal escape sequences (cli/cachepilot)
- **dpkg lock handling**: Installation scripts now only wait for actual dpkg locks, not background processes
  - `install/scripts/install-deps.sh`: Optimized lock detection to check only lock files
  - `install/scripts/setup-nginx.sh`: Optimized lock detection to check only lock files
  - Impact: No more false positives from unattended-upgrades running in background
  - Installation proceeds immediately when locks are not held

## [2.1.1] - 2025-11-04

### Fixed

#### Installation Script Fixes
- **Virtual environment corruption handling**: Fixed installation failure when Python venv exists but pip is missing
  - `install/scripts/setup-api.sh`: Added automatic detection and recreation of corrupted virtual environments
  - `install/upgrade.sh`: Same fix applied to upgrade process
  - Impact: Installation continues successfully instead of failing with "pip not found" error

- **Configuration file paths**: Standardized all configuration to use `/etc/cachepilot/` exclusively
  - `cli/cachepilot`: Changed `CONFIG_FILE` from `${BASE_DIR}/config/system.yaml` to `/etc/cachepilot/system.yaml`
  - `install/scripts/setup-api.sh`: Removed fallback logic, only checks `/etc/cachepilot/`
  - `install/install.sh`: Configuration files copied to `/etc/cachepilot/` before any other steps (Step 0)
  - Impact: Clear, predictable configuration location following FHS standard

- **Missing frontend directory**: Fixed frontend build failure due to missing source files
  - `install/install.sh`: Added frontend directory copy in Step 3
  - Impact: Frontend installation now works from any source directory location

- **User input handling**: Fixed confusing interactive prompts
  - `install/scripts/setup-api.sh`: Removed `-n 1` flag from "Start API service" prompt
  - `install/install.sh`: Added `echo` after server domain input for proper line spacing
  - Impact: Users can now press Enter after input and prompts appear on separate lines

#### Let's Encrypt SSL Certificate Support
- **ACME challenge 404 errors**: Fixed Let's Encrypt certificate acquisition failures
  - `install/scripts/setup-nginx.sh`: Changed from `--nginx` plugin to `--webroot` mode
  - Added `.well-known/acme-challenge/` location to nginx configuration
  - Ensured `/var/www/html` directory exists with proper permissions
  - Impact: Let's Encrypt certificates can now be obtained successfully for real domains

#### Logging Configuration
- **Log path inconsistency**: Fixed hardcoded legacy log paths
  - `cli/lib/security.sh`: Changed from `/opt/cachepilot/data/logs/security.log` to `${LOGS_DIR:-/var/log/cachepilot}/security.log`
  - Impact: All logs consistently use `/var/log/cachepilot/` following FHS standard

#### Code Quality
- **Undefined variable**: Fixed CLI startup error
  - `cli/cachepilot`: Removed reference to undefined `CONFIG_PATHS[templates_dir]`
  - Impact: `cachepilot list` and other commands work without "unbound variable" errors

### Technical Details

All fixes maintain full backward compatibility while enforcing FHS compliance for new installations.

---

## [2.1.0] - 2025-11-04

### Configuration Directory Migration to /etc/cachepilot

This release implements FHS (Filesystem Hierarchy Standard) compliance for configuration files by migrating from `/opt/cachepilot/config/` to `/etc/cachepilot/`.

### Added

#### FHS-Compliant Configuration Structure
- Configuration directory: `/etc/cachepilot/` for system-wide configuration files
  - `/etc/cachepilot/system.yaml` - System configuration
  - `/etc/cachepilot/api.yaml` - API configuration
  - `/etc/cachepilot/frontend.yaml` - Frontend configuration
  - `/etc/cachepilot/logging-config.yaml` - Logging configuration
  - `/etc/cachepilot/monitoring-config.yaml` - Monitoring configuration
  - `/etc/cachepilot/api-keys.json` - API authentication keys (600 permissions)

#### Template Directory
- `config/`: Now serves as template repository only
  - Contains reference YAML files for fresh installations
  - Includes comprehensive `README.md` explaining template vs active configs
  - Used as source during installation process
  - No longer contains active runtime configuration

### Changed

#### All Configuration References Updated

**API Layer:**
- `api/config.py`: All config paths now point to `/etc/cachepilot/`
  - `api_key_file`: `/etc/cachepilot/api-keys.json`
  - `config_dir`: `/etc/cachepilot`
  - `env_file`: `/etc/cachepilot/.env`

**CLI Layer:**
- `cli/lib/common.sh`: Configuration loading from `/etc/cachepilot/system.yaml`
- `cli/lib/logger.sh`: Logging config from `/etc/cachepilot/logging-config.yaml`
- `cli/lib/monitoring.sh`: Monitoring config from `/etc/cachepilot/monitoring-config.yaml`
- `cli/lib/alerts.sh`: Alert config from `/etc/cachepilot/monitoring-config.yaml`
- `cli/lib/validator.sh`: System config validation from `/etc/cachepilot/system.yaml`
- `cli/lib/security.sh`: Security audit uses `/etc/cachepilot` and `/var/cachepilot`

**Configuration Templates:**
- `config/system.yaml`: `config_dir` path updated to `/etc/cachepilot`
- `config/api.yaml`: All paths updated to FHS-compliant locations

**Installation Scripts:**
- `install/install.sh`: Copies config templates to `/etc/cachepilot/` during installation
- `install/upgrade.sh`: Automatically migrates old configs to `/etc/cachepilot/`
- `install/scripts/setup-dirs.sh`: Creates `/etc/cachepilot/` directory during setup
- `install/uninstall.sh`: Handles `/etc/cachepilot/` cleanup

**Documentation:**
- All documentation updated to reference `/etc/cachepilot/`
- `docs/CONFIGURATION.md`: Updated all path references
- `docs/API.md`: Updated API key file location
- `docs/DEPLOYMENT.md`: Updated deployment paths
- `docs/SECURITY.md`: Updated security audit paths
- `README.md`: Updated quick start paths

### Fixed
- `cli/lib/monitoring.sh`: Added config.env existence check to prevent errors on invalid tenant directories

### Migration Guide

#### Fresh Installations
New installations automatically use `/etc/cachepilot/` for all configuration. No migration needed.

#### Upgrading from 2.0.4 or earlier

**Verification:**
```bash
# Check configuration location
ls -la /etc/cachepilot/

# Verify API is using new location
systemctl restart cachepilot-api
systemctl status cachepilot-api

# Test CLI functionality
cachepilot health
cachepilot list
```

### Benefits

1. FHS Compliance: Follows Linux Filesystem Hierarchy Standard
2. Better Security: System configs separated from application code
3. Standard Location: Sysadmins know to look in `/etc/` for configs
4. Package Manager Ready: Meets requirements for DEB/RPM packaging
5. Clear Separation: Code (`/opt`) vs Config (`/etc`) vs Data (`/var`)

### Compatibility

- Fully backward compatible with existing tenant data
- Automatic migration during upgrade preserves all settings
- Template directory remains at `/opt/cachepilot/config/` for reference
- No API changes - all endpoints work identically

### Technical Details

#### Directory Permissions
- `/etc/cachepilot/`: 755 (readable by all, writable by root)
- `/etc/cachepilot/*.yaml`: Existing permissions preserved
- `/etc/cachepilot/api-keys.json`: 600 (root read/write only)

#### Configuration Loading Priority
1. Environment variables (highest priority)
2. `/etc/cachepilot/*.yaml` files
3. Built-in defaults (lowest priority)

---

## [2.0.4] - 2025

### Critical Bug Fixes

This release addresses several critical issues affecting API performance, tenant creation, and container health checks.

### Fixed

#### API Performance Issues
- **RequestValidationMiddleware blocking POST requests**: Fixed middleware that was attempting to read request body, causing complete blocking of POST requests
  - Removed `_validate_body()` call that caused request body to be consumed before FastAPI could process it
  - Request body can only be read once in ASGI applications
  - Impact: POST /api/v1/tenants was completely non-functional, appearing to hang indefinitely
  - `api/middleware/security.py`: Now only validates query parameters, body validation delegated to FastAPI/Pydantic

- **Auth performance degradation**: Removed blocking I/O operation in authentication flow
  - `save_keys()` was being called on every API request during key validation
  - File I/O on every request caused significant performance degradation
  - `api/auth.py`: `save_keys()` now only called when keys are actually modified (generation/revocation), not during validation
  - Impact: Reduced authentication overhead from ~60s to milliseconds

- **Timeout configuration**: Extended all timeouts to support longer-running operations
  - Backend: `api/services/tenant_service.py` - `execute_with_timeout("new", 120, ...)`
  - Frontend: `frontend/src/api/client.ts` - `timeout: 120000` (120 seconds)
  - Nginx: `install/scripts/setup-nginx.sh` - All proxy timeouts set to 120s
  - Impact: Tenant creation operations complete successfully (typical time: 1.5-2 seconds)

#### Frontend Issues
- **Tenant list not updating after creation**: Fixed race condition in React Query cache management
  - `frontend/src/hooks/useTenants.ts`: Added explicit `refetchQueries()` after `invalidateQueries()`
  - Previously only invalidated cache but didn't trigger immediate refetch
  - Impact: Newly created tenants now appear immediately in list without manual page refresh

#### TLS Certificate Issues
- **Container health check failures**: Fixed TLS certificate permissions preventing container startup
  - `cli/lib/certs.sh`: `ca.crt` now correctly copied to tenant directory with 644 permissions
  - Previously `ca.crt` had 600 permissions (root-only) causing "Permission denied" errors
  - Redis containers run as non-root user and couldn't read CA certificate
  - Impact: Containers now start successfully and pass health checks
  - Error message: "Failed to configure CA certificate(s) file/directory: error:8000000D:system library::Permission denied"

- **Automatic fix for existing tenants**: `install/upgrade.sh` now includes automatic repair
  - Copies `ca.crt` to all existing tenant directories
  - Sets correct 644 permissions
  - Runs automatically during upgrade process

#### Docker Container Health Checks
- **Health check timeout too short**: Increased timeout from 30s to 60s
  - `cli/lib/docker.sh`: Both `start_container()` and `update_all_instances()` now use 60s timeout
  - Impact: `cachepilot update all` no longer reports false failures on slower systems or during high load
  - Containers have adequate time to initialize and become healthy

### Performance Improvements

**Before fixes:**
- Tenant creation: 30-60s (often timeout)
- API POST requests: Complete hang/timeout
- Auth overhead: ~60s per request

**After fixes:**
- Tenant creation: 1.5-2 seconds
- API POST requests: Normal FastAPI performance
- Auth overhead: <10ms

### Compatibility

- Fully backward compatible with version 2.0.3
- Existing tenants: Automatically repaired during upgrade
- API endpoints: No changes to API interface
- CLI commands: No changes to command syntax
- Configuration: No configuration changes required

---

## [2.0.3] - 2025

### FHS Compliance & Path Configurability

This release implements full Linux Filesystem Hierarchy Standard (FHS) compliance, making CachePilot production-ready for enterprise deployments and package management systems.

### Added

#### FHS-Compliant Directory Structure
- Application data: `/var/cachepilot/` for runtime data
  - `/var/cachepilot/tenants/` - Tenant configurations and data
  - `/var/cachepilot/ca/` - Certificate authority and SSL certificates
  - `/var/cachepilot/backups/` - Tenant backups
- System logs: `/var/log/cachepilot/` for all log files
  - `/var/log/cachepilot/cachepilot.log` - Main application log
  - `/var/log/cachepilot/audit.log` - Audit trail
  - `/var/log/cachepilot/metrics.log` - Performance metrics
- Application code: `/opt/cachepilot/` - Program files (unchanged)

#### Full Path Configurability
- All paths now configurable through `config/system.yaml`
- Environment variable overrides supported for all paths
- Backward compatibility maintained for existing installations

### Changed

#### Configuration System
- `config/system.yaml`: Added FHS-compliant default paths
- `config/logging-config.yaml`: Updated log file paths to `/var/log/cachepilot/`
- All configuration now loaded dynamically at runtime

#### Application Code Updates

**Shell Libraries (cli/lib/):**
- `common.sh`: Added `load_paths_from_config()` function to parse YAML and export path variables
- `logger.sh`: Log paths now use `$LOGS_DIR` variable from configuration
- `backup.sh`: Backup operations use `$BACKUPS_DIR` and `$TENANTS_DIR` variables
- `tenant.sh`: Tenant management uses `$TENANTS_DIR` throughout
- `certs.sh`: Certificate operations use `$CA_DIR` with proper directory creation
- `monitoring.sh`: Metrics directory uses configured `$LOGS_DIR`

**Python API (api/):**
- `api/config.py`: Added path fields and loads paths from YAML with environment variable overrides
- `api/services/backup_service.py`: Uses `settings.backups_dir` and `settings.tenants_dir`
- `api/services/tenant_service.py`: Uses configured paths throughout
- `api/services/monitoring_service.py`: Uses `settings.logs_dir` for alerts and metrics

**Installation Scripts:**
- `install/scripts/setup-dirs.sh`: Creates FHS-compliant directory structure
- `install/install.sh`: Updated log path references
- `install/upgrade.sh`: Detects old directory structure and recommends migration
- `install/uninstall.sh`: Detects and handles both old and new directory structures

**System Integration:**
- `install/systemd/cachepilot-api.service`: Added environment variables for FHS paths
- `scripts/cron-maintenance.sh`: Uses configured log directory

### Compatibility

- Fully backward compatible with version 2.0.2
- Automatic detection of old directory structure
- No forced migration - both old and new structures supported
- Gradual migration possible - migrate at your convenience

---

## [2.0.2] - 2025

### Security Hardening & Production Readiness

This release focuses on comprehensive security hardening, installation improvements, and production-ready documentation.

### Added

#### Security Documentation
- `docs/SECURITY.md`: Comprehensive security guide
- `SECURITY.md`: Security policy at repository root with vulnerability reporting process

#### Installation & Deployment Hardening
- Pre-flight security checks in `install/scripts/check-deps.sh`
- Automatic backup creation before installation with rollback instructions
- File permission verification
- Enhanced nginx security headers

#### Documentation Enhancements
- API Documentation Security Section
- Enhanced Deployment Guide with comprehensive security checklists
- README improvements with prominent warnings

### Changed

#### Installation Process
- Backup creation: Installer now automatically backs up existing installations
- Rollback instructions: Clear rollback procedures displayed during installation
- Enhanced dependency checks: More comprehensive validation
- File permission enforcement: All sensitive files automatically secured

#### Security Configuration
- API keys file: Automatically set to 600 permissions
- Configuration files: Automatically set to 640 permissions
- CA directory: Automatically set to 700 permissions
- nginx security headers: Enhanced with additional headers for production security

### Security

#### Critical Security Improvements
- Input validation: All user inputs validated against strict patterns
- Command execution: Whitelist-based approach prevents command injection
- Path sanitization: All file paths validated to prevent directory traversal
- API authentication: Enhanced with audit logging
- Rate limiting: Configurable per-endpoint rate limiting
- Error sanitization: Production errors don't expose internal paths or stack traces
- Audit logging: All API requests logged with detailed metadata

#### System Hardening
- File permissions: Strict permissions enforced on all sensitive files
- Network isolation: API only accessible via localhost by default
- TLS enforcement: Strong TLS 1.2+ with secure cipher suites
- CORS restrictions: Restrictive CORS policy (no wildcards in production)
- Security headers: Comprehensive security headers via nginx
- Certificate management: Auto-renewal and expiry monitoring

### Compatibility

- Fully backward compatible with version 2.0.1
- API endpoints unchanged
- CLI commands unchanged
- Configuration format unchanged
- Tenant data format unchanged

---

## [2.0.1] - 2024 Initial Beta Release

### Fixed

**Critical Bug Fixes (Post-Restructuring)**

#### CLI Library Fixes
- `format_bytes()`: Fixed unbound variable error when called without parameter
- `format_uptime()`: Fixed unbound variable error when called without parameter
- `logger.sh Path`: Corrected path reference after restructuring
- Docker exec: Fixed "working directory outside container" error
- `tenant_memory Array`: Fixed unbound variable error in `show_global_stats()`

#### API Service Fixes
- Tenant List Parsing: Fixed header row being parsed as tenant data
- API Key Recognition: Fixed race condition where newly generated API keys were not immediately recognized
  - Implemented 30-second cache with automatic key reload
  - Keys are now automatically detected without requiring API restart

#### Installation Improvements
- nginx Integration: Added automated nginx setup with reverse proxy
- Dependency Checker: Fixed docker compose detection
- Frontend Setup: Added dedicated setup scripts

### Changed
- Frontend uses nginx reverse proxy on port 80/443
- All installation scripts now executable by default

---

## [2.0.0] - 2024 Major Restructuring Release

### Major Restructuring

This is a complete restructuring of CachePilot following professional Linux development standards. This version introduces breaking changes in the directory structure and configuration system, but preserves all functionality.

### Added

#### Directory Structure
- Professional top-level organization: Separated concerns into `cli/`, `api/`, `frontend/`, `config/`, `install/`, `scripts/`, and `data/` directories
- Clear separation of code and data
- Modular installation system

#### Configuration System
- YAML-based configuration replacing bash `.conf` files
- `config/system.yaml`: Main system configuration
- `config/api.yaml`: Dedicated API configuration
- `config/frontend.yaml`: Frontend configuration
- Full path configurability
- Configuration validation

#### Installation & Deployment
- Comprehensive dependency checker
- Automated directory structure creation
- Modular API installation
- Clean uninstallation script
- Upgrade script for future migrations

#### Documentation
- `docs/CONFIGURATION.md`: Complete configuration reference guide
- `docs/FRONTEND.md`: Frontend development and deployment guide
- Updated deployment and API documentation

### Changed

#### Breaking Changes
- Directory structure completely reorganized
- Configuration format changed from bash `.conf` to YAML
- Path references replaced with configuration-based paths
- Installation location changed to subdirectories

### Removed
- `config/cachepilot.conf`: Replaced by `config/system.yaml`
- Old flat structure: All files reorganized into proper directories
- Hardcoded paths: All replaced with configuration-based paths

### Compatibility

- Backward Compatible: Tenant data format unchanged
- API Compatible: API endpoints unchanged
- CLI Compatible: Command syntax unchanged

---

## [1.1.0] - 2024 Feature Release

### Added
- REST API with FastAPI
- Structured logging with JSON format
- Comprehensive health check system
- Alert system with email/webhook notifications
- Time-series metrics collection
- Enhanced monitoring with JSON output
- Audit trail for all operations
- Automated backup system

### Changed
- Improved error handling across all components
- Enhanced monitoring capabilities
- Better logging with structured JSON format

### Fixed
- Various bug fixes and stability improvements

---

## [1.0.0] - 2024 Initial Release

### Initial Release
- Multi-tenant Redis management
- Docker-based isolation
- TLS certificate management
- RedisInsight integration
- Nginx reverse proxy support
- Automated backups
- Command-line interface
- Comprehensive monitoring
