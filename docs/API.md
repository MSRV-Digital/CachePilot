# CachePilot - API Documentation

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>  
Company: MSRV Digital  
Version: 2.1.2-Beta  
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital

## Overview

The CachePilot API provides RESTful access to all tenant management, monitoring, and system operations. All requests require authentication via API key.

**Base URL:** `http://localhost:8000/api/v1`

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
      {"tenant": "client1", "port": "7300", "status": "running"},
      {"tenant": "client2", "port": "7301", "status": "stopped"}
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
    "status": "running",
    "memory_used": "10.5M",
    "clients": "3"
  }
}
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
  "security_mode": "tls-only"
}
```

**Security Modes (v2.2+):**
- `tls-only`: Default, requires CA certificate (most secure)
- `dual-mode`: Both TLS and Plain-Text available
- `plain-only`: Password-only, no certificate required

**Response:**
```json
{
  "success": true,
  "message": "Tenant newclient created successfully",
  "data": {"tenant": "newclient"}
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

#### Delete Tenant
```http
DELETE /api/v1/tenants/{tenant_name}?force=false
```

**Query Parameters:**
- `force` (boolean): Skip confirmation prompt

#### Start Tenant
```http
POST /api/v1/tenants/{tenant_name}/start
```

#### Stop Tenant
```http
POST /api/v1/tenants/{tenant_name}/stop
```

#### Restart Tenant
```http
POST /api/v1/tenants/{tenant_name}/restart
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

#### Get Alerts
```http
GET /api/v1/monitoring/alerts?severity=critical&resolved=false
```

**Query Parameters:**
- `severity` (string): Filter by severity (info, warning, critical)
- `tenant` (string): Filter by tenant name
- `resolved` (boolean): Filter by resolution status

#### Resolve Alert
```http
POST /api/v1/monitoring/alerts/{alert_id}/resolve
```

#### Get Tenant Metrics
```http
GET /api/v1/monitoring/metrics/{tenant_name}?hours=24
```

**Query Parameters:**
- `hours` (integer): Number of hours of history (1-168)

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

#### List Backups
```http
GET /api/v1/system/backups/{tenant_name}
```

#### Restore Backup
```http
POST /api/v1/system/restore
```

**Request Body:**
```json
{
  "tenant": "client1",
  "backup_file": "/opt/cachepilot/backups/client1_20250101_120000.tar.gz"
}
```

#### Verify Backup
```http
POST /api/v1/system/verify-backup?backup_file=/path/to/backup.tar.gz
```

#### Enable Auto Backup
```http
POST /api/v1/system/backup/enable/{tenant_name}
```

#### Disable Auto Backup
```http
POST /api/v1/system/backup/disable/{tenant_name}
```

## Error Responses

All errors follow this format:

```json
{
  "success": false,
  "message": "Error description",
  "error": "Detailed error information"
}
```

### Common HTTP Status Codes

- `200 OK`: Request successful
- `400 Bad Request`: Invalid request parameters
- `401 Unauthorized`: Invalid or missing API key
- `404 Not Found`: Resource not found
- `429 Too Many Requests`: Rate limit exceeded
- `500 Internal Server Error`: Server error

## Rate Limiting

Default rate limits: 100 requests per 60 seconds per API key.

Rate limit information is included in response headers:
- `X-Process-Time`: Request processing time

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

FastAPI provides interactive API documentation:

- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

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

Tenant names must match: `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`

Allowed: `client1`, `test-server`, `prod-cache`  
Blocked: `../../../etc`, `client;rm -rf /`, `<script>alert(1)</script>`

**Audit Logging:**

All API requests are logged to `/opt/cachepilot/data/logs/audit.log`:

```bash
# Monitor live API access
tail -f /opt/cachepilot/data/logs/audit.log

# Find failed authentication attempts
grep '"status": 401' /opt/cachepilot/data/logs/audit.log
```

For complete security documentation, see [SECURITY.md](SECURITY.md).
