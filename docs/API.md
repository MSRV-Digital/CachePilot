# CachePilot - API Documentation

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>  
Company: MSRV Digital  
Version: 2.1.2-Beta  
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital

## Overview

The CachePilot API provides RESTful access to all tenant management, monitoring, and system operations. Most endpoints require authentication via API key.

**Base URL:** `http://localhost:8000/api/v1`

### Root Endpoints (No Authentication Required)

```http
GET /
```
Returns application info (name, version, status).

> **Note:** This endpoint returns raw JSON, not the standard `ApiResponse` wrapper.

**Response:**
```json
{"name": "CachePilot API", "version": "2.1.2-Beta", "status": "running"}
```

```http
GET /api/v1/health
```
Returns health status and timestamp.

> **Note:** This endpoint returns raw JSON, not the standard `ApiResponse` wrapper.

**Response:**
```json
{"status": "healthy", "timestamp": 1735689600.123456}
```

## Authentication

All API endpoints require authentication using an API key in the request header.

```bash
curl -H "X-API-Key: your-api-key-here" http://localhost:8000/api/v1/tenants
```

### API Key Management

#### Generating New API Keys

```bash
cachepilot api key generate <key-name>

# Examples:
cachepilot api key generate monitoring
cachepilot api key generate admin
cachepilot api key generate backup-service
```

**Important:** API keys are shown only once during generation. Store them securely.

**Example Output:**
```
API Key Generated Successfully!

Key Name: monitoring
API Key:  CgAmLJUz9TrMHGiIqVpR5a2VXNIEqhjcnzSOiOEPblo

Store this key securely. It will not be shown again.

To use this key, include it in the X-API-Key header:
  curl -H 'X-API-Key: CgAmLJUz9TrMHGiIqVpR5a2VXNIEqhjcnzSOiOEPblo' http://localhost:8000/api/v1/tenants
```

#### Viewing Existing API Keys

```bash
cachepilot api key list
```

**Output:**
```
CachePilot API Keys

Key Name          Created                  Last Used                Requests
----------------- ------------------------ ------------------------ --------
admin             2025-11-01 22:52:40     2025-11-01 22:57:07     2
monitoring        2025-11-01 23:05:24     Never                    0

Note: Actual API key values are not shown (only hashes are stored).
```

#### Key Storage

API keys are stored in `/etc/cachepilot/api-keys.json`:

```bash
# View all keys and their metadata (without the actual key values)
cat /etc/cachepilot/api-keys.json | jq '.'
```

**Key Storage Format:**
```json
{
  "key-hash": {
    "name": "admin",
    "permissions": ["*"],
    "created": 1762028393.864853,
    "last_used": 1762028850.6372335,
    "request_count": 11
  }
}
```

**Note:** The actual API key values are not stored. Only hashes are kept for security. If you lose an API key, you must generate a new one.

#### Revoking API Keys

```bash
cachepilot api key revoke <key-name>

# Example:
cachepilot api key revoke monitoring
```

After revoking, restart the API service:
```bash
cachepilot api restart
```

## Endpoints

### Tenants

#### List All Tenants
```http
GET /api/v1/tenants
```

**Response:**
```json
{
  "success": true,
  "message": "Found 2 tenants",
  "data": {
    "tenants": [
      {"tenant": "client1", "port": "7300", "status": "running", "security_mode": "tls-only", "port_tls": "7300", "port_plain": ""},
      {"tenant": "client2", "port": "7301", "status": "stopped", "security_mode": "dual-mode", "port_tls": "7301", "port_plain": "7401"}
    ]
  }
}
```

#### Get Tenant Details
```http
GET /api/v1/tenants/{tenant_name}
```

**Response:**
```json
{
  "success": true,
  "message": "Tenant status retrieved",
  "data": {
    "tenant": "client1",
    "port": "7300",
    "security_mode": "tls-only",
    "persistence_mode": "memory-only",
    "port_tls": "7300",
    "port_plain": "",
    "status": "running",
    "memory_used": "10.00M",
    "clients": "3",
    "keys": "150",
    "uptime_seconds": 86400,
    "maxmemory": 256,
    "docker_limit": 512,
    "total_commands": "52340",
    "keyspace_hits": "48201",
    "keyspace_misses": "4139",
    "hit_rate": "92.09%",
    "memory_peak": "12.50M",
    "evicted_keys": "0"
  }
}
```

**Error Response (404):**
```json
{"detail": "Tenant client1 does not exist"}
```

#### Create Tenant
```http
POST /api/v1/tenants
```

**Request Body:**
```json
{
  "tenant_name": "newclient",
  "maxmemory_mb": 256,
  "docker_limit_mb": 512,
  "password": "optional-custom-password",
  "security_mode": "tls-only",
  "persistence_mode": "memory-only"
}
```

**Security Modes (v2.2+):**
- `tls-only`: Default, requires CA certificate (most secure)
- `dual-mode`: Both TLS and Plain-Text available
- `plain-only`: Password-only, no certificate required

**Persistence Modes (v2.2+):**
- `memory-only`: Pure in-memory, no disk writes, 1-5ms latency (default, recommended)
  - Data lost on restart - use on-demand backups if needed
  - Ideal for caches and ephemeral data
- `persistent`: Traditional RDB + AOF persistence, 100-200ms latency
  - Data survives container restarts
  - Use for data that must persist

**Response:**
```json
{
  "success": true,
  "message": "Tenant newclient created successfully",
  "data": {"tenant": "newclient"}
}
```

**Error Response (400 — validation):**
```json
{
  "success": false,
  "message": "Validation error",
  "error": "Memory limit must be between 64 and 4096 MB"
}
```

**Error Response (422 — Pydantic):**
```json
{
  "detail": [
    {"loc": ["body", "tenant_name"], "msg": "string does not match regex '^[a-z0-9][a-z0-9-]{0,62}$'", "type": "value_error.str.regex"},
    {"loc": ["body", "docker_limit_mb"], "msg": "docker_limit_mb must be at least 1.5x maxmemory_mb", "type": "value_error"}
  ]
}
```

#### Update Tenant
```http
PATCH /api/v1/tenants/{tenant_name}
```

**Request Body:**
```json
{
  "maxmemory_mb": 512,
  "docker_limit_mb": 1024
}
```

**Response:**
```json
{
  "success": true,
  "message": "Tenant client1 updated successfully",
  "data": {"tenant": "client1"}
}
```

#### Delete Tenant
```http
DELETE /api/v1/tenants/{tenant_name}?force=false
```

**Query Parameters:**
- `force` (boolean): Skip confirmation prompt

**Response:**
```json
{
  "success": true,
  "message": "Tenant client1 deleted successfully",
  "data": {"tenant": "client1"}
}
```

**Error Response (400):**
```json
{
  "success": false,
  "message": "Invalid tenant name",
  "error": "Tenant name contains invalid characters"
}
```

#### Start Tenant
```http
POST /api/v1/tenants/{tenant_name}/start
```

**Response:**
```json
{
  "success": true,
  "message": "Tenant client1 started successfully",
  "data": {"tenant": "client1", "status": "running"}
}
```

#### Stop Tenant
```http
POST /api/v1/tenants/{tenant_name}/stop
```

**Response:**
```json
{
  "success": true,
  "message": "Tenant client1 stopped successfully",
  "data": {"tenant": "client1", "status": "stopped"}
}
```

#### Restart Tenant
```http
POST /api/v1/tenants/{tenant_name}/restart
```

**Response:**
```json
{
  "success": true,
  "message": "Tenant client1 restarted successfully",
  "data": {"tenant": "client1", "status": "running"}
}
```

#### Rotate Password
```http
POST /api/v1/tenants/{tenant_name}/rotate-password
```

**Response:**
```json
{
  "success": true,
  "message": "Password rotated for tenant client1",
  "data": {
    "tenant": "client1",
    "new_password": "new-secure-password"
  }
}
```

#### Get Handover Information
```http
GET /api/v1/tenants/{tenant_name}/handover
```

**Response:**
```json
{
  "success": true,
  "message": "Handover information retrieved",
  "data": {
    "tenant": "client1",
    "security_mode": "dual-mode",
    "host": "10.0.0.1",
    "public_host": "redis.example.com",
    "public_ip": "203.0.113.10",
    "server_url": "redis.example.com",
    "password": "s3cure-p4ssw0rd",
    "ca_certificate": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----",
    "status": "running",
    "handover_package": "/var/cachepilot/tenants/client1/handover/client1-handover.zip",
    "credentials_text": "...",
    "tls_connection": {
      "port": 7300,
      "connection_string": "rediss://:s3cure-p4ssw0rd@10.0.0.1:7300",
      "wordpress_config": "..."
    },
    "plaintext_connection": {
      "port": 7400,
      "connection_string": "redis://:s3cure-p4ssw0rd@10.0.0.1:7400",
      "wordpress_config": "..."
    }
  }
}
```

> **Note:** `tls_connection` is included when `security_mode` is `tls-only` or `dual-mode`. `plaintext_connection` is included when `security_mode` is `dual-mode` or `plain-only`.

#### Regenerate Handover Package
```http
POST /api/v1/tenants/{tenant_name}/handover/regenerate
```

**Response:**
```json
{
  "success": true,
  "message": "Handover package regenerated for tenant client1",
  "data": {"tenant": "client1"}
}
```

#### Change Security Mode
```http
POST /api/v1/tenants/{tenant_name}/security-mode?security_mode=dual-mode
```

**Query Parameters:**
- `security_mode` (string): New security mode (tls-only, dual-mode, plain-only)

**Response:**
```json
{
  "success": true,
  "message": "Security mode changed to dual-mode for tenant client1",
  "data": {"tenant": "client1", "security_mode": "dual-mode"}
}
```

### RedisInsight Management (v2.1.2+)

RedisInsight provides a web-based GUI for managing and monitoring Redis instances.

#### Enable RedisInsight
```http
POST /api/v1/tenants/{tenant_name}/redisinsight/enable
```

**Response:**
```json
{
  "success": true,
  "message": "RedisInsight enabled for tenant client1",
  "data": {
    "tenant": "client1",
    "redisinsight": {
      "enabled": true,
      "port": 8300,
      "public_url": "https://your-server:8300",
      "internal_url": "https://internal-ip:8300",
      "username": "admin",
      "password": "generated-password",
      "status": "running"
    }
  }
}
```

**Features:**
- Automatic Redis connection configuration (TLS and Plain-Text supported)
- HTTPS with self-signed certificate
- Basic authentication with nginx
- Port range: 8300-8399

#### Get RedisInsight Status
```http
GET /api/v1/tenants/{tenant_name}/redisinsight
```

**Response:**
```json
{
  "success": true,
  "message": "RedisInsight status retrieved",
  "data": {
    "tenant": "client1",
    "redisinsight": {
      "enabled": true,
      "port": 8300,
      "public_url": "https://your-server:8300",
      "internal_url": "https://internal-ip:8300",
      "username": "admin",
      "password": "admin-password",
      "status": "running"
    }
  }
}
```

#### Disable RedisInsight
```http
DELETE /api/v1/tenants/{tenant_name}/redisinsight
```

**Response:**
```json
{
  "success": true,
  "message": "RedisInsight disabled for tenant client1",
  "data": {
    "tenant": "client1"
  }
}
```

**Note:**
- RedisInsight uses a self-signed HTTPS certificate - browsers will show a security warning
- The Redis connection is automatically configured in RedisInsight for immediate use
- Login credentials are automatically generated
- Supports both TLS-enabled and plain-text Redis instances

### Monitoring

#### Health Check
```http
GET /api/v1/monitoring/health
```

**Response:**
```json
{
  "success": true,
  "message": "Health check completed",
  "data": {
    "status": "healthy",
    "services": {
      "docker": "healthy",
      "disk_space": "healthy",
      "certificates": "healthy"
    },
    "total_tenants": 5,
    "running_tenants": 4,
    "issues": []
  }
}
```

#### Global Statistics
```http
GET /api/v1/monitoring/stats
```

**Response:**
```json
{
  "success": true,
  "message": "Statistics retrieved",
  "data": {
    "total_tenants": 5,
    "running_tenants": 4,
    "running": 4,
    "stopped_tenants": 1,
    "stopped": 1,
    "total_memory_used": 536870912,
    "total_memory_limit": 0,
    "total_connections": 0,
    "total_clients": 0,
    "total_keys": 0
  }
}
```

#### Get Alerts
```http
GET /api/v1/monitoring/alerts?severity=critical&resolved=false
```

**Query Parameters:**
- `severity` (string): Filter by severity (info, warning, critical)
- `tenant` (string): Filter by tenant name
- `resolved` (boolean): Filter by resolution status

**Response:**
```json
{
  "success": true,
  "message": "Found 2 alerts",
  "data": {
    "alerts": [
      {
        "id": "alert-001",
        "severity": "critical",
        "tenant": "client1",
        "title": "High memory usage",
        "message": "Memory usage exceeds 90% threshold",
        "timestamp": "2025-11-01T14:30:00Z",
        "resolved": false,
        "resolved_at": null
      },
      {
        "id": "alert-002",
        "severity": "warning",
        "tenant": "client2",
        "title": "Disk space low",
        "message": "Available disk space below 20%",
        "timestamp": "2025-11-01T13:15:00Z",
        "resolved": false,
        "resolved_at": null
      }
    ]
  }
}
```

#### Resolve Alert
```http
POST /api/v1/monitoring/alerts/{alert_id}/resolve
```

**Response:**
```json
{
  "success": true,
  "message": "Alert alert-001 resolved",
  "data": {"alert_id": "alert-001"}
}
```

#### Get Tenant Metrics
```http
GET /api/v1/monitoring/metrics/{tenant_name}?hours=24
```

**Query Parameters:**
- `hours` (integer): Number of hours of history (1-168)

**Response:**
```json
{
  "success": true,
  "message": "Retrieved 3 metrics",
  "data": {
    "metrics": [
      {
        "tenant": "client1",
        "metric_name": "memory_used",
        "value": 10485760.0,
        "unit": "bytes",
        "timestamp": "2025-11-01T14:00:00Z",
        "threshold": null,
        "alert_triggered": false
      }
    ]
  }
}
```

### System

#### Create Backup
```http
POST /api/v1/system/backup
```

**Request Body:**
```json
{
  "tenant": "client1"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Backup created for tenant client1",
  "data": {"tenant": "client1", "output": "Backup saved to /var/cachepilot/backups/client1_20250101_120000.tar.gz"}
}
```

#### List Backups
```http
GET /api/v1/system/backups/{tenant_name}
```

**Response:**
```json
{
  "success": true,
  "message": "Found 3 backups",
  "data": {
    "tenant": "client1",
    "backups": [
      {"file": "client1_20250101_120000.tar.gz", "size": "2.5MB"},
      {"file": "client1_20241231_000000.tar.gz", "size": "2.3MB"},
      {"file": "client1_20241230_000000.tar.gz", "size": "2.1MB"}
    ]
  }
}
```

#### Restore Backup
```http
POST /api/v1/system/restore
```

**Request Body:**
```json
{
  "tenant": "client1",
  "backup_file": "/var/cachepilot/backups/client1_20250101_120000.tar.gz"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Tenant client1 restored from backup successfully",
  "data": {"tenant": "client1", "backup_file": "/var/cachepilot/backups/client1_20250101_120000.tar.gz"}
}
```

#### Verify Backup
```http
POST /api/v1/system/verify-backup?backup_file=/path/to/backup.tar.gz
```

**Response:**
```json
{
  "success": true,
  "message": "Backup verification successful",
  "data": {"backup_file": "/path/to/backup.tar.gz", "valid": true}
}
```

#### Enable Auto Backup
```http
POST /api/v1/system/backup/enable/{tenant_name}
```

**Response:**
```json
{
  "success": true,
  "message": "Automated backups enabled for client1",
  "data": {"tenant": "client1", "auto_backup": true}
}
```

#### Disable Auto Backup
```http
POST /api/v1/system/backup/disable/{tenant_name}
```

**Response:**
```json
{
  "success": true,
  "message": "Automated backups disabled for client1",
  "data": {"tenant": "client1", "auto_backup": false}
}
```

#### Delete Backup
```http
DELETE /api/v1/system/backups/{tenant_name}/{backup_file}
```

**Path Parameters:**
- `tenant_name`: Name of the tenant
- `backup_file`: Filename of the backup to delete

**Response:**
```json
{
  "success": true,
  "message": "Backup client1_20250101_120000.tar.gz deleted successfully",
  "data": {"tenant": "client1", "backup_file": "client1_20250101_120000.tar.gz"}
}
```

## Error Responses

The API uses several different error response formats depending on where the error originates. Not all errors use the `ApiResponse` wrapper.

### Error Format Summary

| Status Code | Source | Format |
|-------------|--------|--------|
| 400 | Route-level / service validation | `{"success": false, "message": "...", "error": "..."}` |
| 400 | Middleware (suspicious input) | `{"detail": "...", "error": "bad_request"}` |
| 401 | Authentication | `{"detail": "..."}` |
| 404 | Route-level | `{"detail": "..."}` |
| 415 | Middleware (content-type) | `{"detail": "...", "error": "unsupported_media_type"}` |
| 422 | Pydantic validation | `{"detail": [{"loc": [...], "msg": "...", "type": "..."}]}` |
| 429 | Middleware (rate limit) | `{"detail": "...", "error": "too_many_requests"}` |
| 500 | Global exception handler | `{"success": false, "message": "...", "error": "internal_server_error"}` |

### Route-Level Errors (400, 404)

Raised via `HTTPException` in route handlers and services. Returns the standard FastAPI format:

```json
{"detail": "Tenant client1 does not exist"}
```

Service-level validation errors use the `ApiResponse` format:

```json
{
  "success": false,
  "message": "Validation error",
  "error": "Memory limit must be between 64 and 4096 MB"
}
```

### Authentication Errors (401)

From the authentication module when the API key is missing or invalid:

```json
{"detail": "Missing API key"}
```

```json
{"detail": "Invalid API key"}
```

### Pydantic Validation Errors (422)

FastAPI's built-in request validation. Returns an array of validation errors:

```json
{
  "detail": [
    {"loc": ["body", "tenant_name"], "msg": "string does not match regex '^[a-z0-9][a-z0-9-]{0,62}$'", "type": "value_error.str.regex"},
    {"loc": ["body", "docker_limit_mb"], "msg": "docker_limit_mb must be at least 1.5x maxmemory_mb", "type": "value_error"}
  ]
}
```

### Rate Limit Errors (429)

From the rate limiting middleware. Includes a `Retry-After` header:

```json
{"detail": "Rate limit exceeded. Please try again later.", "error": "too_many_requests"}
```

> **Note:** The response includes the header `Retry-After: 60`.

### Middleware Validation Errors (400)

From the request validation middleware when suspicious input patterns are detected:

```json
{"detail": "Invalid request parameters", "error": "bad_request"}
```

### Content-Type Errors (415)

From the content security middleware when a request body is sent without `application/json`:

```json
{"detail": "Content-Type must be application/json", "error": "unsupported_media_type"}
```

### Internal Server Errors (500)

From the global exception handler for unhandled exceptions:

```json
{
  "success": false,
  "message": "An error occurred while processing your request",
  "error": "internal_server_error"
}
```

### Common HTTP Status Codes

- `200 OK`: Request successful
- `400 Bad Request`: Invalid request parameters or service validation error
- `401 Unauthorized`: Invalid or missing API key
- `404 Not Found`: Resource not found
- `415 Unsupported Media Type`: Content-Type is not application/json
- `422 Unprocessable Entity`: Request body fails Pydantic validation
- `429 Too Many Requests`: Rate limit exceeded
- `500 Internal Server Error`: Unhandled server error

## Rate Limiting

Rate limits are enforced per API key with different limits per endpoint category:

| Endpoint Category | Rate Limit |
|-------------------|------------|
| `/api/v1/tenants/*` | 50 requests/60s |
| `/api/v1/monitoring/*` | 200 requests/60s |
| `/api/v1/system/*` | 30 requests/60s |
| Default | 100 requests/60s |

**Security Features:**
- IP-based blocking after excessive rate limit violations (15-minute temporary block)
- Failed authentication tracking: 5 failed attempts within 5 minutes triggers security alert

Response headers include:
- `X-Process-Time`: Request processing time in seconds

## Examples

### Using curl

```bash
API_KEY="your-api-key"

curl -H "X-API-Key: $API_KEY" \
  http://localhost:8000/api/v1/tenants

curl -X POST -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"tenant_name": "test", "maxmemory_mb": 256, "docker_limit_mb": 512}' \
  http://localhost:8000/api/v1/tenants
```

### Using Python

```python
import requests

API_KEY = "your-api-key"
BASE_URL = "http://localhost:8000/api/v1"
headers = {"X-API-Key": API_KEY}

response = requests.get(f"{BASE_URL}/tenants", headers=headers)
print(response.json())

new_tenant = {
    "tenant_name": "test",
    "maxmemory_mb": 256,
    "docker_limit_mb": 512
}
response = requests.post(f"{BASE_URL}/tenants", headers=headers, json=new_tenant)
print(response.json())
```

## Interactive Documentation

FastAPI provides interactive API documentation (available when debug mode is enabled):

- Swagger UI: http://localhost:8000/api/docs
- ReDoc: http://localhost:8000/api/redoc
- OpenAPI JSON: http://localhost:8000/openapi.json

## Security Headers

All API responses include the following security headers:

| Header | Value |
|--------|-------|
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `SAMEORIGIN` |
| `X-XSS-Protection` | `1; mode=block` |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Permissions-Policy` | `geolocation=(), microphone=(), camera=()` |

## Security Considerations

For comprehensive security guidance, see [SECURITY.md](SECURITY.md).

### Key Security Practices

**API Key Security:**
- Never commit API keys to version control
- Store keys in environment variables or secure vaults
- Rotate keys regularly (every 90 days recommended)
- Use different keys for different environments

**File Permissions:**
```bash
# Verify permissions (should be 600)
ls -l /etc/cachepilot/api-keys.json

# Fix if needed
sudo chmod 600 /etc/cachepilot/api-keys.json
```

**TLS/SSL Configuration:**

Always use HTTPS in production. The API listens on `localhost:8000` by default and should be accessed through an nginx reverse proxy with TLS.

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d your-domain.com
```

**Rate Limiting:**

When rate limited (429 status), implement exponential backoff:

```python
import time
import requests

def api_call_with_retry(url, headers, max_retries=3):
    for attempt in range(max_retries):
        response = requests.get(url, headers=headers)
        
        if response.status_code == 429:
            wait_time = 2 ** attempt
            time.sleep(wait_time)
            continue
            
        return response
    
    raise Exception("Max retries exceeded")
```

**Input Validation:**

Tenant names must match: `^[a-z0-9][a-z0-9-]{0,62}$` (max 63 characters)

Allowed: `client1`, `test-server`, `prod-cache`  
Blocked: `../../../etc`, `client;rm -rf /`, `<script>alert(1)</script>`

**Audit Logging:**

All API requests are logged to `/var/log/cachepilot/audit.log`:

```bash
# Monitor live API access
tail -f /var/log/cachepilot/audit.log

# Find failed authentication attempts
grep '"status": 401' /var/log/cachepilot/audit.log
```

For complete security documentation, see [SECURITY.md](SECURITY.md).
