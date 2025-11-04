# CachePilot - Configuration Reference

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>  
Company: MSRV Digital  
Version: 2.1.0-beta  
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital

---

**BETA SOFTWARE NOTICE**

This configuration guide is part of CachePilot v2.1.0-beta. All documented options are functional. Configuration structure may evolve as the project approaches stable release. Review all configuration files before production use and test changes in staging first.

---

This document provides a comprehensive reference for all configuration options in CachePilot.

## Overview

CachePilot uses YAML-based configuration files for all settings. This provides:
- **Structured configuration**: Clear hierarchy and organization
- **Type safety**: Proper data types (strings, numbers, booleans, arrays)
- **Comments**: Inline documentation in configuration files
- **Validation**: Built-in validation for required fields and data types
- **Flexibility**: Easy to edit and version control

## Configuration Files

All configuration files are located in `/etc/cachepilot/`:

| File | Purpose | Required |
|------|---------|----------|
| `system.yaml` | Main system configuration | Yes |
| `api.yaml` | REST API configuration | If using API |
| `frontend.yaml` | Frontend configuration | If using frontend |
| `monitoring.yaml` | Monitoring settings | Yes |
| `logging.yaml` | Logging configuration | Yes |
| `api-keys.json` | API authentication keys | If using API |
| `.env.example` | Environment variables template | No |

## system.yaml

Main system configuration file containing all paths, network settings, defaults, and organization information.

### Full Example

```yaml
# CachePilot System Configuration

# System Paths
paths:
  base_dir: /opt/cachepilot
  tenants_dir: /opt/cachepilot/data/tenants
  ca_dir: /opt/cachepilot/data/ca
  backups_dir: /opt/cachepilot/data/backups
  logs_dir: /opt/cachepilot/data/logs
  templates_dir: /opt/cachepilot/templates
  cli_dir: /opt/cachepilot/cli
  api_dir: /opt/cachepilot/api
  frontend_dir: /opt/cachepilot/frontend
  config_dir: /etc/cachepilot

# Network Configuration
network:
  internal_ip: 172.17.0.1
  public_ip: 203.0.113.10
  redis_port_start: 6379
  redis_port_end: 6399
  insight_port_start: 8001
  insight_port_end: 8020

# Default Settings
defaults:
  redis_memory_mb: 256
  docker_memory_mb: 512

# Organization Information
organization:
  name: "Your Company Name"
  contact_name: "Admin Name"
  contact_email: "admin@example.com"
  contact_phone: "+1-555-0100"
  contact_web: "https://example.com"

# Certificate Settings
certificates:
  country: "US"
  state: "California"
  city: "San Francisco"
  validity_days: 365
```

### Configuration Sections

#### paths

Defines all directory paths used by the system.

| Key | Type | Description | Default |
|-----|------|-------------|---------|
| `base_dir` | string | Base installation directory | `/opt/cachepilot` |
| `tenants_dir` | string | Tenant data directory | `{base_dir}/data/tenants` |
| `ca_dir` | string | Certificate authority directory | `{base_dir}/data/ca` |
| `backups_dir` | string | Backup storage directory | `{base_dir}/data/backups` |
| `logs_dir` | string | Log files directory | `{base_dir}/data/logs` |
| `templates_dir` | string | Configuration templates | `{base_dir}/templates` |
| `cli_dir` | string | CLI scripts directory | `{base_dir}/cli` |
| `api_dir` | string | API application directory | `{base_dir}/api` |
| `frontend_dir` | string | Frontend files directory | `{base_dir}/frontend` |
| `config_dir` | string | Configuration files directory | `/etc/cachepilot` |

**Path Requirements:**
- All paths must be absolute (start with `/`)
- Directories will be created if they don't exist
- Appropriate permissions will be set automatically

#### network

Network configuration for Redis and RedisInsight services.

| Key | Type | Description | Valid Range |
|-----|------|-------------|-------------|
| `internal_ip` | string | Docker bridge IP | Any valid IP |
| `public_ip` | string | External access IP | Any valid IP |
| `redis_port_start` | integer | First Redis port | 1024-65535 |
| `redis_port_end` | integer | Last Redis port | > redis_port_start |
| `insight_port_start` | integer | First Insight port | 1024-65535 |
| `insight_port_end` | integer | Last Insight port | > insight_port_start |

**Port Range Rules:**
- Ports must be in range 1024-65535 (non-privileged)
- End port must be greater than start port
- Ranges should not overlap with other services
- Maximum tenants = redis_port_end - redis_port_start + 1

#### defaults

Default values for new tenant creation.

| Key | Type | Description | Min | Max | Recommended |
|-----|------|-------------|-----|-----|-------------|
| `redis_memory_mb` | integer | Redis maxmemory | 64 | 16384 | 256-512 |
| `docker_memory_mb` | integer | Docker container limit | 128 | 32768 | 512-1024 |

**Memory Guidelines:**
- `docker_memory_mb` should be at least 2x `redis_memory_mb`
- Leave overhead for Redis overhead and system buffers
- Consider host system total memory

#### organization

Organization information used in certificates and handover documents.

| Key | Type | Description | Required |
|-----|------|-------------|----------|
| `name` | string | Company/organization name | Yes |
| `contact_name` | string | Primary contact name | Yes |
| `contact_email` | string | Contact email address | Yes |
| `contact_phone` | string | Contact phone number | No |
| `contact_web` | string | Website URL | No |

#### certificates

TLS certificate generation settings.

| Key | Type | Description | Valid Values |
|-----|------|-------------|--------------|
| `country` | string | Two-letter country code | ISO 3166-1 alpha-2 |
| `state` | string | State/province name | Any string |
| `city` | string | City name | Any string |
| `validity_days` | integer | Certificate validity period | 1-3650 |

**Certificate Notes:**
- Certificates are self-signed for internal use
- `validity_days` of 365 (1 year) is recommended
- Certificates auto-renew when near expiration

## api.yaml

REST API configuration for the FastAPI server.

### Full Example

```yaml
# CachePilot API Configuration

# Server Settings
server:
  host: 0.0.0.0
  port: 8000
  workers: 4
  reload: false

# Security Settings
security:
  api_key_file: /etc/cachepilot/api-keys.json
  rate_limit_requests: 100
  rate_limit_window: 60
  cors_origins:
    - "http://localhost:3000"
    - "http://localhost:8080"

# Path Settings
paths:
  redis_mgr_cli: /opt/cachepilot/cli/cachepilot
  base_dir: /opt/cachepilot

# Logging Settings
logging:
  level: INFO
  access_log: true

# Environment
environment: production
```

### Configuration Sections

#### server

API server configuration.

| Key | Type | Description | Default |
|-----|------|-------------|---------|
| `host` | string | Bind address | `0.0.0.0` |
| `port` | integer | Listen port | `8000` |
| `workers` | integer | Uvicorn workers | `4` |
| `reload` | boolean | Auto-reload on changes | `false` |

**Worker Guidelines:**
- Production: `2 * CPU_cores + 1`
- Development: `1` or `2`
- Use `reload: true` only in development

#### security

Security and authentication settings.

| Key | Type | Description |
|-----|------|-------------|
| `api_key_file` | string | Path to api-keys.json |
| `rate_limit_requests` | integer | Requests per window |
| `rate_limit_window` | integer | Window size (seconds) |
| `cors_origins` | array | Allowed CORS origins |

**CORS Origins:**
- List allowed frontend origins
- Use specific origins in production
- Never use `["*"]` in production

#### logging

Logging configuration.

| Key | Type | Description | Options |
|-----|------|-------------|---------|
| `level` | string | Log level | DEBUG, INFO, WARNING, ERROR |
| `access_log` | boolean | Enable access logging | true/false |

## frontend.yaml

Frontend application configuration.

### Full Example

```yaml
# CachePilot Frontend Configuration

# API Connection
api:
  base_url: http://localhost:8000
  timeout: 30

# Application Settings
app:
  title: "CachePilot"
  refresh_interval: 30

# Theme Settings
theme:
  primary_color: "#3B82F6"
  dark_mode: false
```

## Environment Variables

Environment variables can be used to override configuration values.

### System Environment Variables

```bash
# Override base directory
REDIS_MGR_BASE_DIR=/custom/path

# Override specific paths
REDIS_MGR_TENANTS_DIR=/var/redis/tenants
REDIS_MGR_BACKUPS_DIR=/backup/redis

# Override network settings
REDIS_MGR_PUBLIC_IP=203.0.113.10
```

### API Environment Variables

```bash
# Override API settings
REDIS_MGR_API_HOST=0.0.0.0
REDIS_MGR_API_PORT=8000
REDIS_MGR_API_WORKERS=4

# Override security settings
REDIS_MGR_API_KEY_FILE=/custom/api-keys.json
```

## Configuration Validation

Validate configuration files:

```bash
# Validate system configuration
cachepilot validate-config

# Validate specific config file
cachepilot validate-config --file /etc/cachepilot/system.yaml

# Check configuration and show values
cachepilot show-config
```

## Configuration Best Practices

### 1. Security
- Keep sensitive files (api-keys.json) with restrictive permissions (600)
- Use strong API keys (32+ characters)
- Regularly rotate API keys
- Restrict CORS origins in production

### 2. Paths
- Use absolute paths only
- Keep all paths under /opt/cachepilot for easier management
- Ensure sufficient disk space in data directories
- Separate data from application files

### 3. Network
- Use non-conflicting port ranges
- Reserve sufficient ports for growth
- Document public IP in handover packages
- Consider firewall rules for port ranges

### 4. Resources
- Set realistic memory limits
- Monitor actual usage and adjust
- Docker limit should be 2x Redis limit minimum
- Consider host system resources

### 5. Backup
- Configure automatic backups in cron
- Monitor backup directory disk space
- Implement backup rotation policy
- Test restore procedures regularly

## Troubleshooting

### Configuration Errors

**Error: "Configuration file not found"**
- Ensure `/etc/cachepilot/system.yaml` exists
- Check file permissions (should be readable)
- Verify installation completed successfully

**Error: "Invalid YAML syntax"**
- Use YAML validator: `yamllint /etc/cachepilot/system.yaml`
- Check indentation (use spaces, not tabs)
- Verify quotes around strings with special characters

**Error: "Required field missing"**
- Run `cachepilot validate-config` for details
- Check example files in `/etc/cachepilot/`
- Refer to this documentation for required fields

### Path Issues

**Error: "Permission denied"**
- Check directory ownership: `ls -la /opt/cachepilot`
- Verify directory permissions: `chmod 750 /opt/cachepilot/data`
- Ensure proper user has access

**Error: "Directory not found"**
- Run `cachepilot validate-config` to check paths
- Create missing directories with proper permissions
- Re-run setup: `/opt/cachepilot/install/scripts/setup-dirs.sh`

### Network Issues

**Error: "Port already in use"**
- Check port ranges don't conflict: `netstat -tuln | grep :<port>`
- Adjust redis_port_start/end in configuration
- Restart affected tenants

## See Also

- [API Documentation](API.md) - REST API reference
- [Deployment Guide](DEPLOYMENT.md) - Installation and deployment
- [Frontend Guide](FRONTEND.md) - Frontend development
- [README](../README.md) - Project overview
