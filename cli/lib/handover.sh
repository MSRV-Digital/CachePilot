#!/usr/bin/env bash
#
# CachePilot - Customer Handover Package Generator
#
# Creates comprehensive handover packages containing credentials, certificates,
# and detailed setup instructions for WordPress Redis integration.
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Company: MSRV Digital
# Version: 2.1.0-beta
# License: MIT
# Repository: https://github.com/MSRV-Digital/CachePilot
#
# Copyright (c) 2025 Patrick Schlesinger, MSRV Digital
#

generate_handover() {
    local tenant="$1"
    require_tenant "$tenant"
    
    local tenant_dir="${TENANTS_DIR}/${tenant}"
    local handover_dir="${tenant_dir}/handover"
    local temp_dir="${handover_dir}/temp"
    
    source "${tenant_dir}/config.env"
    
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    
    cp "${CA_DIR}/ca.crt" "${temp_dir}/redis-ca.pem"
    
    cat > "${temp_dir}/credentials.txt" << EOF
Redis Connection Details
========================

Host: ${INTERNAL_IP}
Port: $PORT
Password: $PASSWORD

TLS: Enabled
CA Certificate: redis-ca.pem

Created: $CREATED
Tenant: $tenant

Contact:
--------
MSRV Digital
Patrick Schlesinger
Mail: cachepilot@msrv-digital.de
Web: https://msrv-digital.de

RedisInsight:
-------------
Status: $(if [[ -n "${INSIGHT_PORT}" ]] && [[ "${INSIGHT_PORT}" != "0" ]]; then echo "Enabled"; else echo "Disabled"; fi)
$(if [[ -n "${INSIGHT_PORT}" ]] && [[ "${INSIGHT_PORT}" != "0" ]]; then echo "Public URL: https://${PUBLIC_IP}:${INSIGHT_PORT}"; echo "Internal URL: https://${INTERNAL_IP}:${INSIGHT_PORT}"; echo "Username: ${INSIGHT_USER:-admin}"; echo "Password: ${INSIGHT_PASS}"; echo ""; echo "Redis Host (in RedisInsight): redis-${tenant}"; echo "Redis Port (in RedisInsight): 6379"; echo "Redis Password: Use the password above"; echo "Note: Accept the self-signed certificate warning in your browser"; fi)
EOF
    
    cat > "${temp_dir}/README.md" << EOF
# Redis Connection Setup for WordPress

## Overview

This package contains everything needed to connect your WordPress site to your dedicated Redis instance.

## Files Included

- \`redis-ca.pem\` - TLS CA certificate
- \`credentials.txt\` - Connection details and password
- \`README.md\` - This file

## Installation Steps

### 1. Install Redis Object Cache Plugin

Install and activate the "Redis Object Cache" plugin from wordpress.org:
\`\`\`
https://wordpress.org/plugins/redis-cache/
\`\`\`

### 2. Upload CA Certificate

Upload the \`redis-ca.pem\` file to a \`redis\` subdirectory in your WordPress root.

Recommended location: \`ABSPATH/redis/redis-ca.pem\` (e.g., \`/var/www/html/redis/redis-ca.pem\`)

Create the directory if it doesn't exist:
\`\`\`bash
mkdir -p /var/www/html/redis
cp redis-ca.pem /var/www/html/redis/
chmod 644 /var/www/html/redis/redis-ca.pem
\`\`\`

Make sure the file is readable by the web server user.

### 3. Configure wp-config.php

Add the following configuration to your \`wp-config.php\` file (before the "That's all, stop editing!" line):

\`\`\`php
define('WP_REDIS_CLIENT', 'phpredis');
define('WP_REDIS_SCHEME', 'tls');
define('WP_REDIS_HOST', '${INTERNAL_IP}');
define('WP_REDIS_PORT', PORT_FROM_CREDENTIALS);
define('WP_REDIS_PASSWORD', 'PASSWORD_FROM_CREDENTIALS');
define('WP_REDIS_PREFIX', 'wp:');

\$redis_options = [
    'verify_peer' => true,
    'verify_peer_name' => true,
    'cafile' => ABSPATH . 'redis/redis-ca.pem'
];
define('WP_REDIS_SSL_CONTEXT', \$redis_options);
\`\`\`

**Important:** Replace the following placeholders:
- \`PORT_FROM_CREDENTIALS\` - Use the port from credentials.txt
- \`PASSWORD_FROM_CREDENTIALS\` - Use the password from credentials.txt
- \`/path/to/redis-ca.pem\` - Use the actual path where you uploaded the CA certificate

### 4. Enable Redis Object Cache

1. Go to WordPress Admin → Settings → Redis
2. Click "Enable Object Cache"
3. Verify the connection status shows "Connected"

## Verification

After configuration, you should see:
- Green "Connected" status in Redis settings
- Cache statistics being populated
- Improved page load times

## Security Notes

- Keep the password secure and never commit it to version control
- The CA certificate is safe to include in your repository
- Redis is only accessible from the 10.0.0.0/24 network
- TLS encryption is enforced for all connections

## Troubleshooting

### Connection Failed

1. Verify the host, port, and password are correct
2. Check that the CA certificate path is correct and readable
3. Ensure your server can reach ${INTERNAL_IP} on the specified port
4. Verify phpredis extension is installed: \`php -m | grep redis\`

### Certificate Errors

1. Verify the CA certificate file is readable by PHP
2. Check file permissions: \`chmod 644 /path/to/redis-ca.pem\`
3. Ensure the path in wp-config.php is absolute and correct

### Performance Issues

1. Check Redis connection status in WordPress admin
2. Monitor cache hit rate in Redis settings
3. Verify memory limits are appropriate for your traffic

## Support

For technical support or questions:

**MSRV Digital**
Patrick Schlesinger
- Email: cachepilot@msrv-digital.de
- Web: https://msrv-digital.de

---

MSRV Digital
Web: msrv-digital.de
EOF
    
    sed -i "s/PORT_FROM_CREDENTIALS/$PORT/g" "${temp_dir}/README.md"
    sed -i "s/PASSWORD_FROM_CREDENTIALS/$PASSWORD/g" "${temp_dir}/README.md"
    
    cd "$handover_dir"
    zip -q -r "${tenant}-handover.zip" temp/
    
    rm -rf "$temp_dir"
    
    log "Handover package created: ${handover_dir}/${tenant}-handover.zip"
}
